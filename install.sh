#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════════
# VPS流量消耗管理工具 - 一键安装脚本
# ═══════════════════════════════════════════════════════════════════════════════════

# 颜色配置
SUCCESS="\e[92m"
WARNING="\e[93m"
DANGER="\e[91m"
INFO="\e[96m"
WHITE="\e[97m"
MUTED="\e[37m"
RESET="\e[0m"

if [[ ! -t 1 || -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
    SUCCESS="" WARNING="" DANGER="" INFO="" WHITE="" MUTED="" RESET=""
fi

# 配置常量
SCRIPT_URL="https://xh.813099.xyz/vpsflow_latest.sh"
SCRIPT_FALLBACK_URL="https://raw.githubusercontent.com/charmtv/VPS/main/vpsflow_latest.sh"
INSTALL_DIR="/root"
SCRIPT_NAME="vpsflow.sh"
SHORTCUT_NAME="xh"

# 安装过程中需要的命令；systemctl 单列，缺失时无法通过包管理器补救
REQUIRED_COMMANDS=(curl systemctl nproc free df ps grep awk sed)

# ──────────────────────────────── 输出helpers ─────────────────────────────────

error_exit() {
    printf '  %b❌ %s%b\n' "$DANGER" "$1" "$RESET" >&2
    exit 1
}

success_msg() { printf '  %b✅ %s%b\n' "$SUCCESS" "$1" "$RESET"; }
info_msg()    { printf '  %b%s%b\n'   "$INFO" "$1" "$RESET"; }
warning_msg() { printf '  %b⚠️  %s%b\n' "$WARNING" "$1" "$RESET"; }
note_msg()    { printf '  %b%s%b\n'   "$MUTED" "$1" "$RESET"; }

# ──────────────────────────────── 系统检测 ────────────────────────────────────

detect_system() {
    if [[ ! -f /etc/os-release ]]; then
        error_exit "不支持的操作系统，仅支持 Linux 系统"
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID}"
    info_msg "检测到系统：${PRETTY_NAME:-$OS_ID}"
}

# 列出缺失的命令
missing_commands() {
    local cmd
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        command -v "$cmd" &>/dev/null || printf '%s\n' "$cmd"
    done
}

# 把缺失的命令映射成待安装的包名（去重）
packages_for() {
    local cmd
    for cmd in "$@"; do
        case "$cmd" in
            curl)                 printf 'curl\n' ;;
            systemctl)            printf 'systemd\n' ;;
            nproc|free|df|ps)     printf 'procps\n' ;;
            grep)                 printf 'grep\n' ;;
            awk)                  printf 'gawk\n' ;;
            sed)                  printf 'sed\n' ;;
        esac
    done | sort -u
}

update_package_manager() {
    info_msg "正在刷新软件源..."
    case "$OS_ID" in
        ubuntu|debian|linuxmint)
            apt-get update -y &>/dev/null || warning_msg "软件源刷新失败，继续安装..."
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf &>/dev/null; then
                dnf makecache &>/dev/null || warning_msg "软件源刷新失败，继续安装..."
            elif command -v yum &>/dev/null; then
                yum makecache fast &>/dev/null || warning_msg "软件源刷新失败，继续安装..."
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm &>/dev/null || warning_msg "软件源刷新失败，继续安装..."
            ;;
        opensuse*)
            zypper refresh &>/dev/null || warning_msg "软件源刷新失败，继续安装..."
            ;;
        *)
            warning_msg "未知系统类型，跳过软件源刷新"
            ;;
    esac
}

install_packages() {
    local -a packages=("$@")
    case "$OS_ID" in
        ubuntu|debian|linuxmint)
            # Debian 13+ 需要额外的证书与仓库元数据包
            if [[ "$OS_ID" == "debian" && "${OS_VERSION%%.*}" -ge 13 ]]; then
                apt-get install -y "${packages[@]}" ca-certificates gnupg lsb-release &>/dev/null
            else
                apt-get install -y "${packages[@]}" &>/dev/null
            fi
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf &>/dev/null; then
                dnf install -y "${packages[@]}" &>/dev/null
            elif command -v yum &>/dev/null; then
                yum install -y "${packages[@]}" &>/dev/null
            fi
            ;;
        arch|manjaro)
            pacman -S --noconfirm "${packages[@]}" &>/dev/null
            ;;
        opensuse*)
            zypper install -y "${packages[@]}" &>/dev/null
            ;;
        *)
            warning_msg "未知系统类型，请手动安装：${packages[*]}"
            return 1
            ;;
    esac
}

