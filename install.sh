#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════════
# 米粒儿 VPS 流量消耗管理工具 - 一键安装脚本（通用版）
# ═══════════════════════════════════════════════════════════════════════════════════

######################## 颜色配置 ########################
PRIMARY="\e[38;5;39m"
SUCCESS="\e[38;5;46m"
WARNING="\e[38;5;226m"
DANGER="\e[38;5;196m"
INFO="\e[38;5;117m"
WHITE="\e[97m"
RESET="\e[0m"

######################## 配置常量 ########################
REPO_URL="https://github.com/charmtv/VPS"
SCRIPT_URL="https://raw.githubusercontent.com/charmtv/VPS/main/milier_flow_latest.sh"
INSTALL_DIR="/root"
SCRIPT_NAME="milier_flow_latest.sh"
SHORTCUT_NAME="xh"

######################## 工具函数 ########################
error_exit() {
    echo -e "${DANGER}❌ $1${RESET}"
    exit 1
}

info_msg() {
    echo -e "${INFO}ℹ️  $1${RESET}"
}

success_msg() {
    echo -e "${SUCCESS}✅ $1${RESET}"
}

warning_msg() {
    echo -e "${WARNING}⚠️  $1${RESET}"
}

######################## 标题 ########################
show_header() {
    clear
    echo
    echo -e "${PRIMARY}          米粒儿 VPS 流量管理工具${RESET}"
    echo -e "${INFO}               一键安装脚本${RESET}"
    echo -e "${PRIMARY}$(printf '%*s' 60 | tr ' ' '=')${RESET}"
    echo
}

######################## 系统检测 ########################
detect_system() {
    if [[ ! -f /etc/os-release ]]; then
        error_exit "无法识别系统类型"
    fi
    source /etc/os-release
    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"
    info_msg "检测到系统：$PRETTY_NAME"
}

######################## 依赖安装 ########################
install_dependencies() {
    info_msg "正在检查并安装必要依赖..."

    local cmds=("curl" "wget" "nproc" "free" "df" "ps" "grep" "awk" "sed")
    local missing=()

    for c in "${cmds[@]}"; do
        command -v "$c" &>/dev/null || missing+=("$c")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        success_msg "依赖已满足"
        return
    fi

    info_msg "需要安装依赖：${missing[*]}"

    case "$OS_ID" in
        ubuntu|debian|linuxmint)
            apt-get update -y &>/dev/null
            apt-get install -y curl wget procps coreutils &>/dev/null
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf &>/dev/null; then
                dnf install -y curl wget procps-ng coreutils &>/dev/null
            else
                yum install -y curl wget procps-ng coreutils &>/dev/null
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm curl wget procps-ng coreutils &>/dev/null
            ;;
        alpine)
            apk add --no-cache bash curl wget coreutils procps &>/dev/null
            ;;
        *)
            warning_msg "未知系统，请手动安装：${missing[*]}"
            ;;
    esac

    success_msg "依赖安装完成"
}

######################## 下载主脚本 ########################
download_script() {
    info_msg "正在下载主程序..."

    mkdir -p "$INSTALL_DIR" || error_exit "无法创建目录 $INSTALL_DIR"

    if ! curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"; then
        error_exit "下载主脚本失败"
    fi

    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    success_msg "主脚本下载完成"
}

######################## 创建快捷键 ########################
create_shortcut() {
    info_msg "创建快捷启动命令：$SHORTCUT_NAME"

    cat > "/usr/local/bin/$SHORTCUT_NAME" <<EOF
#!/bin/bash
cd "$INSTALL_DIR"
bash "$INSTALL_DIR/$SCRIPT_NAME"
EOF

    chmod +x "/usr/local/bin/$SHORTCUT_NAME"
    success_msg "快捷键创建成功"
}

######################## 完成提示 ########################
show_done() {
    echo
    echo -e "${SUCCESS}🎉 安装完成！${RESET}"
    echo
    echo -e "${WHITE}使用方法：${RESET}"
    echo -e "  • 输入 ${PRIMARY}$SHORTCUT_NAME${RESET} 启动工具"
    echo -e "  • 或运行 ${INFO}bash $INSTALL_DIR/$SCRIPT_NAME${RESET}"
    echo
    echo -e "${WHITE}主要功能：${RESET}"
    echo -e "  • 自定义流量上限（GB）"
    echo -e "  • 自动停止，避免超额"
    echo -e "  • 实时流量统计"
    echo -e "  • 一键启动 / 停止"
    echo
    echo -e "${INFO}项目地址：${WHITE}$REPO_URL${RESET}"
    echo
}

######################## 主流程 ########################
main() {
    [[ $EUID -ne 0 ]] && error_exit "请使用 root 权限运行"

    show_header
    detect_system
    install_dependencies
    download_script
    create_shortcut

    # 初始化配置文件
    touch /root/milier_config.conf

    show_done
}

main "$@"
