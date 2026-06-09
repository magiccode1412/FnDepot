/**
 * Magic Shortcut Manager - 前端交互逻辑
 */

// 全局状态
let currentShortcuts = [];
let deleteTargetId = null;
let uploadedIconFile = null;

// ==================== 初始化 ====================

document.addEventListener('DOMContentLoaded', () => {
    loadShortcuts();
});

// ==================== API 调用 ====================

async function apiRequest(url, options = {}) {
    try {
        const response = await fetch(url, {
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            ...options
        });

        if (!response.ok) {
            const errorData = await response.json().catch(() => ({}));
            throw new Error(errorData.detail || `请求失败: ${response.status}`);
        }

        return await response.json();
    } catch (error) {
        console.error('API Error:', error);
        throw error;
    }
}

// ==================== 数据操作 ====================

async function loadShortcuts() {
    showStatus('正在加载...', 'info');
    
    try {
        const result = await apiRequest('/api/shortcuts');
        currentShortcuts = result.shortcuts || [];
        
        renderShortcuts();
        updateCount();
        
        hideStatus();
    } catch (error) {
        showStatus('加载失败: ' + error.message, 'error');
    }
}

function renderShortcuts() {
    const grid = document.getElementById('shortcutsGrid');
    const emptyState = document.getElementById('emptyState');

    if (currentShortcuts.length === 0) {
        grid.innerHTML = '';
        emptyState.classList.remove('hidden');
        return;
    }

    emptyState.classList.add('hidden');

    grid.innerHTML = currentShortcuts.map(shortcut => `
        <div class="shortcut-card" data-id="${shortcut.id}">
            <div class="shortcut-header">
                <img class="shortcut-icon" 
                     src="/static/../ui/images/${(shortcut.icon || '').replace('images/', '')}" 
                     alt="${escapeHtml(shortcut.title)}"
                     onerror="this.src='data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 64 64%22><rect fill=%22%23667eea%22 width=221264 height=221264 rx=281212/></svg>'">
                <span class="shortcut-title">${escapeHtml(shortcut.title)}</span>
            </div>
            <div class="shortcut-url">
                ${formatUrl(shortcut)}
            </div>
            <div class="shortcut-actions">
                <button class="btn btn-small btn-edit" onclick="showEditModal('${shortcut.id}')">
                    编辑
                </button>
                <button class="btn btn-small btn-delete" onclick="showDeleteModal('${shortcut.id}')">
                    删除
                </button>
            </div>
        </div>
    `).join('');
}

function formatUrl(shortcut) {
    let url = shortcut.url || '';
    
    // 如果 URL 没有协议前缀，根据配置添加
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
        const protocol = shortcut.protocol || 'https';
        url = `${protocol}://${url}`;
    }
    
    // 添加端口（如果有）
    if (shortcut.port && !url.includes(`:${shortcut.port}`)) {
        url = url.replace(/^https?:\/\/([^\/]+)/, `$1:${shortcut.port}`);
    }

    return url;
}

function updateCount() {
    document.getElementById('shortcutCount').textContent = currentShortcuts.length;
}

// ==================== 弹窗控制 ====================

function showAddModal() {
    document.getElementById('modalTitle').textContent = '添加新快捷方式';
    document.getElementById('submitBtn').textContent = '保存';
    document.getElementById('editId').value = '';
    
    resetForm();
    document.getElementById('modal').classList.remove('hidden');
}

function showEditModal(id) {
    const shortcut = currentShortcuts.find(s => s.id === id);
    if (!shortcut) {
        showStatus('快捷方式不存在', 'error');
        return;
    }

    document.getElementById('modalTitle').textContent = '编辑快捷方式';
    document.getElementById('submitBtn').textContent = '更新';
    document.getElementById('editId').value = id;

    // 填充表单数据
    document.getElementById('title').value = shortcut.title || '';
    document.getElementById('url').value = shortcut.url || '';
    document.getElementById('protocol').value = shortcut.protocol || '';
    document.getElementById('port').value = shortcut.port || '';
    document.getElementById('allUsers').checked = shortcut.allUsers !== false;
    document.getElementById('iconFilename').value = shortcut.icon?.replace('images/', '') || '';

    // 显示已有图标的预览
    if (shortcut.icon) {
        const iconPath = `/static/../ui/images/${shortcut.icon.replace('images/', '')}`;
        document.getElementById('previewImage').src = iconPath;
        document.getElementById('uploadPreview').classList.remove('hidden');
        document.getElementById('uploadPlaceholder').classList.add('hidden');
    } else {
        clearUpload();
    }

    document.getElementById('modal').classList.remove('hidden');
}

function showModal(modalId) {
    document.getElementById(modalId).classList.remove('hidden');
}

function hideModal() {
    document.getElementById('modal').classList.add('hidden');
    resetForm();
}

function showDeleteModal(id) {
    deleteTargetId = id;
    document.getElementById('deleteModal').classList.remove('hidden');
}

function hideDeleteModal() {
    document.getElementById('deleteModal').classList.add('hidden');
    deleteTargetId = null;
}

function resetForm() {
    document.getElementById('shortcutForm').reset();
    document.getElementById('editId').value = '';
    uploadedIconFile = null;
    clearUpload();
}

function clearUpload() {
    document.getElementById('iconFile').value = '';
    document.getElementById('iconFilename').value = '';
    document.getElementById('previewImage').src = '';
    document.getElementById('uploadPreview').classList.add('hidden');
    document.getElementById('uploadPlaceholder').classList.remove('hidden');
    uploadedIconFile = null;
}

// ==================== 表单处理 ====================

