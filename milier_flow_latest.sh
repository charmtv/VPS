# 米粒儿VPS流量管理工具 - 一键安装

## 🚀 方案1：在线一键安装（推荐）

复制以下整个代码块，粘贴到VPS终端执行：

```bash
#!/bin/bash
echo "正在安装米粒儿VPS流量管理工具..."

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "❌ 需要root权限，请使用: sudo bash"
    exit 1
fi

# 创建主脚本
cat > /root/milier_flow.sh << 'MAIN_SCRIPT_EOF'
#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════════
# 米粒儿VPS流量消耗管理工具 - 官方版本
# 官方TG群：https://t.me/mlkjfx6
# ═══════════════════════════════════════════════════════════════════════════════════

# ──────────────────────────────── 配置常量 ────────────────────────────────────
SERVICE_NAME="milier_flow"
LOG_FILE="/root/milier_flow.log"
MONITOR_SCRIPT="/root/milier_monitor.sh"
UNINSTALL_SCRIPT="/root/milier_uninstall.sh"
CONFIG_FILE="/root/milier_config.conf"
SHORTCUT_CONFIG="/root/milier_shortcut.conf"
DEFAULT_SHORTCUT="xh"

# ──────────────────────────────── 统一颜色方案 ────────────────────────────────
PRIMARY="\e[38;5;39m"         # 主蓝色
SECONDARY="\e[38;5;51m"       # 次蓝色
SUCCESS="\e[38;5;46m"         # 亮绿色
WARNING="\e[38;5;226m"        # 亮黄色
DANGER="\e[38;5;196m"         # 亮红色
INFO="\e[38;5;117m"           # 浅蓝色
ACCENT="\e[38;5;213m"         # 紫红色
LINK="\e[38;5;87m"            # 青色 - 统一链接颜色
WHITE="\e[97m"                # 纯白色
GRAY="\e[90m"                 # 灰色
BOLD="\e[1m"                  # 加粗
RESET="\e[0m"                 # 重置

# ──────────────────────────────── 工具函数 ────────────────────────────────────

# 错误处理函数
error_exit() {
    echo -e "${DANGER}❌ 错误：$1${RESET}" >&2
    read -p "按回车返回菜单..."
}

# 检查命令执行结果
check_command() {
    if [[ $? -ne 0 ]]; then
        error_exit "$1"
        return 1
    fi
    return 0
}

# 获取快捷键名称
get_shortcut_name() {
    if [[ -f "$SHORTCUT_CONFIG" ]]; then
        source "$SHORTCUT_CONFIG"
        echo "${SHORTCUT_NAME:-$DEFAULT_SHORTCUT}"
    else
        echo "$DEFAULT_SHORTCUT"
    fi
}

# 保存快捷键配置
save_shortcut_config() {
    local shortcut_name="$1"
    cat > "$SHORTCUT_CONFIG" << EOF
# 快捷键配置文件
SHORTCUT_NAME="$shortcut_name"
SHORTCUT_PATH="/usr/local/bin/$shortcut_name"
CREATED_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
}

# 安全的网络接口检测
detect_network_interface() {
    local interfaces=($(ls /sys/class/net 2>/dev/null | grep -v -E "lo|docker|veth"))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        error_exit "未找到可用的网络接口"
        return 1
    elif [[ ${#interfaces[@]} -eq 1 ]]; then
        echo "${interfaces[0]}"
    else
        echo -e "${INFO}检测到多个网络接口：${RESET}"
        for i in "${!interfaces[@]}"; do
            printf "  ${PRIMARY}%d)${RESET} ${WHITE}%-15s${RESET}\n" "$((i+1))" "${interfaces[i]}"
        done
        while true; do
            read -p "请选择接口编号 [1-${#interfaces[@]}]：" choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#interfaces[@]} ]]; then
                echo "${interfaces[$((choice-1))]}"
                break
            else
                echo -e "${DANGER}  ❌ 无效选择，请重新输入${RESET}"
            fi
        done
    fi
}

# 验证线程数
validate_threads() {
    local threads="$1"
    local max_cores=$(nproc)
    local max_threads=$((max_cores * 4))
    
    if ! [[ "$threads" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${DANGER}  ❌ 线程数必须为正整数${RESET}"
        return 1
    fi
    
    if [[ $threads -gt $max_threads ]]; then
        echo -e "${WARNING}  ⚠️  线程数过高（推荐最大：$max_threads），可能影响系统性能${RESET}"
        read -p "  是否继续？(y/N)：" confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || return 1
    fi
    
    return 0
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" << EOF
# ═══════════════════════════════════════════════════════════════════
# 米粒儿配置文件 - $(date '+%Y-%m-%d %H:%M:%S')
# ═══════════════════════════════════════════════════════════════════
LAST_URL="$1"
LAST_THREADS="$2"
LAST_INTERFACE="$3"
INSTALL_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
# ═══════════════════════════════════════════════════════════════════
EOF
}

# 读取配置
load_config() {
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}

# 获取服务状态信息
get_service_info() {
    if systemctl is-active --quiet $SERVICE_NAME; then
        local pid=$(systemctl show -p MainPID --value $SERVICE_NAME 2>/dev/null)
        local uptime=$(systemctl show -p ActiveEnterTimestamp --value $SERVICE_NAME 2>/dev/null | cut -d' ' -f2-3)
        printf "${SUCCESS}服务状态：${WHITE}%-8s${RESET}    ${SUCCESS}进程PID：${WHITE}%-8s${RESET}\n" "运行中" "${pid:-"N/A"}"
        [[ -n "$uptime" ]] && printf "${INFO}启动时间：${WHITE}%s${RESET}\n" "$uptime"
    else
        printf "${DANGER}服务状态：${WHITE}%-8s${RESET}\n" "已停止"
    fi
}

# ──────────────────────────────── 快捷键管理 ──────────────────────────────────

# 创建快捷键脚本
create_shortcut() {
    local shortcut_name="${1:-$(get_shortcut_name)}"
    local shortcut_path="/usr/local/bin/$shortcut_name"
    local script_path="$0"
    local script_dir=$(dirname "$(readlink -f "$script_path")")
    
    echo -e "${INFO}正在设置快捷键 ${PRIMARY}$shortcut_name${RESET}${INFO}...${RESET}"
    
    # 删除旧的快捷键
    if [[ -f "$SHORTCUT_CONFIG" ]]; then
        source "$SHORTCUT_CONFIG"
        [[ -n "$SHORTCUT_PATH" ]] && rm -f "$SHORTCUT_PATH"
    fi
    
    cat > "$shortcut_path" << EOF
#!/bin/bash
# 米粒儿VPS流量管理工具快捷启动脚本
cd "$script_dir"
bash "$script_path" "\$@"
EOF
    
    chmod +x "$shortcut_path"
    if check_command "创建快捷键失败"; then
        save_shortcut_config "$shortcut_name"
        echo -e "${SUCCESS}✅ 快捷键设置成功！现在可以使用 ${PRIMARY}$shortcut_name${RESET} ${SUCCESS}命令启动工具${RESET}"
    fi
}

# 删除快捷键
remove_shortcut() {
    if [[ -f "$SHORTCUT_CONFIG" ]]; then
        source "$SHORTCUT_CONFIG"
        if [[ -n "$SHORTCUT_PATH" && -f "$SHORTCUT_PATH" ]]; then
            rm -f "$SHORTCUT_PATH"
            echo -e "${WARNING}已删除快捷键: ${PRIMARY}$(basename "$SHORTCUT_PATH")${RESET}"
        fi
        rm -f "$SHORTCUT_CONFIG"
    else
        echo -e "${WARNING}未找到快捷键配置${RESET}"
    fi
}

# ──────────────────────────────── 初始化服务 ──────────────────────────────────
init_service() {
    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        return 0
    fi
    
    echo -e "${WARNING}⚠️  正在初始化米粒儿服务...${RESET}"

    # 检查系统权限
    if [[ $EUID -ne 0 ]]; then
        error_exit "需要 root 权限运行此脚本"
        return 1
    fi

    # 创建必要目录和文件
    mkdir -p /root
    touch "$LOG_FILE" && chmod 666 "$LOG_FILE"
    check_command "创建文件失败" || return 1

    # 网络接口检测
    local interface
    interface=$(detect_network_interface)
    [[ $? -ne 0 ]] && return 1

    # 默认配置
    local cpu_cores default_threads default_url
    cpu_cores=$(nproc)
    default_threads=$((cpu_cores * 2))
    default_url="https://speed.cloudflare.com/__down?bytes=104857600"

    # 创建 systemd 服务
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=米粒儿 VPS 流量消耗后台服务
After=network.target
StartLimitBurst=3
StartLimitIntervalSec=60

[Service]
Type=simple
WorkingDirectory=/root
Environment="MILIER_URL=$default_url"
Environment="MILIER_THREADS=$default_threads"
ExecStart=/bin/bash -c '\
URL="\$MILIER_URL"; THREADS="\$MILIER_THREADS"; LOG_FILE="$LOG_FILE"; \
echo "$(date "+%%Y-%%m-%%d %%H:%%M:%%S"): [启动] \$THREADS 线程开始下载 \$URL" | tee -a \$LOG_FILE; \
for ((i=1;i<=THREADS;i++)); do \
  bash -c "while true; do curl -s -m 30 --connect-timeout 10 -o /dev/null \$URL; sleep 0.1; done" >>\$LOG_FILE 2>&1 & \
done; wait'
ExecStop=/usr/bin/pkill -f "curl.*cloudflare"
ExecStopPost=/bin/bash -c 'echo "$(date "+%%Y-%%m-%%d %%H:%%M:%%S"): [停止] 服务已停止" >> $LOG_FILE'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    check_command "系统配置失败" || return 1

    # 创建监控脚本
    cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
INTERFACE=$1

if [[ -z "$INTERFACE" ]] || [[ ! -d "/sys/class/net/$INTERFACE" ]]; then
    echo -e "\e[38;5;196m❌ 网络接口无效\e[0m"
    exit 1
fi

# 统一颜色方案
PRIMARY="\e[38;5;39m"; SUCCESS="\e[38;5;46m"; WARNING="\e[38;5;226m"
INFO="\e[38;5;117m"; WHITE="\e[97m"; BOLD="\e[1m"; RESET="\e[0m"
BAR_LEN=50

# 格式化函数
format_speed() {
    local bytes=$1
    if [[ $bytes -ge 1048576 ]]; then
        awk "BEGIN{printf \"%.2f MB/s\", $bytes/1024/1024}"
    elif [[ $bytes -ge 1024 ]]; then
        awk "BEGIN{printf \"%.2f KB/s\", $bytes/1024}"
    else
        printf "%d B/s" "$bytes"
    fi
}

format_total() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        awk "BEGIN{printf \"%.2f GB\", $bytes/1024/1024/1024}"
    elif [[ $bytes -ge 1048576 ]]; then
        awk "BEGIN{printf \"%.2f MB\", $bytes/1024/1024}"
    else
        awk "BEGIN{printf \"%.2f KB\", $bytes/1024}"
    fi
}

draw_bar() {
    local rate=$1 max_rate=$2
    local fill=$((rate * BAR_LEN / max_rate))
    [[ $fill -gt $BAR_LEN ]] && fill=$BAR_LEN
    printf "["; for ((i=0; i<fill; i++)); do printf "█"; done
    for ((i=fill; i<BAR_LEN; i++)); do printf "░"; done; printf "]"
}

# 初始化
RX_PREV=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX_PREV=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo 0)
RX_TOTAL=0; TX_TOTAL=0; DURATION=0

clear
echo -e "${PRIMARY}                                实时流量监控${RESET}"
echo -e "${INFO}                          网络接口：${WHITE}$INTERFACE${RESET}"
echo -e "${PRIMARY}$(printf '%*s' 80 | tr ' ' '=')"
echo

trap 'echo -e "\n${WARNING}监控已停止${RESET}"; exit 0' INT

while true; do
    sleep 1; ((DURATION++))
    
    RX_CUR=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo $RX_PREV)
    TX_CUR=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo $TX_PREV)
    RX_RATE=$((RX_CUR - RX_PREV)); TX_RATE=$((TX_CUR - TX_PREV))
    RX_PREV=$RX_CUR; TX_PREV=$TX_CUR
    RX_TOTAL=$((RX_TOTAL + RX_RATE)); TX_TOTAL=$((TX_TOTAL + TX_RATE))
    
    RX_SPEED=$(format_speed $RX_RATE); TX_SPEED=$(format_speed $TX_RATE)
    RX_TOTAL_DISPLAY=$(format_total $RX_TOTAL); TX_TOTAL_DISPLAY=$(format_total $TX_TOTAL)
    
    MAX_SPEED=$((10*1024*1024))
    [[ $RX_RATE -gt $MAX_SPEED ]] && MAX_SPEED=$RX_RATE
    [[ $TX_RATE -gt $MAX_SPEED ]] && MAX_SPEED=$TX_RATE
    
    RX_BAR=$(draw_bar $RX_RATE $MAX_SPEED); TX_BAR=$(draw_bar $TX_RATE $MAX_SPEED)
    HOURS=$((DURATION / 3600)); MINS=$(((DURATION % 3600) / 60)); SECS=$((DURATION % 60))
    AVG_RX=$(( DURATION > 0 ? RX_TOTAL / DURATION : 0 ))
    AVG_TX=$(( DURATION > 0 ? TX_TOTAL / DURATION : 0 ))
    
    printf "\r${SUCCESS}下载：${WHITE}%-12s${RESET} ${PRIMARY}%s${RESET} ${INFO}累计：${WHITE}%-12s${RESET}\n" "$RX_SPEED" "$RX_BAR" "$RX_TOTAL_DISPLAY"
    printf "\r${INFO}上传：${WHITE}%-12s${RESET} ${PRIMARY}%s${RESET} ${INFO}累计：${WHITE}%-12s${RESET}\n" "$TX_SPEED" "$TX_BAR" "$TX_TOTAL_DISPLAY"
    printf "\r${WARNING}运行时长：${WHITE}%02d:%02d:%02d${RESET} ${PRIMARY}|${RESET} ${INFO}平均：下载 ${WHITE}%-12s${RESET} 上传 ${WHITE}%-12s${RESET}" \
        $HOURS $MINS $SECS "$(format_speed $AVG_RX)" "$(format_speed $AVG_TX)"
    printf "\033[3A"
done
EOF
    chmod +x "$MONITOR_SCRIPT"

    # 创建卸载脚本
    cat > "$UNINSTALL_SCRIPT" << EOF
#!/bin/bash
SUCCESS="\e[38;5;46m"; WARNING="\e[38;5;226m"; WHITE="\e[97m"; BOLD="\e[1m"; RESET="\e[0m"

echo -e "\${WARNING}正在卸载米粒儿服务...\${RESET}"
systemctl stop $SERVICE_NAME 2>/dev/null
systemctl disable $SERVICE_NAME 2>/dev/null
rm -f /etc/systemd/system/$SERVICE_NAME.service
systemctl daemon-reload
rm -f "$MONITOR_SCRIPT" "$UNINSTALL_SCRIPT" "$LOG_FILE" "$CONFIG_FILE"

# 删除快捷键
if [[ -f "$SHORTCUT_CONFIG" ]]; then
    source "$SHORTCUT_CONFIG"
    [[ -n "\$SHORTCUT_PATH" ]] && rm -f "\$SHORTCUT_PATH"
    rm -f "$SHORTCUT_CONFIG"
fi

pkill -f "curl.*cloudflare" 2>/dev/null
echo -e "\${SUCCESS}✅ 卸载完成\${RESET}"
EOF
    chmod +x "$UNINSTALL_SCRIPT"
    
    # 创建快捷键和保存配置
    save_config "$default_url" "$default_threads" "$interface"
    create_shortcut "$DEFAULT_SHORTCUT"
    
    echo -e "${SUCCESS}✅ 初始化完成${RESET}"
}

# ──────────────────────────────── 服务管理函数 ──────────────────────────────────

# 启动服务
start_service() {
    clear
    echo -e "${PRIMARY}配置流量消耗参数${RESET}"
    echo -e "${PRIMARY}$(printf '%*s' 30 | tr ' ' '─')${RESET}"
    echo
    
    load_config
    
    # URL配置
    if [[ -n "$LAST_URL" ]]; then
        echo -e "${INFO}上次使用：${WHITE}$LAST_URL${RESET}"
    fi
    read -p "请输入下载URL（回车使用默认）：" url
    url=${url:-${LAST_URL:-"https://speed.cloudflare.com/__down?bytes=104857600"}}
    
    # 线程数配置
    local cpu_cores=$(nproc)
    local recommended_threads=$((cpu_cores * 2))
    printf "${INFO}%-12s${WHITE}%-12s${RESET}    ${INFO}%-12s${WHITE}%-12s${RESET}\n" \
        "CPU核心：" "$cpu_cores" "推荐线程：" "$recommended_threads"
    if [[ -n "$LAST_THREADS" ]]; then
        echo -e "${INFO}上次使用：${WHITE}$LAST_THREADS${RESET}"
    fi
    read -p "请输入线程数（回车使用推荐）：" threads
    threads=${threads:-${LAST_THREADS:-$recommended_threads}}
    
    if ! validate_threads "$threads"; then
        read -p "按回车返回菜单..."
        return
    fi
    
    # 确认配置
    echo
    echo -e "${PRIMARY}配置确认${RESET}"
    echo -e "${PRIMARY}$(printf '%*s' 20 | tr ' ' '─')${RESET}"
    printf "${INFO}%-12s${WHITE}%s${RESET}\n" "下载URL：" "$url"
    printf "${INFO}%-12s${WHITE}%s${RESET}\n" "线程数量：" "$threads"
    echo
    read -p "确认启动？(Y/n)：" confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && return
    
    export MILIER_URL="$url" MILIER_THREADS="$threads"
    systemctl stop $SERVICE_NAME 2>/dev/null
    systemctl start $SERVICE_NAME
    
    if check_command "服务启动失败"; then
        interface=$(detect_network_interface)
        save_config "$url" "$threads" "$interface"
        echo -e "${SUCCESS}✅ 服务启动成功${RESET}"
    fi
    
    read -p "按回车返回菜单..."
}

# 停止服务
stop_service() {
    echo -e "${WARNING}正在停止服务...${RESET}"
    systemctl stop $SERVICE_NAME
    if check_command "停止失败"; then
        pkill -f "curl.*cloudflare" 2>/dev/null
        echo -e "${SUCCESS}✅ 服务已停止${RESET}"
    fi
    read -p "按回车返回菜单..."
}

# 重启服务
restart_service() {
    echo -e "${WARNING}正在重启服务...${RESET}"
    systemctl restart $SERVICE_NAME
    if check_command "重启失败"; then
        echo -e "${SUCCESS}✅ 服务已重启${RESET}"
    fi
    read -p "按回车返回菜单..."
}

# 显示监控
show_monitor() {
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${DANGER}❌ 服务未运行${RESET}"
        read -p "按回车返回菜单..."
        return
    fi
    
    load_config
    local interface=${LAST_INTERFACE:-$(detect_network_interface)}
    [[ $? -ne 0 ]] && return
    
    echo -e "${INFO}启动监控...${RESET}"
    sleep 1
    bash "$MONITOR_SCRIPT" "$interface"
}

# 显示日志
show_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${DANGER}❌ 日志文件不存在${RESET}"
        read -p "按回车返回菜单..."
        return
    fi
    
    clear
    echo -e "${PRIMARY}服务日志${RESET}"
    echo -e "${PRIMARY}$(printf '%*s' 20 | tr ' ' '─')${RESET}"
    echo -e "${INFO}按 'q' 退出${RESET}"
    echo
    tail -50 "$LOG_FILE" | less -R
}

# 快捷键管理
shortcut_management() {
    clear
    echo -e "${PRIMARY}快捷键管理${RESET}"
    echo -e "${PRIMARY}$(printf '%*s' 20 | tr ' ' '─')${RESET}"
    echo
    
    local current_shortcut=$(get_shortcut_name)
    if [[ -f "$SHORTCUT_CONFIG" ]]; then
        source "$SHORTCUT_CONFIG"
        if [[ -f "${SHORTCUT_PATH:-/usr/local/bin/$current_shortcut}" ]]; then
            echo -e "${SUCCESS}✅ 当前快捷键：${PRIMARY}$current_shortcut${RESET}"
            echo -e "${INFO}   安装路径：${WHITE}${SHORTCUT_PATH:-/usr/local/bin/$current_shortcut}${RESET}"
            [[ -n "$CREATED_TIME" ]] && echo -e "${INFO}   创建时间：${WHITE}$CREATED_TIME${RESET}"
        else
            echo -e "${WARNING}❌ 快捷键文件不存在${RESET}"
        fi
    else
        echo -e "${WARNING}❌ 快捷键未安装${RESET}"
    fi
    
    echo
    echo -e "${WHITE}1) 安装/重新安装快捷键${RESET}"
    echo -e "${WHITE}2) 自定义快捷键名称${RESET}"
    echo -e "${WHITE}3) 删除快捷键${RESET}"
    echo -e "${WHITE}0) 返回主菜单${RESET}"
    echo
    
    read -p "请选择 [0-3]：" choice
    case $choice in
        1) 
            create_shortcut "$current_shortcut"
            read -p "按回车继续..."
            shortcut_management 
            ;;
        2) 
            echo -e "${INFO}当前快捷键：${PRIMARY}$current_shortcut${RESET}"
            read -p "请输入新的快捷键名称（英文字母开头）：" new_name
            
            # 验证快捷键名称
            if [[ ! "$new_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
                echo -e "${DANGER}❌ 无效名称！只能使用英文字母、数字和下划线，且必须以字母开头${RESET}"
            elif [[ -z "$new_name" ]]; then
                echo -e "${WARNING}❌ 快捷键名称不能为空${RESET}"
            elif [[ "$new_name" == "$current_shortcut" ]]; then
                echo -e "${WARNING}⚠️ 与当前快捷键相同${RESET}"
            else
                create_shortcut "$new_name"
                echo -e "${SUCCESS}✅ 快捷键已更新为：${PRIMARY}$new_name${RESET}"
            fi
            read -p "按回车继续..."
            shortcut_management 
            ;;
        3) 
            remove_shortcut
            read -p "按回车继续..."
            shortcut_management 
            ;;
        0) return ;;
        *) 
            echo -e "${DANGER}无效选项${RESET}"
            sleep 1
            shortcut_management 
            ;;
    esac
}

# 卸载服务
uninstall_service() {
    clear
    echo -e "${DANGER}危险操作警告${RESET}"
    echo -e "${DANGER}$(printf '%*s' 30 | tr ' ' '─')${RESET}"
    echo
    echo -e "${WARNING}此操作将删除所有服务、文件和配置（不可恢复）${RESET}"
    echo
    read -p "确认卸载请输入 'YES'：" confirm
    
    if [[ "$confirm" == "YES" ]]; then
        [[ -f "$UNINSTALL_SCRIPT" ]] && bash "$UNINSTALL_SCRIPT"
        exit 0
    else
        echo -e "${WARNING}操作已取消${RESET}"
        read -p "按回车返回菜单..."
    fi
}

# ──────────────────────────────── 主菜单显示 ──────────────────────────────────
show_menu() {
    clear
    # 主标题 - 简洁居中
    echo
    echo -e "${PRIMARY}                            米粒儿VPS流量消耗管理工具${RESET}"
    echo -e "${SECONDARY}                                    v2.0${RESET}"
    echo -e "${PRIMARY}$(printf '%*s' 80 | tr ' ' '=')"
    echo

    # 服务状态
    get_service_info
    echo
    


    # 官方联系方式 - 简洁排列，统一颜色
    echo -e "${ACCENT}官方联系方式${RESET}"
    echo -e "${ACCENT}$(printf '%*s' 30 | tr ' ' '─')${RESET}"
    printf "${INFO}%-12s${LINK}%-35s${RESET} ${INFO}%-12s${LINK}%-20s${RESET}\n" \
        "📱 TG群：" "https://t.me/mlkjfx6" \
        "🌐 博客：" "https://ooovps.com"
    printf "${INFO}%-12s${LINK}%-35s${RESET}\n" \
        "🏛️  论坛：" "https://nodeloc.com"
    echo

    # 操作菜单 - 竖排布局
    echo -e "${PRIMARY}操作菜单${RESET}"
    echo -e "${PRIMARY}$(printf '%*s' 20 | tr ' ' '─')${RESET}"
    echo -e "${SUCCESS}1) 启动流量消耗服务${RESET}"
    echo -e "${DANGER}2) 停止流量消耗服务${RESET}"
    echo -e "${INFO}3) 实时流量监控${RESET}"
    echo -e "${WARNING}4) 重启流量服务${RESET}"
    echo -e "${INFO}5) 查看服务日志${RESET}"
    echo -e "${SECONDARY}6) 快捷键管理${RESET}"
    echo -e "${DANGER}7) 卸载全部服务${RESET}"
    echo -e "${GRAY}0) 退出程序${RESET}"
    echo
    
    read -p "请选择操作 [0-7]：" choice
    
    case $choice in
        1) start_service ;;
        2) stop_service ;;
        3) show_monitor ;;
        4) restart_service ;;
        5) show_logs ;;
        6) shortcut_management ;;
        7) uninstall_service ;;
        0) 
            clear
            echo
            echo -e "${SUCCESS}                        感谢使用米粒儿工具${RESET}"
            echo -e "${LINK}                   欢迎加入官方TG群：@mlkjfx6${RESET}"
            echo
            echo -e "${WHITE}                              再见！${RESET}"
            echo
            exit 0
            ;;
        *) 
            echo -e "${DANGER}❌ 无效选项，请输入 0-7${RESET}"
            sleep 1
            ;;
    esac
}

# ──────────────────────────────── 环境检查 ────────────────────────────────────
check_environment() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${DANGER}❌ 需要root权限${RESET}"
        exit 1
    fi

    for cmd in systemctl curl nproc free df; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${DANGER}❌ 缺少命令：$cmd${RESET}"
            exit 1
        fi
    done
}

# ──────────────────────────────── 程序主入口 ──────────────────────────────────

# 检查环境并初始化
check_environment
init_service

# 主循环
while true; do
    show_menu
done
MAIN_SCRIPT_EOF

# 设置权限
chmod +x /root/milier_flow.sh

# 创建快捷键
cat > /usr/local/bin/xh << 'SHORTCUT_EOF'
#!/bin/bash
# 米粒儿VPS流量管理工具快捷启动脚本
cd "/root"
bash "/root/milier_flow.sh" "$@"
SHORTCUT_EOF

# 设置快捷键权限
chmod +x /usr/local/bin/xh

# 创建快捷键配置文件
cat > /root/milier_shortcut.conf << 'CONFIG_EOF'
# 快捷键配置文件
SHORTCUT_NAME="xh"
SHORTCUT_PATH="/usr/local/bin/xh"
CREATED_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
CONFIG_EOF

echo "🎉 米粒儿VPS流量管理工具安装完成！"
echo "✅ 现在可以使用 'xh' 命令启动工具"
echo "📱 官方TG群：https://t.me/mlkjfx6"
```

## 🚀 方案2：手动分步安装

如果一键命令太长，可以分步执行：

```bash
# 第1步：创建主脚本
nano /root/milier_flow.sh
# 粘贴完整脚本内容，保存退出

# 第2步：设置权限
chmod +x /root/milier_flow.sh

# 第3步：创建快捷键
cat > /usr/local/bin/xh << 'EOF'
#!/bin/bash
cd "/root"
bash "/root/milier_flow.sh" "$@"
EOF

# 第4步：设置快捷键权限
chmod +x /usr/local/bin/xh

# 第5步：测试
xh
```

## 📋 GitHub仓库修复建议

要修复GitHub的404问题：

1. **确认文件上传**：访问 https://github.com/charmtv/VPS 确保文件真的存在
2. **检查分支名**：确认默认分支是否为 `main`
3. **等待缓存**：GitHub的CDN可能需要几分钟更新
4. **重新上传**：如果文件不存在，重新上传 `install.sh` 到仓库根目录

现在用户可以直接使用上面的一键安装命令，不依赖GitHub文件！🎊

