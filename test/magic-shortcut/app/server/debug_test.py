#!/usr/bin/env python3
"""
Magic Shortcut Manager - 调试/测试脚本
用于验证环境和依赖是否正确安装
"""

import sys
import os
from pathlib import Path

def check_python_version():
    """检查 Python 版本"""
    version = sys.version_info
    print(f"✓ Python 版本: {version.major}.{version.minor}.{version.micro}")
    
    if version.major < 3 or (version.major == 3 and version.minor < 8):
        print("⚠ 警告：Python 版本过低，建议使用 3.8+")
        return False
    return True


def check_imports():
    """检查必要的依赖包"""
    packages = [
        ('fastapi', 'FastAPI'),
        ('uvicorn', 'Uvicorn'),
        ('pydantic', 'Pydantic'),
    ]
    
    optional_packages = [
        ('PIL', 'Pillow (图像处理)'),
        ('multipart', 'Multipart (文件上传)'),
    ]
    
    print("\n检查必需依赖...")
    for package, name in packages:
        try:
            __import__(package)
            print(f"✓ {name} 已安装")
        except ImportError as e:
            print(f"✗ 错误：{name} 未安装 - {e}")
            return False
    
    print("\n检查可选依赖...")
    for package, name in optional_packages:
        try:
            __import__(package)
            print(f"✓ {name} 已安装")
        except ImportError:
            print(f"⚠ 警告：{name} 未安装（部分功能不可用）")
    
    return True


def check_paths():
    """检查关键路径"""
    trim_appdest = os.environ.get('TRIM_APPDEST')
    
    print(f"\n环境变量:")
    print(f"  TRIM_APPDEST: {trim_appdest or '(未设置)'}")
    print(f"  TRIM_PKGVAR: {os.environ.get('TRIM_PKGVAR', '(未设置)')}")
    print(f"  TRIM_DATA_SHARE_PATHS: {os.environ.get('TRIM_DATA_SHARE_PATHS', '(未设置)')}")
    
    if not trim_appdest:
        print("⚠ 警告：TRIM_APPDEST 未设置，使用当前目录")
        base_dir = Path(__file__).parent
    else:
        base_dir = Path(trim_appdest)
    
    paths = {
        '应用目录': base_dir,
        'Server 目录': base_dir / "server",
        'UI 目录': base_dir / "ui",
        'Config 文件': base_dir / "ui/config",
        'Images 目录': base_dir / "ui/images",
        '静态文件目录': base_dir / "server/static",
    }
    
    print("\n检查路径:")
    all_exist = True
    for name, path in paths.items():
        exists = path.exists()
        status = "✓" if exists else "✗"
        print(f"  {status} {name}: {path}")
        
        # 显示额外信息
        if exists and path.is_file():
            size = path.stat().st_size
            print(f"      大小: {size} bytes")
        elif exists and path.is_dir():
            items = list(path.iterdir())
            print(f"      包含 {len(items)} 个项目")
        
        if not exists and name in ['Config 文件']:
            all_exist = False
    
    return all_exist


def test_fastapi_import():
    """测试能否正常导入和创建 FastAPI 实例"""
    print("\n测试 FastAPI 导入...")
    try:
        from fastapi import FastAPI
        app = FastAPI(title="Test")
        print("✓ FastAPI 实例创建成功")
        return True
    except Exception as e:
        print(f"✗ FastAPI 测试失败: {e}")
        return False


def main():
    """运行所有检查"""
    print("=" * 60)
    print("  Magic Shortcut Manager - 环境检测")
    print("=" * 60)
    
    results = []
    
    results.append(("Python 版本", check_python_version()))
    results.append(("依赖包", check_imports()))
    results.append(("文件路径", check_paths()))
    results.append(("FastAPI", test_fastapi_import()))
    
    print("\n" + "=" * 60)
    print("  检测结果汇总")
    print("=" * 60)
    
    all_passed = True
    for name, passed in results:
        status = "✅ 通过" if passed else "❌ 失败"
        print(f"  {name}: {status}")
        if not passed:
            all_passed = False
    
    print()
    if all_passed:
        print("🎉 所有检查通过！可以启动服务了。")
        print("\n启动命令:")
        print(f"  cd {Path(__file__).parent}")
        print("  python -m uvicorn main:app --unix-socket ./test.sock")
        return 0
    else:
        print("⚠️  存在问题需要修复！")
        print("\n建议操作:")
        print("  1. 检查 Python 版本是否 >= 3.8")
        print("  2. 运行: pip install -r requirements.txt")
        print("  3. 确保所有必要目录已创建")
        print("  4. 设置正确的环境变量")
        return 1


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