# 依赖齐全时直接跳过软件源刷新，省掉一次不必要的 apt-get update
install_dependencies() {
    local -a missing=() packages=()
    mapfile -t missing < <(missing_commands)

    if [[ ${#missing[@]} -eq 0 ]]; then
        success_msg "依赖已满足"
        return 0
    fi

    info_msg "缺失依赖：${missing[*]}"
    mapfile -t packages < <(packages_for "${missing[@]}")

    update_package_manager
    if [[ ${#packages[@]} -gt 0 ]]; then
        info_msg "正在安装：${packages[*]}"
        install_packages "${packages[@]}"
    fi

    mapfile -t missing < <(missing_commands)
    if [[ ${#missing[@]} -gt 0 ]]; then
        error_exit "以下依赖安装失败：${missing[*]}，请手动安装后重试"
    fi
    success_msg "依赖安装完成"
}

# Debian 13 兼容性补充
debian13_optimization() {
    [[ "$OS_ID" == "debian" && "${OS_VERSION%%.*}" -ge 13 ]] || return 0
    info_msg "检测到 Debian 13，执行兼容性优化..."

    if [[ ! -f /etc/apt/sources.list.d/debian-security.list ]]; then
        echo "deb http://security.debian.org/debian-security/ trixie-security main" \
            > /etc/apt/sources.list.d/debian-security.list 2>/dev/null || true
    fi
    apt-get install -y procps net-tools iproute2 &>/dev/null \
        || warning_msg "部分兼容性包安装失败，不影响主要功能"
    success_msg "Debian 13 优化完成"
}

check_environment() {
    info_msg "正在检查系统环境..."

    [[ $EUID -eq 0 ]] || error_exit "此脚本需要 root 权限运行，请使用：sudo bash $0"

    detect_system
    install_dependencies

    command -v systemctl &>/dev/null || error_exit "系统不支持 systemd，无法使用此工具"
    [[ -d /sys/class/net ]] || error_exit "找不到 /sys/class/net，无法读取网卡流量统计"

    if ! curl -s --max-time 10 --connect-timeout 5 https://www.cloudflare.com &>/dev/null; then
        warning_msg "网络连接可能有问题，但继续安装..."
    fi

    debian13_optimization
    success_msg "环境检查通过"
}

# ──────────────────────────────── 安装步骤 ────────────────────────────────────

# 下载主脚本：主地址异常时自动切换到 GitHub；先做完整性校验与语法检查再替换
download_script() {
    info_msg "正在下载主脚本..."

    local temp_file headers_file download_url request_url separator
    local expected_sha actual_sha
    temp_file=$(mktemp) || error_exit "创建临时文件失败"
    headers_file=$(mktemp) || { rm -f "$temp_file"; error_exit "创建临时文件失败"; }
    mkdir -p "$INSTALL_DIR"

    for download_url in "$SCRIPT_URL" "$SCRIPT_FALLBACK_URL"; do
        separator="?"
        [[ "$download_url" == *"?"* ]] && separator="&"
        request_url="${download_url}${separator}t=$(date +%s)"

        if ! curl -fsSL -H "Cache-Control: no-cache" --retry 3 --connect-timeout 10 --max-time 90 \
            -D "$headers_file" -o "$temp_file" "$request_url"; then
            continue
        fi

        # 响应头带 X-SHA256 时校验完整性，不一致视为本次尝试失败
        expected_sha=$(awk -F': ' 'tolower($1)=="x-sha256" {print $2; exit}' "$headers_file" \
            | tr -d '\r' | tr '[:upper:]' '[:lower:]')
        if [[ -n "$expected_sha" ]] && command -v sha256sum &>/dev/null; then
            actual_sha=$(sha256sum "$temp_file" | awk '{print $1}')
            if [[ "$actual_sha" != "$expected_sha" ]]; then
                warning_msg "完整性校验失败，尝试备用源..."
                continue
            fi
        fi

        if bash -n "$temp_file" 2>/dev/null \
            && install -m 755 "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME"; then
            rm -f "$temp_file" "$headers_file"
            success_msg "主脚本下载完成"
            return 0
        fi
    done

    rm -f "$temp_file" "$headers_file"
    error_exit "脚本下载或语法校验失败，请检查网络连接"
}

# 创建全局快捷键
create_global_shortcut() {
    local shortcut_path="/usr/local/bin/$SHORTCUT_NAME"

    cat > "$shortcut_path" << EOF
#!/bin/bash
# VPS流量消耗管理工具快捷启动脚本
cd "$INSTALL_DIR" || exit 1
bash "$INSTALL_DIR/$SCRIPT_NAME" "\$@"
EOF

    chmod +x "$shortcut_path" || error_exit "创建快捷键失败"
    success_msg "快捷键 '$SHORTCUT_NAME' 已创建"
}

# 安装结果校验
verify_installation() {
    local target="$INSTALL_DIR/$SCRIPT_NAME"
    local shortcut="/usr/local/bin/$SHORTCUT_NAME"

    [[ -f "$target" && -x "$target" ]]     || error_exit "主脚本安装校验失败"
    [[ -f "$shortcut" && -x "$shortcut" ]] || error_exit "快捷键安装校验失败"

    [[ -r /sys/class/net ]] || warning_msg "网络接口目录访问受限，可能影响监控功能"
    systemctl --version &>/dev/null || warning_msg "systemd 异常，后台服务功能可能受影响"

    success_msg "安装校验通过"
}

# ──────────────────────────────── 主流程 ──────────────────────────────────────

main() {
    echo
    printf '  %b正在准备VPS 流量消耗管理工具...%b\n' "$WHITE" "$RESET"
    echo
    check_environment
    download_script
    create_global_shortcut
    verify_installation
    echo
    note_msg "以后直接输入 '$SHORTCUT_NAME' 即可启动控制台"
    sleep 1

    # curl | bash 的标准输入通常已到文件尾，切换到终端后直接进入主菜单
    clear
    if [[ ! -t 0 ]] && (: </dev/tty) 2>/dev/null; then
        exec bash "$INSTALL_DIR/$SCRIPT_NAME" </dev/tty
    fi
    exec bash "$INSTALL_DIR/$SCRIPT_NAME"
}

main "$@"
