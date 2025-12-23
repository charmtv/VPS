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

# 安全的网络接口检测 - 自动选择第一个可用接口
detect_network_interface() {
    local interfaces=($(ls /sys/class/net 2>/dev/null | grep -v -E "lo|docker|veth|br-"))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        echo "未找到可用的网络接口" >&2
        return 1
    fi
    
    # 自动选择第一个可用接口，优先选择以eth、ens、enp开头的接口
    local selected_interface=""
    for interface in "${interfaces[@]}"; do
        # 检查接口是否真正可用（有统计文件）
        if [[ -r "/sys/class/net/$interface/statistics/rx_bytes" ]] && [[ -r "/sys/class/net/$interface/statistics/tx_bytes" ]]; then
            if [[ "$interface" =~ ^(eth|ens|enp) ]]; then
                selected_interface="$interface"
                break
            elif [[ -z "$selected_interface" ]]; then
                # 如果还没有选择接口，先记录这个可用的接口
                selected_interface="$interface"
            fi
        fi
    done
    
    # 如果没有找到可用接口，再试一次不检查统计文件
    if [[ -z "$selected_interface" ]]; then
        for interface in "${interfaces[@]}"; do
            if [[ "$interface" =~ ^(eth|ens|enp) ]]; then
                selected_interface="$interface"
                break
            fi
        done
        
        # 如果还是没有，选择第一个
        if [[ -z "$selected_interface" ]]; then
            selected_interface="${interfaces[0]}"
        fi
    fi
    
    if [[ -z "$selected_interface" ]]; then
        echo "无法确定有效的网络接口" >&2
        return 1
    fi
    
    # 只输出接口名称，不输出提示信息（避免污染变量赋值）
    echo "$selected_interface"
    return 0
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
USAGE_COUNT="$((${USAGE_COUNT:-0} + 1))"
LAST_USED="$(date '+%Y-%m-%d %H:%M:%S')"
# ═══════════════════════════════════════════════════════════════════
EOF
}

# 保存高级配置
save_advanced_config() {
    local preset_name="$1" url="$2" threads="$3" refresh_rate="$4" dl_threshold="$5" ul_threshold="$6"
    local preset_file="/root/milier_presets.conf"
    
    # 添加预设到文件
    {
        echo "# 预设：$preset_name - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "PRESET_${preset_name}_URL=\"$url\""
        echo "PRESET_${preset_name}_THREADS=\"$threads\""
        echo "PRESET_${preset_name}_REFRESH=\"$refresh_rate\""
        echo "PRESET_${preset_name}_DL_THRESHOLD=\"$dl_threshold\""
        echo "PRESET_${preset_name}_UL_THRESHOLD=\"$ul_threshold\""
        echo
    } >> "$preset_file"
}

# 加载预设配置
load_preset() {
    local preset_name="$1"
    local preset_file="/root/milier_presets.conf"
    
    if [[ -f "$preset_file" ]]; then
        source "$preset_file"
        
        local url_var="PRESET_${preset_name}_URL"
        local threads_var="PRESET_${preset_name}_THREADS"
        local refresh_var="PRESET_${preset_name}_REFRESH"
        local dl_var="PRESET_${preset_name}_DL_THRESHOLD"
        local ul_var="PRESET_${preset_name}_UL_THRESHOLD"
        
        echo "${!url_var:-}" "${!threads_var:-}" "${!refresh_var:-}" "${!dl_var:-}" "${!ul_var:-}"
    fi
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

# 获取增强的系统信息
get_system_info() {
    # 基本系统信息
    local hostname=$(hostname 2>/dev/null || echo "未知")
    local kernel=$(uname -r 2>/dev/null || echo "未知")
    local uptime_info=$(uptime 2>/dev/null | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' || echo "未知")
    
    # CPU信息
    local cpu_cores=$(nproc 2>/dev/null || echo "未知")
    local cpu_model=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "未知")
    
    # 内存信息
    local mem_total mem_used mem_free
    if [[ -r /proc/meminfo ]]; then
        mem_total=$(awk '/MemTotal/ {printf "%.2f GB", $2/1024/1024}' /proc/meminfo)
        mem_free=$(awk '/MemAvailable/ {printf "%.2f GB", $2/1024/1024}' /proc/meminfo)
        mem_used=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%.2f GB", $3/1024}' || echo "未知")
    else
        mem_total="未知"; mem_used="未知"; mem_free="未知"
    fi
    
    # 磁盘信息
    local disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}' || echo "未知")
    
    # 网络接口信息
    local interfaces_count=$(ls /sys/class/net 2>/dev/null | grep -v -E "lo|docker|veth|br-" | wc -l || echo 0)
    
    # 负载信息
    local load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs || echo "未知")
    
    # 格式化显示
    printf "${INFO}%-12s${WHITE}%-20s${RESET}    ${INFO}%-12s${WHITE}%-20s${RESET}\n" \
        "主机名：" "$hostname" \
        "内核：" "$kernel"
    printf "${INFO}%-12s${WHITE}%-20s${RESET}    ${INFO}%-12s${WHITE}%-20s${RESET}\n" \
        "运行时间：" "$uptime_info" \
        "CPU核心：" "$cpu_cores"
    printf "${INFO}%-12s${WHITE}%-20s${RESET}    ${INFO}%-12s${WHITE}%-20s${RESET}\n" \
        "内存使用：" "$mem_used" \
        "总内存：" "$mem_total"
    printf "${INFO}%-12s${WHITE}%-20s${RESET}    ${INFO}%-12s${WHITE}%-20s${RESET}\n" \
        "磁盘使用：" "$disk_usage" \
        "网络接口：" "$interfaces_count"
    printf "${INFO}%-12s${WHITE}%-50s${RESET}\n" \
        "系统负载：" "$load_avg"
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

    # 创建增强的监控脚本
    cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
# 米粒儿VPS流量监控脚本 - 增强版
INTERFACE=$1

# 显示启动信息
echo -e "\e[38;5;117m正在启动监控脚本...\e[0m"
echo -e "\e[38;5;117m传入参数：$*\e[0m"

# 参数验证
if [[ -z "$INTERFACE" ]]; then
    echo -e "\e[38;5;196m❌ 错误：未指定网络接口\e[0m"
    echo -e "\e[38;5;117m用法：$0 <网络接口名>\e[0m"
    read -p "按回车继续..."
    exit 1
fi

echo -e "\e[38;5;117m检查网络接口：$INTERFACE\e[0m"

