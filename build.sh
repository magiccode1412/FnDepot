#!/usr/bin/env bash
#
# FnDepot Build Script (V2)
# 根据 FnDepot 外部应用源 V2 规范，自动化构建应用仓库
# 功能：依赖检测 → fnpack build 打包 → 目录组装 → fnpack.json (V2) 生成 → 校验
#

set -euo pipefail

# ======================== 配置区 ========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_DIR="${SCRIPT_DIR}/projects"          # 源码目录
OUTPUT_DIR="${SCRIPT_DIR}"                      # 输出目录（项目根目录）
FNPACK_JSON="${OUTPUT_DIR}/fnpack.json"         # 全局索引输出路径
ICONS_DIR="${OUTPUT_DIR}/assets/icons"          # 图标目录
PACKAGES_DIR="${OUTPUT_DIR}/packages"           # 安装包目录

# ---- 源信息（V2 source_info，按 M1 决策填写）----
SRC_NAME="魔法领域"
SRC_AUTHOR="魔法代码"
SRC_HOMEPAGE="https://github.com/magiccode1412/FnDepot"
SRC_DESCRIPTION="飞牛第三方应用仓库"

# ---- 资源 base URL（按 M3/M4/M9 决策）----
# 分支动态获取（M9）
GIT_BRANCH="$(git -C "${SCRIPT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
# 发布仓库为 GitHub（开发仓库在 cnb.cool，发布时用 GitHub 仓库发布）
# GitHub raw 格式；分支由 M9 动态获取
RAW_BASE="https://raw.githubusercontent.com/magiccode1412/FnDepot/${GIT_BRANCH}"

# bug_report_url（M5：保留指向各上游 issues；manifest 中无此字段，故在此集中配置）
declare -A BUG_REPORT_URLS=(
    ["magic-bililivego"]="https://github.com/bililive-go/bililive-go/issues"
    ["magic-bilisync"]="https://github.com/amtoaer/bili-sync/issues"
    ["magic-ddnsgo"]="https://github.com/jeessy2/ddns-go/issues"
    ["magic-fnmessagebot"]="https://github.com/Sunanang/FNMessageBots/issues"
    ["magic-qiandao"]="https://github.com/qd-today/qd/issues"
    ["magic-qinglong"]="https://github.com/whyour/qinglong/issues"
    ["magic-speedtest"]="https://github.com/librespeed/speedtest/issues"
    ["magic-splayer"]="https://github.com/imsyy/SPlayer/issues"
    ["magic-uptimekuma"]="https://github.com/louislam/uptime-kuma/issues"
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ======================== 日志函数 ========================
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${BLUE}${BOLD}====== $* ======${NC}"; }

# ======================== 依赖检测 ========================
check_dependencies() {
    log_step "检测构建依赖"

    local missing=0

    if command -v fnpack &>/dev/null; then
        log_info "fnpack: $(command -v fnpack) ✓"
    else
        log_error "fnpack: 未找到 ✗ (飞牛官方打包工具，请确认已安装)"
        missing=1
    fi

    for cmd in cp ls grep sed awk stat find mkdir rm cat sha256sum; do
        if command -v "$cmd" &>/dev/null; then
            :
        else
            log_error "$cmd: 未找到 ✗"
            missing=1
        fi
    done

    local has_json_tool=0
    if command -v jq &>/dev/null; then
        log_info "jq: $(jq --version 2>/dev/null || echo '已安装') ✓"
        has_json_tool=1
    fi
    if command -v python3 &>/dev/null; then
        log_info "python3: $(python3 --version 2>&1) ✓"
        has_json_tool=1
    fi
    if [ "$has_json_tool" -eq 0 ]; then
        log_error "jq/python3 均未安装，无法生成 JSON"
        missing=1
    fi

    if [ "$missing" -ne 0 ]; then
        log_error "存在缺失的依赖，脚本退出"
        exit 1
    fi

    log_info "所有核心依赖检查通过 (branch=${GIT_BRANCH})"
}

# ======================== Manifest 解析 ========================
parse_manifest() {
    local app_dir="$1"
    local manifest_file="${app_dir}/manifest"

    if [ ! -f "$manifest_file" ]; then
        return 1
    fi

    M_APPNAME=""
    M_VERSION=""
    M_DISPLAY_NAME=""
    M_DESC=""
    M_PLATFORM=""
    M_MAINTAINER=""
    M_MAINTAINER_URL=""
    M_DISTRIBUTOR=""
    M_DISTRIBUTOR_URL=""
    M_SERVICE_PORT=""

    local in_multiline=0
    local multiline_key=""
    local multiline_content=""

    local TQ='"""'
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        if [ "$in_multiline" -eq 1 ]; then
            if [[ "$line" == *"${TQ}"* ]]; then
                local content="${line%${TQ}*}"
                multiline_content+=$'\n'"${content}"
                case "$multiline_key" in
                    desc)   M_DESC="$multiline_content" ;;
                esac
                in_multiline=0
                multiline_key=""
                multiline_content=""
            else
                multiline_content+=$'\n'"${line}"
            fi
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

            if [[ "$value" == "${TQ}"* ]]; then
                value="${value#${TQ}}"
                if [[ "$value" == *"${TQ}" ]]; then
                    value="${value%${TQ}}"
                else
                    in_multiline=1
                    multiline_key="$key"
                    multiline_content="$value"
                    continue
                fi
            fi

            if [[ "$value" == \"* && "$value" == *\" ]]; then
                value="${value#\"}"; value="${value%\"}"
            elif [[ "$value" == \'* && "$value" == *\' ]]; then
                value="${value#\'}"; value="${value%\'}"
            fi

            case "$key" in
                appname)         M_APPNAME="$value" ;;
                version)         M_VERSION="$value" ;;
                display_name)    M_DISPLAY_NAME="$value" ;;
                desc)            M_DESC="$value" ;;
                platform)        M_PLATFORM="$value" ;;
                maintainer)      M_MAINTAINER="$value" ;;
                maintainer_url)  M_MAINTAINER_URL="$value" ;;
                distributor)     M_DISTRIBUTOR="$value" ;;
                distributor_url) M_DISTRIBUTOR_URL="$value" ;;
                service_port)    M_SERVICE_PORT="$value" ;;
            esac
        fi
    done < "$manifest_file"

    return 0
}

