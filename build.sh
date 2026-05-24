#!/usr/bin/env bash
#
# FnDepot Build Script
# 根据 FnDepot Protocol v1.1.1 规范，自动化构建应用仓库
# 功能：依赖检测 → fnpack build 打包 → 目录组装 → fnpack.json 生成
#

set -euo pipefail

# ======================== 配置区 ========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_DIR="${SCRIPT_DIR}/projects"          # 源码目录
OUTPUT_DIR="${SCRIPT_DIR}"                      # 输出目录（项目根目录）
FNPACK_JSON="${OUTPUT_DIR}/fnpack.json"         # 全局索引输出路径

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

    # 核心依赖：fnpack
    if command -v fnpack &>/dev/null; then
        log_info "fnpack: $(command -v fnpack) ✓"
    else
        log_error "fnpack: 未找到 ✗ (飞牛官方打包工具，请确认已安装)"
        missing=1
    fi

    # 基础工具
    for cmd in cp ls grep sed awk stat find mkdir rm cat; do
        if command -v "$cmd" &>/dev/null; then
            : # 存在，静默通过
        else
            log_error "$cmd: 未找到 ✗"
            missing=1
        fi
    done

    # JSON 处理工具（至少需要一个，或用纯 Shell 兜底）
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
        log_warn "jq/python3 均未安装，将使用纯 Shell 拼接 JSON（格式可能不完美）"
    fi

    if [ "$missing" -ne 0 ]; then
        log_error "存在缺失的依赖，脚本退出"
        exit 1
    fi

    log_info "所有核心依赖检查通过"
}

