#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════════
# 米粒儿VPS流量消耗管理工具 - 一键安装脚本
# 官方TG群：https://t.me/mlkjfx6
# GitHub：https://github.com/charmtv/mlnb-xh
# ═══════════════════════════════════════════════════════════════════════════════════

# 颜色配置
PRIMARY="\e[38;5;39m"
SUCCESS="\e[38;5;46m"
WARNING="\e[38;5;226m"
DANGER="\e[38;5;196m"
INFO="\e[38;5;117m"
WHITE="\e[97m"
RESET="\e[0m"

# 配置常量
REPO_URL="https://github.com/charmtv/VPS"
SCRIPT_URL="https://raw.githubusercontent.com/charmtv/VPS/main/milier_flow_latest.sh"
INSTALL_DIR="/root"
SCRIPT_NAME="milier_flow.sh"
SHORTCUT_NAME="xh"

# 显示标题
show_header() {
    clear
    echo
    echo -e "${PRIMARY}                    米粒儿VPS流量消耗管理工具${RESET}"
    echo -e "${INFO}                          一键安装脚本${RESET}"
    echo -e "${PRIMARY}$(printf '%*s' 70 | tr ' ' '=')"
    echo
}

# 错误退出函数
error_exit() {
    echo -e "${DANGER}❌ $1${RESET}" >&2
    exit 1
}

# 成功信息函数
success_msg() {
    echo -e "${SUCCESS}✅ $1${RESET}"
}

# 信息提示函数
info_msg() {
    echo -e "${INFO}ℹ️  $1${RESET}"
}

# 警告信息函数
warning_msg() {
    echo -e "${WARNING}⚠️  $1${RESET}"
}

# 检查系统环境
check_environment() {
    info_msg "正在检查系统环境..."
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要root权限运行，请使用: sudo bash $0"
    fi
    
    # 检查系统类型
    if [[ ! -f /etc/os-release ]]; then
        error_exit "不支持的操作系统，仅支持Linux系统"
    fi
    
    # 检查必要命令
    local required_commands=("curl" "systemctl" "chmod" "nproc")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error_exit "缺少必要命令: $cmd"
        fi
    done
    
    success_msg "环境检查通过"
}

# 下载主脚本
download_script() {
    info_msg "正在下载米粒儿主脚本..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 下载脚本文件
    if curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"; then
        success_msg "脚本下载成功"
    else
        error_exit "脚本下载失败，请检查网络连接"
    fi
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    success_msg "脚本权限设置完成"
}

# 创建快捷键
create_global_shortcut() {
    info_msg "正在创建全局快捷键 '$SHORTCUT_NAME'..."
    
    local shortcut_path="/usr/local/bin/$SHORTCUT_NAME"
    
    cat > "$shortcut_path" << EOF
#!/bin/bash
# 米粒儿VPS流量管理工具快捷启动脚本
cd "$INSTALL_DIR"
bash "$INSTALL_DIR/$SCRIPT_NAME" "\$@"
EOF
    
    chmod +x "$shortcut_path"
    success_msg "快捷键创建成功"
}

# 检查安装结果
verify_installation() {
    info_msg "正在验证安装..."
    
    # 检查脚本文件
    if [[ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        error_exit "主脚本文件验证失败"
    fi
    
    # 检查快捷键
    if [[ ! -f "/usr/local/bin/$SHORTCUT_NAME" ]]; then
        error_exit "快捷键验证失败"
    fi
    
    # 检查权限
    if [[ ! -x "$INSTALL_DIR/$SCRIPT_NAME" ]] || [[ ! -x "/usr/local/bin/$SHORTCUT_NAME" ]]; then
        error_exit "文件权限验证失败"
    fi
    
    success_msg "安装验证通过"
}

# 显示安装完成信息
show_completion() {
    echo
    echo -e "${SUCCESS}🎉 米粒儿VPS流量消耗管理工具安装完成！${RESET}"
    echo
    echo -e "${PRIMARY}使用方法：${RESET}"
    echo -e "  ${WHITE}• 快捷启动：${PRIMARY}$SHORTCUT_NAME${RESET}"
    echo -e "  ${WHITE}• 完整路径：${INFO}bash $INSTALL_DIR/$SCRIPT_NAME${RESET}"
    echo
    echo -e "${PRIMARY}功能特点：${RESET}"
    echo -e "  ${WHITE}• 智能多线程流量消耗${RESET}"
    echo -e "  ${WHITE}• 实时流量监控与统计${RESET}"
    echo -e "  ${WHITE}• 系统服务后台运行${RESET}"
    echo -e "  ${WHITE}• 配置参数持久化保存${RESET}"
    echo
    echo -e "${PRIMARY}官方支持：${RESET}"
    echo -e "  ${WHITE}• TG群：${INFO}https://t.me/mlkjfx6${RESET}"
    echo -e "  ${WHITE}• GitHub：${INFO}$REPO_URL${RESET}"
    echo
    echo -e "${WARNING}现在就可以输入 '${PRIMARY}$SHORTCUT_NAME${WARNING}' 开始使用！${RESET}"
    echo
}

# 主安装流程
main() {
    show_header
    
    echo -e "${INFO}正在安装米粒儿VPS流量消耗管理工具...${RESET}"
    echo -e "${INFO}GitHub项目：${WHITE}$REPO_URL${RESET}"
    echo
    
    check_environment
    download_script
    create_global_shortcut
    verify_installation
    show_completion
}

# 执行安装
main "$@"
