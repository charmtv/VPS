#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════════
# 米粒儿VPS流量消耗管理工具 - 一键安装脚本
# 米粒VPS交流群：https://t.me/mlkjfx66
# ═══════════════════════════════════════════════════════════════════════════════════

# 颜色配置
SUCCESS="\e[32m"
WARNING="\e[33m"
DANGER="\e[31m"
INFO="\e[36m"
RESET="\e[0m"

# 配置常量
SCRIPT_URL="https://xh.813099.xyz/milier_flow_latest.sh"
SCRIPT_FALLBACK_URL="https://raw.githubusercontent.com/charmtv/VPS/main/milier_flow_latest.sh"
INSTALL_DIR="/root"
SCRIPT_NAME="milier_flow.sh"
SHORTCUT_NAME="xh"

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

# 检测系统类型
detect_system() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
        info_msg "检测到系统：$PRETTY_NAME"
    else
        error_exit "不支持的操作系统，仅支持Linux系统"
    fi
}

# 更新系统包管理器
update_package_manager() {
    info_msg "正在更新系统包管理器..."
    
    case "$OS_ID" in
        ubuntu|debian|linuxmint)
            apt-get update -y &>/dev/null || warning_msg "包管理器更新失败，继续安装..."
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v yum &>/dev/null; then
                yum update -y &>/dev/null || warning_msg "包管理器更新失败，继续安装..."
            elif command -v dnf &>/dev/null; then
                dnf update -y &>/dev/null || warning_msg "包管理器更新失败，继续安装..."
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm &>/dev/null || warning_msg "包管理器更新失败，继续安装..."
            ;;
        opensuse*)
            zypper refresh -y &>/dev/null || warning_msg "包管理器更新失败，继续安装..."
            ;;
        *)
            warning_msg "未知系统类型，跳过包管理器更新"
            ;;
    esac
    
    success_msg "包管理器更新完成"
}