if [[ ! -d "/sys/class/net/$INTERFACE" ]]; then
    echo -e "\e[38;5;196m❌ 错误：网络接口 '$INTERFACE' 不存在\e[0m"
    echo -e "\e[38;5;117m可用接口：\e[0m"
    ls -la /sys/class/net/ 2>/dev/null | grep -v -E "lo|docker|veth|br-" | head -10
    read -p "按回车继续..."
    exit 1
fi

# 检查接口状态文件权限
if [[ ! -r "/sys/class/net/$INTERFACE/statistics/rx_bytes" ]] || [[ ! -r "/sys/class/net/$INTERFACE/statistics/tx_bytes" ]]; then
    echo -e "\e[38;5;196m❌ 错误：无法读取网络接口统计信息\e[0m"
    echo -e "\e[38;5;117m接口路径：/sys/class/net/$INTERFACE/statistics/\e[0m"
    echo -e "\e[38;5;117m权限检查：\e[0m"
    ls -la "/sys/class/net/$INTERFACE/statistics/" 2>/dev/null | head -5
    echo -e "\e[38;5;117m当前用户：$(whoami)\e[0m"
    echo -e "\e[38;5;117m请确保以root权限运行\e[0m"
    read -p "按回车继续..."
    exit 1
fi

echo -e "\e[38;5;46m✅ 接口检查通过\e[0m"

# 统一颜色方案
PRIMARY="\e[38;5;39m"; SUCCESS="\e[38;5;46m"; WARNING="\e[38;5;226m"
INFO="\e[38;5;117m"; WHITE="\e[97m"; BOLD="\e[1m"; RESET="\e[0m"
DANGER="\e[38;5;196m"
BAR_LEN=50

# 检查必要命令
check_commands() {
    local missing=()
    for cmd in awk printf cat; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${DANGER}❌ 缺少必要命令: ${missing[*]}${RESET}"
        exit 1
    fi
}

# 增强的格式化函数，兼容不同的awk实现
format_speed() {
    local bytes=$1
    if [[ -z "$bytes" ]] || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        bytes=0
    fi
    
    if [[ $bytes -ge 1048576 ]]; then
        if command -v awk &>/dev/null; then
            awk "BEGIN{printf \"%.2f MB/s\", $bytes/1024/1024}" 2>/dev/null || printf "%.0f MB/s" "$((bytes/1024/1024))"
        else
            printf "%.0f MB/s" "$((bytes/1024/1024))"
        fi
    elif [[ $bytes -ge 1024 ]]; then
        if command -v awk &>/dev/null; then
            awk "BEGIN{printf \"%.2f KB/s\", $bytes/1024}" 2>/dev/null || printf "%.0f KB/s" "$((bytes/1024))"
        else
            printf "%.0f KB/s" "$((bytes/1024))"
        fi
    else
        printf "%d B/s" "$bytes"
    fi
}

format_total() {
    local bytes=$1
    if [[ -z "$bytes" ]] || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        bytes=0
    fi
    
    if [[ $bytes -ge 1073741824 ]]; then
        if command -v awk &>/dev/null; then
            awk "BEGIN{printf \"%.2f GB\", $bytes/1024/1024/1024}" 2>/dev/null || printf "%.1f GB" "$((bytes/1024/1024/1024))"
        else
            printf "%.1f GB" "$((bytes/1024/1024/1024))"
        fi
    elif [[ $bytes -ge 1048576 ]]; then
        if command -v awk &>/dev/null; then
            awk "BEGIN{printf \"%.2f MB\", $bytes/1024/1024}" 2>/dev/null || printf "%.0f MB" "$((bytes/1024/1024))"
        else
            printf "%.0f MB" "$((bytes/1024/1024))"
        fi
    else
        if command -v awk &>/dev/null; then
            awk "BEGIN{printf \"%.2f KB\", $bytes/1024}" 2>/dev/null || printf "%.0f KB" "$((bytes/1024))"
        else
            printf "%.0f KB" "$((bytes/1024))"
        fi
    fi
}

# 简化的进度条绘制
draw_bar() {
    local rate=$1 max_rate=$2
    if [[ $max_rate -eq 0 ]]; then
        max_rate=1
    fi
    
    local fill=$((rate * BAR_LEN / max_rate))
    [[ $fill -gt $BAR_LEN ]] && fill=$BAR_LEN
    [[ $fill -lt 0 ]] && fill=0
    
    printf "["
    for ((i=0; i<fill; i++)); do printf "█"; done
    for ((i=fill; i<BAR_LEN; i++)); do printf "░"; done
    printf "]"
}