# ======================== Manifest 解析 ========================
# 解析 INI 格式的 manifest 文件
# 用法: parse_manifest <app_dir>
# 输出全局变量: M_ 前缀的各字段值
parse_manifest() {
    local app_dir="$1"
    local manifest_file="${app_dir}/manifest"

    if [ ! -f "$manifest_file" ]; then
        return 1
    fi

    # 重置变量
    M_APPNAME=""
    M_VERSION=""
    M_DISPLAY_NAME=""
    M_DESC=""
    M_PLATFORM=""
    M_MAINTAINER=""
    M_MAINTAINER_URL=""
    M_DISTRIBUTOR=""
    M_DISTRIBUTOR_URL=""

    # 状态机解析：支持多行 desc（三引号/普通引号包裹）
    local in_multiline=0
    local multiline_key=""
    local multiline_content=""

    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # 多行模式内
        if [ "$in_multiline" -eq 1 ]; then
            if [[ "$line" == *"""* ]]; then
                # 三引号结束
                local content="${line%\"\"\"*}"
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

        # 提取 key = value 或 key=value 格式
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # 去除首尾空白
            value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')'

            # 检测三引号开头
            if [[ "$value" == \"\"\"* ]]; then
                value="${value#\"\"\"}"
                if [[ "$value" == *\"\"\" ]]; then
                    # 当行闭合的三引号
                    value="${value%\"\"\"}"
                else
                    # 进入多行模式
                    in_multiline=1
                    multiline_key="$key"
                    multiline_content="$value"
                    continue
                fi
            fi

            # 去除单引号或双引号包裹
            if [[ "$value" == \"* && "$value" == *\" ]]; then
                value="${value#\"}"; value="${value%\"}"
            elif [[ "$value" == \'* && "$value" == *\' ]]; then
                value="${value#\'}"; value="${value%\'}"
            fi

            # 赋值到对应变量
            case "$key" in
                appname)         M_APPNAME="$value" ;;
                version)         M_VERSION="$value" ;;
                display_name)    M_DISPLAY_NAME="$value" ;;
                desc)            M_DESC="$value" ;;
                platform)        M_PLATFORM="$value" ;;
                maintainer)      M_MAINTAINER="$value" ;;
                maintainer_url)  M_MAINTAINER_URL="$value" ;;
                distributor)     M_DISTRIBUTOR="$value" ;;
                distributor_url)M_DISTRIBUTOR_URL="$value" ;;
            esac
        fi
    done < "$manifest_file"

    return 0
}

# ======================== 获取应用的实际 appname（从 manifest 解析）========================
# fnpack build 使用 manifest 中的 appname 字段作为 .fpk 文件名，可能与目录名不同
get_manifest_appname() {
    local app_dir="$1"
    local appname=""
    # 从 manifest 中提取 appname 字段
    if [ -f "${app_dir}/manifest" ]; then
        appname=$(grep -E '^appname[[:space:]]*=' "${app_dir}/manifest" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')
    fi
    echo "${appname}"
}

# 查找目录下的 .fpk 文件（兼容 appname 与目录名不一致的情况）
find_fpk_file() {
    local app_dir="$1"
    local dir_name="$2"
    
    # 优先按目录名查找
    if [ -f "${app_dir}/${dir_name}.fpk" ]; then
        echo "${dir_name}.fpk"
        return 0
    fi
    
    # 再按 manifest 的 appname 查找
    local m_appname
    m_appname=$(get_manifest_appname "$app_dir")
    if [ -n "$m_appname" ] && [ -f "${app_dir}/${m_appname}.fpk" ]; then
        echo "${m_appname}.fpk"
        return 0
    fi
    
    # 最后通配扫描
    local fpk
    fpk=$(ls "${app_dir}"/*.fpk 2>/dev/null | head -1)
    if [ -n "$fpk" ]; then
        basename "$fpk"
        return 0
    fi
    
    return 1
}

# ======================== FPK 打包 ========================
# 使用 fnpack build 官方工具打包
build_fpk() {
    local app_name="$1"
    local app_dir="${PROJECTS_DIR}/${app_name}"

    log_step "打包应用: ${app_name}"

    if [ ! -d "$app_dir" ]; then
        log_error "源码目录不存在: ${app_dir}"
        return 1
    fi

    if [ ! -f "${app_dir}/manifest" ]; then
        log_error "manifest 文件不存在: ${app_dir}/manifest"
        return 1
    fi

    # 在源码目录执行 fnpack build
    log_info "执行: cd ${app_dir} && fnpack build"
    (
        cd "$app_dir"
        fnpack build
    )
    if [ $? -ne 0 ]; then
        log_error "fnpack build 失败 ✗"
        return 1
    fi
    log_info "fnpack build 成功 ✓"

    # 检查 .fpk 是否生成（使用 find_fpk_file 兼容命名差异）
    local fpk_filename
    fpk_filename=$(find_fpk_file "$app_dir" "$app_name") || {
        log_error ".fpk 文件未生成"
        return 1
    }

    local fpk_file="${app_dir}/${fpk_filename}"
    local size
    size=$(stat -c%s "$fpk_file" 2>/dev/null || stat -f%z "$fpk_file" 2>/dev/null || echo 0)
    log_info "生成文件: ${fpk_file} ($(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size} bytes"))"
    return 0
}

# ======================== 目录组装 ========================
# 将 .fpk 和 ICON.PNG 复制到项目根目录的 {app_name}/ 下
assemble_app() {
    local app_name="$1"
    local app_dir="${PROJECTS_DIR}/${app_name}"
    local target_dir="${OUTPUT_DIR}/${app_name}"

    log_step "组装发布目录: ${app_name}"

    # 创建目标目录
    mkdir -p "$target_dir"
    log_info "创建目录: ${target_dir}"

    # 查找 .fpk 文件（兼容命名差异）
    local fpk_filename
    fpk_filename=$(find_fpk_file "$app_dir" "$app_name") || {
        log_warn ".fpk 文件不存在，跳过复制"
        return 0
    }

    local src_fpk="${app_dir}/${fpk_filename}"
    
    # .fpk 在输出目录中的文件名统一为 {app_name}.fpk（以目录名为准）
    mv -f "$src_fpk" "${target_dir}/${app_name}.fpk"
    log_info "移动 ${fpk_filename} → ${app_name}.fpk ✓"

    # 复制 ICON.PNG（全大写）
    local icon_src="${app_dir}/ICON.PNG"
    if [ -f "$icon_src" ]; then
        cp -f "$icon_src" "${target_dir}/ICON.PNG"
        log_info "复制 ICON.PNG ✓"
    else
        log_warn "ICON.PNG 不存在，跳过: ${icon_src}"
    fi

    # 复制 Preview 目录（如果存在）
    if [ -d "${app_dir}/Preview" ]; then
        cp -r "${app_dir}/Preview" "${target_dir}/Preview"
        log_info "复制 Preview/ 目录 ✓"
    fi

    # 复制 README.md（如果存在）
    if [ -f "${app_dir}/README.md" ]; then
        cp -f "${app_dir}/README.md" "${target_dir}/README.md"
        log_info "复制 README.md ✓"
    fi
}

# ======================== fnpack.json 生成 ========================
# 使用 python3 一次性完成 manifest 解析 + JSON 生成（避免 bash 变量作用域问题）
generate_fnpack_json() {
    log_step "生成 fnpack.json 全局索引"

    local built_count=0

    # 使用 python3 完成：遍历所有应用 → 解析 manifest → 计算 size → 输出 JSON
    python3 - "$PROJECTS_DIR" "$OUTPUT_DIR" "$FNPACK_JSON" << 'PYEOF'
import os, sys, json, re, glob

projects_dir = sys.argv[1]
output_dir = sys.argv[2]
output_file = sys.argv[3]

def parse_manifest(app_dir):
    """解析 INI 格式 manifest，返回字段字典"""
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
        
        # 跳过空行和注释
        if not line or line.startswith("#"):
            i += 1
            continue
        
        # 匹配 key = value 或 key=value
        m = re.match(r"^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.*)", line)
        if m:
            key = m.group(1)
            value = m.group(2).strip()
            
            # 处理三引号多行值
            if value.startswith('"""'):
                value = value[3:]
                if value.endswith('"""'):
                    value = value[:-3]
                else:
                    # 多行模式：收集直到闭合三引号
                    parts = [value]
                    i += 1
                    while i < len(lines):
                        if '"""' in lines[i]:
                            parts.append(lines[i][:lines[i].index('"""')])
                            break
                        parts.append(lines[i])
                        i += 1
                    value = "\n".join(parts)
            elif value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            elif value.startswith("'") and value.endswith("'"):
                value = value[1:-1]
            
            data[key] = value
        
        i += 1
    
    return data


def find_fpk_file(app_dir):
    """在目录中查找 .fpk 文件"""
    fpks = glob.glob(os.path.join(app_dir, "*.fpk"))
    return fpks[0] if fpks else None


def get_size_str(filepath):
    """获取文件大小字符串，不足1M使用KB为单位"""
    try:
        size_bytes = os.path.getsize(filepath)
        if size_bytes < 1048576:
            return f"{round(size_bytes / 1024, 1)}KB"
        else:
            return f"{round(size_bytes / 1048576, 1)}MB"
    except:
        return "0.0KB"


def check_is_docker(app_dir):
    """检测是否 Docker 应用"""
    for dc_name in ["docker-compose.yaml", "docker-compose.yml"]:
        if os.path.isfile(os.path.join(app_dir, "app", "docker", dc_name)):
            return True
    return False


# 需要保留的手动编辑字段（不会从 manifest 自动生成）
MANUAL_FIELDS = {"labels", "bug_report_url", "install_type", "download_url", "changelog"}


def load_existing_json(output_file):
    """加载已有的 fnpack.json，用于保留手动编辑的字段"""
    if os.path.isfile(output_file):
        try:
            with open(output_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    return {}


# 构建完整 JSON
fnpack = {}

# 加载已有 JSON，用于合并手动字段
existing_json = load_existing_json(output_file)

if os.path.isdir(projects_dir):
    for entry in sorted(os.listdir(projects_dir)):
        app_dir = os.path.join(projects_dir, entry)
        if not os.path.isdir(app_dir):
            continue
        
        manifest_path = os.path.join(app_dir, "manifest")
        if not os.path.isfile(manifest_path):
            continue
        
        # 解析 manifest
        m = parse_manifest(app_dir)
        if not m:
            print(f"[WARN] 跳过 {entry}: manifest 解析失败", file=sys.stderr)
            continue
        
        appname = m.get("appname", entry)
        
        # 查找输出目录中的 .fpk 文件
        fpk_out = os.path.join(output_dir, entry, f"{entry}.fpk")
        if not os.path.isfile(fpk_out):
            print(f"[WARN] 跳过 {entry}: 未找到 {entry}.fpk", file=sys.stderr)
            continue
        
        # 构建条目
        entry_data = {
            "display_name": m.get("display_name", ""),
            "platform": m.get("platform", ""),
            "version": m.get("version", ""),
            "desc": m.get("desc", ""),
            "labels": "",
            "distributor": m.get("distributor", ""),
            "distributor_url": m.get("distributor_url", ""),
            "author": m.get("maintainer", ""),
            "author_url": m.get("maintainer_url", ""),
            "bug_report_url": "",
            "isdocker": "true" if check_is_docker(app_dir) else "false",
            "install_type": "",
            "size": get_size_str(fpk_out),
            "download_url": "",
            "changelog": ""
        }
        
        # 合并手动编辑的字段（保留旧文件中用户自定义的非空值）
        if appname in existing_json:
            old_entry = existing_json[appname]
            for field in MANUAL_FIELDS:
                old_val = old_entry.get(field, "")
                if old_val and old_val.strip():
                    entry_data[field] = old_val
        
        fnpack[appname] = entry_data
        print(f"[INFO] 索引应用: {appname} ({entry_data['display_name']}) v{entry_data['version']} [{entry_data['platform']}] ({entry_data['size']}MB)", file=sys.stderr)

# 写入文件
with open(output_file, "w", encoding="utf-8") as f:
    json.dump(fnpack, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"[INFO] 共收录 {len(fnpack)} 个应用", file=sys.stderr)
PYEOF

    # 检查执行结果
    if [ -f "$FNPACK_JSON" ]; then
        log_step "fnpack.json 生成完成"
        log_info "路径: ${FNPACK_JSON}"
    else
        log_error "fnpack.json 生成失败"
    fi
}

# ======================== 单个应用完整构建流程 ========================
build_single() {
    local app_name="$1"
    local app_dir="${PROJECTS_DIR}/${app_name}"

    log_step "开始构建应用: ${app_name}"

    if [ ! -d "$app_dir" ]; then
        log_error "应用目录不存在: ${app_dir}"
        return 1
    fi

    # Step 1: 打包
    if ! build_fpk "$app_name"; then
        log_error "打包失败: ${app_name}"
        return 1
    fi

    # Step 2: 组装
    assemble_app "$app_name"

    log_info "应用 ${app_name} 构建完成 ✓"
    return 0
}

# ======================== 全量构建 ========================
build_all() {
    log_step "FnDepot 全量构建开始"
    log_info "源码目录: ${PROJECTS_DIR}"
    log_info "输出目录: ${OUTPUT_DIR}"
    log_info "时间: $(date '+%Y-%m-%d %H:%M:%S')"

    local total=0
    local success=0
    local failed=0

    for app_dir in "${PROJECTS_DIR}"/*/; do
        [ -d "$app_dir" ] || continue
        local app_name
        app_name=$(basename "$app_dir")

        # 仅处理包含 manifest 的目录
        [ -f "${app_dir}/manifest" ] || continue

        total=$((total + 1))

        if build_single "$app_name"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
    done

    # 全部打包完成后，生成 fnpack.json
    generate_fnpack_json

    # 最终摘要
    echo ""
    log_step "构建摘要"
    log_info "总计: ${total} 个应用"
    log_info "成功: ${success} 个 ✓"
    if [ "$failed" -gt 0 ]; then
        log_warn "失败: ${failed} 个 ✗"
    fi
    log_info "产物位置: ${OUTPUT_DIR}"
    log_info "索引文件: ${FNPACK_JSON}"
}

# ======================== 清理 ========================
clean() {
    log_step "清理构建产物"

    # 清理根目录下生成的应用目录（排除 projects/、自身等固定项）
    local cleaned=0
    for item in "${OUTPUT_DIR}"/*/; do
        [ -d "$item" ] || continue
        local name
        name=$(basename "$item")
        
        # 排除固定的非产物目录
        case "$name" in
            projects|.git|node_modules|.codebuddy) 
                continue 
                ;;
        esac
        
        # 如果是应用目录（含 .fpk 或 ICON.PNG），则删除
        if [ -f "${item}/ICON.PNG" ] || [ -f "${item}/${name}.fpk" ] || ls "${item}"/*.fpk &>/dev/null 2>&1; then
            rm -rf "$item"
            log_info "已清理: ${item}"
            cleaned=$((cleaned + 1))
        fi
    done

    # 不清理 fnpack.json（保留手动编辑的字段）
    # if [ -f "$FNPACK_JSON" ]; then
    #     rm -f "$FNPACK_JSON"
    #     log_info "已清理: ${FNPACK_JSON}"
    #     cleaned=$((cleaned + 1))
    # fi

    if [ "$cleaned" -eq 0 ]; then
        log_info "没有需要清理的产物"
    else
        log_info "共清理 ${cleaned} 项"
    fi
}

# ======================== 清理 FPK ========================
clean_fpk() {
    log_step "清理所有目录中的 .fpk 文件"

    local cleaned=0

    # 扫描 projects/ 下的 .fpk 文件
    for fpk in "${PROJECTS_DIR}"/*/*.fpk; do
        [ -f "$fpk" ] || continue
        rm -f "$fpk"
        log_info "已删除: ${fpk}"
        cleaned=$((cleaned + 1))
    done

    # 扫描根目录下应用子目录的 .fpk 文件
    for item in "${OUTPUT_DIR}"/*/; do
        [ -d "$item" ] || continue
        local name
        name=$(basename "$item")

        # 排除非产物目录
        case "$name" in
            projects|.git|node_modules|.codebuddy) continue ;;
        esac

        for fpk in "${item}"/*.fpk; do
            [ -f "$fpk" ] || continue
            rm -f "$fpk"
            log_info "已删除: ${fpk}"
            cleaned=$((cleaned + 1))
        done
    done

    if [ "$cleaned" -eq 0 ]; then
        log_info "没有找到 .fpk 文件"
    else
        log_info "共清理 ${cleaned} 个 .fpk 文件"
    fi
}

# ======================== 帮助信息 ========================
show_help() {
    echo "FnDepot Build Script - 应用仓库构建工具"
    echo ""
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  build-all       构建所有应用（默认）"
    echo "  build <name>    构建指定应用"
    echo "  clean           清理构建产物"
    echo "  cleanfpk        删除所有 .fpk 文件"
    echo "  help            显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                      # 构建全部应用"
    echo "  $0 build-all            # 同上"
    echo "  $0 build fnmessagebot   # 仅构建单个应用"
    echo "  $0 clean                # 清理产物"
    echo "  $0 cleanfpk             # 删除所有 .fpk 文件"
}

# ======================== 主入口 ========================
main() {
    local command="${1:-build-all}"

    echo ""
    echo "========================================="
    echo "  FnDepot Build Script"
    echo "  Protocol v1.1.1"
    echo "========================================="
    echo ""

    # 阶段 1: 依赖检测
    check_dependencies

    case "$command" in
        build-all|all)
            build_all
            ;;
        build)
            if [ -z "${2:-}" ]; then
                log_error "用法: $0 build <app_name>"
                show_help
                exit 1
            fi
            build_single "$2"
            # 单个构建后也更新 fnpack.json
            generate_fnpack_json
            ;;
        clean)
            clean
            ;;
        cleanfpk)
            clean_fpk
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: ${command}"
            show_help
            exit 1
            ;;
    esac

    echo ""
    log_info "全部完成！"
    echo ""
}

main "$@"