# 安装依赖包
install_dependencies() {
    info_msg "正在安装必要依赖..."
    
    local packages_to_install=()
    local required_commands=("curl" "wget" "systemctl" "nproc" "free" "df" "ps" "grep" "awk" "sed" "bc")
    
    # 检查缺失的命令
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            case "$cmd" in
                "curl") packages_to_install+=("curl") ;;
                "wget") packages_to_install+=("wget") ;;
                "systemctl") packages_to_install+=("systemd") ;;
                "nproc"|"free"|"df"|"ps") packages_to_install+=("procps") ;;
                "grep"|"awk"|"sed") packages_to_install+=("coreutils") ;;
                "bc") packages_to_install+=("bc") ;;
            esac
        fi
    done
    
    # 如果有缺失的包，则安装
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        info_msg "需要安装: ${packages_to_install[*]}"
        
        case "$OS_ID" in
            ubuntu|debian|linuxmint)
                # Debian系列特殊处理
                if [[ "$OS_ID" == "debian" && "${OS_VERSION%%.*}" -ge 13 ]]; then
                    # Debian 13+ 特殊处理
                    apt-get install -y "${packages_to_install[@]}" ca-certificates gnupg lsb-release &>/dev/null
                else
                    apt-get install -y "${packages_to_install[@]}" &>/dev/null
                fi
                ;;
            centos|rhel|fedora|rocky|almalinux)
                if command -v yum &>/dev/null; then
                    yum install -y "${packages_to_install[@]}" &>/dev/null
                elif command -v dnf &>/dev/null; then
                    dnf install -y "${packages_to_install[@]}" &>/dev/null
                fi
                ;;
            arch|manjaro)
                pacman -S --noconfirm "${packages_to_install[@]}" &>/dev/null
                ;;
            opensuse*)
                zypper install -y "${packages_to_install[@]}" &>/dev/null
                ;;
            *)
                warning_msg "未知系统类型，请手动安装: ${packages_to_install[*]}"
                ;;
        esac
        
        # 再次检查依赖是否安装成功
        local missing_deps=()
        for cmd in "${required_commands[@]}"; do
            if ! command -v "$cmd" &>/dev/null; then
                missing_deps+=("$cmd")
            fi
        done
        
        if [[ ${#missing_deps[@]} -gt 0 ]]; then
            error_exit "以下依赖安装失败: ${missing_deps[*]}，请手动安装后重试"
        fi
        
        success_msg "依赖安装完成"
    else
        success_msg "所有依赖已满足"
    fi
}

# 检查系统环境
check_environment() {
    info_msg "正在检查系统环境..."
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要root权限运行，请使用: sudo bash $0"
    fi
    
    # 检测系统类型
    detect_system
    
    # 更新包管理器并安装依赖
    update_package_manager
    install_dependencies
    
    # 检查systemd
    if ! command -v systemctl &>/dev/null; then
        error_exit "系统不支持systemd，无法使用此工具"
    fi
    
    # 检查网络连接
    if ! curl -s --max-time 10 --connect-timeout 5 https://www.cloudflare.com &>/dev/null; then
        warning_msg "网络连接可能有问题，但继续安装..."
    fi
    
    success_msg "环境检查通过"
}

# 下载主脚本
download_script() {
    info_msg "正在下载米粒儿主脚本..."

    local temp_file download_url request_url separator
    temp_file=$(mktemp) || error_exit "创建临时文件失败"
    mkdir -p "$INSTALL_DIR"

    # 主地址异常时自动切换到 GitHub，下载完成后先做语法检查再替换。
    for download_url in "$SCRIPT_URL" "$SCRIPT_FALLBACK_URL"; do
        separator="?"
        [[ "$download_url" == *"?"* ]] && separator="&"
        request_url="${download_url}${separator}t=$(date +%s)"
        if curl -fsSL -H "Cache-Control: no-cache" --retry 3 --connect-timeout 10 --max-time 90 "$request_url" -o "$temp_file" \
            && bash -n "$temp_file" 2>/dev/null \
            && install -m 755 "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME"; then
            rm -f "$temp_file"
            success_msg "脚本下载成功"
            return 0
        fi
    done

    rm -f "$temp_file"
    error_exit "脚本下载或语法校验失败，请检查网络连接"
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

# Debian 13特殊优化
debian13_optimization() {
    if [[ "$OS_ID" == "debian" && "${OS_VERSION%%.*}" -ge 13 ]]; then
        info_msg "检测到Debian 13，执行特殊优化..."
        
        # 确保必要的仓库可用
        if [[ ! -f "/etc/apt/sources.list.d/debian-security.list" ]]; then
            echo "deb http://security.debian.org/debian-security/ trixie-security main" > "/etc/apt/sources.list.d/debian-security.list" 2>/dev/null || true
        fi
        
        # 安装额外的兼容性包
        apt-get install -y procps-ng net-tools iproute2 &>/dev/null || warning_msg "部分兼容性包安装失败，但不影响主要功能"
        
        # 检查并修复可能的权限问题
        if [[ -d "/sys/class/net" ]]; then
            chmod 755 "/sys/class/net" 2>/dev/null || true
        fi
        
        success_msg "Debian 13优化完成"
    fi
}

# 最终验证和优化
final_verification() {
    info_msg "正在进行最终验证..."
    
    # 验证关键文件
    if [[ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]] || [[ ! -x "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        error_exit "主脚本安装验证失败"
    fi
    
    # 验证快捷键
    if [[ ! -f "/usr/local/bin/$SHORTCUT_NAME" ]] || [[ ! -x "/usr/local/bin/$SHORTCUT_NAME" ]]; then
        error_exit "快捷键安装验证失败"
    fi
    
    # 验证网络接口访问权限
    if [[ ! -r "/sys/class/net" ]] || [[ ! -d "/sys/class/net" ]]; then
        warning_msg "网络接口目录访问受限，可能影响监控功能"
    fi
    
    # 验证systemd服务支持
    if ! systemctl --version &>/dev/null; then
        warning_msg "systemd未正确安装，后台服务功能可能受影响"
    fi
    
    # 特殊系统优化
    debian13_optimization
    
    success_msg "最终验证通过"
}

# 主安装流程
main() {
    echo -e "${INFO}正在准备米粒儿 VPS 流量控制台...${RESET}"
    check_environment
    download_script
    create_global_shortcut
    verify_installation
    final_verification

    # curl | bash 的标准输入通常已到文件尾，切换到终端后直接进入主菜单。
    clear
    if [[ ! -t 0 ]] && (: </dev/tty) 2>/dev/null; then
        exec bash "$INSTALL_DIR/$SCRIPT_NAME" </dev/tty
    fi
    exec bash "$INSTALL_DIR/$SCRIPT_NAME"
}

# 执行安装
main "$@"