# 安全的数值读取
safe_read_bytes() {
    local file="$1"
    if [[ -r "$file" ]]; then
        local value=$(cat "$file" 2>/dev/null)
        if [[ "$value" =~ ^[0-9]+$ ]]; then
            echo "$value"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# 检查命令可用性
echo -e "${INFO}检查必要命令...${RESET}"
check_commands

# 初始化，使用安全读取
echo -e "${INFO}正在初始化监控...${RESET}"
echo -e "${INFO}读取接口统计文件...${RESET}"

RX_PREV=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/rx_bytes")
TX_PREV=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/tx_bytes")
RX_TOTAL=0; TX_TOTAL=0; DURATION=0

echo -e "${INFO}初始读取 - RX: $RX_PREV bytes, TX: $TX_PREV bytes${RESET}"

# 检查初始读取是否成功
if [[ "$RX_PREV" == "0" ]] && [[ "$TX_PREV" == "0" ]]; then
    echo -e "${WARNING}⚠️  警告：初始流量数据为零，可能是接口刚启动或无流量${RESET}"
    echo -e "${INFO}这不影响监控功能，将显示相对变化量${RESET}"
    sleep 2
else
    echo -e "${SUCCESS}✅ 初始数据读取成功${RESET}"
fi

echo -e "${INFO}准备启动监控界面...${RESET}"
sleep 1

clear
echo -e "${PRIMARY}                                实时流量监控${RESET}"
echo -e "${INFO}                          网络接口：${WHITE}$INTERFACE${RESET}"
echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
echo -e "${WARNING}按 Ctrl+C 退出监控${RESET}"
echo

# 设置信号处理
trap 'echo -e "\n${WARNING}监控已停止${RESET}"; exit 0' INT TERM

# 主监控循环
echo -e "${SUCCESS}开始监控循环...${RESET}"
LOOP_COUNT=0

while true; do
    sleep 1
    ((DURATION++))
    ((LOOP_COUNT++))
    
    # 定期检查接口是否仍然存在
    if [[ $((LOOP_COUNT % 30)) -eq 0 ]]; then
        if [[ ! -d "/sys/class/net/$INTERFACE" ]]; then
            echo -e "\n${DANGER}❌ 网络接口 $INTERFACE 已不存在${RESET}"
            break
        fi
    fi
    
    # 安全读取当前数值
    RX_CUR=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/rx_bytes")
    TX_CUR=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/tx_bytes")
    
    # 调试输出（前3次循环）
    if [[ $LOOP_COUNT -le 3 ]]; then
        echo -e "${INFO}Loop $LOOP_COUNT - Current: RX=$RX_CUR, TX=$TX_CUR, Prev: RX=$RX_PREV, TX=$TX_PREV${RESET}"
    fi
    
    # 计算速率（防止负数和异常值）
    if [[ "$RX_CUR" =~ ^[0-9]+$ ]] && [[ "$TX_CUR" =~ ^[0-9]+$ ]] && [[ "$RX_PREV" =~ ^[0-9]+$ ]] && [[ "$TX_PREV" =~ ^[0-9]+$ ]]; then
        RX_RATE=$((RX_CUR >= RX_PREV ? RX_CUR - RX_PREV : 0))
        TX_RATE=$((TX_CUR >= TX_PREV ? TX_CUR - TX_PREV : 0))
        
        # 防止异常大值（可能是计数器重置）
        [[ $RX_RATE -gt 1073741824 ]] && RX_RATE=0  # 1GB/s限制
        [[ $TX_RATE -gt 1073741824 ]] && TX_RATE=0
    else
        echo -e "\n${WARNING}数据读取异常，跳过此次统计${RESET}"
        RX_RATE=0; TX_RATE=0
    fi
    
    # 更新累计值
    RX_PREV=$RX_CUR; TX_PREV=$TX_CUR
    RX_TOTAL=$((RX_TOTAL + RX_RATE)); TX_TOTAL=$((TX_TOTAL + TX_RATE))
    
    # 格式化显示数据
    RX_SPEED=$(format_speed $RX_RATE 2>/dev/null || echo "0 B/s")
    TX_SPEED=$(format_speed $TX_RATE 2>/dev/null || echo "0 B/s")
    RX_TOTAL_DISPLAY=$(format_total $RX_TOTAL 2>/dev/null || echo "0 KB")
    TX_TOTAL_DISPLAY=$(format_total $TX_TOTAL 2>/dev/null || echo "0 KB")
    
    # 动态调整最大速度刻度
    MAX_SPEED=$((10*1024*1024))  # 默认10MB/s
    [[ $RX_RATE -gt $MAX_SPEED ]] && MAX_SPEED=$RX_RATE
    [[ $TX_RATE -gt $MAX_SPEED ]] && MAX_SPEED=$TX_RATE
    
    # 绘制进度条
    RX_BAR=$(draw_bar $RX_RATE $MAX_SPEED 2>/dev/null || echo "[░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]")
    TX_BAR=$(draw_bar $TX_RATE $MAX_SPEED 2>/dev/null || echo "[░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]")
    
    # 计算时间和平均值
    HOURS=$((DURATION / 3600))
    MINS=$(((DURATION % 3600) / 60))
    SECS=$((DURATION % 60))
    AVG_RX=$(( DURATION > 0 ? RX_TOTAL / DURATION : 0 ))
    AVG_TX=$(( DURATION > 0 ? TX_TOTAL / DURATION : 0 ))
    
    # 显示统计信息
    if [[ $LOOP_COUNT -gt 3 ]]; then
        # 正常显示模式（清除调试信息后）
        printf "\r${SUCCESS}下载：${WHITE}%-12s${RESET} ${PRIMARY}%s${RESET} ${INFO}累计：${WHITE}%-12s${RESET}\n" "$RX_SPEED" "$RX_BAR" "$RX_TOTAL_DISPLAY"
        printf "\r${INFO}上传：${WHITE}%-12s${RESET} ${PRIMARY}%s${RESET} ${INFO}累计：${WHITE}%-12s${RESET}\n" "$TX_SPEED" "$TX_BAR" "$TX_TOTAL_DISPLAY"
        printf "\r${WARNING}运行时长：${WHITE}%02d:%02d:%02d${RESET} ${PRIMARY}|${RESET} ${INFO}平均：下载 ${WHITE}%-12s${RESET} 上传 ${WHITE}%-12s${RESET}" \
            $HOURS $MINS $SECS "$(format_speed $AVG_RX 2>/dev/null || echo "0 B/s")" "$(format_speed $AVG_TX 2>/dev/null || echo "0 B/s")"
        
        # 移动光标到上一行开始位置，实现刷新效果
        printf "\033[3A"
    else
        # 调试模式显示
        printf "${SUCCESS}下载：${WHITE}%-12s${RESET} ${INFO}累计：${WHITE}%-12s${RESET}\n" "$RX_SPEED" "$RX_TOTAL_DISPLAY"
        printf "${INFO}上传：${WHITE}%-12s${RESET} ${INFO}累计：${WHITE}%-12s${RESET}\n" "$TX_SPEED" "$TX_TOTAL_DISPLAY"
    fi
done

echo -e "\n${INFO}监控循环结束${RESET}"
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
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
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
    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
    printf "${INFO}%-12s${WHITE}%s${RESET}\n" "下载URL：" "$url"
    printf "${INFO}%-12s${WHITE}%s${RESET}\n" "线程数量：" "$threads"
    echo -e "${GRAY}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
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
    echo -e "${INFO}正在启动实时流量监控...${RESET}"
    
    # 检查服务状态（非强制要求）
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${WARNING}⚠️  流量消耗服务未运行，但监控功能仍可使用${RESET}"
    else
        echo -e "${SUCCESS}✅ 流量消耗服务运行中${RESET}"
    fi
    
    # 检查监控脚本是否存在
    if [[ ! -f "$MONITOR_SCRIPT" ]]; then
        echo -e "${DANGER}❌ 监控脚本不存在：$MONITOR_SCRIPT${RESET}"
        echo -e "${INFO}正在重新初始化服务...${RESET}"
        init_service
        if [[ ! -f "$MONITOR_SCRIPT" ]]; then
            echo -e "${DANGER}❌ 监控脚本创建失败${RESET}"
            read -p "按回车返回菜单..."
            return
        fi
    fi
    
    # 确保监控脚本可执行
    chmod +x "$MONITOR_SCRIPT" 2>/dev/null
    
    # 加载配置
    load_config
    
    # 获取网络接口
    local interface=""
    if [[ -n "$LAST_INTERFACE" ]]; then
        # 验证保存的接口是否仍然有效
        if [[ -d "/sys/class/net/$LAST_INTERFACE" ]]; then
            interface="$LAST_INTERFACE"
            echo -e "${INFO}使用已保存的网络接口：${WHITE}$interface${RESET}"
        else
            echo -e "${WARNING}⚠️  已保存的接口无效，重新检测...${RESET}"
        fi
    fi
    
    # 如果没有有效接口，重新检测
    if [[ -z "$interface" ]]; then
        echo -e "${INFO}正在检测网络接口...${RESET}"
        interface=$(detect_network_interface 2>&1)
        local detect_result=$?
        
        if [[ $detect_result -ne 0 ]] || [[ -z "$interface" ]]; then
            echo -e "${DANGER}❌ 网络接口检测失败${RESET}"
            echo -e "${INFO}检测结果：${WHITE}$interface${RESET}"
            echo -e "${INFO}可用接口列表：${RESET}"
            ls -la /sys/class/net/ 2>/dev/null | grep -v -E "lo|docker|veth|br-" | head -5
            read -p "按回车返回菜单..."
            return
        fi
    fi
    
    # 验证接口有效性
    if [[ ! -d "/sys/class/net/$interface" ]]; then
        echo -e "${DANGER}❌ 网络接口无效：$interface${RESET}"
        read -p "按回车返回菜单..."
        return
    fi
    
    # 检查接口统计文件权限
    if [[ ! -r "/sys/class/net/$interface/statistics/rx_bytes" ]] || [[ ! -r "/sys/class/net/$interface/statistics/tx_bytes" ]]; then
        echo -e "${DANGER}❌ 无法读取网络接口统计信息${RESET}"
        echo -e "${INFO}请确保以root权限运行此脚本${RESET}"
        read -p "按回车返回菜单..."
        return
    fi
    
    echo -e "${SUCCESS}✅ 准备完成，启动监控界面...${RESET}"
    echo -e "${INFO}使用网络接口：${WHITE}$interface${RESET}"
    echo -e "${WARNING}提示：按 Ctrl+C 可退出监控${RESET}"
    sleep 2
    
    # 启动监控脚本
    if ! bash "$MONITOR_SCRIPT" "$interface"; then
        echo
        echo -e "${DANGER}❌ 监控脚本执行失败${RESET}"
        echo -e "${INFO}脚本路径：${WHITE}$MONITOR_SCRIPT${RESET}"
        echo -e "${INFO}网络接口：${WHITE}$interface${RESET}"
        read -p "按回车返回菜单..."
    fi
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
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${INFO}按 'q' 退出${RESET}"
    echo
    tail -50 "$LOG_FILE" | less -R
}