async function handleIconUpload(input) {
    const file = input.files[0];
    if (!file) return;

    // 验证文件类型
    const allowedTypes = ['image/png', 'image/jpeg', 'image/gif', 'image/x-icon', 'image/webp'];
    if (!allowedTypes.includes(file.type)) {
        showStatus('不支持的文件格式，请上传 PNG、JPG、GIF、ICO 或 WebP 图片', 'error');
        return;
    }

    // 验证文件大小 (10MB)
    if (file.size > 10 * 1024 * 1024) {
        showStatus('文件大小不能超过 10MB', 'error');
        return;
    }

    // 显示预览
    const reader = new FileReader();
    reader.onload = (e) => {
        document.getElementById('previewImage').src = e.target.result;
        document.getElementById('uploadPreview').classList.remove('hidden');
        document.getElementById('uploadPlaceholder').classList.add('hidden');
        uploadedIconFile = file;
    };
    reader.readAsDataURL(file);

    showStatus('请点击保存按钮完成上传和创建', 'info');
}

async function handleSubmit(event) {
    event.preventDefault();

    const editId = document.getElementById('editId').value;
    const title = document.getElementById('title').value.trim();
    const url = document.getElementById('url').value.trim();
    const protocol = document.getElementById('protocol').value;
    const port = document.getElementById('port').value.trim();
    const allUsers = document.getElementById('allUsers').checked;

    // 基础验证
    if (!title || !url) {
        showStatus('请填写必填字段', 'error');
        return;
    }

    // 图标验证
    let iconFilename = document.getElementById('iconFilename').value;
    
    // 如果是新建或用户重新上传了图标，需要先上传
    if ((!editId || uploadedIconFile) && !uploadedIconFile && !iconFilename) {
        showStatus('请上传图标文件', 'error');
        return;
    }

    try {
        // 禁用提交按钮防止重复提交
        const submitBtn = document.getElementById('submitBtn');
        submitBtn.disabled = true;
        submitBtn.textContent = editId ? '更新中...' : '保存中...';

        // 如果有新上传的图标文件，先上传图标
        if (uploadedIconFile) {
            showStatus('正在上传图标...', 'info');
            
            const formData = new FormData();
            formData.append('file', uploadedIconFile);
            
            const uploadResponse = await fetch('/api/upload-icon', {
                method: 'POST',
                body: formData
            });

            if (!uploadResponse.ok) {
                const errorData = await uploadResponse.json().catch(() => ({}));
                throw new Error(errorData.detail || '图标上传失败');
            }

            const uploadResult = await uploadResponse.json();
            iconFilename = uploadResult.data.icon_filename;
            
            document.getElementById('iconFilename').value = iconFilename;
        }

        // 创建或更新快捷方式
        const formData = new URLSearchParams();
        formData.append('title', title);
        formData.append('url', url);
        formData.append('protocol', protocol);
        formData.append('port', port);
        formData.append('iconFilename', iconFilename);
        formData.append('allUsers', allUsers);

        let response;
        if (editId) {
            // 更新现有快捷方式
            showStatus('正在更新...', 'info');
            response = await apiRequest(`/api/shortcuts/${editId}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    title,
                    url,
                    protocol,
                    port,
                    all_users: allUsers,
                    icon_filename: iconFilename
                })
            });
        } else {
            // 创建新快捷方式
            showStatus('正在创建...', 'info');
            response = await apiRequest('/api/shortcuts', {
                method: 'POST',
                body: formData
            });
        }

        // 成功
        hideModal();
        showStatus(response.message, 'success');
        
        // 提示用户桌面将刷新
        setTimeout(() => {
            showStatus('桌面正在刷新，请稍候...新快捷方式将在几秒后显示', 'info');
        }, 2000);

        // 重新加载数据
        setTimeout(loadShortcuts, 3000);

    } catch (error) {
        showStatus('操作失败: ' + error.message, 'error');
    } finally {
        const submitBtn = document.getElementById('submitBtn');
        submitBtn.disabled = false;
        submitBtn.textContent = editId ? '更新' : '保存';
    }
}

async function confirmDelete() {
    if (!deleteTargetId) return;

    try {
        const deleteBtn = document.getElementById('confirmDeleteBtn');
        deleteBtn.disabled = true;
        deleteBtn.textContent = '删除中...';

        showStatus('正在删除...', 'info');

        const result = await apiRequest(`/api/shortcuts/${deleteTargetId}`, {
            method: 'DELETE'
        });

        hideDeleteModal();
        showStatus(result.message, 'success');

        // 提示刷新
        setTimeout(() => {
            showStatus('桌面正在刷新，已删除的快捷方式将在几秒后消失', 'info');
        }, 2000);

        // 重新加载数据
        setTimeout(loadShortcuts, 3000);

    } catch (error) {
        showStatus('删除失败: ' + error.message, 'error');
    } finally {
        const deleteBtn = document.getElementById('confirmDeleteBtn');
        deleteBtn.disabled = false;
        deleteBtn.textContent = '删除';
    }
}

// 绑定确认删除按钮事件
document.getElementById('confirmDeleteBtn').addEventListener('click', confirmDelete);

// ==================== 工具函数 ====================

function showStatus(message, type = 'info') {
    const statusEl = document.getElementById('statusMessage');
    statusEl.textContent = message;
    statusEl.className = `status-message ${type}`;
    statusEl.classList.remove('hidden');

    // 自动隐藏成功消息
    if (type === 'success') {
        setTimeout(hideStatus, 5000);
    }
}

function hideStatus() {
    document.getElementById('statusMessage').classList.add('hidden');
}

function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// ESC 关闭弹窗
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        hideModal();
        hideDeleteModal();
    }
});
