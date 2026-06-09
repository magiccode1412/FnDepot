# 🔧 Magic Shortcut Manager - 故障排除指南

## ❌ 问题现象
- 安装后打开应用显示 **Bad Gateway**
- 应用启动后立即停止
- 无法访问管理界面

---

## ✅ 已修复的关键问题

### 1️⃣ Uvicorn 启动参数冲突（根本原因）
**问题**：
```bash
# ❌ 错误的命令（已修复）
$VENV_DIR/bin/uvicorn main:app --unix-socket $SOCKET_PATH --host 0.0.0.0
```

**原因**：`--host` 和 `--unix-socket` 参数冲突，导致 uvicorn 启动失败

**修复**：
```bash
# ✅ 正确的命令
$VENV_DIR/bin/python3 -m uvicorn main:app \
    --unix-socket "$SOCKET_PATH" \
    --workers 1 \
    --log-level info
```

**文件位置**: `cmd/main` (第 85-90 行)

---

### 2️⃣ 缺乏错误处理和日志
**问题**：
- 启动失败无任何提示
- Socket 未创建原因不明
- 进程崩溃无法排查

**修复**：
- ✅ 添加详细启动日志（环境变量、路径、PID）
- ✅ 检测进程存活状态（防止僵尸进程）
- ✅ 超时自动检测并报告错误
- ✅ 记录最后 20 行日志便于排查

**文件位置**: `cmd/main`

---

### 3️⃣ FastAPI 导入失败处理
**问题**：
- 依赖未安装时应用直接崩溃
- 路径不存在导致异常
- 无友好的错误信息

**修复**：
- ✅ try-except 包裹所有导入操作
- ✅ 自动创建缺失的目录
- ✅ 启动时打印详细的环境信息
- ✅ startup 事件验证关键资源

**文件位置**: `server/main.py`

---

### 4️⃣ 安装脚本健壮性不足
**问题**：
- venv 创建失败未检测
- pip 安装无重试机制
- 权限设置可能失败

**修复**：
- ✅ 验证 Python 和 venv 可用性
- ✅ pip 安装最多重试 3 次
- ✅ 验证关键依赖安装结果
- ✅ 分步骤显示安装进度
- ✅ 设置正确的目录权限

**文件位置**: `cmd/install_callback`

---

## 🧪 测试和验证方法

### 方法 1：使用调试脚本测试环境
```bash
cd /workspace/test/magic-shortcut/server
python3 debug_test.py
```

**预期输出**：
```
============================================================
  Magic Shortcut Manager - 环境检测
============================================================
✓ Python 版本: 3.12.x

检查必需依赖...
✓ FastAPI 已安装
✓ Uvicorn 已安装
✓ Pydantic 已安装

检查可选依赖...
✓ Pillow (图像处理) 已安装
...

🎉 所有检查通过！可以启动服务了。
```

### 方法 2：手动启动服务进行测试
```bash
cd /workspace/test/magic-shortcut/server

# 创建虚拟环境（如果需要）
python3 -m venv venv

# 安装依赖
./venv/bin/pip install -r requirements.txt

# 手动启动服务（用于调试）
TRIM_APPDEST=/workspace/test/magic-shortcut/app \
./venv/bin/python -m uvicorn main:app \
  --unix-socket /tmp/test_shortcut.sock \
  --log-level debug
```

**预期输出**：
```
============================================================
  Magic Shortcut Manager - Starting Server
============================================================
  Socket Path: /tmp/test_shortcut.sock
  Working Dir: /workspace/test/magic-shortcut/server
  ...
[STARTUP] Magic Shortcut Manager starting...
[STARTUP] Config loaded: 1 entries
INFO:     Started server process
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on unix socket /tmp/test_shortcut.sock
```

### 方法 3：测试 Unix Socket 连接
```bash
# 在另一个终端测试连接
curl --unix-socket /tmp/test_shortcut.sock http://localhost/
```

