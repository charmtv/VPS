# 🚀 米粒儿VPS流量消耗管理工具

[![GitHub](https://img.shields.io/badge/GitHub-charmtv/VPS-blue?logo=github)](https://github.com/charmtv/VPS)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash)](https://www.gnu.org/software/bash/)

专业的VPS流量消耗管理工具，支持多线程并发下载、实时流量监控、系统服务集成等功能。

## ⚡ 一键安装

### 方法1：使用curl（推荐）
```bash
curl -fsSL https://raw.githubusercontent.com/charmtv/VPS/main/install.sh | sudo bash
```

### 方法2：使用wget
```bash
wget -qO- https://raw.githubusercontent.com/charmtv/VPS/main/install.sh | sudo bash
```

### 方法3：手动安装
```bash
# 下载安装脚本
wget https://raw.githubusercontent.com/charmtv/VPS/main/install.sh
chmod +x install.sh
sudo bash install.sh
```

## 🎯 快速开始

安装完成后，直接输入快捷键启动：
```bash
xh
```

## 📋 功能特点

- ✅ **智能快捷键管理** - 自动创建全局快捷键
- ✅ **实时流量监控** - 彩色进度条显示网络流量
- ✅ **多线程下载** - 基于CPU核心数智能推荐线程数
- ✅ **系统服务集成** - 使用systemd管理后台服务
- ✅ **配置持久化** - 自动保存上次使用的配置
- ✅ **一键卸载** - 完全清理所有文件和服务
- ✅ **网络接口检测** - 自动检测并选择网络接口
- ✅ **安全验证** - 完整的权限和环境检查

## 🎮 主要功能

| 功能 | 描述 |
|------|------|
| **启动流量消耗服务** | 配置URL和线程数开始消耗流量 |
| **停止/重启服务** | 灵活控制服务状态 |
| **实时流量监控** | 美观的实时流量监控界面 |
| **快捷键管理** | 自定义快捷键名称 |
| **日志查看** | 查看服务运行日志 |
| **完全卸载** | 一键清理所有组件 |

## 📊 监控界面预览

```
                                实时流量监控
                          网络接口：eth0
================================================================================

下载：156.32 MB/s   [████████████████████████████████████████░░░░░░░░░░]   累计：15.67 GB  
上传：12.45 MB/s    [██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]   累计：1.23 GB   
运行时长：02:15:30 | 平均：下载 142.58 MB/s 上传 10.87 MB/s
```

## 🛠️ 系统要求

- **操作系统**：Linux (Ubuntu/Debian/CentOS/RedHat等)
- **权限**：Root权限
- **网络**：稳定的互联网连接
- **依赖**：curl, systemctl, nproc等基础命令

## 📝 使用说明

## 🔄 同步更新到仓库

如果直接克隆了本仓库，保持最新只需在项目根目录执行：

```bash
git pull origin main
```

如果您在自己的 fork 中开发，建议按以下步骤同步上游更新：

```bash
# 添加上游远程（只需执行一次）
git remote add upstream https://github.com/charmtv/VPS.git

# 获取上游最新提交
git fetch upstream

# 切换到本地主分支并合并上游
git checkout main
git merge upstream/main

# 将同步后的主分支推送到您的 fork
git push origin main
```

随后可在自己的功能分支上继续开发：

```bash
git checkout -b feature/my-change
```

### 基本操作
```bash
# 启动工具
xh

# 直接运行主脚本
bash /root/milier_flow.sh
```

### 服务管理
```bash
# 查看服务状态
systemctl status milier_flow

# 手动启停服务
systemctl start milier_flow
systemctl stop milier_flow
```

### 配置文件位置
```
/root/milier_config.conf      # 主配置文件
/root/milier_shortcut.conf    # 快捷键配置
/root/milier_flow.log         # 运行日志
```

## 🔧 高级配置

### 自定义快捷键
在主菜单中选择 `6) 快捷键管理` 可以：
- 重新安装快捷键
- 自定义快捷键名称
- 删除快捷键

### 线程数配置
- 工具会根据CPU核心数自动推荐线程数
- 推荐值：CPU核心数 × 2
- 最大值：CPU核心数 × 4

### URL配置
默认使用Cloudflare测速链接，也可以配置其他下载链接：
```
https://speed.cloudflare.com/__down?bytes=104857600  # 100MB测试文件
```

## 🗑️ 完全卸载

在主菜单选择 `7) 卸载全部服务`，或运行：
```bash
bash /root/milier_uninstall.sh
```

## 🔍 故障排除

### 快捷键无反应
1. 检查快捷键是否存在：`ls -la /usr/local/bin/xh`
2. 检查PATH环境：`echo $PATH | grep /usr/local/bin`
3. 手动测试：`/usr/local/bin/xh`
4. 重新安装快捷键：在主菜单选择快捷键管理

### 服务无法启动
1. 检查日志：`journalctl -u milier_flow -f`
2. 检查权限：确保以root权限运行
3. 检查网络：确保能访问下载URL
4. 重新安装：重新运行安装脚本

### 监控显示错误
1. 检查网络接口：`ip link show`
2. 重新选择接口：在主菜单中重新配置
3. 检查权限：确保有读取网络统计的权限

## 📞 支持与反馈

- 🔗 **官方TG群**：[https://t.me/mlkjfx6](https://t.me/mlkjfx6)
- 🌐 **官方博客**：[https://ooovps.com](https://ooovps.com)
- 🏛️ **技术论坛**：[https://nodeloc.com](https://nodeloc.com)
- 💻 **GitHub项目**：[https://github.com/charmtv/VPS](https://github.com/charmtv/VPS)

## 📜 开源协议

本项目采用 MIT 协议开源，详见 [LICENSE](LICENSE) 文件。

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request 来改进这个项目！

---

**⭐ 如果这个工具对您有帮助，请给我们一个Star支持！**