get_manifest_appname() {
    local app_dir="$1"
    if [ -f "${app_dir}/manifest" ]; then
        grep -E '^appname[[:space:]]*=' "${app_dir}/manifest" | head -1 \
            | sed 's/^[^=]*=[[:space:]]*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//'
    fi
}

find_fpk_file() {
    local app_dir="$1"
    local dir_name="$2"
    if [ -f "${app_dir}/${dir_name}.fpk" ]; then echo "${dir_name}.fpk"; return 0; fi
    local m_appname; m_appname=$(get_manifest_appname "$app_dir")
    if [ -n "$m_appname" ] && [ -f "${app_dir}/${m_appname}.fpk" ]; then echo "${m_appname}.fpk"; return 0; fi
    local fpk; fpk=$(ls "${app_dir}"/*.fpk 2>/dev/null | head -1)
    if [ -n "$fpk" ]; then basename "$fpk"; return 0; fi
    return 1
}

# ======================== FPK 打包 ========================
build_fpk() {
    local app_name="$1"
    local app_dir="${PROJECTS_DIR}/${app_name}"

    log_step "打包应用: ${app_name}"

    if [ ! -d "$app_dir" ]; then log_error "源码目录不存在: ${app_dir}"; return 1; fi
    if [ ! -f "${app_dir}/manifest" ]; then log_error "manifest 不存在: ${app_dir}/manifest"; return 1; fi

    log_info "执行: cd ${app_dir} && fnpack build"
    ( cd "$app_dir" && fnpack build )
    if [ $? -ne 0 ]; then log_error "fnpack build 失败 ✗"; return 1; fi
    log_info "fnpack build 成功 ✓"

    local fpk_filename
    fpk_filename=$(find_fpk_file "$app_dir" "$app_name") || { log_error ".fpk 未生成"; return 1; }

    local fpk_file="${app_dir}/${fpk_filename}"
    local size
    size=$(stat -c%s "$fpk_file" 2>/dev/null || stat -f%z "$fpk_file" 2>/dev/null || echo 0)
    log_info "生成文件: ${fpk_file} ($(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size} bytes"))"
    return 0
}

# ======================== 目录组装（V2 推荐结构）========================
assemble_app() {
    local app_name="$1"
    local app_dir="${PROJECTS_DIR}/${app_name}"

    log_step "组装发布资源: ${app_name}"

    # 解析 manifest 取得真实 appname（可能与目录名不同，如 magic-ddnsgo）
    parse_manifest "$app_dir" || true
    local real_appname="${M_APPNAME:-$app_name}"

    # 图标 → assets/icons/<appname>.png（M4）
    mkdir -p "$ICONS_DIR"
    if [ -f "${app_dir}/ICON.PNG" ]; then
        cp -f "${app_dir}/ICON.PNG" "${ICONS_DIR}/${real_appname}.png"
        log_info "复制图标 → assets/icons/${real_appname}.png ✓"
    else
        log_warn "ICON.PNG 不存在: ${app_dir}/ICON.PNG"
    fi

    # 安装包 → packages/<appname>-<version>-<arch>.fpk（M6）
    mkdir -p "$PACKAGES_DIR"
    local fpk_filename
    fpk_filename=$(find_fpk_file "$app_dir" "$app_name") || {
        log_warn ".fpk 不存在，跳过移动"
        return 0
    }
    local src_fpk="${app_dir}/${fpk_filename}"

    # 解析版本与平台用于命名（platform 默认 all）
    local ver="${M_VERSION:-unknown}"
    local arch="${M_PLATFORM:-all}"
    local dest_fpk="${PACKAGES_DIR}/${real_appname}-${ver}-${arch}.fpk"

    mv -f "$src_fpk" "$dest_fpk"
    log_info "移动 ${fpk_filename} → packages/$(basename "$dest_fpk") ✓"

    return 0
}

# ======================== fnpack.json (V2) 生成 ========================
generate_fnpack_json() {
    log_step "生成 fnpack.json (V2)"

    # 将 BUG_REPORT_URLS 序列化为 JSON（键含连字符，直接 bash 拼接，值均为安全 URL）
    local bug_json="{"
    local first=1
    for k in "${!BUG_REPORT_URLS[@]}"; do
        local val="${BUG_REPORT_URLS[$k]}"
        if [ "$first" -eq 1 ]; then first=0; else bug_json+=","; fi
        bug_json+="\"${k}\":\"${val}\""
    done
    bug_json+="}"

    python3 - "$PROJECTS_DIR" "$OUTPUT_DIR" "$FNPACK_JSON" "$ICONS_DIR" "$PACKAGES_DIR" "$RAW_BASE" "$SRC_NAME" "$SRC_AUTHOR" "$SRC_HOMEPAGE" "$SRC_DESCRIPTION" "$bug_json" << 'PYEOF'
import os, sys, json, re, glob, hashlib

projects_dir   = sys.argv[1]
output_dir     = sys.argv[2]
output_file    = sys.argv[3]
icons_dir      = sys.argv[4]
packages_dir   = sys.argv[5]
raw_base       = sys.argv[6].rstrip("/")
src_name       = sys.argv[7]
src_author     = sys.argv[8]
src_homepage   = sys.argv[9]
src_desc       = sys.argv[10]
bug_report_map = json.loads(sys.argv[11])

# 固定分类（V2 §4.2）
VALID_CATEGORIES = {"影音娱乐","系统工具","编程开发","AI赋能","生活服务","智能智控","教育学习","游戏地带","硬件驱动"}

# appname -> 推荐分类（M2：ddns-go/speedtest 归入 系统工具）
DEFAULT_CATEGORIES = {
    "magic-bililivego": ["影音娱乐"],
    "magic-bilisync":   ["影音娱乐"],
    "magic-ddns-go":    ["系统工具"],
    "magic-fnmessagebot": ["系统工具"],
    "magic-qiandao":    ["生活服务"],
    "magic-qinglong":   ["系统工具"],
    "magic-speedtest":  ["系统工具"],
    "magic-splayer":    ["影音娱乐"],
    "magic-uptimekuma": ["系统工具"],
}

# 手动保留字段（V2）
MANUAL_FIELDS = {"categories","bug_report_url","icon_url","install_type","changelog","distributor","distributor_url"}

def parse_manifest(app_dir):
    manifest_path = os.path.join(app_dir, "manifest")
    if not os.path.isfile(manifest_path):
        return None
    data = {}
    with open(manifest_path, "r", encoding="utf-8") as f:
        content = f.read()
    lines = content.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line or line.startswith("#"):
            i += 1; continue
        m = re.match(r"^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)", line)
        if m:
            key = m.group(1); value = m.group(2).strip()
            if value.startswith('"""'):
                value = value[3:]
                if value.endswith('"""'):
                    value = value[:-3]
                else:
                    parts = [value]; i += 1
                    while i < len(lines):
                        if '"""' in lines[i]:
                            parts.append(lines[i][:lines[i].index('"""')]); break
                        parts.append(lines[i]); i += 1
                    value = "\n".join(parts)
            elif value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            elif value.startswith("'") and value.endswith("'"):
                value = value[1:-1]
            data[key] = value
        i += 1
    return data

def find_fpk_file(app_dir):
    fpks = sorted(glob.glob(os.path.join(app_dir, "*.fpk")))
    return fpks[0] if fpks else None

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

def check_is_docker(app_dir):
    for dc in ["docker-compose.yaml", "docker-compose.yml"]:
        if os.path.isfile(os.path.join(app_dir, "app", "docker", dc)):
            return True
    return False

def load_existing_json(output_file):
    if os.path.isfile(output_file):
        try:
            with open(output_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    return {}

existing_json = load_existing_json(output_file)

fnpack = {
    "schema_version": "2",
    "source_info": {
        "name": src_name,
        "author": src_author,
        "homepage": src_homepage,
        "description": src_desc,
    },
    "apps": {},
}

if os.path.isdir(projects_dir):
    for entry in sorted(os.listdir(projects_dir)):
        app_dir = os.path.join(projects_dir, entry)
        if not os.path.isdir(app_dir):
            continue
        manifest_path = os.path.join(app_dir, "manifest")
        if not os.path.isfile(manifest_path):
            continue

        m = parse_manifest(app_dir)
        if not m:
            print(f"[WARN] 跳过 {entry}: manifest 解析失败", file=sys.stderr)
            continue

        appname = m.get("appname", entry)
        version = m.get("version", "")
        platform = m.get("platform", "all")

        # 安装包：优先 packages/ 下已移动的文件，否则回退源码目录
        pkg_path = None
        pat = os.path.join(packages_dir, f"{appname}-{version}-{platform}.fpk")
        if os.path.isfile(pat):
            pkg_path = pat
        else:
            src_fpk = find_fpk_file(app_dir)
            if src_fpk:
                pkg_path = src_fpk

        if not pkg_path or not os.path.isfile(pkg_path):
            print(f"[WARN] 跳过 {entry}: 未找到安装包", file=sys.stderr)
            continue

        size_bytes = os.path.getsize(pkg_path)
        digest = sha256_of(pkg_path)
        # download_url（M3 方案A）：packages/ 下文件使用 raw base
        rel = os.path.relpath(pkg_path, output_dir)
        download_url = f"{raw_base}/{rel}"
        icon_rel = f"assets/icons/{appname}.png"
        icon_url = f"{raw_base}/{icon_rel}"

        # 分类
        cats = DEFAULT_CATEGORIES.get(appname, ["系统工具"])
        # 校验分类合法性
        for c in cats:
            if c not in VALID_CATEGORIES:
                print(f"[WARN] {appname} 分类非法: {c}，回退 系统工具", file=sys.stderr)
                cats = ["系统工具"]

        entry_data = {
            "display_name": m.get("display_name", ""),
            "desc": m.get("desc", ""),
            "platform": [platform] if platform != "all" else ["all"],
            "categories": cats,
            "icon_url": icon_url,
            "run_as": "package",
            "install_type": "",
            "is_docker": check_is_docker(app_dir),
            "maintainer": m.get("maintainer", ""),
            "maintainer_url": m.get("maintainer_url", ""),
            "distributor": m.get("distributor", ""),
            "distributor_url": m.get("distributor_url", ""),
            "bug_report_url": bug_report_map.get(appname, ""),
            "releases": {
                version: {
                    "changelog": "",
                    "packages": {
                        "all": {
                            "download_url": download_url,
                            "sha256": digest,
                            "size": size_bytes,
                        }
                    }
                }
            },
        }

        # 合并手动编辑字段（保留旧文件中用户自定义的非空值）
        if appname in existing_json:
            old_entry = existing_json[appname]
            for field in MANUAL_FIELDS:
                old_val = old_entry.get(field, "")
                if old_val and (not isinstance(old_val, str) or old_val.strip()):
                    entry_data[field] = old_val
            # 若旧文件已有 releases（含 changelog / 多版本），保留
            if isinstance(old_entry.get("releases"), dict) and old_entry["releases"]:
                entry_data["releases"] = old_entry["releases"]

        fnpack["apps"][appname] = entry_data
        print(f"[INFO] 索引: {appname} v{version} [{platform}] {size_bytes}B {digest[:12]}", file=sys.stderr)

with open(output_file, "w", encoding="utf-8") as f:
    json.dump(fnpack, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"[INFO] 共收录 {len(fnpack['apps'])} 个应用", file=sys.stderr)
PYEOF

    if [ -f "$FNPACK_JSON" ]; then
        log_step "fnpack.json (V2) 生成完成"
        log_info "路径: ${FNPACK_JSON}"
    else
        log_error "fnpack.json 生成失败"
    fi
}

# ======================== 校验（V2 §9/§12）========================
validate() {
    log_step "V2 校验"

    if command -v jq &>/dev/null; then
        if ! jq empty "$FNPACK_JSON" 2>/dev/null; then
            log_error "fnpack.json 不是合法 JSON"
            return 1
        fi
        log_info "JSON 语法 ✓ (jq)"
    else
        if ! python3 -c "import json,sys; json.load(open('$FNPACK_JSON',encoding='utf-8'))" 2>/dev/null; then
            log_error "fnpack.json 不是合法 JSON"
            return 1
        fi
        log_info "JSON 语法 ✓ (python3, jq 未安装)"
    fi

    python3 - "$FNPACK_JSON" << 'PYEOF'
import sys, json
f = sys.argv[1]
data = json.load(open(f, encoding="utf-8"))
errs = []
VALID_CAT = {"影音娱乐","系统工具","编程开发","AI赋能","生活服务","智能智控","教育学习","游戏地带","硬件驱动"}
VALID_PLAT = {"all","x86","arm"}
if data.get("schema_version") != "2":
    errs.append("schema_version 不是 '2'")
si = data.get("source_info", {})
if not si.get("name"): errs.append("source_info.name 为空")
if not si.get("author"): errs.append("source_info.author 为空")
for name, app in data.get("apps", {}).items():
    for c in app.get("categories", []):
        if c not in VALID_CAT: errs.append(f"{name}: 分类非法 {c}")
    plat = app.get("platform")
    if isinstance(plat, str): plat = [plat]
    for p in (plat or []):
        if p not in VALID_PLAT: errs.append(f"{name}: platform 非法 {p}")
    if not isinstance(app.get("is_docker"), bool): errs.append(f"{name}: is_docker 非布尔")
    if app.get("run_as") not in ("package","root"): errs.append(f"{name}: run_as 非法")
    rels = app.get("releases", {})
    if not rels: errs.append(f"{name}: 无 releases")
    for ver, rv in rels.items():
        for arch, pk in rv.get("packages", {}).items():
            if arch not in VALID_PLAT: errs.append(f"{name}/{ver}: 架构键 {arch} 非法")
            if "download_url" not in pk: errs.append(f"{name}/{ver}/{arch}: 缺 download_url")
            sz = pk.get("size")
            if not isinstance(sz, int) or sz < 0: errs.append(f"{name}/{ver}/{arch}: size 非整数")
            sh = pk.get("sha256","")
            if sh and (len(sh)!=64 or not all(ch in '0123456789abcdef' for ch in sh)):
                errs.append(f"{name}/{ver}/{arch}: sha256 格式错误")
if errs:
    print("校验失败:")
    for e in errs: print("  -", e)
    sys.exit(1)
print("所有 V2 校验项通过 ✓")
PYEOF
}

# ======================== 单应用构建 ========================
build_single() {
    local app_name="$1"
    local app_dir="${PROJECTS_DIR}/${app_name}"
    log_step "开始构建应用: ${app_name}"
    if [ ! -d "$app_dir" ]; then log_error "应用目录不存在: ${app_dir}"; return 1; fi
    build_fpk "$app_name" || { log_error "打包失败: ${app_name}"; return 1; }
    assemble_app "$app_name"
    log_info "应用 ${app_name} 构建完成 ✓"
    return 0
}

# ======================== 全量构建 ========================
build_all() {
    log_step "FnDepot V2 全量构建开始"
    log_info "源码目录: ${PROJECTS_DIR}"
    log_info "输出目录: ${OUTPUT_DIR}"
    log_info "RAW_BASE: ${RAW_BASE}"
    log_info "时间: $(date '+%Y-%m-%d %H:%M:%S')"

    local total=0 success=0 failed=0
    for app_dir in "${PROJECTS_DIR}"/*/; do
        [ -d "$app_dir" ] || continue
        local app_name; app_name=$(basename "$app_dir")
        [ -f "${app_dir}/manifest" ] || continue
        total=$((total+1))
        if build_single "$app_name"; then success=$((success+1)); else failed=$((failed+1)); fi
    done

    generate_fnpack_json
    validate

    echo ""
    log_step "构建摘要"
    log_info "总计: ${total} 个应用"
    log_info "成功: ${success} 个 ✓"
    [ "$failed" -gt 0 ] && log_warn "失败: ${failed} 个 ✗"
    log_info "产物位置: ${OUTPUT_DIR}"
    log_info "索引文件: ${FNPACK_JSON}"
}

# ======================== 清理 ========================
clean() {
    log_step "清理构建产物"
    local cleaned=0
    # 清理根级应用目录（旧结构）
    for item in "${OUTPUT_DIR}"/*/; do
        [ -d "$item" ] || continue
        local name; name=$(basename "$item")
        case "$name" in
            projects|.git|node_modules|.codebuddy|assets|packages) continue ;;
        esac
        if [ -f "${item}/ICON.PNG" ] || ls "${item}"/*.fpk &>/dev/null 2>&1; then
            rm -rf "$item"; log_info "已清理: ${item}"; cleaned=$((cleaned+1))
        fi
    done
    [ "$cleaned" -eq 0 ] && log_info "没有需要清理的产物" || log_info "共清理 ${cleaned} 项"
}

clean_fpk() {
    log_step "清理所有 .fpk 文件"
    local cleaned=0
    for fpk in "${PROJECTS_DIR}"/*/*.fpk "${PACKAGES_DIR}"/*.fpk; do
        [ -f "$fpk" ] || continue
        rm -f "$fpk"; log_info "已删除: $fpk"; cleaned=$((cleaned+1))
    done
    [ "$cleaned" -eq 0 ] && log_info "没有找到 .fpk 文件" || log_info "共清理 ${cleaned} 个 .fpk"
}

# ======================== 帮助 ========================
show_help() {
    echo "FnDepot Build Script (V2) - 应用仓库构建工具"
    echo ""
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  build-all       构建所有应用（默认）"
    echo "  build <name>    构建指定应用"
    echo "  validate        仅校验 fnpack.json"
    echo "  clean           清理根级旧应用目录"
    echo "  cleanfpk        删除所有 .fpk 文件"
    echo "  help            显示帮助信息"
}

# ======================== 主入口 ========================
main() {
    local command="${1:-build-all}"
    echo ""
    echo "========================================="
    echo "  FnDepot Build Script (V2)"
    echo "  External Source Schema v2"
    echo "========================================="
    echo ""

    check_dependencies

    case "$command" in
        build-all|all) build_all ;;
        build)
            [ -z "${2:-}" ] && { log_error "用法: $0 build <app_name>"; show_help; exit 1; }
            build_single "$2"; generate_fnpack_json; validate ;;
        validate) validate ;;
        clean) clean ;;
        cleanfpk) clean_fpk ;;
        help|--help|-h) show_help ;;
        *) log_error "未知命令: ${command}"; show_help; exit 1 ;;
    esac

    echo ""
    log_info "全部完成！"
    echo ""
}

main "$@"