# 快捷键管理
shortcut_management() {
    clear
    echo -e "${PRIMARY}快捷键管理${RESET}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
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

# 测试监控功能
test_monitor() {
    clear
    echo -e "${PRIMARY}监控功能测试${RESET}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo
    
    echo -e "${INFO}正在执行监控功能诊断...${RESET}"
    echo
    
    # 1. 检查脚本文件
    echo -e "${INFO}1. 检查监控脚本文件...${RESET}"
    if [[ -f "$MONITOR_SCRIPT" ]]; then
        echo -e "${SUCCESS}✅ 监控脚本存在：$MONITOR_SCRIPT${RESET}"
        if [[ -x "$MONITOR_SCRIPT" ]]; then
            echo -e "${SUCCESS}✅ 监控脚本可执行${RESET}"
        else
            echo -e "${WARNING}⚠️  监控脚本无执行权限，正在修复...${RESET}"
            chmod +x "$MONITOR_SCRIPT"
        fi
    else
        echo -e "${DANGER}❌ 监控脚本不存在，正在创建...${RESET}"
        init_service
    fi
    
    # 2. 检查网络接口
    echo -e "${INFO}2. 检查网络接口...${RESET}"
    echo -e "${INFO}可用网络接口列表：${RESET}"
    if ls /sys/class/net/ 2>/dev/null; then
        local interfaces=($(ls /sys/class/net 2>/dev/null | grep -v -E "lo|docker|veth|br-"))
        echo -e "${INFO}过滤后的接口：${WHITE}${interfaces[*]}${RESET}"
        
        if [[ ${#interfaces[@]} -gt 0 ]]; then
            local test_interface="${interfaces[0]}"
            echo -e "${SUCCESS}✅ 选择测试接口：$test_interface${RESET}"
            
            # 3. 检查接口权限
            echo -e "${INFO}3. 检查接口统计文件权限...${RESET}"
            if [[ -r "/sys/class/net/$test_interface/statistics/rx_bytes" ]]; then
                local rx_bytes=$(cat "/sys/class/net/$test_interface/statistics/rx_bytes" 2>/dev/null)
                echo -e "${SUCCESS}✅ 可读取RX统计：$rx_bytes bytes${RESET}"
            else
                echo -e "${DANGER}❌ 无法读取RX统计文件${RESET}"
            fi
            
            if [[ -r "/sys/class/net/$test_interface/statistics/tx_bytes" ]]; then
                local tx_bytes=$(cat "/sys/class/net/$test_interface/statistics/tx_bytes" 2>/dev/null)
                echo -e "${SUCCESS}✅ 可读取TX统计：$tx_bytes bytes${RESET}"
            else
                echo -e "${DANGER}❌ 无法读取TX统计文件${RESET}"
            fi
            
            # 4. 测试命令可用性
            echo -e "${INFO}4. 检查必需命令...${RESET}"
            local required_cmds=("awk" "printf" "cat" "sleep" "bash")
            for cmd in "${required_cmds[@]}"; do
                if command -v "$cmd" &>/dev/null; then
                    echo -e "${SUCCESS}✅ $cmd 命令可用${RESET}"
                else
                    echo -e "${DANGER}❌ $cmd 命令缺失${RESET}"
                fi
            done
            
            # 5. 快速监控测试
            echo
            echo -e "${INFO}5. 执行快速监控测试（10秒）...${RESET}"
            echo -e "${WARNING}测试中，请稍等...${RESET}"
            
            # 启动后台监控测试
            timeout 10 bash -c "
                source /dev/stdin << 'TESTEOF'
INTERFACE='$test_interface'
safe_read_bytes() {
    local file=\"\$1\"
    if [[ -r \"\$file\" ]]; then
        local value=\$(cat \"\$file\" 2>/dev/null)
        if [[ \"\$value\" =~ ^[0-9]+\$ ]]; then
            echo \"\$value\"
        else
            echo \"0\"
        fi
    else
        echo \"0\"
    fi
}

echo \"开始监控测试...\"
RX_PREV=\$(safe_read_bytes \"/sys/class/net/\$INTERFACE/statistics/rx_bytes\")
TX_PREV=\$(safe_read_bytes \"/sys/class/net/\$INTERFACE/statistics/tx_bytes\")
echo \"初始值 - RX: \$RX_PREV, TX: \$TX_PREV\"

for i in {1..5}; do
    sleep 2
    RX_CUR=\$(safe_read_bytes \"/sys/class/net/\$INTERFACE/statistics/rx_bytes\")
    TX_CUR=\$(safe_read_bytes \"/sys/class/net/\$INTERFACE/statistics/tx_bytes\")
    RX_RATE=\$((RX_CUR - RX_PREV))
    TX_RATE=\$((TX_CUR - TX_PREV))
    echo \"第\${i}次检测 - RX变化: \$RX_RATE bytes/2s, TX变化: \$TX_RATE bytes/2s\"
    RX_PREV=\$RX_CUR; TX_PREV=\$TX_CUR
done
echo \"监控测试完成\"
TESTEOF
            " && echo -e "${SUCCESS}✅ 监控测试完成${RESET}" || echo -e "${WARNING}⚠️  监控测试超时或失败${RESET}"
            
        else
            echo -e "${DANGER}❌ 没有可用的网络接口${RESET}"
        fi
    else
        echo -e "${DANGER}❌ 无法访问网络接口目录${RESET}"
    fi
    
    echo
    echo -e "${INFO}诊断完成！${RESET}"
    echo
    echo -e "${PRIMARY}如果测试正常，实时监控应该可以工作${RESET}"
    echo -e "${WARNING}如果仍有问题，请检查以上失败的项目${RESET}"
    echo
    read -p "按回车返回菜单..."
}

# 高级监控功能
advanced_monitor() {
    clear
    echo -e "${PRIMARY}高级流量监控${RESET}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo
    
    # 获取网络接口
    echo -e "${INFO}正在检测网络接口...${RESET}"
    load_config
    local interface=""
    if [[ -n "$LAST_INTERFACE" ]] && [[ -d "/sys/class/net/$LAST_INTERFACE" ]]; then
        interface="$LAST_INTERFACE"
    else
        interface=$(detect_network_interface 2>/dev/null)
    fi
    
    if [[ -z "$interface" ]] || [[ ! -d "/sys/class/net/$interface" ]]; then
        echo -e "${DANGER}❌ 无法检测到有效的网络接口${RESET}"
        read -p "按回车返回菜单..."
        return
    fi
    
    echo -e "${SUCCESS}✅ 使用网络接口：${WHITE}$interface${RESET}"
    echo
    
    # 配置选项
    echo -e "${PRIMARY}配置监控参数：${RESET}"
    echo -e "${INFO}1. 刷新间隔 (1-10秒，推荐1秒)${RESET}"
    read -p "请输入刷新间隔 [1]：" refresh_interval
    refresh_interval=${refresh_interval:-1}
    
    if ! [[ "$refresh_interval" =~ ^[1-9]$ ]] || [[ $refresh_interval -gt 10 ]]; then
        refresh_interval=1
    fi
    
    echo -e "${INFO}2. 流量警告阈值 (MB/s，0表示禁用)${RESET}"
    read -p "请输入下载速度警告阈值 [100]：" dl_threshold
    dl_threshold=${dl_threshold:-100}
    
    read -p "请输入上传速度警告阈值 [50]：" ul_threshold
    ul_threshold=${ul_threshold:-50}
    
    # 转换为字节
    local dl_threshold_bytes=$((dl_threshold * 1024 * 1024))
    local ul_threshold_bytes=$((ul_threshold * 1024 * 1024))
    
    echo -e "${INFO}3. 是否启用历史峰值记录？ [y/N]${RESET}"
    read -p "" enable_history
    local enable_history_flag=false
    [[ "$enable_history" =~ ^[Yy]$ ]] && enable_history_flag=true
    
    echo
    echo -e "${SUCCESS}✅ 配置完成，启动高级监控...${RESET}"
    echo -e "${WARNING}按 Ctrl+C 退出监控${RESET}"
    sleep 2
    
    # 启动高级监控
    advanced_monitor_loop "$interface" "$refresh_interval" "$dl_threshold_bytes" "$ul_threshold_bytes" "$enable_history_flag"
}

# 高级监控主循环
advanced_monitor_loop() {
    local interface="$1"
    local refresh_interval="$2"
    local dl_threshold="$3"
    local ul_threshold="$4"
    local enable_history="$5"
    
    # 初始化变量
    local RX_PREV=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
    local TX_PREV=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)
    local RX_TOTAL=0 TX_TOTAL=0 DURATION=0
    local RX_PEAK=0 TX_PEAK=0 RX_PEAK_TIME="" TX_PEAK_TIME=""
    local ALERT_COUNT=0
    
    # 历史数据数组
    local -a RX_HISTORY TX_HISTORY TIME_HISTORY
    local HISTORY_SIZE=60  # 保留60个数据点
    
    # 颜色和符号
    local SUCCESS="\e[38;5;46m" WARNING="\e[38;5;226m" DANGER="\e[38;5;196m"
    local INFO="\e[38;5;117m" WHITE="\e[97m" RESET="\e[0m" PRIMARY="\e[38;5;39m"
    
    clear
    echo -e "${PRIMARY}                          高级实时流量监控${RESET}"
    echo -e "${INFO}              网络接口: ${WHITE}$interface${RESET} | 刷新间隔: ${WHITE}${refresh_interval}s${RESET}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${WARNING}按 Ctrl+C 退出 | 按 s 保存数据 | 按 r 重置统计${RESET}"
    echo
    
    trap 'echo -e "\n${WARNING}正在保存数据并退出...${RESET}"; save_monitor_data "$interface" "$RX_TOTAL" "$TX_TOTAL" "$DURATION" "$RX_PEAK" "$TX_PEAK"; exit 0' INT
    
    while true; do
        sleep "$refresh_interval"
        ((DURATION += refresh_interval))
        
        # 读取当前值
        local RX_CUR=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
        local TX_CUR=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)
        
        # 计算速率
        local RX_RATE=$((RX_CUR >= RX_PREV ? (RX_CUR - RX_PREV) / refresh_interval : 0))
        local TX_RATE=$((TX_CUR >= TX_PREV ? (TX_CUR - TX_PREV) / refresh_interval : 0))
        
        # 防止异常值
        [[ $RX_RATE -gt 1073741824 ]] && RX_RATE=0
        [[ $TX_RATE -gt 1073741824 ]] && TX_RATE=0
        
        # 更新累计值
        RX_PREV=$RX_CUR; TX_PREV=$TX_CUR
        RX_TOTAL=$((RX_TOTAL + RX_RATE * refresh_interval))
        TX_TOTAL=$((TX_TOTAL + TX_RATE * refresh_interval))
        
        # 更新峰值记录
        if [[ $RX_RATE -gt $RX_PEAK ]]; then
            RX_PEAK=$RX_RATE
            RX_PEAK_TIME=$(date '+%H:%M:%S')
        fi
        
        if [[ $TX_RATE -gt $TX_PEAK ]]; then
            TX_PEAK=$TX_RATE
            TX_PEAK_TIME=$(date '+%H:%M:%S')
        fi
        
        # 历史数据记录
        if [[ "$enable_history" == "true" ]]; then
            RX_HISTORY+=($RX_RATE)
            TX_HISTORY+=($TX_RATE)
            TIME_HISTORY+=($(date '+%H:%M:%S'))
            
            # 限制历史数据大小
            if [[ ${#RX_HISTORY[@]} -gt $HISTORY_SIZE ]]; then
                RX_HISTORY=("${RX_HISTORY[@]:1}")
                TX_HISTORY=("${TX_HISTORY[@]:1}")
                TIME_HISTORY=("${TIME_HISTORY[@]:1}")
            fi
        fi
        
        # 阈值检查
        local alert_msg=""
        if [[ $dl_threshold -gt 0 ]] && [[ $RX_RATE -gt $dl_threshold ]]; then
            alert_msg="${DANGER}⚠️ 下载速度超过阈值！${RESET}"
            ((ALERT_COUNT++))
        fi
        
        if [[ $ul_threshold -gt 0 ]] && [[ $TX_RATE -gt $ul_threshold ]]; then
            alert_msg="${alert_msg} ${DANGER}⚠️ 上传速度超过阈值！${RESET}"
            ((ALERT_COUNT++))
        fi
        
        # 格式化显示
        local rx_speed=$(format_bytes_per_sec $RX_RATE)
        local tx_speed=$(format_bytes_per_sec $TX_RATE)
        local rx_total=$(format_bytes $RX_TOTAL)
        local tx_total=$(format_bytes $TX_TOTAL)
        local rx_peak_speed=$(format_bytes_per_sec $RX_PEAK)
        local tx_peak_speed=$(format_bytes_per_sec $TX_PEAK)
        
        # 计算运行时间
        local hours=$((DURATION / 3600))
        local mins=$(((DURATION % 3600) / 60))
        local secs=$((DURATION % 60))
        
        # 计算平均值
        local avg_rx=$(( DURATION > 0 ? RX_TOTAL / DURATION : 0 ))
        local avg_tx=$(( DURATION > 0 ? TX_TOTAL / DURATION : 0 ))
        local avg_rx_speed=$(format_bytes_per_sec $avg_rx)
        local avg_tx_speed=$(format_bytes_per_sec $avg_tx)
        
        # 生成进度条
        local max_speed=$(( RX_RATE > TX_RATE ? RX_RATE : TX_RATE ))
        [[ $max_speed -lt $((10*1024*1024)) ]] && max_speed=$((10*1024*1024))
        
        local rx_bar=$(generate_bar $RX_RATE $max_speed 40)
        local tx_bar=$(generate_bar $TX_RATE $max_speed 40)
        
        # 显示界面
        printf "\033[2J\033[H"  # 清屏并移到顶部
        echo -e "${PRIMARY}                          高级实时流量监控${RESET}"
        echo -e "${INFO}              网络接口: ${WHITE}$interface${RESET} | 刷新间隔: ${WHITE}${refresh_interval}s${RESET}"
        echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
        echo
        
        # 当前速度
        printf "${SUCCESS}下载: ${WHITE}%-12s${RESET} ${PRIMARY}%s${RESET}\n" "$rx_speed" "$rx_bar"
        printf "${INFO}上传: ${WHITE}%-12s${RESET} ${PRIMARY}%s${RESET}\n" "$tx_speed" "$tx_bar"
        echo
        
        # 统计信息
        printf "${INFO}累计下载: ${WHITE}%-12s${RESET} | ${INFO}累计上传: ${WHITE}%-12s${RESET}\n" "$rx_total" "$tx_total"
        printf "${INFO}平均下载: ${WHITE}%-12s${RESET} | ${INFO}平均上传: ${WHITE}%-12s${RESET}\n" "$avg_rx_speed" "$avg_tx_speed"
        
        if [[ -n "$RX_PEAK_TIME" ]] && [[ -n "$TX_PEAK_TIME" ]]; then
            printf "${WARNING}峰值下载: ${WHITE}%-12s${RESET} @${WHITE}%s${RESET} | ${WARNING}峰值上传: ${WHITE}%-12s${RESET} @${WHITE}%s${RESET}\n" \
                "$rx_peak_speed" "$RX_PEAK_TIME" "$tx_peak_speed" "$TX_PEAK_TIME"
        fi
        
        printf "${PRIMARY}运行时长: ${WHITE}%02d:%02d:%02d${RESET}" $hours $mins $secs
        [[ $ALERT_COUNT -gt 0 ]] && printf " | ${DANGER}警告次数: ${WHITE}%d${RESET}" $ALERT_COUNT
        echo
        
        # 显示警告信息
        [[ -n "$alert_msg" ]] && echo -e "$alert_msg"
        
        # 显示历史趋势（简单ASCII图）
        if [[ "$enable_history" == "true" ]] && [[ ${#RX_HISTORY[@]} -gt 10 ]]; then
            echo
            echo -e "${INFO}流量趋势 (最近${#RX_HISTORY[@]}个数据点):${RESET}"
            display_ascii_chart "${RX_HISTORY[*]}" "下载"
        fi
        
        echo
        echo -e "${GRAY}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
        echo -e "${GRAY}按 Ctrl+C 退出 | s:保存数据 | r:重置统计${RESET}"
    done
}

# 字节格式化函数 - 优化版
format_bytes_per_sec() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        printf "%.2f GB/s" "$(echo "scale=2; $bytes/1073741824" | bc 2>/dev/null || echo "$((bytes/1073741824))")"
    elif [[ $bytes -ge 1048576 ]]; then
        printf "%.2f MB/s" "$(echo "scale=2; $bytes/1048576" | bc 2>/dev/null || echo "$((bytes/1048576))")"
    elif [[ $bytes -ge 1024 ]]; then
        printf "%.2f KB/s" "$(echo "scale=2; $bytes/1024" | bc 2>/dev/null || echo "$((bytes/1024))")"
    else
        printf "%d B/s" "$bytes"
    fi
}

format_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        printf "%.2f GB" "$(echo "scale=2; $bytes/1073741824" | bc 2>/dev/null || echo "$((bytes/1073741824))")"
    elif [[ $bytes -ge 1048576 ]]; then
        printf "%.2f MB" "$(echo "scale=2; $bytes/1048576" | bc 2>/dev/null || echo "$((bytes/1048576))")"
    elif [[ $bytes -ge 1024 ]]; then
        printf "%.2f KB" "$(echo "scale=2; $bytes/1024" | bc 2>/dev/null || echo "$((bytes/1024))")"
    else
        printf "%d B" "$bytes"
    fi
}

# 生成进度条
generate_bar() {
    local current=$1
    local max=$2
    local width=${3:-50}
    
    local fill=$((current * width / max))
    [[ $fill -gt $width ]] && fill=$width
    [[ $fill -lt 0 ]] && fill=0
    
    printf "["
    for ((i=0; i<fill; i++)); do printf "█"; done
    for ((i=fill; i<width; i++)); do printf "░"; done
    printf "]"
}

# 简单ASCII图表显示
display_ascii_chart() {
    local data=($1)
    local label="$2"
    local max_val=0
    
    # 找到最大值
    for val in "${data[@]}"; do
        [[ $val -gt $max_val ]] && max_val=$val
    done
    
    [[ $max_val -eq 0 ]] && max_val=1
    
    local chart_height=5
    printf "${INFO}%s趋势: " "$label"
    
    for val in "${data[@]:(-20)}"; do  # 只显示最后20个数据点
        local bar_height=$(( val * chart_height / max_val ))
        [[ $bar_height -eq 0 ]] && [[ $val -gt 0 ]] && bar_height=1
        
        case $bar_height in
            0) printf "▁" ;;
            1) printf "▂" ;;
            2) printf "▃" ;;
            3) printf "▅" ;;
            4) printf "▆" ;;
            *) printf "▇" ;;
        esac
    done
    echo -e "${RESET}"
}

# 保存监控数据
save_monitor_data() {
    local interface="$1" rx_total="$2" tx_total="$3" duration="$4" rx_peak="$5" tx_peak="$6"
    local data_file="/root/milier_monitor_data.log"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    {
        echo "==============================="
        echo "监控数据保存 - $timestamp"
        echo "网络接口: $interface"
        echo "监控时长: $duration 秒"
        echo "累计下载: $(format_bytes $rx_total)"
        echo "累计上传: $(format_bytes $tx_total)"
        echo "峰值下载速度: $(format_bytes_per_sec $rx_peak)"
        echo "峰值上传速度: $(format_bytes_per_sec $tx_peak)"
        echo "平均下载速度: $(format_bytes_per_sec $((rx_total / duration)))"
        echo "平均上传速度: $(format_bytes_per_sec $((tx_total / duration)))"
        echo "==============================="
        echo
    } >> "$data_file"
    
    echo -e "${SUCCESS}✅ 数据已保存到: $data_file${RESET}"
}

# 检查更新功能
check_update() {
    clear
    echo -e "${PRIMARY}检查脚本更新${RESET}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo
    
    echo -e "${INFO}正在检查更新...${RESET}"
    
    # 获取当前版本
    local current_version="v2.0"
    local script_url="https://raw.githubusercontent.com/charmtv/VPS/main/milier_flow_latest.sh"
    local temp_file="/tmp/milier_latest_check.sh"
    
    # 下载最新版本检查
    if curl -fsSL "$script_url" -o "$temp_file" --max-time 15; then
        echo -e "${SUCCESS}✅ 获取最新版本信息成功${RESET}"
        
        # 简单版本检查（通过文件大小和修改时间）
        local current_size=$(stat -c%s "$0" 2>/dev/null || echo 0)
        local latest_size=$(stat -c%s "$temp_file" 2>/dev/null || echo 0)
        local size_diff=$(( latest_size > current_size ? latest_size - current_size : current_size - latest_size ))
        
        echo -e "${INFO}当前版本：${WHITE}$current_version${RESET}"
        echo -e "${INFO}当前脚本大小：${WHITE}$(format_file_size $current_size)${RESET}"
        echo -e "${INFO}最新脚本大小：${WHITE}$(format_file_size $latest_size)${RESET}"
        
        if [[ $size_diff -gt 1024 ]]; then
            echo -e "${WARNING}⚠️  发现更新（大小差异：$(format_file_size $size_diff)）${RESET}"
            echo
            echo -e "${INFO}是否要更新到最新版本？${RESET}"
            echo -e "${WARNING}注意：更新会覆盖当前脚本，但配置文件会保留${RESET}"
            echo
            read -p "确认更新？ (y/N): " confirm_update
            
            if [[ "$confirm_update" =~ ^[Yy]$ ]]; then
                echo -e "${INFO}正在备份当前脚本...${RESET}"
                cp "$0" "${0}.backup.$(date +%Y%m%d_%H%M%S)"
                
                echo -e "${INFO}正在更新脚本...${RESET}"
                if cp "$temp_file" "$0" && chmod +x "$0"; then
                    echo -e "${SUCCESS}✅ 更新完成！${RESET}"
                    echo -e "${WARNING}请重新启动脚本以使用新版本${RESET}"
                    echo
                    read -p "现在重启脚本？ (Y/n): " restart_now
                    if [[ ! "$restart_now" =~ ^[Nn]$ ]]; then
                        exec bash "$0"
                    fi
                else
                    echo -e "${DANGER}❌ 更新失败，已恢复备份${RESET}"
                    cp "${0}.backup.$(date +%Y%m%d_%H%M%S | head -1)" "$0" 2>/dev/null
                fi
            else
                echo -e "${INFO}已取消更新${RESET}"
            fi
        else
            echo -e "${SUCCESS}✅ 您已经使用的是最新版本！${RESET}"
        fi
        
        rm -f "$temp_file"
    else
        echo -e "${DANGER}❌ 无法连接到更新服务器${RESET}"
        echo -e "${INFO}请检查网络连接或稍后再试${RESET}"
    fi
    
    echo
    read -p "按回车返回菜单..."
}

# 格式化文件大小
format_file_size() {
    local size=$1
    if [[ $size -ge 1048576 ]]; then
        printf "%.2f MB" "$(echo "scale=2; $size/1048576" | bc 2>/dev/null || echo "$((size/1048576))")"
    elif [[ $size -ge 1024 ]]; then
        printf "%.2f KB" "$(echo "scale=2; $size/1024" | bc 2>/dev/null || echo "$((size/1024))")"
    else
        printf "%d B" "$size"
    fi
}

# 卸载服务
uninstall_service() {
    clear
    echo -e "${DANGER}危险操作警告${RESET}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
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
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo

    # 服务状态和系统信息
    get_service_info
    echo
    
    # 系统信息
    echo -e "${ACCENT}系统信息${RESET}"
    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
    get_system_info
    
    # 使用统计
    load_config
    if [[ -n "$USAGE_COUNT" ]] && [[ $USAGE_COUNT -gt 0 ]]; then
        printf "${INFO}使用次数：${WHITE}%-8s${RESET}    ${INFO}最后使用：${WHITE}%-20s${RESET}\n" "$USAGE_COUNT" "${LAST_USED:-未知}"
    fi
    echo

    # 官方联系方式 - 简洁排列，统一颜色
    echo -e "${ACCENT}官方联系方式${RESET}"
    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
    printf "${INFO}%-12s${LINK}%-35s${RESET} ${INFO}%-12s${LINK}%-20s${RESET}\n" \
        "📱 TG群：" "https://t.me/mlkjfx6" \
        "🌐 博客：" "https://ooovps.com"
    printf "${INFO}%-12s${LINK}%-35s${RESET}\n" \
        "🏛️  论坛：" "https://nodeloc.com"
    echo

    # 操作菜单 - 竖排布局
    echo -e "${PRIMARY}操作菜单${RESET}"
    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${SUCCESS}1) 启动流量消耗服务${RESET}"
    echo -e "${DANGER}2) 停止流量消耗服务${RESET}"
    echo -e "${INFO}3) 实时流量监控${RESET}"
    echo -e "${WARNING}4) 重启流量服务${RESET}"
    echo -e "${INFO}5) 查看服务日志${RESET}"
    echo -e "${SECONDARY}6) 快捷键管理${RESET}"
    echo -e "${ACCENT}8) 测试监控功能${RESET}"
    echo -e "${SECONDARY}9) 高级监控${RESET}"
    echo -e "${WARNING}A) 检查更新${RESET}"
    echo -e "${DANGER}7) 卸载全部服务${RESET}"
    echo -e "${GRAY}0) 退出程序${RESET}"
    echo -e "${GRAY}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
    echo
    
    read -p "请选择操作 [0-9,A]：" choice
    
    case $choice in
        1) start_service ;;
        2) stop_service ;;
        3) show_monitor ;;
        4) restart_service ;;
        5) show_logs ;;
        6) shortcut_management ;;
        7) uninstall_service ;;
        8) test_monitor ;;
        9) advanced_monitor ;;
        [Aa]) check_update ;;
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
            echo -e "${DANGER}❌ 无效选项，请输入 0-9 或 A${RESET}"
            sleep 1
            ;;
    esac
}

