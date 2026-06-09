"""
Magic Shortcut Manager - FastAPI 后端服务
独立运行，通过 HTTP 端口提供服务
"""

import os
import sys
import json
import uuid
from pathlib import Path
from typing import Optional, List, Dict

# 添加当前目录到 Python 路径（确保模块可导入）
sys.path.insert(0, str(Path(__file__).parent))

try:
    from fastapi import FastAPI, Request, UploadFile, File, HTTPException
    from fastapi.responses import HTMLResponse, JSONResponse
    from fastapi.staticfiles import StaticFiles
    from pydantic import BaseModel
except ImportError as e:
    print(f"ERROR: Failed to import FastAPI: {e}")
    print("Please ensure dependencies are installed: pip install -r requirements.txt")
    sys.exit(1)

# 配置路径（使用环境变量或默认值）
TRIM_APPDEST = os.environ.get('TRIM_APPDEST', str(Path(__file__).parent.parent))
BASE_DIR = Path(__file__).parent
UI_DIR = Path(TRIM_APPDEST) / "ui"
CONFIG_FILE = UI_DIR / "config"
IMAGES_DIR = UI_DIR / "images"
DATA_SHARE_PATHS = os.environ.get('TRIM_DATA_SHARE_PATHS', '')
# 服务端口
SERVER_PORT = int(os.environ.get('SERVER_PORT', '8090'))

# 安全处理 DATA_FILE 路径
if DATA_SHARE_PATHS:
    try:
        DATA_FILE = Path(DATA_SHARE_PATHS.split(":")[0]) / "shortcuts.json"
        # 确保父目录存在
        DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        print(f"WARNING: Invalid data path: {e}")
        DATA_FILE = None
else:
    DATA_FILE = None

print(f"[INFO] Starting Magic Shortcut Manager...")
print(f"[INFO] TRIM_APPDEST: {TRIM_APPDEST}")
print(f"[INFO] BASE_DIR: {BASE_DIR}")
print(f"[INFO] UI_DIR: {UI_DIR}")
print(f"[INFO] CONFIG_FILE: {CONFIG_FILE}")
print(f"[INFO] IMAGES_DIR: {IMAGES_DIR}")
print(f"[INFO] DATA_FILE: {DATA_FILE}")

# 验证关键路径存在
if not CONFIG_FILE.exists():
    print(f"[WARNING] Config file not found: {CONFIG_FILE}")

if not IMAGES_DIR.exists():
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[INFO] Created images directory: {IMAGES_DIR}")

app = FastAPI(title="Magic Shortcut Manager")

# 安全挂载静态文件目录（如果不存在则创建）
static_dir = BASE_DIR / "static"
if not static_dir.exists():
    print(f"[WARNING] Static directory not found: {static_dir}")
else:
    app.mount("/static", StaticFiles(directory=static_dir), name="static")


# ==================== 数据模型 ====================

class ShortcutCreate(BaseModel):
    title: str
    url: str
    protocol: str = ""
    port: str = ""
    icon_filename: str
    all_users: bool = True


class ShortcutUpdate(BaseModel):
    title: Optional[str] = None
    url: Optional[str] = None
    protocol: Optional[str] = None
    port: Optional[str] = None
    all_users: Optional[bool] = None


# ==================== 工具函数 ====================

def get_config() -> Dict:
    """读取 config 文件"""
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"无法读取配置文件: {str(e)}")


def save_config(config: Dict) -> bool:
    """保存 config 文件（原子写入）"""
    try:
        tmp_file = f"{CONFIG_FILE}.tmp"
        with open(tmp_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        
        # 原子操作替换
        os.replace(tmp_file, CONFIG_FILE)
        return True
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"无法保存配置文件: {str(e)}")


def backup_data(shortcuts: List):
    """备份数据到共享目录"""
    if DATA_FILE:
        try:
            with open(DATA_FILE, 'w', encoding='utf-8') as f:
                json.dump({"shortcuts": shortcuts}, f, indent=4, ensure_ascii=False)
        except Exception as e:
            print(f"警告：数据备份失败 - {e}")


def restart_app():
    """重启提示（简化版，不做实际重启）"""
    print("[INFO] 快捷方式已更新，刷新页面即可查看效果")
    return True