**预期返回**：
```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>...快捷方式管理器...</head>
<body>...</body>
</html>
```

---

## 📋 完整的重新部署流程

如果之前已经安装过旧版本，建议按以下步骤完全重新部署：

### Step 1: 卸载旧版本
```bash
# 在飞牛设备上卸载应用（保留数据）
# 或者在应用中心点击"卸载"
```

### Step 2: 重新打包
```bash
cd /workspace/test/magic-shortcut

# 清理旧的打包产物（如果有）
rm -f *.fpk

# 重新打包
fnpack build
```

### Step 3: 安装新版本
```bash
# 使用 CLI 安装
appcenter-cli install-local magic-shortcut.fpk

# 或者通过应用中心上传 .fpk 文件
```

### Step 4: 验证安装
```bash
# 检查服务是否运行
appcenter-cli status magic-shortcut

# 应该显示 "running"
```

### Step 5: 测试访问
在浏览器中访问：
```
http://<飞牛IP>:5666/app/magic-shortcut
```

**应该看到**：快捷方式管理器界面（不是 Bad Gateway）

---

## 🐛 常见问题 FAQ

### Q1: 还是显示 Bad Gateway 怎么办？
**A**: 按以下步骤排查：
1. 查看日志文件：`cat /var/apps/magic-shortcut/var/info.log`
2. 检查 socket 是否存在：`ls -la /var/apps/magic-shortcut/target/shortcut.sock`
3. 手动运行调试脚本：`cd /var/apps/magic-shortcut/server && ./venv/bin/python debug_test.py`
4. 查看进程状态：`ps aux | grep uvicorn`

### Q2: 日志显示 "Virtual environment not found"
**A**: install_callback 执行失败，可能的原因：
- Python 不可用或版本不对
- 磁盘空间不足
- 权限问题

**解决**：
```bash
# 检查 Python
python3 --version

# 手动创建虚拟环境
cd /var/apps/magic-shortcut/target/server
python3 -m venv venv

# 安装依赖
./venv/bin/pip install -r requirements.txt

# 重启应用
appcenter-cli restart magic-shortcut
```

### Q3: 权限错误 "Permission denied"
**A**: 文件权限不正确，执行以下命令修复：
```bash
sudo chown -R magic-shortcut:magic-shortcut /var/apps/magic-shortcut/
sudo chmod -R 755 /var/apps/magic-shortcut/ui/images/
```

### Q4: 依赖安装超时或失败
**A**: 网络问题或 PyPI 源不可达，尝试：
```bash
# 使用国内镜像源
./venv/bin/pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# 重新安装
./venv/bin/pip install -r requirements.txt
```

### Q5: 应用启动后几秒就停止
**A**: 查看 PID 文件和日志：
```bash
cat /var/apps/magic-shortcut/var/app.pid
tail -100 /var/apps/magic-shortcut/var/info.log
```
根据日志中的错误信息进行针对性修复。

---

## 📞 需要帮助？

如果以上方法都无法解决问题，请收集以下信息：

1. **完整日志**：
   ```bash
   cat /var/apps/magic-shortcut/var/info.log
   ```

2. **系统信息**：
   ```bash
   cat /etc/os-release
   python3 --version
   ```

3. **文件列表**：
   ```bash
   ls -lhR /var/apps/magic-shortcut/
   ```

4. **进程状态**：
   ```bash
   ps aux | grep -E "(uvicorn|magic-shortcut)"
   ```

将这些信息提供给开发者进行进一步分析。

---

## ✨ 更新历史

### v1.0.1 (2026-06-09)
- ✅ 修复 uvicorn 启动参数冲突导致的 Bad Gateway
- ✅ 增强错误处理和日志记录
- ✅ 改进安装脚本的健壮性
- ✅ 添加调试辅助工具 (debug_test.py)
- ✅ 增加 startup 事件验证
- ✅ 完善故障排除文档

---

**祝使用愉快！** 🎉
