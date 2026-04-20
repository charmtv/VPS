# 🚀 米粒儿VPS流量消耗管理工具 v3.0

[![GitHub](https://img.shields.io/badge/GitHub-charmtv/VPS-blue?logo=github)](https://github.com/charmtv/VPS)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-3.0-brightgreen)](https://github.com/charmtv/VPS)

专业的VPS流量消耗管理工具，支持多线程并发下载、实时流量监控、流量目标管理、网络测速、系统服务集成等功能。

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
- 🆕 **流量目标管理** - 设置流量消耗目标，达标自动停止
- 🆕 **多URL预设** - 内置多种下载源（100MB/1GB/10GB）

## 功能菜单

```bash
  ═════════════════════════════════════════════════════════
           米粒儿VPS流量消耗管理工具  v3.0
              官方TG群: https://t.me/mlkjfx6
  ═════════════════════════════════════════════════════════

  [服务控制]
   [1] 启动流量消耗服务
   [2] 停止流量消耗服务
   [3] 重启流量消耗服务
   [4] 流量消耗目标设置          NEW

  [监控工具]
   [5] 实时流量监控
   [6] 高级流量监控
   [7] 监控功能诊断
   [8] 网络速度测试              NEW

  [系统管理]
   [9] 查看服务日志
   [A] 快捷键管理
   [B] 检查脚本更新
   [U] 卸载全部服务

   [0] 退出程序
```

## 监控界面预览

```
                                实时流量监控
                          网络接口：eth0
================================================================================

下载：156.32 MB/s   [████████████████████████████████████████░░░░░░░░░░]   累计：15.67 GB
上传：12.45 MB/s    [██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]   累计：1.23 GB
运行时长：02:15:30 | 平均：下载 142.58 MB/s 上传 10.87 MB/s
```

## 系统要求

- **操作系统**：Linux (Ubuntu/Debian/CentOS/RedHat/Arch等)
- **权限**：Root权限
- **网络**：稳定的互联网连接
- **依赖**：curl, systemctl, nproc等基础命令（自动安装）

## 使用说明

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
/root/milier_target.conf      # 流量目标配置
/root/milier_flow.log         # 运行日志
```

## 高级配置

### 下载URL预设
启动服务时可选择预设URL（均为境外节点）：
| 选项 | 节点 | 说明 |
|------|------|------|
| [1] | 香港 Datapacket 100MB | 推荐，低延迟 |
| [2] | 日本东京 Datapacket 100MB | 亚洲优选 |
| [3] | 新加坡 OVH 1GB | 大文件模式 |
| [4] | 德国 Hetzner 1GB | 欧洲高速 |
| [5] | 美西洛杉矶 Datapacket 1GB | 北美 |
| [6] | 法国 OVH 10GB | 超大文件 |
| [7] | 上次使用 | 自动记忆上次配置 |
| [8] | 自定义URL | 手动输入任意下载链接 |

### 流量目标管理
在菜单中选择 `[4] 流量消耗目标设置` 可以：
- 设置流量消耗目标（单位：GB）
- 查看当前消耗进度（进度条显示）
- 启用自动停止（达到目标后自动停止服务）

### 自定义快捷键
在主菜单中选择 `[A] 快捷键管理` 可以：
- 重新安装快捷键
- 自定义快捷键名称
- 删除快捷键

### 线程数配置
- 工具会根据CPU核心数自动推荐线程数
- 推荐值：CPU核心数 × 2
- 最大值：CPU核心数 × 4

## 🗑️ 完全卸载

在主菜单选择 `[U] 卸载全部服务`，或运行：
```bash
bash /root/milier_uninstall.sh
```

## 🔍 故障排除

### 快捷键无反应
1. 检查快捷键是否存在：`ls -la /usr/local/bin/xh`
2. 检查PATH环境：`echo $PATH | grep /usr/local/bin`
3. 手动测试：`/usr/local/bin/xh`
4. 重新安装快捷键：在主菜单选择 `[A] 快捷键管理`

### 服务无法启动
1. 检查日志：`journalctl -u milier_flow -f`
2. 检查权限：确保以root权限运行
3. 检查网络：确保能访问下载URL
4. 重新安装：重新运行安装脚本

### 监控显示错误
1. 运行 `[7] 监控功能诊断` 自动检测问题
2. 检查网络接口：`ip link show`
3. 检查权限：确保有读取网络统计的权限

## 📌 v3.0 更新日志

- 🎨 **全新交互菜单** - 分组式布局，更清晰直观
- 🎯 **流量目标管理** - 设置消耗目标，支持自动停止
- 🌐 **网络速度测试** - 一键测速评估网络性能
- 📦 **多URL预设** - 内置100MB/1GB/10GB多种下载源
- 🐛 **修复systemd配置** - 用户修改URL/线程数后正确更新服务
- 🐛 **修复备份恢复** - 更新失败时能正确恢复备份
- 🐛 **修复除零错误** - 监控数据保存时的除零保护
- 🐛 **修复刷新间隔** - 支持1-10秒完整范围
- ⚡ **优化网络检测** - 使用Cloudflare替代Google进行连通性检查
- 📋 **版本号管理** - 统一版本常量，便于维护

## 📞 支持与反馈

- 🔗 **官方TG群**：[https://t.me/mlkjfx6](https://t.me/mlkjfx6)
- 🌐 **官方博客**：[https://ooovps.com](https://ooovps.com)
- 💻 **GitHub项目**：[https://github.com/charmtv/VPS](https://github.com/charmtv/VPS)

## 📜 开源协议

本项目采用 MIT 协议开源，详见 [LICENSE](LICENSE) 文件。

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request 来改进这个项目！

---

**⭐ 如果这个工具对您有帮助，请给我们一个Star支持！**