def process_icon(file_content: bytes, original_filename: str) -> tuple[str, str]:
    """
    处理上传的图标，生成 64px 和 256px 版本
    
    Returns:
        (filename_64, filename_256)
    """
    from PIL import Image
    from io import BytesIO
    
    image = Image.open(BytesIO(file_content))
    
    # 转换为 RGBA 模式以支持透明度
    if image.mode != 'RGBA':
        image = image.convert('RGBA')
    
    # 生成唯一 ID
    icon_id = uuid.uuid4().hex[:8]
    
    # 保存 64x64 版本
    img_64 = image.resize((64, 64), Image.LANCZOS)
    filename_64 = f"icon_custom_{icon_id}_64.png"
    img_64.save(str(IMAGES_DIR / filename_64), 'PNG')
    
    # 保存 256x256 版本
    img_256 = image.resize((256, 256), Image.LANCZOS)
    filename_256 = f"icon_custom_{icon_id}_256.png"
    img_256.save(str(IMAGES_DIR / filename_256), 'PNG')
    
    return filename_64, filename_256


# ==================== API 接口 ====================

@app.get("/", response_class=HTMLResponse)
async def index():
    """返回管理界面主页"""
    html_file = BASE_DIR / "static" / "index.html"
    return HTMLResponse(content=html_file.read_text(encoding='utf-8'))


@app.get("/api/user")
async def get_user_info():
    """获取当前用户信息（简化版）"""
    return {
        "uid": "local-user",
        "username": "admin",
        "is_admin": True
    }


@app.get("/api/shortcuts")
async def list_shortcuts():
    """
    获取所有自定义快捷方式列表
    
    返回格式：
    [
        {
            "id": "custom_xxxx",
            "title": "...",
            "url": "...",
            ...
        },
        ...
    ]
    """
    config = get_config()
    shortcuts = []
    
    for key, value in config.get(".url", {}).items():
        # 只返回用户创建的 shortcut（id 以 custom_ 开头）
        if ".Application" in key and "custom_" in key.lower():
            shortcut_id = key.replace(".Application", "")
            if shortcut_id.startswith("custom_"):
                shortcuts.append({
                    "id": shortcut_id,
                    **value
                })
    
    return {"shortcuts": shortcuts}