# ──────────────────────────────── 环境检查 ────────────────────────────────────

# 检测系统类型
detect_system_type() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID}"
        OS_NAME="${PRETTY_NAME}"
    fi
}

# 安装缺失的依赖
install_missing_deps() {
    local missing_cmds=()
    local required_commands=("curl" "systemctl" "nproc" "free" "df" "ps" "grep" "awk" "sed" "less")
    
    # 检查缺失的命令
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    # 如果有缺失的命令，尝试安装
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        echo -e "${WARNING}⚠️  检测到缺失依赖: ${missing_cmds[*]}${RESET}"
        echo -e "${INFO}正在尝试自动安装...${RESET}"
        
        case "$OS_ID" in
            ubuntu|debian|linuxmint)
                apt-get update &>/dev/null
                apt-get install -y curl procps coreutils systemd less &>/dev/null
                ;;
            centos|rhel|fedora|rocky|almalinux)
                if command -v yum &>/dev/null; then
                    yum install -y curl procps-ng coreutils systemd less &>/dev/null
                elif command -v dnf &>/dev/null; then
                    dnf install -y curl procps-ng coreutils systemd less &>/dev/null
                fi
                ;;
            arch|manjaro)
                pacman -S --noconfirm curl procps-ng coreutils systemd less &>/dev/null
                ;;
        esac
        
        # 再次检查
        local still_missing=()
        for cmd in "${required_commands[@]}"; do
            if ! command -v "$cmd" &>/dev/null; then
                still_missing+=("$cmd")
            fi
        done
        
        if [[ ${#still_missing[@]} -gt 0 ]]; then
            echo -e "${DANGER}❌ 以下依赖安装失败: ${still_missing[*]}${RESET}"
            echo -e "${INFO}请手动安装后重新运行脚本${RESET}"
            exit 1
        else
            echo -e "${SUCCESS}✅ 依赖安装完成${RESET}"
        fi
    fi
}

check_environment() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${DANGER}❌ 需要root权限${RESET}"
        exit 1
    fi

    # 检测系统类型
    detect_system_type
    
    # 检查并安装缺失的依赖
    install_missing_deps
    
    # 检查关键系统文件
    if [[ ! -d "/sys/class/net" ]]; then
        echo -e "${DANGER}❌ 系统网络接口目录不存在${RESET}"
        exit 1
    fi
    
    # 检查systemd支持
    if ! systemctl --version &>/dev/null; then
        echo -e "${DANGER}❌ 系统不支持systemd${RESET}"
        exit 1
    fi
}

# ──────────────────────────────── 程序主入口 ──────────────────────────────────

# 检查环境并初始化
check_environment
init_service

# 主循环
while true; do
    show_menu
done