@app.post("/api/upload-icon")
async def upload_icon(file: UploadFile = File(...)):
    """
    上传并处理图标文件
    
    支持 PNG、JPG、ICO 等常见图片格式
    自动生成 64px 和 256px 版本
    """
    # 验证文件类型
    allowed_types = ['image/png', 'image/jpeg', 'image/gif', 'image/x-icon', 'image/webp']
    if file.content_type not in allowed_types:
        raise HTTPException(
            status_code=400,
            detail="不支持的文件格式。请上传 PNG、JPG、GIF、ICO 或 WebP 格式的图片"
        )
    
    # 读取文件内容
    content = await file.read()
    
    if len(content) > 10 * 1024 * 1024:  # 10MB 限制
        raise HTTPException(status_code=400, detail="文件大小不能超过 10MB")
    
    try:
        filename_64, filename_256 = process_icon(content, file.filename)
        return {
            "success": True,
            "message": "图标处理成功",
            "data": {
                "icon_filename": filename_64,
                "icon_64": filename_64,
                "icon_256": filename_256
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"图标处理失败: {str(e)}")


@app.post("/api/shortcuts")
async def create_shortcut(request: Request):
    """
    创建新的自定义快捷方式（兼容 JSON 和 Form 两种请求格式）
    
    成功后会自动更新 config 文件
    """
    # 手动解析 body，兼容前端 content-type 与实际格式不一致的问题
    content_type = request.headers.get("content-type", "")
    raw_body = await request.body()

    if b"=" in raw_body and not raw_body.strip().startswith(b"{"):
        # URL-encoded 表单数据
        from urllib.parse import parse_qs
        params = parse_qs(raw_body.decode("utf-8"))
        title = (params.get("title") or [""])[0]
        url = (params.get("url") or [""])[0]
        protocol = (params.get("protocol") or [""])[0]
        port = (params.get("port") or [""])[0]
        iconFilename = (params.get("iconFilename") or [""])[0]
        allUsers = (params.get("allUsers") or ["true"])[0]
    else:
        # 尝试 JSON
        try:
            data = json.loads(raw_body)
            title = data.get("title", "")
            url = data.get("url", "")
            protocol = data.get("protocol", "")
            port = data.get("port", "")
            iconFilename = data.get("iconFilename", "")
            allUsers = str(data.get("allUsers", True)).lower()
        except Exception:
            raise HTTPException(status_code=400, detail="无法解析请求数据")

    if not title or not url or not iconFilename:
        raise HTTPException(status_code=400, detail="缺少必填字段: title, url, iconFilename")

    config = get_config()
    
    # 生成唯一 ID
    shortcut_id = f"custom_{uuid.uuid4().hex[:8]}"
    entry_key = f"{shortcut_id}.Application"
    
    # 创建新条目
    new_shortcut = {
        "title": title.strip(),
        "icon": f"images/{iconFilename}",
        "type": "url",
        "protocol": protocol.strip(),
        "port": port.strip(),
        "url": url.strip(),
        "allUsers": str(allUsers).lower() == "true"
    }
    
    config[".url"][entry_key] = new_shortcut
    
    # 保存配置
    save_config(config)
    
    # 更新备份
    shortcuts_list = [s for s in config.get(".url", {}).keys() 
                      if "custom_" in s]
    backup_data(shortcuts_list)
    
    # 触发应用重启
    restart_app()
    
    return {
        "success": True,
        "message": "快捷方式创建成功！正在刷新桌面...",
        "data": {
            "id": shortcut_id,
            **new_shortcut
        }
    }


@app.put("/api/shortcuts/{shortcut_id}")
async def update_shortcut(shortcut_id: str, data: ShortcutUpdate):
    """
    更新现有快捷方式的信息
    
    成功后会自动更新 config 文件并重启应用
    """
    entry_key = f"{shortcut_id}.Application"
    config = get_config()
    
    if entry_key not in config.get(".url", {}):
        raise HTTPException(status_code=404, detail="快捷方式不存在")
    
    # 更新字段
    shortcut = config[".url"][entry_key]
    
    if data.title is not None:
        shortcut["title"] = data.title.strip()
    if data.url is not None:
        shortcut["url"] = data.url.strip()
    if data.protocol is not None:
        shortcut["protocol"] = data.protocol.strip()
    if data.port is not None:
        shortcut["port"] = data.port.strip()
    if data.all_users is not None:
        shortcut["allUsers"] = data.all_users
    
    # 保存配置
    save_config(config)
    
    # 触发重启
    restart_app()
    
    return {
        "success": True,
        "message": "快捷方式更新成功！正在刷新桌面...",
        "data": {
            "id": shortcut_id,
            **shortcut
        }
    }


@app.delete("/api/shortcuts/{shortcut_id}")
async def delete_shortcut(shortcut_id: str):
    """
    删除指定的快捷方式及其关联的图标文件
    
    成功后会自动更新 config 文件并重启应用
    """
    entry_key = f"{shortcut_id}.Application"
    config = get_config()
    
    if entry_key not in config.get(".url", {}):
        raise HTTPException(status_code=404, detail="快捷方式不存在")
    
    # 删除关联的图标文件
    shortcut = config[".url"][entry_key]
    icon_path = shortcut.get("icon", "")
    
    if icon_path.startswith("images/icon_custom_"):
        icon_name = icon_path.replace("images/", "")
        
        # 删除 64px 和 256px 版本的图标
        for size_suffix in ["_64.png", "_256.png"]:
            base_name = icon_name.replace("_64.png", "").replace("_256.png", "")
            full_name = f"{base_name}{size_suffix}"
            file_path = IMAGES_DIR / full_name
            
            if file_path.exists():
                file_path.unlink()
                print(f"已删除图标文件: {full_name}")
    
    # 从配置中删除条目
    del config[".url"][entry_key]
    
    # 保存配置
    save_config(config)
    
    # 触发重启
    restart_app()
    
    return {
        "success": True,
        "message": "快捷方式删除成功！正在刷新桌面..."
    }


# ==================== 启动入口 ====================

@app.on_event("startup")
async def startup_event():
    """应用启动时的初始化操作"""
    print("\n[STARTUP] Magic Shortcut Manager starting...")
    
    # 验证关键目录
    if not IMAGES_DIR.exists():
        try:
            IMAGES_DIR.mkdir(parents=True, exist_ok=True)
            print(f"[STARTUP] Created images directory: {IMAGES_DIR}")
        except Exception as e:
            print(f"[ERROR] Failed to create images dir: {e}")
    
    # 检查 config 文件
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                config = json.load(f)
            entries_count = len(config.get('.url', {}))
            print(f"[STARTUP] Config loaded: {entries_count} entries")
        except Exception as e:
            print(f"[WARNING] Config exists but cannot read: {e}")
    else:
        print(f"[WARNING] Config file not found: {CONFIG_FILE}")


if __name__ == "__main__":
    import uvicorn

    print("=" * 60)
    print("  Magic Shortcut Manager - Starting Server")
    print("=" * 60)
    print(f"  Port: {SERVER_PORT}")
    print(f"  Working Dir: {os.getcwd()}")
    print(f"  Python: {sys.executable}")
    print(f"  Version: {sys.version}")
    print("=" * 60)

    try:
        uvicorn.run(
            app,
            host="0.0.0.0",
            port=SERVER_PORT,
            log_level="info",
            access_log=True
        )

        print("[SUCCESS] Server shutdown complete")

    except Exception as e:
        print(f"\n[CRITICAL ERROR] Server failed to start!")
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
