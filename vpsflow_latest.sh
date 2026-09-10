#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════════
# VPS 流量消耗管理工具
# ═══════════════════════════════════════════════════════════════════════════════════

# ──────────────────────────────── 配置常量 ────────────────────────────────────
SCRIPT_VERSION="v3.4.0"
SCRIPT_NAME="vpsflow.sh"
SERVICE_NAME="vpsflow"
APP_TITLE="VPS 流量消耗管理工具"
LOG_FILE="/root/vpsflow.log"
MONITOR_SCRIPT="/root/vpsflow_monitor.sh"
UNINSTALL_SCRIPT="/root/vpsflow_uninstall.sh"
CONFIG_FILE="/root/vpsflow_config.conf"
SHORTCUT_CONFIG="/root/vpsflow_shortcut.conf"
TARGET_CONFIG_FILE="/root/vpsflow_target.conf"
PRESET_CONFIG_FILE="/root/vpsflow_presets.conf"
STATE_DIR="/run/vpsflow"
DEFAULT_SHORTCUT="xh"

# ──────────────────────────────── 专业高对比度配色 ────────────────────────────
# 主界面只使用高亮青和白色；绿色、黄色、红色仅表达状态。
PRIMARY="\e[96m"          # 高亮青：标题、分组、操作键
SUCCESS="\e[92m"          # 高亮绿：运行、成功
WARNING="\e[93m"          # 高亮黄：提醒
DANGER="\e[91m"           # 高亮红：停止、错误、危险操作
INFO="\e[96m"             # 高亮信息青
WHITE="\e[97m"            # 高亮白：主文字
GRAY="\e[37m"             # 标准白：次级文字
MUTED="\e[37m"            # 标准白：弱文字
PANEL="\e[37m"            # 标准白：分隔线
VALUE="\e[97m"            # 高亮白：字段值
KEY="\e[96m"              # 高亮青：操作键
BOLD="\e[1m"              # 加粗
REV="\e[7m"               # 反色（菜单选中项高亮）
RESET="\e[0m"             # 重置

# 非交互输出、NO_COLOR 或简易终端下关闭颜色控制码。
if [[ ! -t 1 || -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
    PRIMARY="" SUCCESS="" WARNING="" DANGER="" INFO=""
    WHITE="" GRAY="" MUTED="" PANEL="" VALUE="" KEY="" BOLD="" REV="" RESET=""
fi

shopt -s extglob  # 供 str_width 去除 ANSI 颜色码时使用

# ═══════════════════════════════════════════════════════════════════════════════
# 界面绘制工具（自适应宽度 / 中文对齐 / 全局统一样式）
# 所有交互界面都通过这一层绘制，保证标题、分隔线、字段、提示的排版完全一致。
# ═══════════════════════════════════════════════════════════════════════════════

UI_MIN_WIDTH=60           # 最小可用宽度，窄于此值按此值排版
UI_MAX_WIDTH=96           # 最大排版宽度，超宽终端不再拉伸，避免视线跨度过大
UI_INDENT="  "            # 全局左边距

# 是否为 UTF-8 终端，启动时判定一次，避免 str_width 每次调用都做 case 匹配
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) UI_UTF8=1 ;;
    *) UI_UTF8=0 ;;
esac

# 重复字符 n 次
repeat() {
    local ch="$1" n="$2" out
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    (( n <= 0 )) && return 0
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$ch}"
}

# 终端实际列数
term_width() {
    local w
    w=$(tput cols 2>/dev/null)
    [[ "$w" =~ ^[0-9]+$ ]] || w="${COLUMNS:-80}"
    [[ "$w" =~ ^[0-9]+$ ]] || w=80
    (( w < UI_MIN_WIDTH )) && w=$UI_MIN_WIDTH
    printf '%d' "$w"
}

# 排版宽度：终端宽度收敛到 [UI_MIN_WIDTH, UI_MAX_WIDTH]
ui_width() {
    local w
    w=$(term_width)
    (( w > UI_MAX_WIDTH )) && w=$UI_MAX_WIDTH
    printf '%d' "$w"
}

# 内容宽度：排版宽度减去左右边距
ui_inner() {
    printf '%d' $(( $(ui_width) - 4 ))
}

# 显示宽度：CJK/全角字符按 2 列计；先去除 ANSI 颜色码（真实 ESC 序列与字面 \e 写法）
str_width() {
    local s="$1"
    s="${s//$'\e'[[]*([0-9;])m/}"
    s="${s//\e[[]*([0-9;])m/}"
    if (( UI_UTF8 == 0 )); then
        printf '%d' "${#s}"
        return 0
    fi
    local c n=0 i
    for ((i=0; i<${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            [\ -~])                              n=$((n+1)) ;;  # ASCII
            █|░|─|│|┌|┐|└|┘|├|┤|▸|●|○|·|↑|↓|←|→|▁|▂|▃|▅|▆|▇)
                                                 n=$((n+1)) ;;  # 制表/块元素按 1 列渲染
            *)                                   n=$((n+2)) ;;  # CJK 与 emoji 按 2 列
        esac
    done
    printf '%d' "$n"
}

# 按显示宽度右侧补空格
pad_line() {
    local text="$1" width="$2" tw pad
    tw=$(str_width "$text")
    pad=$((width - tw))
    (( pad < 0 )) && pad=0
    printf '%s%s' "$text" "$(repeat ' ' "$pad")"
}

# 一行两栏：左对齐 + 右对齐，中间自动撑开
ui_split() {
    local left="$1" right="$2" width gap
    width="${3:-$(ui_width)}"
    if [[ -z "$right" ]]; then
        printf '%s%b\n' "$UI_INDENT" "$left"
        return 0
    fi
    gap=$(( width - 4 - $(str_width "$left") - $(str_width "$right") ))
    (( gap < 2 )) && gap=2
    printf '%s%b%s%b\n' "$UI_INDENT" "$left" "$(repeat ' ' "$gap")" "$right"
}

# 细分隔线
ui_rule() {
    local width="${1:-$(ui_width)}"
    printf '%s%b%s%b\n' "$UI_INDENT" "$PANEL" "$(repeat '─' $((width-4)))" "$RESET"
}

# 页面标题：左侧标题，右侧版本号，下方分隔线
ui_title() {
    local title="$1" right="${2:-$SCRIPT_VERSION}" width
    width=$(ui_width)
    ui_split "${WHITE}${BOLD}${title}${RESET}" "${MUTED}${right}${RESET}" "$width"
    ui_rule "$width"
}

# 清屏并绘制页面标题
ui_page() {
    clear
    echo
    ui_title "$1" "${2:-$SCRIPT_VERSION}"
    echo
}

# 字段行：标签左对齐到固定宽度，值紧随其后
ui_kv() {
    local label="$1" value="$2" pad
    pad=$(( 10 - $(str_width "$label") ))
    (( pad < 1 )) && pad=1
    printf '%s%b%s%b%s%b\n' "$UI_INDENT" "$MUTED" "$label" "$RESET" "$(repeat ' ' "$pad")" "$value"
}

# 选项行：[键] 标签 + 右侧说明
ui_item() {
    local key="$1" label="$2" hint="$3" key_color="${4:-$KEY}" pad
    pad=$(( 24 - $(str_width "$label") ))
    (( pad < 2 )) && pad=2
    if [[ -z "$hint" ]]; then
        printf '%s  %b[%s]%b %b%s%b\n' "$UI_INDENT" "$key_color" "$key" "$RESET" "$WHITE" "$label" "$RESET"
    else
        printf '%s  %b[%s]%b %b%s%b%s%b%s%b\n' "$UI_INDENT" "$key_color" "$key" "$RESET" \
            "$WHITE" "$label" "$RESET" "$(repeat ' ' "$pad")" "$MUTED" "$hint" "$RESET"
    fi
}

# 分组小标题
ui_group() {
    printf '%s%b%s%b\n' "$UI_INDENT" "$PRIMARY" "$1" "$RESET"
}

# 状态消息
ui_ok()   { printf '%s%b✅ %s%b\n' "$UI_INDENT" "$SUCCESS" "$1" "$RESET"; }
ui_warn() { printf '%s%b⚠️  %s%b\n' "$UI_INDENT" "$WARNING" "$1" "$RESET"; }
ui_err()  { printf '%s%b❌ %s%b\n' "$UI_INDENT" "$DANGER" "$1" "$RESET"; }
ui_info() { printf '%s%b%s%b\n' "$UI_INDENT" "$INFO" "$1" "$RESET"; }
ui_note() { printf '%s%b%s%b\n' "$UI_INDENT" "$MUTED" "$1" "$RESET"; }
ui_step() { printf '%s%b▸%b %b%s%b\n' "$UI_INDENT" "$PRIMARY" "$RESET" "$WHITE" "$1" "$RESET"; }

# 底部操作提示
ui_keyhint() {
    printf '%s%b%s%b\n' "$UI_INDENT" "$MUTED" "$1" "$RESET"
}

# 等待回车；非交互输入时直接返回，避免卡死
ui_pause() {
    local msg="${1:-按回车返回菜单...}"
    [[ -t 0 ]] || return 0
    echo
    read -r -p "${UI_INDENT}${msg}" _ || true
}

# 读取一行输入到指定变量：ui_ask 变量名 "提示" "默认值"
ui_ask() {
    local __var="$1" prompt="$2" default="$3" reply label
    label="$prompt"
    [[ -n "$default" ]] && label="$prompt [$default]"
    if ! read -r -p "${UI_INDENT}${label}: " reply; then
        echo
        reply=""
    fi
    reply="${reply:-$default}"
    printf -v "$__var" '%s' "$reply"
}

# 绿→黄→红渐变进度条
gradient_bar() {
    local percent="$1" width="$2" fill i c
    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
    [[ "$width" =~ ^[0-9]+$ ]] || width=20
    (( width < 8 )) && width=8
    (( width > 40 )) && width=40
    (( percent > 100 )) && percent=100
    (( percent < 0 )) && percent=0
    fill=$((percent * width / 100))
    (( fill > width )) && fill=$width
    printf '%b[%b' "$PANEL" "$RESET"
    for ((i=1; i<=width; i++)); do
        if (( i <= fill )); then
            if (( percent >= 80 )); then c="$DANGER"
            elif (( percent >= 50 )); then c="$WARNING"
            else c="$SUCCESS"; fi
            printf '%b█%b' "$c" "$RESET"
        else
            printf '%b░%b' "$MUTED" "$RESET"
        fi
    done
    printf '%b]%b' "$PANEL" "$RESET"
}

# ──────────────────────────────── 下载源与更新源 ──────────────────────────────
# 下载源表：名称 / 说明 / URL 三个数组下标一一对应，菜单与实际取值共用同一份数据
MIRROR_NAMES=(
    "香港 Datapacket 100MB"
    "日本东京 Datapacket 100MB"
    "新加坡 OVH 1GB"
    "德国 Hetzner 1GB"
    "美西洛杉矶 Datapacket 1GB"
    "法国 OVH 10GB"
)
MIRROR_HINTS=(
    "推荐，低延迟" "亚洲优选" "大文件模式"
    "欧洲高速"     "北美"     "超大文件"
)
MIRROR_URLS=(
    "http://hkg.download.datapacket.com/100mb.bin"
    "http://tyo.download.datapacket.com/100mb.bin"
    "https://sgp.proof.ovh.net/files/1Gb.dat"
    "https://nbg1-speed.hetzner.com/1GB.bin"
    "http://lax.download.datapacket.com/1000mb.bin"
    "https://gra.proof.ovh.net/files/10Gb.dat"
)
MIRROR_COUNT=${#MIRROR_URLS[@]}

# 脚本更新源，按顺序尝试
UPDATE_URLS=(
    "https://xh.813099.xyz/vpsflow_latest.sh"
    "https://raw.githubusercontent.com/charmtv/VPS/main/vpsflow_latest.sh"
)

# 读取网卡计数器，非法或不可读时返回 0：safe_stat_bytes <接口> <rx|tx>
safe_stat_bytes() {
    local file="/sys/class/net/$1/statistics/$2_bytes" value
    if [[ -r "$file" ]]; then
        value=$(< "$file")
        [[ "$value" =~ ^[0-9]+$ ]] && { printf '%s' "$value"; return 0; }
    fi
    printf '0'
}
# ──────────────────────────────── 工具函数 ────────────────────────────────────

# 报错并等待确认；不会退出脚本，由调用方决定后续返回值
# （非交互输入下 ui_pause 会直接返回，不会挂起）
error_notice() {
    ui_err "$1" >&2
    ui_pause
}

# 检查上一条命令的执行结果；必须紧跟被检查的命令调用
check_command() {
    local rc=$?
    if (( rc != 0 )); then
        error_notice "$1"
        return 1
    fi
    return 0
}

# 配置文件只允许简单 KEY="value" 赋值，避免 source 被注入命令。
is_safe_config_value() {
    local value="$1"
    [[ "$value" != *$'\n'* ]] || return 1
    [[ "$value" != *$'\r'* ]] || return 1
    [[ "$value" != *'"'* ]] || return 1
    [[ "$value" != *'`'* ]] || return 1
    [[ "$value" != *'$'* ]] || return 1
    [[ "$value" != *\\* ]] || return 1
    return 0
}

write_config_line() {
    local key="$1" value="$2"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    is_safe_config_value "$value" || return 1
    printf '%s="%s"\n' "$key" "$value"
}

safe_source_config() {
    local file="$1"
    shift
    [[ -f "$file" ]] || return 1

    local allowed=" $* "
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=\"([^\"]*)\"[[:space:]]*$ ]]; then
            echo -e "${WARNING}⚠️  配置文件格式异常，已跳过：$file${RESET}" >&2
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [[ "$allowed" != *" $key "* ]] || ! is_safe_config_value "$value"; then
            echo -e "${WARNING}⚠️  配置文件包含不允许的内容，已跳过：$file${RESET}" >&2
            return 1
        fi
    done < "$file"

    # shellcheck disable=SC1090
    source "$file"
}

validate_url() {
    local url="$1"
    [[ "$url" =~ ^https?:// ]] || return 1
    [[ "$url" != *[[:space:]]* ]] || return 1
    is_safe_config_value "$url" || return 1
    return 0
}

validate_interface_name() {
    local interface="$1"
    [[ "$interface" =~ ^[A-Za-z0-9_.:-]+$ ]]
}

# 输出可用网络接口，每行一个；过滤回环和常见虚拟接口。
list_network_interfaces() {
    local interface_path interface
    for interface_path in /sys/class/net/*; do
        [[ -e "$interface_path" ]] || continue
        interface="${interface_path##*/}"
        case "$interface" in
            lo|docker*|veth*|br-*) continue ;;
        esac
        validate_interface_name "$interface" && printf '%s\n' "$interface"
    done
}

escape_sed_replacement() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//&/\\&}"
    value="${value//|/\\|}"
    printf '%s' "$value"
}

# 获取快捷键名称
get_shortcut_name() {
    unset SHORTCUT_NAME SHORTCUT_PATH CREATED_TIME
    if [[ -f "$SHORTCUT_CONFIG" ]]; then
        safe_source_config "$SHORTCUT_CONFIG" SHORTCUT_NAME SHORTCUT_PATH CREATED_TIME || return 1
        echo "${SHORTCUT_NAME:-$DEFAULT_SHORTCUT}"
    else
        echo "$DEFAULT_SHORTCUT"
    fi
}

# 保存快捷键配置
save_shortcut_config() {
    local shortcut_name="$1"
    [[ "$shortcut_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || return 1
    {
        echo "# 快捷键配置文件"
        write_config_line "SHORTCUT_NAME" "$shortcut_name" || return 1
        write_config_line "SHORTCUT_PATH" "/usr/local/bin/$shortcut_name" || return 1
        write_config_line "CREATED_TIME" "$(date '+%Y-%m-%d %H:%M:%S')" || return 1
    } > "$SHORTCUT_CONFIG"
    chmod 600 "$SHORTCUT_CONFIG" 2>/dev/null
}

save_target_config() {
    local target_gb="$1" start_rx="$2" interface="$3" auto_stop="$4" prev_consumed="${5:-0}"
    [[ "$target_gb" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    [[ "$start_rx" =~ ^[0-9]+$ ]] || start_rx=0
    validate_interface_name "$interface" || interface="eth0"
    [[ "$auto_stop" == "true" || "$auto_stop" == "false" ]] || auto_stop="false"
    [[ "$prev_consumed" =~ ^[0-9]+$ ]] || prev_consumed=0

    # 先写临时文件再原子替换，避免与后台检查线程并发写坏配置
    rm -f "${TARGET_CONFIG_FILE}".tmp.*
    local tmp_file="${TARGET_CONFIG_FILE}.tmp.$$"
    {
        echo "# 流量目标配置"
        write_config_line "TARGET_GB" "$target_gb" || return 1
        write_config_line "TARGET_START_RX" "$start_rx" || return 1
        write_config_line "TARGET_INTERFACE" "$interface" || return 1
        write_config_line "TARGET_SET_TIME" "$(date '+%Y-%m-%d %H:%M:%S')" || return 1
        write_config_line "TARGET_AUTO_STOP" "$auto_stop" || return 1
        write_config_line "TARGET_PREV_CONSUMED" "$prev_consumed" || return 1
    } > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv -f "$tmp_file" "$TARGET_CONFIG_FILE"
    chmod 600 "$TARGET_CONFIG_FILE" 2>/dev/null
}

load_target_config() {
    unset TARGET_GB TARGET_START_RX TARGET_INTERFACE TARGET_SET_TIME TARGET_AUTO_STOP TARGET_PREV_CONSUMED
    safe_source_config "$TARGET_CONFIG_FILE" TARGET_GB TARGET_START_RX TARGET_INTERFACE TARGET_SET_TIME TARGET_AUTO_STOP TARGET_PREV_CONSUMED
}

# 计算流量目标进度，结果写入以下全局变量；无有效目标时返回 1 并清空。
#   TARGET_CONSUMED_BYTES / TARGET_TOTAL_BYTES / TARGET_PERCENT
target_progress() {
    TARGET_CONSUMED_BYTES=0
    TARGET_TOTAL_BYTES=0
    TARGET_PERCENT=""

    load_target_config 2>/dev/null || return 1
    [[ "$TARGET_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    [[ "$TARGET_GB" != "0" ]] || return 1

    local interface="${TARGET_INTERFACE:-}"
    if [[ -z "$interface" || ! -r "/sys/class/net/$interface/statistics/rx_bytes" ]]; then
        interface="${LAST_INTERFACE:-}"
    fi
    [[ -n "$interface" && -r "/sys/class/net/$interface/statistics/rx_bytes" ]] || return 1

    local current_rx start_rx previous total
    current_rx=$(< "/sys/class/net/$interface/statistics/rx_bytes") || current_rx=0
    [[ "$current_rx" =~ ^[0-9]+$ ]] || current_rx=0
    start_rx="${TARGET_START_RX:-$current_rx}"
    [[ "$start_rx" =~ ^[0-9]+$ ]] || start_rx=$current_rx
    previous="${TARGET_PREV_CONSUMED:-0}"
    [[ "$previous" =~ ^[0-9]+$ ]] || previous=0

    # 网卡计数回绕（重启或重置）时只累加当前值，避免出现负数
    if (( current_rx >= start_rx )); then
        TARGET_CONSUMED_BYTES=$(( current_rx - start_rx + previous ))
    else
        TARGET_CONSUMED_BYTES=$(( current_rx + previous ))
    fi

    total=$(awk -v gb="$TARGET_GB" 'BEGIN { printf "%.0f", gb * 1073741824 }' 2>/dev/null)
    [[ "$total" =~ ^[0-9]+$ ]] || return 1
    (( total > 0 )) || return 1
    TARGET_TOTAL_BYTES=$total

    TARGET_PERCENT=$(( TARGET_CONSUMED_BYTES * 100 / TARGET_TOTAL_BYTES ))
    (( TARGET_PERCENT > 100 )) && TARGET_PERCENT=100
    return 0
}

# 生成一行流量目标摘要写入指定变量，同时刷新 TARGET_PERCENT 供进度条使用
# 用法：get_target_summary <变量名> [compact]，compact 用于窄终端，省略自动停止状态
get_target_summary() {
    local __var="$1" mode="${2:-full}" summary consumed_gb auto_stop
    if target_progress; then
        consumed_gb=$(awk -v b="$TARGET_CONSUMED_BYTES" 'BEGIN { printf "%.2f", b / 1073741824 }')
        summary="${VALUE}${consumed_gb}${RESET}${MUTED} / ${RESET}${VALUE}${TARGET_GB} GB${RESET} ${MUTED}·${RESET} ${VALUE}${TARGET_PERCENT}%${RESET}"
        if [[ "$mode" != "compact" ]]; then
            auto_stop="${MUTED}· 自动停止 关${RESET}"
            [[ "${TARGET_AUTO_STOP:-false}" == "true" ]] && auto_stop="${SUCCESS}· 自动停止 开${RESET}"
            summary="${summary} ${auto_stop}"
        fi
    else
        summary="${MUTED}未设置${RESET}"
    fi
    printf -v "$__var" '%s' "$summary"
}

# 安全的网络接口检测 - 自动选择第一个可用接口
detect_network_interface() {
    local -a interfaces=()
    mapfile -t interfaces < <(list_network_interfaces)

    if [[ ${#interfaces[@]} -eq 0 ]]; then
        echo "未找到可用的网络接口" >&2
        return 1
    fi

    # 自动选择第一个可用接口，优先选择以eth、ens、enp开头的接口
    local selected_interface="" interface
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
    local max_cores
    max_cores=$(nproc)
    local max_threads=$((max_cores * 4))

    if ! [[ "$threads" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${DANGER}  ❌ 线程数必须为正整数${RESET}"
        return 1
    fi

    if [[ $threads -gt $max_threads ]]; then
        echo -e "${WARNING}  ⚠️  线程数过高（推荐最大：$max_threads），可能影响系统性能${RESET}"
        read -r -p "  是否继续？(y/N)：" confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || return 1
    fi

    return 0
}

# 保存配置（USAGE_COUNT 由主入口累加，这里原样保留；INSTALL_TIME 保持不变）
save_config() {
    local url="$1" threads="$2" interface="$3"
    validate_url "$url" || {
        echo -e "${DANGER}❌ URL 格式不安全，配置未保存${RESET}"
        return 1
    }
    [[ "$threads" =~ ^[1-9][0-9]*$ ]] || return 1
    validate_interface_name "$interface" || return 1

    local usage_count="${USAGE_COUNT:-0}" install_time
    [[ "$usage_count" =~ ^[0-9]+$ ]] || usage_count=0
    install_time="${INSTALL_TIME:-$(date '+%Y-%m-%d %H:%M:%S')}"

    {
        echo "# ═══════════════════════════════════════════════════════════════════"
        echo "# 配置文件 - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# ═══════════════════════════════════════════════════════════════════"
        write_config_line "LAST_URL" "$url" || return 1
        write_config_line "LAST_THREADS" "$threads" || return 1
        write_config_line "LAST_INTERFACE" "$interface" || return 1
        write_config_line "INSTALL_TIME" "$install_time" || return 1
        write_config_line "USAGE_COUNT" "$usage_count" || return 1
        write_config_line "LAST_USED" "$(date '+%Y-%m-%d %H:%M:%S')" || return 1
        echo "# ═══════════════════════════════════════════════════════════════════"
    } > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE" 2>/dev/null
}

# （v3.3 已移除未使用的预设保存/加载函数，URL 预设直接内置在启动菜单中）

# 读取配置
load_config() {
    unset LAST_URL LAST_THREADS LAST_INTERFACE INSTALL_TIME USAGE_COUNT LAST_USED
    safe_source_config "$CONFIG_FILE" LAST_URL LAST_THREADS LAST_INTERFACE INSTALL_TIME USAGE_COUNT LAST_USED || return 1
}

# ──────────────────────────────── 快捷键管理 ──────────────────────────────────

# 创建快捷键脚本：create_shortcut [快捷键名] [目标脚本路径]
# 目标脚本路径默认取 $0；迁移场景下需要显式指向新路径
create_shortcut() {
    local shortcut_name="${1:-$(get_shortcut_name)}"
    [[ -z "$shortcut_name" ]] && shortcut_name="$DEFAULT_SHORTCUT"
    [[ "$shortcut_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || shortcut_name="$DEFAULT_SHORTCUT"
    local shortcut_path="/usr/local/bin/$shortcut_name"
    local script_path
    script_path=$(readlink -f "${2:-$0}")
    local script_dir
    script_dir=$(dirname "$script_path")

    echo -e "${INFO}正在设置快捷键 ${PRIMARY}$shortcut_name${RESET}${INFO}...${RESET}"

    # 删除旧的快捷键
    if [[ -f "$SHORTCUT_CONFIG" ]]; then
        safe_source_config "$SHORTCUT_CONFIG" SHORTCUT_NAME SHORTCUT_PATH CREATED_TIME || SHORTCUT_PATH=""
        [[ "$SHORTCUT_PATH" =~ ^/usr/local/bin/[A-Za-z][A-Za-z0-9_]*$ ]] && rm -f "$SHORTCUT_PATH"
    fi

    cat > "$shortcut_path" << EOF
#!/bin/bash
# VPS流量消耗管理工具快捷启动脚本
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
        safe_source_config "$SHORTCUT_CONFIG" SHORTCUT_NAME SHORTCUT_PATH CREATED_TIME || SHORTCUT_PATH=""
        if [[ "$SHORTCUT_PATH" =~ ^/usr/local/bin/[A-Za-z][A-Za-z0-9_]*$ && -f "$SHORTCUT_PATH" ]]; then
            rm -f "$SHORTCUT_PATH"
            echo -e "${WARNING}已删除快捷键: ${PRIMARY}$(basename "$SHORTCUT_PATH")${RESET}"
        fi
        rm -f "$SHORTCUT_CONFIG"
    else
        echo -e "${WARNING}未找到快捷键配置${RESET}"
    fi
}

# ──────────────────────────── 旧版本（milier_*）迁移 ──────────────────────────
# v3.4.0 起标识符统一为 vpsflow_*。已装旧版的机器如果不迁移，会留下一个仍在跑的
# milier_flow 服务和一堆孤儿文件，这里在启动时一次性接管并清理。

LEGACY_SERVICE="milier_flow"
LEGACY_SCRIPT="/root/milier_flow.sh"

# 是否存在旧版安装痕迹
has_legacy_install() {
    [[ -f "/etc/systemd/system/${LEGACY_SERVICE}.service" ]] && return 0
    local f
    for f in "$LEGACY_SCRIPT" /root/milier_config.conf /root/milier_target.conf \
             /root/milier_shortcut.conf /root/milier_start.sh /root/milier_monitor.sh; do
        [[ -e "$f" ]] && return 0
    done
    return 1
}

migrate_legacy_install() {
    has_legacy_install || return 0

    local self shortcut_name f
    self=$(readlink -f "$0")

    echo
    ui_warn "检测到旧版本安装，正在迁移到新的命名..."

    # 1. 停止并移除旧服务，清掉残留下载线程
    if [[ -f "/etc/systemd/system/${LEGACY_SERVICE}.service" ]]; then
        systemctl stop "$LEGACY_SERVICE" 2>/dev/null
        systemctl disable "$LEGACY_SERVICE" 2>/dev/null
        rm -f "/etc/systemd/system/${LEGACY_SERVICE}.service"
        systemctl daemon-reload 2>/dev/null
    fi
    pkill -f milier_thread 2>/dev/null
    pkill -f "curl -A MilierFlow" 2>/dev/null

    # 2. 迁移配置与日志（新文件已存在时不覆盖）
    [[ -f /root/milier_config.conf && ! -f "$CONFIG_FILE" ]] \
        && mv -f /root/milier_config.conf "$CONFIG_FILE"
    [[ -f /root/milier_target.conf && ! -f "$TARGET_CONFIG_FILE" ]] \
        && mv -f /root/milier_target.conf "$TARGET_CONFIG_FILE"
    [[ -f /root/milier_flow.log && ! -f "$LOG_FILE" ]] \
        && mv -f /root/milier_flow.log "$LOG_FILE"

    # 3. 记住旧快捷键名（旧快捷键文件指向旧脚本路径，需要重建）
    shortcut_name="$DEFAULT_SHORTCUT"
    if [[ -f /root/milier_shortcut.conf ]]; then
        SHORTCUT_NAME=""
        safe_source_config /root/milier_shortcut.conf SHORTCUT_NAME SHORTCUT_PATH CREATED_TIME 2>/dev/null
        [[ "$SHORTCUT_NAME" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] && shortcut_name="$SHORTCUT_NAME"
        rm -f /root/milier_shortcut.conf
    fi

    # 4. 清理旧定时任务、辅助脚本与缓存（不删正在运行的自己）
    crontab -l 2>/dev/null | grep -v "milier_target_check.sh" | crontab - 2>/dev/null
    for f in /root/milier_monitor.sh /root/milier_uninstall.sh /root/milier_start.sh \
             /root/milier_target_check.sh /root/milier_presets.conf \
             /root/milier_monitor_data.log /root/.milier_menu_speed.state; do
        [[ "$f" == "$self" ]] || rm -f "$f"
    done
    rm -f /root/milier_flow*.log /tmp/milier_*
    rm -rf /run/milier

    # 5. 主脚本仍在旧路径运行时（旧版通过“检查更新”原地升级的情况），
    #    迁到新路径、重建快捷键，再从新路径重启
    if [[ "$self" == "$LEGACY_SCRIPT" ]]; then
        if install -m 755 "$self" "/root/$SCRIPT_NAME"; then
            rm -f "$self"
            create_shortcut "$shortcut_name" "/root/$SCRIPT_NAME"
            ui_ok "已迁移到 /root/$SCRIPT_NAME，正在重启..."
            sleep 1
            exec bash "/root/$SCRIPT_NAME"
        fi
        ui_err "迁移到新路径失败，请重新运行安装命令"
        return 1
    fi

    create_shortcut "$shortcut_name"
    ui_ok "旧版本已迁移完成"
    sleep 1
}

# ──────────────────────────────── 初始化服务 ──────────────────────────────────
# 输出嵌入到生成脚本（vpsflow_start.sh / vpsflow_target_check.sh / 监控脚本）中的公共安全函数库
emit_common_library() {
    cat << 'LIBEOF'
is_safe_config_value() {
  local value="$1"
  [[ "$value" != *$'\n'* ]] || return 1
  [[ "$value" != *$'\r'* ]] || return 1
  [[ "$value" != *'"'* ]] || return 1
  [[ "$value" != *'`'* ]] || return 1
  [[ "$value" != *'$'* ]] || return 1
  [[ "$value" != *\\* ]] || return 1
}

safe_source_target_config() {
  local file="/root/vpsflow_target.conf"
  [[ -f "$file" ]] || return 1
  local allowed=" TARGET_GB TARGET_START_RX TARGET_INTERFACE TARGET_SET_TIME TARGET_AUTO_STOP TARGET_PREV_CONSUMED "
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=\"([^\"]*)\"[[:space:]]*$ ]] || return 1
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    [[ "$allowed" == *" $key "* ]] || return 1
    is_safe_config_value "$value" || return 1
  done < "$file"
  source "$file"
}
LIBEOF
}

# 创建后台启动脚本 /root/vpsflow_start.sh
create_start_script() {
    {
        echo '#!/bin/bash'
        emit_common_library
        cat << 'STARTEOF'
# 流量消耗后台启动脚本
URL="$VPSFLOW_URL"
THREADS="$VPSFLOW_THREADS"
LOG_FILE="/root/vpsflow.log"
TARGET_FILE="/root/vpsflow_target.conf"

[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || THREADS=1

write_target_runtime_config() {
  local tmp_file="${TARGET_FILE}.tmp.$$"
  cat > "$tmp_file" << EOF
# 流量目标配置
TARGET_GB="$TARGET_GB"
TARGET_START_RX="$TARGET_START_RX"
TARGET_INTERFACE="$TARGET_INTERFACE"
TARGET_SET_TIME="${TARGET_SET_TIME:-未知}"
TARGET_AUTO_STOP="${TARGET_AUTO_STOP:-true}"
TARGET_PREV_CONSUMED="${TARGET_PREV_CONSUMED:-0}"
EOF
  mv -f "$tmp_file" "$TARGET_FILE" 2>/dev/null
  chmod 600 "$TARGET_FILE" 2>/dev/null
}

echo "$(date "+%Y-%m-%d %H:%M:%S"): [启动] $THREADS 线程开始下载 $URL" | tee -a "$LOG_FILE"

# 1. 流量自检后台线程
if [[ -f "$TARGET_FILE" ]]; then
  (
    while true; do
      safe_source_target_config || { sleep 5; continue; }
      if [[ "$TARGET_AUTO_STOP" == "true" ]] && [[ "$TARGET_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        INTERFACE="${TARGET_INTERFACE:-eth0}"
        [[ "$INTERFACE" =~ ^[A-Za-z0-9_.:-]+$ ]] || { sleep 5; continue; }
        CURRENT_RX=$(cat "/sys/class/net/$INTERFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
        START_RX="${TARGET_START_RX:-0}"
        PREV_CONSUMED="${TARGET_PREV_CONSUMED:-0}"
        [[ "$CURRENT_RX" =~ ^[0-9]+$ ]] || CURRENT_RX=0
        [[ "$START_RX" =~ ^[0-9]+$ ]] || START_RX=0
        [[ "$PREV_CONSUMED" =~ ^[0-9]+$ ]] || PREV_CONSUMED=0

      # 容错：防止系统重启/网卡重置导致 rx_bytes 清零
        if [[ $CURRENT_RX -lt $START_RX ]]; then
          PREV_CONSUMED=$((PREV_CONSUMED + START_RX))
          START_RX=$CURRENT_RX
          TARGET_START_RX="$START_RX"
          TARGET_PREV_CONSUMED="$PREV_CONSUMED"
          write_target_runtime_config
        fi

        CONSUMED=$((CURRENT_RX - START_RX + PREV_CONSUMED))
        TARGET_BYTES=$(awk -v gb="$TARGET_GB" 'BEGIN { printf "%.0f", gb * 1073741824 }' 2>/dev/null || echo 0)
        TARGET_BYTES="${TARGET_BYTES%.*}"
        [[ "$TARGET_BYTES" =~ ^[0-9]+$ && "$TARGET_BYTES" -gt 0 ]] || { sleep 5; continue; }

        if [[ $CONSUMED -ge $TARGET_BYTES ]] 2>/dev/null; then
          echo "$(date '+%Y-%m-%d %H:%M:%S'): 流量目标 ${TARGET_GB}GB 已达成，服务自动停止" >> "$LOG_FILE"
          systemctl stop vpsflow
          exit 0
        fi
      fi
      sleep 5
    done
  ) &
fi

# 2. 启动下载并发线程
for ((i=1;i<=THREADS;i++)); do
  bash -c 'while true; do
    if curl -A "VPSFlow" -s -m 30 --connect-timeout 10 --retry 2 --retry-delay 1 -o /dev/null "$1"; then
      sleep 0.1
    else
      sleep 2
    fi
  done' vpsflow_thread "$URL" &
done

wait
STARTEOF
    } > /root/vpsflow_start.sh
    chmod +x /root/vpsflow_start.sh
}

# 创建 systemd 服务单元；优先沿用已保存的 URL/线程数
create_service_file() {
    local url="$1" threads="$2"
    if load_config 2>/dev/null; then
        [[ -n "$LAST_URL" ]] && validate_url "$LAST_URL" && url="$LAST_URL"
        [[ "$LAST_THREADS" =~ ^[1-9][0-9]*$ ]] && threads="$LAST_THREADS"
    fi

    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=VPS 流量消耗后台服务
After=network.target
StartLimitBurst=3
StartLimitIntervalSec=60

[Service]
Type=simple
WorkingDirectory=/root
Environment="VPSFLOW_URL=$url"
Environment="VPSFLOW_THREADS=$threads"
ExecStart=/bin/bash /root/vpsflow_start.sh
ExecStop=/usr/bin/pkill -f vpsflow_thread
ExecStopPost=/bin/bash -c 'pkill -f vpsflow_check; pkill -f "curl -A VPSFlow"; echo "\$(date "+%%Y-%%m-%%d %%H:%%M:%%S"): [停止] 服务已停止" >> $LOG_FILE'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    check_command "系统配置失败" || return 1
}

# 创建实时监控脚本 /root/vpsflow_monitor.sh
create_monitor_script() {
    {
        echo '#!/bin/bash'
        emit_common_library
        cat << 'MONITOREOF'
# VPS 实时流量监控
INTERFACE=$1

# ── 配色（与主控制台保持一致） ──
PRIMARY="\e[96m"; SUCCESS="\e[92m"; WARNING="\e[93m"; DANGER="\e[91m"
INFO="\e[96m"; WHITE="\e[97m"; MUTED="\e[37m"; PANEL="\e[37m"
VALUE="\e[97m"; BOLD="\e[1m"; RESET="\e[0m"

if [[ ! -t 1 || -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
    PRIMARY=""; SUCCESS=""; WARNING=""; DANGER=""; INFO=""; WHITE=""
    MUTED=""; PANEL=""; VALUE=""; BOLD=""; RESET=""
fi

die() {
    printf '  %b❌ %s%b\n' "$DANGER" "$1" "$RESET" >&2
    [[ -t 0 ]] && read -r -p "  按回车继续..."
    exit 1
}

# ── 参数与环境校验 ──
[[ -n "$INTERFACE" ]] || die "未指定网络接口，用法：$0 <网络接口名>"
[[ -d "/sys/class/net/$INTERFACE" ]] || die "网络接口 '$INTERFACE' 不存在"
[[ -r "/sys/class/net/$INTERFACE/statistics/rx_bytes" && -r "/sys/class/net/$INTERFACE/statistics/tx_bytes" ]] \
    || die "无法读取 $INTERFACE 的统计信息，请确认以 root 权限运行"

for cmd in awk cat; do
    command -v "$cmd" &>/dev/null || die "缺少必要命令：$cmd"
done

# ── 排版工具 ──
ui_width() {
    local w
    w=$(tput cols 2>/dev/null)
    [[ "$w" =~ ^[0-9]+$ ]] || w=80
    (( w < 60 )) && w=60
    (( w > 96 )) && w=96
    printf '%d' "$w"
}

repeat() {
    local ch="$1" n="$2" out
    [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )) || return 0
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$ch}"
}

rule() { printf '  %b%s%b\n' "$PANEL" "$(repeat '─' $(( $(ui_width) - 4 )))" "$RESET"; }

# 速率格式化：统一保留两位小数
format_speed() {
    local bytes=$1
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if (( bytes >= 1073741824 )); then
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB/s", b/1073741824 }'
    elif (( bytes >= 1048576 )); then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB/s", b/1048576 }'
    elif (( bytes >= 1024 )); then
        awk -v b="$bytes" 'BEGIN { printf "%.2f KB/s", b/1024 }'
    else
        printf '%d B/s' "$bytes"
    fi
}

format_total() {
    local bytes=$1
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if (( bytes >= 1073741824 )); then
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB", b/1073741824 }'
    elif (( bytes >= 1048576 )); then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB", b/1048576 }'
    elif (( bytes >= 1024 )); then
        awk -v b="$bytes" 'BEGIN { printf "%.2f KB", b/1024 }'
    else
        printf '%d B' "$bytes"
    fi
}

# 进度条，宽度随终端自适应
draw_bar() {
    local rate=$1 max_rate=$2 width=$3 fill i
    [[ "$rate" =~ ^[0-9]+$ ]] || rate=0
    [[ "$max_rate" =~ ^[0-9]+$ ]] && (( max_rate > 0 )) || max_rate=1
    [[ "$width" =~ ^[1-9][0-9]*$ ]] || width=30
    fill=$(( rate * width / max_rate ))
    (( fill > width )) && fill=$width
    (( fill < 0 )) && fill=0
    printf '%b[%b' "$PANEL" "$RESET"
    printf '%b%s%b' "$PRIMARY" "$(repeat '█' "$fill")" "$RESET"
    printf '%b%s%b' "$MUTED" "$(repeat '░' $((width - fill)))" "$RESET"
    printf '%b]%b' "$PANEL" "$RESET"
}

safe_read_bytes() {
    local file="$1" value
    if [[ -r "$file" ]]; then
        value=$(< "$file")
        [[ "$value" =~ ^[0-9]+$ ]] && { printf '%s' "$value"; return 0; }
    fi
    printf '0'
}

# 流量目标进度（safe_source_target_config 由公共函数库提供）
show_target_progress() {
    safe_source_target_config || return 0
    [[ "$TARGET_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 0
    [[ "$TARGET_GB" != "0" ]] || return 0

    local current_rx start_rx prev_consumed consumed consumed_gb target_bytes percent
    current_rx=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/rx_bytes")
    start_rx="${TARGET_START_RX:-0}"
    prev_consumed="${TARGET_PREV_CONSUMED:-0}"
    [[ "$start_rx" =~ ^[0-9]+$ ]] || start_rx=0
    [[ "$prev_consumed" =~ ^[0-9]+$ ]] || prev_consumed=0

    # 网卡计数回绕（重启或重置）时只累加当前值，避免出现负数
    if (( current_rx >= start_rx )); then
        consumed=$(( current_rx - start_rx + prev_consumed ))
    else
        consumed=$(( current_rx + prev_consumed ))
    fi

    consumed_gb=$(awk -v b="$consumed" 'BEGIN { printf "%.2f", b/1073741824 }')
    target_bytes=$(awk -v gb="$TARGET_GB" 'BEGIN { printf "%.0f", gb * 1073741824 }')
    [[ "$target_bytes" =~ ^[0-9]+$ ]] || target_bytes=0
    percent=$(( target_bytes > 0 ? consumed * 100 / target_bytes : 0 ))
    (( percent > 100 )) && percent=100

    rule
    printf '  %b目标%b   %b%s%b%b / %s GB · %d%%%b  %s\n' \
        "$MUTED" "$RESET" "$VALUE" "$consumed_gb" "$RESET" \
        "$MUTED" "$TARGET_GB" "$percent" "$RESET" "$(draw_bar "$percent" 100 20)"
}

# ── 初始化 ──
RX_PREV=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/rx_bytes")
TX_PREV=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/tx_bytes")
RX_TOTAL=0; TX_TOTAL=0; DURATION=0
RX_PEAK=0; TX_PEAK=0

trap 'printf "\033[H\033[J"; printf "  %b监控已停止%b\n\n" "$WARNING" "$RESET"; exit 0' INT TERM

printf '\033[H\033[J'

# ── 主循环 ──
while true; do
    sleep 1
    ((DURATION++))

    # 定期确认接口仍然存在
    if (( DURATION % 30 == 0 )) && [[ ! -d "/sys/class/net/$INTERFACE" ]]; then
        printf '\033[H\033[J'
        printf '  %b网络接口 %s 已不存在%b\n' "$DANGER" "$INTERFACE" "$RESET"
        break
    fi

    RX_CUR=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/rx_bytes")
    TX_CUR=$(safe_read_bytes "/sys/class/net/$INTERFACE/statistics/tx_bytes")

    RX_RATE=$(( RX_CUR >= RX_PREV ? RX_CUR - RX_PREV : 0 ))
    TX_RATE=$(( TX_CUR >= TX_PREV ? TX_CUR - TX_PREV : 0 ))
    # 单秒超过 1GB 视为计数异常，丢弃该采样
    (( RX_RATE > 1073741824 )) && RX_RATE=0
    (( TX_RATE > 1073741824 )) && TX_RATE=0

    RX_PREV=$RX_CUR; TX_PREV=$TX_CUR
    RX_TOTAL=$((RX_TOTAL + RX_RATE)); TX_TOTAL=$((TX_TOTAL + TX_RATE))
    (( RX_RATE > RX_PEAK )) && RX_PEAK=$RX_RATE
    (( TX_RATE > TX_PEAK )) && TX_PEAK=$TX_RATE

    AVG_RX=$(( DURATION > 0 ? RX_TOTAL / DURATION : 0 ))
    AVG_TX=$(( DURATION > 0 ? TX_TOTAL / DURATION : 0 ))

    # 进度条刻度：下载与上传共用，最低 10MB/s
    MAX_SPEED=$((10*1024*1024))
    (( RX_RATE > MAX_SPEED )) && MAX_SPEED=$RX_RATE
    (( TX_RATE > MAX_SPEED )) && MAX_SPEED=$TX_RATE

    WIDTH=$(ui_width)
    BAR_LEN=$(( WIDTH - 22 ))
    (( BAR_LEN > 46 )) && BAR_LEN=46
    (( BAR_LEN < 16 )) && BAR_LEN=16

    HOURS=$((DURATION / 3600)); MINS=$(((DURATION % 3600) / 60)); SECS=$((DURATION % 60))
    HEADER_RIGHT=$(printf '%s · %02d:%02d:%02d' "$INTERFACE" "$HOURS" "$MINS" "$SECS")
    GAP=$(( WIDTH - 4 - 12 - ${#HEADER_RIGHT} ))
    (( GAP < 2 )) && GAP=2

    # ── 整屏重绘 ──
    printf '\033[H'
    echo
    printf '  %b%b实时流量监控%b%s%b%s%b\n' "$WHITE" "$BOLD" "$RESET" \
        "$(repeat ' ' "$GAP")" "$MUTED" "$HEADER_RIGHT" "$RESET"
    rule
    echo

    printf '  %b↓ 下载%b  %b%-12s%b  %s\n' "$SUCCESS" "$RESET" "$VALUE" \
        "$(format_speed "$RX_RATE")" "$RESET" "$(draw_bar "$RX_RATE" "$MAX_SPEED" "$BAR_LEN")"
    printf '  %b        累计 %s · 平均 %s · 峰值 %s%b\n' "$MUTED" \
        "$(format_total "$RX_TOTAL")" "$(format_speed "$AVG_RX")" "$(format_speed "$RX_PEAK")" "$RESET"
    echo

    printf '  %b↑ 上传%b  %b%-12s%b  %s\n' "$WARNING" "$RESET" "$VALUE" \
        "$(format_speed "$TX_RATE")" "$RESET" "$(draw_bar "$TX_RATE" "$MAX_SPEED" "$BAR_LEN")"
    printf '  %b        累计 %s · 平均 %s · 峰值 %s%b\n' "$MUTED" \
        "$(format_total "$TX_TOTAL")" "$(format_speed "$AVG_TX")" "$(format_speed "$TX_PEAK")" "$RESET"
    echo

    show_target_progress

    rule
    printf '  %bQ / ESC / Ctrl+C 退出监控%b\n' "$MUTED" "$RESET"
    printf '\033[J'

    # 按键退出
    if read -rsn1 -t 0.1 key 2>/dev/null; then
        [[ "$key" == "q" || "$key" == "Q" || "$key" == $'\e' ]] && break
    fi
done

printf '\033[H\033[J'
printf '  %b监控已结束%b\n\n' "$INFO" "$RESET"
MONITOREOF
    } > "$MONITOR_SCRIPT"
    chmod +x "$MONITOR_SCRIPT"
}

# 创建卸载脚本
create_uninstall_script() {
    cat > "$UNINSTALL_SCRIPT" << EOF
#!/bin/bash
SUCCESS="\e[32m"; WARNING="\e[33m"; WHITE="\e[97m"; BOLD="\e[1m"; RESET="\e[0m"

echo -e "\${WARNING}正在卸载服务...\${RESET}"
systemctl stop $SERVICE_NAME 2>/dev/null
systemctl disable $SERVICE_NAME 2>/dev/null
rm -f /etc/systemd/system/$SERVICE_NAME.service
systemctl daemon-reload

# 删除快捷键
if [[ -f "$SHORTCUT_CONFIG" ]]; then
    shortcut_path=\$(awk -F'"' '/^SHORTCUT_PATH="/ {print \$2; exit}' "$SHORTCUT_CONFIG" 2>/dev/null)
    [[ "\$shortcut_path" =~ ^/usr/local/bin/[A-Za-z][A-Za-z0-9_]*$ ]] && rm -f "\$shortcut_path"
fi

pkill -f vpsflow_thread 2>/dev/null
pkill -f vpsflow_check 2>/dev/null
pkill -f "curl -A VPSFlow" 2>/dev/null
crontab -l 2>/dev/null | grep -v "vpsflow_target_check.sh" | crontab - 2>/dev/null
rm -f "$MONITOR_SCRIPT" "$UNINSTALL_SCRIPT" "$LOG_FILE" "$CONFIG_FILE" "$SHORTCUT_CONFIG" "$TARGET_CONFIG_FILE" "$PRESET_CONFIG_FILE" "/root/vpsflow_start.sh" "/root/vpsflow_target_check.sh" "/root/$SCRIPT_NAME" "/root/vpsflow_monitor_data.log" /tmp/vpsflow_latest_check.* /tmp/vpsflow_* 2>/dev/null
echo -e "\${SUCCESS}✅ 卸载完成\${RESET}"
EOF
    chmod +x "$UNINSTALL_SCRIPT"
}

init_service() {
    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]] && [[ -f "/root/vpsflow_start.sh" ]] \
        && [[ -f "$MONITOR_SCRIPT" ]] && [[ -f "$UNINSTALL_SCRIPT" ]]; then
        return 0
    fi

    echo -e "${WARNING}⚠️  正在初始化服务...${RESET}"

    # 检查系统权限
    if [[ $EUID -ne 0 ]]; then
        error_notice "需要 root 权限运行此脚本"
        return 1
    fi

    # 创建必要目录和文件
    mkdir -p /root
    touch "$LOG_FILE" && chmod 644 "$LOG_FILE"
    check_command "创建文件失败" || return 1

    # 网络接口检测与默认配置
    local interface cpu_cores default_threads default_url
    interface=$(detect_network_interface)
    [[ $? -ne 0 ]] && return 1
    cpu_cores=$(nproc)
    default_threads=$((cpu_cores * 2))
    default_url="https://speed.cloudflare.com/__down?bytes=104857600"

    # 只补建缺失的部分，避免覆盖用户已有配置
    [[ -f "/root/vpsflow_start.sh" ]] || create_start_script
    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        systemctl daemon-reload 2>/dev/null
    else
        create_service_file "$default_url" "$default_threads"
    fi
    [[ -f "$MONITOR_SCRIPT" ]] || create_monitor_script
    [[ -f "$UNINSTALL_SCRIPT" ]] || create_uninstall_script

    # 仅首次安装时写入默认配置与快捷键
    if [[ ! -f "$CONFIG_FILE" ]]; then
        save_config "$default_url" "$default_threads" "$interface"
    fi
    if [[ ! -f "$SHORTCUT_CONFIG" ]]; then
        create_shortcut "$DEFAULT_SHORTCUT"
    fi

    echo -e "${SUCCESS}✅ 初始化完成${RESET}"
}

# ──────────────────────────────── 服务管理函数 ──────────────────────────────────

# 交互式下载源选择：方向键 + 回车 + 数字键直达；返回选项编号（Q 返回 0）
select_url_choice() {
    local -a keys=(1 2 3 4 5 6)
    [[ -n "$LAST_URL" ]] && keys+=(7)
    keys+=(8)
    local count=${#keys[@]} sel=0 k i cur plain_choice

    # 非交互终端：退回传统数字输入，避免 read -rsn1 失败导致死循环
    if [[ ! -t 0 || ! -t 1 ]]; then
        ui_info "请选择下载源："
        for ((i=0; i<MIRROR_COUNT; i++)); do
            url_row $((i+1)) "${MIRROR_NAMES[$i]}" "${MIRROR_HINTS[$i]}" ""
        done
        [[ -n "$LAST_URL" ]] && url_row 7 "上次使用" "$LAST_URL" ""
        url_row 8 "自定义 URL" "手动输入任意下载链接" ""
        if ! read -r -p "${UI_INDENT}请选择 [1]: " plain_choice; then
            echo
            printf '%s\n' "1"
            return 0
        fi
        plain_choice=${plain_choice:-1}
        [[ "$plain_choice" =~ ^[1-8]$ ]] || plain_choice=1
        [[ "$plain_choice" == "7" && -z "$LAST_URL" ]] && plain_choice=1
        printf '%s\n' "$plain_choice"
        return 0
    fi

    while true; do
        ui_page "选择下载源"
        cur="${keys[$sel]}"

        ui_group "亚洲节点"
        for ((i=0; i<3 && i<MIRROR_COUNT; i++)); do
            url_row $((i+1)) "${MIRROR_NAMES[$i]}" "${MIRROR_HINTS[$i]}" "$cur"
        done
        echo
        ui_group "欧美节点"
        for ((i=3; i<MIRROR_COUNT; i++)); do
            url_row $((i+1)) "${MIRROR_NAMES[$i]}" "${MIRROR_HINTS[$i]}" "$cur"
        done
        echo
        ui_group "其他"
        [[ -n "$LAST_URL" ]] && url_row 7 "上次使用" "$LAST_URL" "$cur"
        url_row 8 "自定义 URL" "手动输入任意下载链接" "$cur"

        echo
        ui_rule
        ui_keyhint "↑↓ 选择 · Enter 确认 · 数字直达 · Q 返回"

        k=$(menu_read_key)
        case "$k" in
            TIMEOUT) continue ;;
            EOF)     printf '%s\n' "0"; return 0 ;;
            UP)      sel=$(( (sel - 1 + count) % count )) ;;
            DOWN)    sel=$(( (sel + 1) % count )) ;;
            ENTER)   printf '%s\n' "${keys[$sel]}"; return 0 ;;
            ESC)     : ;;
            *)
                [[ "${k^^}" == "Q" ]] && { printf '%s\n' "0"; return 0; }
                [[ "${k^^}" == "K" ]] && { sel=$(( (sel - 1 + count) % count )); continue; }
                [[ "${k^^}" == "J" ]] && { sel=$(( (sel + 1) % count )); continue; }
                for ((i=0; i<count; i++)); do
                    if [[ "$k" == "${keys[$i]}" ]]; then
                        printf '%s\n' "${keys[$i]}"
                        return 0
                    fi
                done
                ;;
        esac
    done
}

# 单个下载源选项行；名称与说明分列对齐，当前项整行反色
url_row() {
    local num="$1" name="$2" hint="$3" cur="$4" plain pad width name_pad
    width=$(ui_inner)
    (( width > 74 )) && width=74
    name_pad=$(( 30 - $(str_width "$name") ))
    (( name_pad < 2 )) && name_pad=2
    plain="[${num}] ${name}"
    [[ -n "$hint" ]] && plain="${plain}$(repeat ' ' "$name_pad")${hint}"
    pad=$(( width - 2 - $(str_width "$plain") ))
    (( pad < 0 )) && pad=0
    if [[ "$num" == "$cur" ]]; then
        printf '%s%b▸ %s%s%b\n' "$UI_INDENT" "$REV" "$plain" "$(repeat ' ' "$pad")" "$RESET"
    elif [[ -z "$hint" ]]; then
        printf '%s  %b[%s]%b %b%s%b\n' "$UI_INDENT" "$KEY" "$num" "$RESET" "$WHITE" "$name" "$RESET"
    else
        printf '%s  %b[%s]%b %b%s%b%s%b%s%b\n' "$UI_INDENT" \
            "$KEY" "$num" "$RESET" "$WHITE" "$name" "$RESET" \
            "$(repeat ' ' "$name_pad")" "$MUTED" "$hint" "$RESET"
    fi
}

# 启动服务：选择下载源 → 设置线程数 → 确认 → 写入 systemd 并启动
start_service() {
    local url="" threads="" interface="" url_choice confirm escaped_url
    local cpu_cores recommended_threads
    load_config

    url_choice=$(select_url_choice)
    [[ "$url_choice" == "0" ]] && return

    case "$url_choice" in
        [1-6]) url="${MIRROR_URLS[$((url_choice - 1))]}" ;;
        7)     url="${LAST_URL:-${MIRROR_URLS[0]}}" ;;
        8)
            ui_page "自定义下载源"
            ui_note "需以 http:// 或 https:// 开头，不能包含空格与引号"
            echo
            ui_ask url "请输入下载 URL" "${MIRROR_URLS[0]}"
            ;;
        *) url="${MIRROR_URLS[0]}" ;;
    esac

    if ! validate_url "$url"; then
        ui_err "URL 必须以 http:// 或 https:// 开头，且不能包含空格、引号、反斜杠、反引号或 \$ 符号"
        ui_pause
        return
    fi

    ui_page "配置线程数"
    cpu_cores=$(nproc)
    recommended_threads=$((cpu_cores * 2))
    ui_kv "下载源" "${VALUE}${url}${RESET}"
    ui_kv "CPU" "${VALUE}${cpu_cores}${RESET} 核"
    ui_kv "推荐" "${VALUE}${recommended_threads}${RESET} 线程"
    [[ -n "$LAST_THREADS" ]] && ui_kv "上次" "${VALUE}${LAST_THREADS}${RESET} 线程"
    echo
    ui_ask threads "请输入线程数" "${LAST_THREADS:-$recommended_threads}"

    if ! validate_threads "$threads"; then
        ui_pause
        return
    fi

    echo
    ui_rule
    ui_kv "确认" "${VALUE}${threads}${RESET} 线程 ${MUTED}·${RESET} ${VALUE}${url}${RESET}"
    echo
    ui_ask confirm "确认启动？(Y/n)" "Y"
    [[ "$confirm" =~ ^[Nn]$ ]] && return

    # 更新 systemd 服务文件中的 URL 与线程数
    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
        escaped_url=$(escape_sed_replacement "$url")
        sed -i "s|Environment=\"VPSFLOW_URL=.*\"|Environment=\"VPSFLOW_URL=$escaped_url\"|" "/etc/systemd/system/$SERVICE_NAME.service"
        sed -i "s|Environment=\"VPSFLOW_THREADS=.*\"|Environment=\"VPSFLOW_THREADS=$threads\"|" "/etc/systemd/system/$SERVICE_NAME.service"
        systemctl daemon-reload
    fi

    echo
    ui_step "正在启动服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    if systemctl start "$SERVICE_NAME"; then
        interface=$(detect_network_interface)
        if save_config "$url" "$threads" "$interface"; then
            ui_ok "服务启动成功"
        else
            ui_warn "服务已启动，但配置保存失败"
        fi
    else
        ui_err "服务启动失败，可用 journalctl -u $SERVICE_NAME 查看原因"
    fi

    ui_pause
}

# 停止服务并清理残留的下载线程
stop_service() {
    ui_page "停止服务"
    ui_step "正在停止服务..."
    if systemctl stop "$SERVICE_NAME"; then
        # 兜底清理：systemd 未能回收的下载线程
        pkill -f vpsflow_thread 2>/dev/null
        pkill -f "curl -A VPSFlow" 2>/dev/null
        ui_ok "服务已停止"
    else
        ui_err "停止失败，可用 systemctl status $SERVICE_NAME 查看状态"
    fi
    ui_pause
}

# 以当前配置重启服务
restart_service() {
    ui_page "重启服务"
    ui_step "正在重启服务..."
    if systemctl restart "$SERVICE_NAME"; then
        ui_ok "服务已重启"
    else
        ui_err "重启失败，可用 systemctl status $SERVICE_NAME 查看状态"
    fi
    ui_pause
}

# 实时流量监控
show_monitor() {
    local interface=""
    ui_page "实时流量监控"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        ui_ok "流量消耗服务运行中"
    else
        ui_warn "流量消耗服务未运行，监控仍可使用"
    fi

    if [[ ! -f "$MONITOR_SCRIPT" ]]; then
        ui_warn "监控脚本不存在，正在重新初始化..."
        init_service
        if [[ ! -f "$MONITOR_SCRIPT" ]]; then
            ui_err "监控脚本创建失败"
            ui_pause
            return
        fi
    fi
    chmod +x "$MONITOR_SCRIPT" 2>/dev/null

    load_config
    if [[ -n "$LAST_INTERFACE" && -d "/sys/class/net/$LAST_INTERFACE" ]]; then
        interface="$LAST_INTERFACE"
    else
        interface=$(detect_network_interface 2>/dev/null)
    fi

    if [[ -z "$interface" || ! -d "/sys/class/net/$interface" ]]; then
        ui_err "网络接口检测失败"
        ui_note "可用接口：$(list_network_interfaces | tr '\n' ' ')"
        ui_pause
        return
    fi

    if [[ ! -r "/sys/class/net/$interface/statistics/rx_bytes" ]] \
        || [[ ! -r "/sys/class/net/$interface/statistics/tx_bytes" ]]; then
        ui_err "无法读取网络接口统计信息，请确认以 root 权限运行"
        ui_pause
        return
    fi

    ui_kv "网络接口" "${VALUE}${interface}${RESET}"
    ui_note "按 Ctrl+C 可退出监控"
    sleep 1

    if ! bash "$MONITOR_SCRIPT" "$interface"; then
        echo
        ui_err "监控脚本执行失败"
        ui_kv "脚本" "${VALUE}${MONITOR_SCRIPT}${RESET}"
        ui_kv "接口" "${VALUE}${interface}${RESET}"
        ui_pause
    fi
}

# 查看服务日志
show_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        ui_page "服务日志"
        ui_err "日志文件不存在：$LOG_FILE"
        ui_pause
        return
    fi

    ui_page "服务日志"
    ui_note "显示最近 100 行 · 按 q 退出"
    echo
    if command -v less &>/dev/null; then
        tail -100 "$LOG_FILE" | less -R
    else
        tail -100 "$LOG_FILE"
        ui_pause
    fi
}

# 快捷键管理
shortcut_management() {
    local choice current_shortcut new_name
    while true; do
        ui_page "快捷键管理"

        current_shortcut=$(get_shortcut_name)
        [[ -z "$current_shortcut" ]] && current_shortcut="$DEFAULT_SHORTCUT"
        if [[ -f "$SHORTCUT_CONFIG" ]]; then
            safe_source_config "$SHORTCUT_CONFIG" SHORTCUT_NAME SHORTCUT_PATH CREATED_TIME || SHORTCUT_PATH=""
            if [[ -f "${SHORTCUT_PATH:-/usr/local/bin/$current_shortcut}" ]]; then
                ui_kv "快捷键" "${SUCCESS}${current_shortcut}${RESET}"
                ui_kv "路径" "${VALUE}${SHORTCUT_PATH:-/usr/local/bin/$current_shortcut}${RESET}"
                [[ -n "$CREATED_TIME" ]] && ui_kv "创建于" "${VALUE}${CREATED_TIME}${RESET}"
            else
                ui_kv "快捷键" "${WARNING}文件缺失${RESET}"
            fi
        else
            ui_kv "快捷键" "${WARNING}未安装${RESET}"
        fi

        echo
        ui_item 1 "安装 / 重装快捷键" "以当前名称重新生成"
        ui_item 2 "自定义快捷键名称" "改用其他命令名启动"
        ui_item 3 "删除快捷键" "移除 /usr/local/bin 下的命令"
        ui_item 0 "返回主菜单" "" "$GRAY"
        echo
        ui_rule

        ui_ask choice "请选择 [0-3]" ""
        echo
        case "$choice" in
            1)
                create_shortcut "$current_shortcut"
                ui_pause "按回车继续..."
                ;;
            2)
                ui_ask new_name "新的快捷键名称（英文字母开头）" ""
                echo
                if [[ -z "$new_name" ]]; then
                    ui_warn "快捷键名称不能为空"
                elif [[ ! "$new_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
                    ui_err "无效名称：只能使用英文字母、数字和下划线，且必须以字母开头"
                elif [[ "$new_name" == "$current_shortcut" ]]; then
                    ui_warn "与当前快捷键相同"
                else
                    create_shortcut "$new_name"
                fi
                ui_pause "按回车继续..."
                ;;
            3)
                remove_shortcut
                ui_pause "按回车继续..."
                ;;
            0|"") return ;;
            *)
                ui_err "无效选项"
                sleep 1
                ;;
        esac
    done
}

# 功能诊断：逐项检查监控所依赖的脚本、接口与命令
test_monitor() {
    local -a interfaces=()
    local test_interface cmd rx_bytes tx_bytes
    ui_page "功能诊断"

    # 1. 监控脚本
    ui_group "1. 监控脚本"
    if [[ -f "$MONITOR_SCRIPT" ]]; then
        ui_ok "脚本存在：$MONITOR_SCRIPT"
        if [[ -x "$MONITOR_SCRIPT" ]]; then
            ui_ok "脚本可执行"
        else
            ui_warn "脚本无执行权限，正在修复..."
            chmod +x "$MONITOR_SCRIPT" && ui_ok "权限已修复"
        fi
    else
        ui_warn "脚本不存在，正在重新生成..."
        init_service
        [[ -f "$MONITOR_SCRIPT" ]] && ui_ok "脚本已生成" || ui_err "脚本生成失败"
    fi

    # 2. 网络接口
    echo
    ui_group "2. 网络接口"
    mapfile -t interfaces < <(list_network_interfaces)
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        ui_err "没有可用的网络接口"
        ui_pause
        return
    fi
    ui_kv "可用接口" "${VALUE}${interfaces[*]}${RESET}"
    test_interface="${LAST_INTERFACE:-}"
    [[ -n "$test_interface" && -d "/sys/class/net/$test_interface" ]] || test_interface="${interfaces[0]}"
    ui_ok "测试接口：$test_interface"

    # 3. 统计文件权限
    echo
    ui_group "3. 统计文件权限"
    if [[ -r "/sys/class/net/$test_interface/statistics/rx_bytes" ]]; then
        rx_bytes=$(< "/sys/class/net/$test_interface/statistics/rx_bytes")
        ui_ok "RX 可读：$rx_bytes bytes"
    else
        ui_err "无法读取 RX 统计文件"
    fi
    if [[ -r "/sys/class/net/$test_interface/statistics/tx_bytes" ]]; then
        tx_bytes=$(< "/sys/class/net/$test_interface/statistics/tx_bytes")
        ui_ok "TX 可读：$tx_bytes bytes"
    else
        ui_err "无法读取 TX 统计文件"
    fi

    # 4. 必需命令
    echo
    ui_group "4. 必需命令"
    for cmd in awk cat sleep bash curl systemctl; do
        if command -v "$cmd" &>/dev/null; then
            ui_ok "$cmd 可用"
        else
            ui_err "$cmd 缺失"
        fi
    done

    # 5. 采样测试：直接在当前 shell 中采样，无需再嵌套一层脚本
    echo
    ui_group "5. 采样测试（约 10 秒）"
    local i rx_prev tx_prev rx_cur tx_cur
    rx_prev=$(safe_stat_bytes "$test_interface" rx)
    tx_prev=$(safe_stat_bytes "$test_interface" tx)
    ui_note "初始值 RX=$rx_prev TX=$tx_prev"
    for ((i=1; i<=5; i++)); do
        sleep 2
        rx_cur=$(safe_stat_bytes "$test_interface" rx)
        tx_cur=$(safe_stat_bytes "$test_interface" tx)
        printf '%s%b第 %d 次%b  RX %s  TX %s\n' "$UI_INDENT" "$MUTED" "$i" "$RESET" \
            "$(format_bytes_per_sec $(( (rx_cur - rx_prev) / 2 )))" \
            "$(format_bytes_per_sec $(( (tx_cur - tx_prev) / 2 )))"
        rx_prev=$rx_cur
        tx_prev=$tx_cur
    done

    echo
    ui_rule
    ui_ok "诊断完成，以上全部通过则实时监控可正常工作"
    ui_pause
}

# 高级流量监控
advanced_monitor() {
    local interface="" refresh_interval dl_threshold ul_threshold enable_history
    ui_page "高级流量监控"

    load_config
    if [[ -n "$LAST_INTERFACE" && -d "/sys/class/net/$LAST_INTERFACE" ]]; then
        interface="$LAST_INTERFACE"
    else
        interface=$(detect_network_interface 2>/dev/null)
    fi

    if [[ -z "$interface" || ! -d "/sys/class/net/$interface" ]]; then
        ui_err "无法检测到有效的网络接口"
        ui_pause
        return
    fi

    ui_kv "网络接口" "${VALUE}${interface}${RESET}"
    echo
    ui_group "监控参数"
    ui_ask refresh_interval "刷新间隔（1-10 秒）" "1"
    [[ "$refresh_interval" =~ ^([1-9]|10)$ ]] || refresh_interval=1

    ui_ask dl_threshold "下载告警阈值（MB/s，0 关闭）" "100"
    [[ "$dl_threshold" =~ ^[0-9]+$ ]] || dl_threshold=0

    ui_ask ul_threshold "上传告警阈值（MB/s，0 关闭）" "50"
    [[ "$ul_threshold" =~ ^[0-9]+$ ]] || ul_threshold=0

    ui_ask enable_history "记录历史峰值？(y/N)" "N"
    local enable_history_flag=false
    [[ "$enable_history" =~ ^[Yy]$ ]] && enable_history_flag=true

    echo
    ui_ok "配置完成，正在启动高级监控"
    ui_note "按 Q 或 Ctrl+C 退出 · 按 s 保存数据 · 按 r 重置统计"
    sleep 1

    advanced_monitor_loop "$interface" "$refresh_interval" \
        $((dl_threshold * 1024 * 1024)) $((ul_threshold * 1024 * 1024)) "$enable_history_flag"
}

# 高级监控主循环
advanced_monitor_loop() {
    local interface="$1"
    local refresh_interval="$2"
    local dl_threshold="$3"
    local ul_threshold="$4"
    local enable_history="$5"

    # 初始化变量
    local RX_PREV TX_PREV
    RX_PREV=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
    TX_PREV=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)
    local RX_TOTAL=0 TX_TOTAL=0 DURATION=0
    local RX_PEAK=0 TX_PEAK=0 RX_PEAK_TIME="" TX_PEAK_TIME=""
    local ALERT_COUNT=0

    # 历史数据数组
    local -a RX_HISTORY TX_HISTORY TIME_HISTORY
    local HISTORY_SIZE=60  # 保留60个数据点


    clear
    echo
    ui_title "高级流量监控"
    ui_kv "接口" "${VALUE}${interface}${RESET}${MUTED} · 刷新 ${refresh_interval}s${RESET}"
    echo
    ui_note "正在采样，请稍候..."
    echo

    trap 'echo -e "\n${WARNING}正在保存数据并退出...${RESET}"; save_monitor_data "$interface" "$RX_TOTAL" "$TX_TOTAL" "$DURATION" "$RX_PEAK" "$TX_PEAK"; exit 0' INT

    while true; do
        sleep "$refresh_interval"
        ((DURATION += refresh_interval))

        # 读取当前值
        local RX_CUR TX_CUR
        RX_CUR=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
        TX_CUR=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)

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
            RX_HISTORY+=("$RX_RATE")
            TX_HISTORY+=("$TX_RATE")
            TIME_HISTORY+=("$(date '+%H:%M:%S')")

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
        local rx_speed tx_speed rx_total tx_total rx_peak_speed tx_peak_speed
        rx_speed=$(format_bytes_per_sec "$RX_RATE")
        tx_speed=$(format_bytes_per_sec "$TX_RATE")
        rx_total=$(format_bytes "$RX_TOTAL")
        tx_total=$(format_bytes "$TX_TOTAL")
        rx_peak_speed=$(format_bytes_per_sec "$RX_PEAK")
        tx_peak_speed=$(format_bytes_per_sec "$TX_PEAK")

        # 计算运行时间
        local hours=$((DURATION / 3600))
        local mins=$(((DURATION % 3600) / 60))
        local secs=$((DURATION % 60))

        # 计算平均值
        local avg_rx=$(( DURATION > 0 ? RX_TOTAL / DURATION : 0 ))
        local avg_tx=$(( DURATION > 0 ? TX_TOTAL / DURATION : 0 ))
        local avg_rx_speed avg_tx_speed
        avg_rx_speed=$(format_bytes_per_sec "$avg_rx")
        avg_tx_speed=$(format_bytes_per_sec "$avg_tx")

        # 生成进度条
        local max_speed=$(( RX_RATE > TX_RATE ? RX_RATE : TX_RATE ))
        [[ $max_speed -lt $((10*1024*1024)) ]] && max_speed=$((10*1024*1024))

        local rx_bar tx_bar
        rx_bar=$(generate_bar "$RX_RATE" "$max_speed" 40)
        tx_bar=$(generate_bar "$TX_RATE" "$max_speed" 40)

        # 显示界面
        # 显示界面：整屏定位重绘，避免闪烁
        printf '\033[H'
        echo
        ui_title "高级流量监控"
        ui_kv "接口" "${VALUE}${interface}${RESET}${MUTED} · 刷新 ${refresh_interval}s · 运行 $(printf '%02d:%02d:%02d' "$hours" "$mins" "$secs")${RESET}"
        ui_rule
        echo

        printf '%s%b下载%b  %b%s%b  %b%s%b\n' "$UI_INDENT" "$SUCCESS" "$RESET" \
            "$VALUE" "$(pad_line "$rx_speed" 12)" "$RESET" "$PRIMARY" "$rx_bar" "$RESET"
        printf '%s%b上传%b  %b%s%b  %b%s%b\n' "$UI_INDENT" "$INFO" "$RESET" \
            "$VALUE" "$(pad_line "$tx_speed" 12)" "$RESET" "$PRIMARY" "$tx_bar" "$RESET"
        echo

        ui_kv "累计" "${MUTED}↓${RESET} ${VALUE}$(pad_line "$rx_total" 14)${RESET}${MUTED}↑${RESET} ${VALUE}${tx_total}${RESET}"
        ui_kv "平均" "${MUTED}↓${RESET} ${VALUE}$(pad_line "$avg_rx_speed" 14)${RESET}${MUTED}↑${RESET} ${VALUE}${avg_tx_speed}${RESET}"
        if [[ -n "$RX_PEAK_TIME" || -n "$TX_PEAK_TIME" ]]; then
            ui_kv "峰值" "${MUTED}↓${RESET} ${VALUE}$(pad_line "$rx_peak_speed" 14)${RESET}${MUTED}↑${RESET} ${VALUE}${tx_peak_speed}${RESET}"
            ui_kv "" "${MUTED}↓ ${RX_PEAK_TIME:--} · ↑ ${TX_PEAK_TIME:--}${RESET}"
        fi
        (( ALERT_COUNT > 0 )) && ui_kv "告警" "${DANGER}${ALERT_COUNT} 次${RESET}"

        [[ -n "$alert_msg" ]] && { echo; printf '%s%b\n' "$UI_INDENT" "$alert_msg"; }

        # 历史趋势（简单 ASCII 图）
        if [[ "$enable_history" == "true" ]] && (( ${#RX_HISTORY[@]} > 10 )); then
            echo
            ui_note "流量趋势（最近 ${#RX_HISTORY[@]} 个采样点）"
            printf '%s' "$UI_INDENT"
            display_ascii_chart "${RX_HISTORY[*]}" "下载"
        fi

        echo
        ui_rule
        ui_keyhint "Q 退出 · S 保存数据 · R 重置统计"
        printf '\033[J'

        # 键盘控制：s 保存数据 / r 重置统计 / q 退出
        local key=""
        if IFS= read -rsn1 -t 0.15 key 2>/dev/null; then
            case "$key" in
                q|Q|$'\e') break ;;
                s|S)
                    save_monitor_data "$interface" "$RX_TOTAL" "$TX_TOTAL" "$DURATION" "$RX_PEAK" "$TX_PEAK"
                    ;;
                r|R)
                    RX_TOTAL=0; TX_TOTAL=0; DURATION=0
                    RX_PEAK=0; TX_PEAK=0; RX_PEAK_TIME=""; TX_PEAK_TIME=""
                    ALERT_COUNT=0
                    ;;
            esac
        fi
    done
}

# 字节格式化函数 - 优化版（awk 替代 bc）
format_bytes_per_sec() {
    local bytes=$1
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if [[ $bytes -ge 1073741824 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB/s", b / 1073741824 }'
    elif [[ $bytes -ge 1048576 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB/s", b / 1048576 }'
    elif [[ $bytes -ge 1024 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f KB/s", b / 1024 }'
    else
        printf "%d B/s" "$bytes"
    fi
}

format_bytes() {
    local bytes=$1
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if [[ $bytes -ge 1073741824 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB", b / 1073741824 }'
    elif [[ $bytes -ge 1048576 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB", b / 1048576 }'
    elif [[ $bytes -ge 1024 ]]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f KB", b / 1024 }'
    else
        printf "%d B" "$bytes"
    fi
}

# 生成进度条
generate_bar() {
    local current=$1
    local max=$2
    local width=${3:-50}
    local fill i

    [[ "$current" =~ ^[0-9]+$ ]] || current=0
    [[ "$max" =~ ^[0-9]+$ ]] || max=0
    [[ "$width" =~ ^[1-9][0-9]*$ ]] || width=50

    if (( max <= 0 )); then
        fill=0
    else
        fill=$(( current * width / max ))
    fi
    (( fill > width )) && fill=$width
    (( fill < 0 )) && fill=0

    printf "["
    for ((i=0; i<fill; i++)); do printf "█"; done
    for ((i=fill; i<width; i++)); do printf "░"; done
    printf "]"
}

# 简单ASCII图表显示
display_ascii_chart() {
    local -a data=()
    read -r -a data <<< "$1"
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
    local data_file="/root/vpsflow_monitor_data.log"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "==============================="
        echo "监控数据保存 - $timestamp"
        echo "网络接口: $interface"
        echo "监控时长: $duration 秒"
        echo "累计下载: $(format_bytes $rx_total)"
        echo "累计上传: $(format_bytes $tx_total)"
        echo "峰值下载速度: $(format_bytes_per_sec $rx_peak)"
        echo "峰值上传速度: $(format_bytes_per_sec $tx_peak)"
        if [[ $duration -gt 0 ]]; then
            echo "平均下载速度: $(format_bytes_per_sec $((rx_total / duration)))"
            echo "平均上传速度: $(format_bytes_per_sec $((tx_total / duration)))"
        else
            echo "平均下载速度: 0 B/s"
            echo "平均上传速度: 0 B/s"
        fi
        echo "==============================="
        echo
    } >> "$data_file"

    echo -e "${SUCCESS}✅ 数据已保存到: $data_file${RESET}"
}

# 比较语义版本号，仅当候选版本更高时返回成功。
version_is_newer() {
    local candidate="${1#v}" current="${2#v}" newest
    [[ "$candidate" =~ ^[0-9]+([.][0-9]+)*$ ]] || return 1
    [[ "$current" =~ ^[0-9]+([.][0-9]+)*$ ]] || return 1
    [[ "$candidate" != "$current" ]] || return 1
    newest=$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n 1)
    [[ "$newest" == "$candidate" ]]
}

# 检查并安装脚本更新
check_update() {
    ui_page "检查脚本更新"
    ui_step "正在获取远端版本..."

    local current_version="$SCRIPT_VERSION"
    local current_script temp_file script_url request_url separator download_ok=false
    current_script=$(readlink -f "$0")
    temp_file=$(mktemp /tmp/vpsflow_latest_check.XXXXXX.sh) || {
        ui_err "创建临时文件失败"
        ui_pause
        return
    }

    # 主地址异常时切换到 GitHub；只接受语法检查通过的脚本
    for script_url in "${UPDATE_URLS[@]}"; do
        separator="?"
        [[ "$script_url" == *"?"* ]] && separator="&"
        request_url="${script_url}${separator}t=$(date +%s)"
        if curl -fsSL -H "Cache-Control: no-cache" --retry 2 --connect-timeout 8 --max-time 30 "$request_url" -o "$temp_file" \
            && bash -n "$temp_file" 2>/dev/null; then
            download_ok=true
            break
        fi
    done

    if [[ "$download_ok" != "true" ]]; then
        rm -f "$temp_file"
        echo
        ui_err "无法连接到更新服务器"
        ui_note "请检查网络连接或稍后再试"
        ui_pause
        return
    fi

    # 优先按版本号判断，取不到版本号时再退回文件大小差异
    local current_size latest_size size_diff
    local latest_version latest_hash has_update=false update_reason="" remote_is_older=false
    current_size=$(stat -c%s "$current_script" 2>/dev/null || echo 0)
    latest_size=$(stat -c%s "$temp_file" 2>/dev/null || echo 0)
    size_diff=$(( latest_size > current_size ? latest_size - current_size : current_size - latest_size ))
    latest_version=$(awk -F= '/^SCRIPT_VERSION=/{gsub(/"/, "", $2); print $2; exit}' "$temp_file" 2>/dev/null)
    command -v sha256sum &>/dev/null && latest_hash=$(sha256sum "$temp_file" | awk '{print $1}')

    echo
    ui_kv "当前版本" "${VALUE}${current_version}${RESET}"
    ui_kv "远端版本" "${VALUE}${latest_version:-未知}${RESET}"
    ui_kv "当前大小" "${VALUE}$(format_file_size "$current_size")${RESET}"
    ui_kv "远端大小" "${VALUE}$(format_file_size "$latest_size")${RESET}"
    [[ -n "$latest_hash" ]] && ui_kv "远端校验" "${MUTED}${latest_hash:0:16}...${RESET}"
    echo

    if version_is_newer "$latest_version" "$current_version"; then
        has_update=true
        update_reason="$current_version → $latest_version"
    elif [[ -n "$latest_version" && "$latest_version" != "$current_version" ]]; then
        remote_is_older=true
    elif [[ -z "$latest_version" ]] && (( size_diff > 1024 )); then
        has_update=true
        update_reason="无法读取远端版本，大小差异 $(format_file_size "$size_diff")"
    fi

    if [[ "$has_update" == "true" ]]; then
        local confirm_update backup_file staged_file restart_now
        ui_warn "发现新版本（$update_reason）"
        ui_note "更新会覆盖当前脚本，配置文件保留"
        echo
        ui_ask confirm_update "确认更新？(y/N)" "N"
        echo

        if [[ ! "$confirm_update" =~ ^[Yy]$ ]]; then
            ui_note "已取消更新"
            rm -f "$temp_file"
            ui_pause
            return
        fi

        backup_file="${current_script}.backup.$(date +%Y%m%d_%H%M%S)"
        staged_file="${current_script}.new.$$"
        cp "$current_script" "$backup_file"
        ui_step "已备份到 $backup_file"

        if install -m 755 "$temp_file" "$staged_file" && mv -f "$staged_file" "$current_script"; then
            ui_ok "更新完成"
            rm -f "$temp_file"
            echo
            ui_ask restart_now "现在重启脚本？(Y/n)" "Y"
            if [[ ! "$restart_now" =~ ^[Nn]$ ]]; then
                # 恢复终端屏幕再重启，避免残留备用屏状态
                tput rmcup 2>/dev/null
                tput cnorm 2>/dev/null
                exec bash "$current_script"
            fi
            return
        fi

        rm -f "$staged_file"
        ui_err "更新失败，正在恢复备份..."
        cp "$backup_file" "$current_script" 2>/dev/null
    elif [[ "$remote_is_older" == "true" ]]; then
        ui_ok "当前版本高于远端版本，无需更新"
    elif (( size_diff > 1024 )); then
        ui_warn "版本号相同但文件大小不同（$(format_file_size "$size_diff")）"
        ui_note "通常是非版本化调整；如需强制更新请重新运行安装命令"
    else
        ui_ok "已是最新版本"
    fi

    rm -f "$temp_file"
    ui_pause
}

# 格式化文件大小
format_file_size() {
    local size=$1
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    if [[ $size -ge 1048576 ]]; then
        awk -v s="$size" 'BEGIN { printf "%.2f MB", s / 1048576 }'
    elif [[ $size -ge 1024 ]]; then
        awk -v s="$size" 'BEGIN { printf "%.2f KB", s / 1024 }'
    else
        printf "%d B" "$size"
    fi
}

# ──────────────────────────────── 流量目标管理 ──────────────────────────────

# 创建流量目标自动停止检查脚本
create_target_check_script() {
    {
        echo '#!/bin/bash'
        emit_common_library
        cat << 'TARGETEOF'
# 流量目标自动停止检查脚本
TARGET_FILE="/root/vpsflow_target.conf"

safe_source_target_config || exit 0
[[ "$TARGET_AUTO_STOP" != "true" ]] && exit 0
[[ "$TARGET_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]] || exit 0

INTERFACE="${TARGET_INTERFACE:-eth0}"
CURRENT_RX=$(cat "/sys/class/net/$INTERFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
START_RX="${TARGET_START_RX:-0}"
PREV_CONSUMED="${TARGET_PREV_CONSUMED:-0}"
[[ "$CURRENT_RX" =~ ^[0-9]+$ ]] || CURRENT_RX=0
[[ "$START_RX" =~ ^[0-9]+$ ]] || START_RX=0
[[ "$PREV_CONSUMED" =~ ^[0-9]+$ ]] || PREV_CONSUMED=0
if [[ $CURRENT_RX -ge $START_RX ]]; then
    CONSUMED=$((CURRENT_RX - START_RX + PREV_CONSUMED))
else
    CONSUMED=$((CURRENT_RX + PREV_CONSUMED))
fi
TARGET_BYTES=$(awk -v gb="$TARGET_GB" 'BEGIN { printf "%.0f", gb * 1073741824 }' 2>/dev/null || echo 0)
TARGET_BYTES="${TARGET_BYTES%.*}"
[[ "$TARGET_BYTES" =~ ^[0-9]+$ && "$TARGET_BYTES" -gt 0 ]] || exit 0

if [[ $CONSUMED -ge $TARGET_BYTES ]] 2>/dev/null; then
    systemctl stop vpsflow 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S'): 流量目标 ${TARGET_GB}GB 已达成，服务已自动停止" >> /root/vpsflow.log
fi
TARGETEOF
    } > /root/vpsflow_target_check.sh
    chmod +x /root/vpsflow_target_check.sh
}

# 启用流量目标自动停止：生成检查脚本并挂到 crontab
target_arm_auto_stop() {
    create_target_check_script
    (crontab -l 2>/dev/null | grep -v "vpsflow_target_check.sh"; \
        echo "*/5 * * * * /bin/bash /root/vpsflow_target_check.sh") | crontab -
}

# 关闭流量目标自动停止：摘掉 crontab 条目并删除检查脚本
target_disarm_auto_stop() {
    crontab -l 2>/dev/null | grep -v "vpsflow_target_check.sh" | crontab - 2>/dev/null
    rm -f /root/vpsflow_target_check.sh
}

# 设置流量消耗目标
set_traffic_target() {
    local choice target_gb interface start_rx consumed_gb total_gb prev_auto auto_stop_action

    while true; do
        ui_page "流量目标"
        load_config 2>/dev/null || true

        if target_progress; then
            consumed_gb=$(awk -v b="$TARGET_CONSUMED_BYTES" 'BEGIN { printf "%.2f", b / 1073741824 }')
            ui_kv "目标" "${VALUE}${TARGET_GB} GB${RESET}${MUTED} · 网卡 ${TARGET_INTERFACE:-未知}${RESET}"
            ui_kv "已消耗" "${VALUE}${consumed_gb} GB${RESET}${MUTED} · ${TARGET_PERCENT}%${RESET}"
            ui_kv "设置于" "${VALUE}${TARGET_SET_TIME:-未知}${RESET}"
            if [[ "${TARGET_AUTO_STOP:-false}" == "true" ]]; then
                ui_kv "自动停止" "${SUCCESS}已开启${RESET}${MUTED} · 每 5 分钟检查一次${RESET}"
            else
                ui_kv "自动停止" "${MUTED}已关闭${RESET}"
            fi
            echo
            printf '%s%s\n' "$UI_INDENT" "$(gradient_bar "$TARGET_PERCENT" 40)"
        else
            ui_kv "目标" "${MUTED}未设置${RESET}"
        fi

        auto_stop_action="启用自动停止"
        [[ "${TARGET_AUTO_STOP:-false}" == "true" ]] && auto_stop_action="关闭自动停止"

        echo
        ui_item 1 "设置新的流量目标" "重新计数并写入目标值"
        ui_item 2 "清除流量目标" "同时移除自动停止任务"
        ui_item 3 "$auto_stop_action" "达到目标后自动停止服务"
        ui_item 0 "返回主菜单" "" "$GRAY"
        echo
        ui_rule

        ui_ask choice "请选择 [0-3]" ""
        echo

        case "$choice" in
            1)
                ui_ask target_gb "目标流量（GB）" ""
                echo
                if ! [[ "$target_gb" =~ ^[0-9]+\.?[0-9]*$ ]] \
                    || [[ "$(awk -v v="$target_gb" 'BEGIN { print (v == 0) ? 1 : 0 }' 2>/dev/null || echo 1)" == "1" ]]; then
                    ui_err "请输入有效的数值"
                    ui_pause "按回车继续..."
                    continue
                fi

                # 保留原有的自动停止开关，避免改目标时被静默关掉
                prev_auto="${TARGET_AUTO_STOP:-false}"
                interface="${LAST_INTERFACE:-}"
                [[ -n "$interface" ]] || interface=$(detect_network_interface 2>/dev/null)
                interface="${interface:-eth0}"
                start_rx=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)

                if save_target_config "$target_gb" "$start_rx" "$interface" "$prev_auto" 0; then
                    ui_ok "流量目标已设置为 ${target_gb} GB"
                    if [[ "$prev_auto" == "true" ]]; then
                        target_arm_auto_stop
                        ui_note "自动停止仍为开启状态，已按新目标重新计数"
                    fi
                else
                    ui_err "流量目标保存失败"
                fi
                ui_pause "按回车继续..."
                ;;
            2)
                rm -f "$TARGET_CONFIG_FILE"
                target_disarm_auto_stop
                ui_ok "流量目标已清除"
                ui_pause "按回车继续..."
                ;;
            3)
                if ! target_progress; then
                    ui_warn "请先设置流量目标"
                    ui_pause "按回车继续..."
                    continue
                fi
                if [[ "${TARGET_AUTO_STOP:-false}" == "true" ]]; then
                    if save_target_config "$TARGET_GB" "${TARGET_START_RX:-0}" "${TARGET_INTERFACE:-eth0}" "false" "${TARGET_PREV_CONSUMED:-0}"; then
                        target_disarm_auto_stop
                        ui_ok "自动停止已关闭"
                    else
                        ui_err "自动停止配置保存失败"
                    fi
                elif save_target_config "$TARGET_GB" "${TARGET_START_RX:-0}" "${TARGET_INTERFACE:-eth0}" "true" "${TARGET_PREV_CONSUMED:-0}"; then
                    target_arm_auto_stop
                    ui_ok "自动停止已启用"
                    ui_note "流量达到 ${TARGET_GB} GB 时服务将自动停止（每 5 分钟检查一次）"
                else
                    ui_err "自动停止配置保存失败"
                fi
                ui_pause "按回车继续..."
                ;;
            0|"") return ;;
            *)
                ui_err "无效选项"
                sleep 1
                ;;
        esac
    done
}

# 网络速度测试
speed_test() {
    ui_page "网络测速"
    ui_kv "测试源" "${VALUE}香港 Datapacket${RESET}${MUTED} · 4 并发 × 10MB${RESET}"
    echo
    ui_step "正在测试下载速度..."

    local start_time end_time bytes_downloaded test_url tmp_dir
    test_url="${MIRROR_URLS[0]}"
    start_time=$(date +%s%N)

    if command -v xargs &>/dev/null && command -v seq &>/dev/null; then
        # 4 并发下载测试，更接近多线程服务的真实吞吐
        tmp_dir=$(mktemp -d /tmp/vpsflow_speedtest.XXXXXX)
        seq 4 | xargs -P4 -I{} curl -s -o /dev/null -w '%{size_download}\n' \
            --max-time 15 --connect-timeout 5 -r 0-10485759 "$test_url" 2>/dev/null > "$tmp_dir/sizes"
        bytes_downloaded=$(awk '{s += $1} END {print s + 0}' "$tmp_dir/sizes" 2>/dev/null || echo 0)
        rm -rf "$tmp_dir"
    else
        # 缺少 xargs/seq 时退回单连接测试
        bytes_downloaded=$(curl -s -o /dev/null -w '%{size_download}' --max-time 15 --connect-timeout 5 -r 0-10485759 "$test_url" 2>/dev/null || echo 0)
    fi
    end_time=$(date +%s%N)

    echo
    if [[ "$bytes_downloaded" =~ ^[0-9]+$ ]] && (( bytes_downloaded > 0 )); then
        local elapsed_ms speed_bps speed_mbps grade
        elapsed_ms=$(( (end_time - start_time) / 1000000 ))
        (( elapsed_ms == 0 )) && elapsed_ms=1
        speed_bps=$(( bytes_downloaded * 1000 / elapsed_ms ))
        speed_mbps=$(awk -v b="$speed_bps" 'BEGIN { printf "%.2f", b / 1048576 }')
        grade=$(awk -v s="$speed_mbps" 'BEGIN { if (s > 100) print 4; else if (s > 50) print 3; else if (s > 10) print 2; else print 1 }')

        ui_kv "下载量" "${VALUE}$(format_bytes "$bytes_downloaded")${RESET}"
        ui_kv "耗时" "${VALUE}${elapsed_ms}${RESET} ms"
        ui_kv "速度" "${VALUE}${speed_mbps}${RESET} MB/s"
        echo
        case "$grade" in
            4) ui_ok "网络速度极快，非常适合大量流量消耗" ;;
            3) ui_ok "网络速度良好" ;;
            2) ui_warn "网络速度一般" ;;
            *) ui_warn "网络速度较慢" ;;
        esac
    else
        ui_err "速度测试失败，请检查网络连接"
    fi

    ui_pause
}

# 卸载：删除服务、脚本、配置与快捷键
uninstall_service() {
    local confirm saved_shortcut_path="" self_path
    ui_page "卸载全部服务"
    ui_err "此操作将彻底删除服务、脚本、配置与缓存，且不可恢复"
    echo
    ui_note "保留项：无。卸载后需重新执行安装命令才能使用。"
    echo
    ui_rule
    ui_ask confirm "确认卸载请输入 ok" ""

    if [[ "$confirm" != "ok" ]]; then
        echo
        ui_warn "操作已取消"
        ui_pause
        return
    fi

    echo
    ui_step "正在卸载..."

    if [[ -f "$SHORTCUT_CONFIG" ]]; then
        safe_source_config "$SHORTCUT_CONFIG" SHORTCUT_NAME SHORTCUT_PATH CREATED_TIME || SHORTCUT_PATH=""
        [[ "$SHORTCUT_PATH" =~ ^/usr/local/bin/[A-Za-z][A-Za-z0-9_]*$ ]] && saved_shortcut_path="$SHORTCUT_PATH"
    fi

    # 1. 停止并禁用服务
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null

    # 2. 杀死所有残留进程
    pkill -f vpsflow_thread 2>/dev/null
    pkill -f vpsflow_check 2>/dev/null
    pkill -f "curl -A VPSFlow" 2>/dev/null

    # 3. 删除 systemd 服务文件
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload

    # 4. 删除主脚本与辅助脚本
    rm -f "/root/$SCRIPT_NAME" "$MONITOR_SCRIPT" "$UNINSTALL_SCRIPT" \
          /root/vpsflow_start.sh /root/vpsflow_target_check.sh

    # 5. 删除全部配置
    rm -f "$CONFIG_FILE" "$SHORTCUT_CONFIG" "$TARGET_CONFIG_FILE" "$PRESET_CONFIG_FILE"

    # 6. 删除日志与监控数据
    rm -f "$LOG_FILE" /root/vpsflow*.log /root/vpsflow_monitor_data.log

    # 7. 清理临时文件与运行期状态
    rm -f /tmp/vpsflow_* /root/.vpsflow_menu_speed.state
    rm -rf "$STATE_DIR"

    # 8. 清理 crontab 中的相关条目
    crontab -l 2>/dev/null | grep -v "vpsflow_target_check.sh" | crontab - 2>/dev/null

    # 9. 删除快捷键
    [[ -n "$saved_shortcut_path" ]] && rm -f "$saved_shortcut_path"
    rm -f "/usr/local/bin/$DEFAULT_SHORTCUT"

    echo
    ui_ok "卸载完成，已清理所有文件、配置与缓存"
    echo

    # 10. 最后删除自身
    self_path=$(readlink -f "$0")
    rm -f "$self_path" 2>/dev/null
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 主菜单（竖排单列 + 方向键选择 + 状态区实时刷新）
# ═══════════════════════════════════════════════════════════════════════════════

# ── 菜单数据：键 / 名称 / 说明 三者一一对应，交互菜单与降级菜单共用 ──

MENU_KEYS=("1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "U" "0")
MENU_LABELS=(
    "启动 / 重新配置" "停止服务"     "重启服务"       "流量目标"
    "实时流量监控"    "高级流量监控" "功能诊断"       "网络测速"
    "查看服务日志"    "快捷键管理"   "检查脚本更新"
    "卸载全部服务"    "退出控制台"
)
MENU_HINTS=(
    "选择下载源与线程数并启动服务" "停止服务与全部下载线程"
    "以当前配置重新启动服务"       "设置消耗上限与达标自动停止"
    "实时速率、累计流量与进度"     "峰值记录、趋势图与速率告警"
    "检查依赖与网卡统计可读性"     "4 并发测试当前出口下载速度"
    "浏览最近的服务运行日志"       "安装、改名或删除命令快捷方式"
    "对比远端版本并原地升级"
    "删除服务、脚本与全部配置"     "返回系统 Shell"
)
MENU_COUNT=${#MENU_KEYS[@]}
MENU_SELECTED=0

MENU_RESIZED=0
MENU_IDLE_REFRESH=2                       # 空闲多少秒自动刷新一次状态区
MENU_LABEL_WIDTH=18                       # 名称列宽度，说明列由此对齐
MENU_HINT_MIN_WIDTH=62                    # 低于该宽度隐藏说明列，改在底部单行显示

# 运行期缓存，避免每次刷新都重复 fork 外部命令
MENU_HOST_NAME=""
MENU_CPU_CORES=""
MENU_DISK_INFO=""
MENU_DISK_TS=0
MENU_SPEED_STATE=""

# 速率采样状态文件放在 root 私有目录，避免 /tmp 下的可预测路径被抢占
menu_state_file() {
    if [[ -z "$MENU_SPEED_STATE" ]]; then
        if mkdir -p "$STATE_DIR" 2>/dev/null && chmod 700 "$STATE_DIR" 2>/dev/null; then
            MENU_SPEED_STATE="$STATE_DIR/menu_speed.state"
        else
            MENU_SPEED_STATE="/root/.vpsflow_menu_speed.state"
        fi
    fi
    printf '%s' "$MENU_SPEED_STATE"
}

# ── 交互：读取一个按键 ──
# 返回 UP / DOWN / ENTER / ESC / TIMEOUT / EOF 或单个字符
menu_read_key() {
    local k='' rc seq=''
    IFS= read -rsn1 -t "$MENU_IDLE_REFRESH" k
    rc=$?
    (( rc > 128 )) && { printf 'TIMEOUT'; return 0; }
    (( rc != 0 )) && { printf 'EOF'; return 0; }
    if [[ "$k" == $'\e' ]]; then
        IFS= read -rsn2 -t 0.1 seq 2>/dev/null
        case "$seq" in
            '[A') printf 'UP' ;;
            '[B') printf 'DOWN' ;;
            *)    printf 'ESC' ;;
        esac
        return 0
    fi
    [[ -z "$k" ]] && { printf 'ENTER'; return 0; }
    printf '%s' "$k"
}

# 上下移动，到头循环
menu_move() {
    if [[ "$1" == "up" ]]; then
        MENU_SELECTED=$(( (MENU_SELECTED - 1 + MENU_COUNT) % MENU_COUNT ))
    else
        MENU_SELECTED=$(( (MENU_SELECTED + 1) % MENU_COUNT ))
    fi
}

# ── 状态数据 ──

# 主机名与 CPU 核数在整个会话中不变，只取一次
menu_static_info() {
    [[ -n "$MENU_HOST_NAME" ]] && return 0
    MENU_HOST_NAME=$(hostname 2>/dev/null || echo "未知")
    MENU_CPU_CORES=$(nproc 2>/dev/null || echo "?")
}

# 磁盘占用变化缓慢，30 秒刷新一次即可
menu_disk_info() {
    local now
    now=$(printf '%(%s)T' -1 2>/dev/null || date +%s)
    if [[ -z "$MENU_DISK_INFO" ]] || (( now - MENU_DISK_TS >= 30 )); then
        MENU_DISK_INFO=$(df -h / 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}')
        [[ -n "$MENU_DISK_INFO" ]] || MENU_DISK_INFO="未知"
        MENU_DISK_TS=$now
    fi
    printf '%s' "$MENU_DISK_INFO"
}

# 当前下行速率：跨两次渲染读取网卡计数增量，优先使用已保存的接口
get_current_speed() {
    local iface rx now prev ts dt state
    CURRENT_SPEED_TEXT="--"
    CURRENT_SPEED_IFACE=""

    iface="${LAST_INTERFACE:-}"
    if [[ -z "$iface" || ! -r "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
        iface=$(list_network_interfaces | head -1)
    fi
    [[ -n "$iface" ]] || return 0
    CURRENT_SPEED_IFACE="$iface"

    rx=$(< "/sys/class/net/$iface/statistics/rx_bytes") || return 0
    [[ "$rx" =~ ^[0-9]+$ ]] || return 0
    now=$(printf '%(%s)T' -1 2>/dev/null || date +%s)

    state=$(menu_state_file)
    prev=0
    ts=0
    [[ -f "$state" ]] && IFS=' ' read -r prev ts < "$state"
    [[ "$prev" =~ ^[0-9]+$ ]] || prev=0
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=$now
    dt=$((now - ts))

    if (( dt > 0 )) && (( rx >= prev )) && (( prev > 0 )); then
        CURRENT_SPEED_TEXT=$(format_bytes_per_sec $(( (rx - prev) / dt )))
    fi
    printf '%s %s\n' "$rx" "$now" > "$state"
    chmod 600 "$state" 2>/dev/null
}

# ── 绘制组件 ──

MENU_ROW_WIDTH_HINT=0     # 含说明列时的最长行宽
MENU_ROW_WIDTH_PLAIN=0    # 仅名称时的最长行宽

# 选中行的反色条只覆盖菜单内容宽度，不拉到终端边缘；宽度由菜单数据算出并缓存
menu_row_width() {
    local show_hint="$1" i w body label_pad
    if (( show_hint == 1 )); then
        (( MENU_ROW_WIDTH_HINT > 0 )) && { printf '%d' "$MENU_ROW_WIDTH_HINT"; return 0; }
    else
        (( MENU_ROW_WIDTH_PLAIN > 0 )) && { printf '%d' "$MENU_ROW_WIDTH_PLAIN"; return 0; }
    fi

    w=0
    for ((i=0; i<MENU_COUNT; i++)); do
        label_pad=$(( MENU_LABEL_WIDTH - $(str_width "${MENU_LABELS[$i]}") ))
        (( label_pad < 2 )) && label_pad=2
        if (( show_hint == 1 )); then
            body="[${MENU_KEYS[$i]}] ${MENU_LABELS[$i]}$(repeat ' ' "$label_pad")${MENU_HINTS[$i]}"
        else
            body="[${MENU_KEYS[$i]}] ${MENU_LABELS[$i]}"
        fi
        local bw
        bw=$(str_width "$body")
        (( bw > w )) && w=$bw
    done

    if (( show_hint == 1 )); then
        MENU_ROW_WIDTH_HINT=$w
    else
        MENU_ROW_WIDTH_PLAIN=$w
    fi
    printf '%d' "$w"
}

# 单个选项行；选中项整行反色，名称与说明分列对齐
menu_row() {
    local idx="$1" row_width="$2" show_hint="$3"
    local key label hint body pad label_pad key_color

    key="${MENU_KEYS[$idx]}"
    label="${MENU_LABELS[$idx]}"
    hint="${MENU_HINTS[$idx]}"

    label_pad=$(( MENU_LABEL_WIDTH - $(str_width "$label") ))
    (( label_pad < 2 )) && label_pad=2

    if (( show_hint == 1 )); then
        body="[$key] ${label}$(repeat ' ' "$label_pad")${hint}"
    else
        body="[$key] ${label}"
    fi

    if (( idx == MENU_SELECTED )); then
        pad=$(( row_width - $(str_width "$body") ))
        (( pad < 0 )) && pad=0
        printf '%s%b▸ %s%s%b\n' "$UI_INDENT" "$REV" "$body" "$(repeat ' ' "$pad")" "$RESET"
        return 0
    fi

    key_color="$KEY"
    [[ "$key" == "U" ]] && key_color="$DANGER"
    [[ "$key" == "0" ]] && key_color="$GRAY"
    if (( show_hint == 1 )); then
        printf '%s  %b[%s]%b %b%s%b%s%b%s%b\n' "$UI_INDENT" \
            "$key_color" "$key" "$RESET" "$WHITE" "$label" "$RESET" \
            "$(repeat ' ' "$label_pad")" "$MUTED" "$hint" "$RESET"
    else
        printf '%s  %b[%s]%b %b%s%b\n' "$UI_INDENT" \
            "$key_color" "$key" "$RESET" "$WHITE" "$label" "$RESET"
    fi
}

# 状态区：服务 / 目标 / 主机 三行，标签对齐
menu_status_block() {
    local width="$1"
    local status_badge pid_value target_summary bar_part speed_part mem_used mem_total
    local compact=full bar_width=16 host_line

    # 窄终端下压缩次要信息，避免状态行折行
    if (( width < 80 )); then
        compact=compact
        bar_width=10
    fi

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        pid_value=$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null)
        status_badge="${SUCCESS}● 运行中${RESET}${MUTED} · PID ${pid_value:-N/A}${RESET}"
    else
        status_badge="${DANGER}○ 已停止${RESET}"
    fi

    get_current_speed
    speed_part="${SUCCESS}↓${RESET} ${VALUE}${CURRENT_SPEED_TEXT}${RESET}${MUTED} · ${CURRENT_SPEED_IFACE:-无接口}${RESET}"

    get_target_summary target_summary "$compact"
    bar_part=""
    [[ -n "$TARGET_PERCENT" ]] && bar_part=$(gradient_bar "$TARGET_PERCENT" "$bar_width")

    menu_static_info
    mem_used=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%.1f", $3/1024}')
    mem_total=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null)

    host_line="${VALUE}${MENU_HOST_NAME}${RESET}${MUTED} · CPU ${MENU_CPU_CORES} 核 · 内存 ${mem_used:-?}/${mem_total:-?} GB"
    [[ "$compact" == "full" ]] && host_line="${host_line} · 磁盘 $(menu_disk_info)"
    host_line="${host_line}${RESET}"

    ui_split "${MUTED}服务${RESET}   ${status_badge}" "$speed_part" "$width"
    ui_split "${MUTED}目标${RESET}   ${target_summary}" "$bar_part" "$width"
    ui_split "${MUTED}主机${RESET}   ${host_line}" "" "$width"
}

# ── 渲染 ──
# 整屏定位重绘（\033[H 归位、\033[J 清尾），不闪烁

render_main_menu() {
    local width inner show_hint row_width i

    width=$(ui_width)
    inner=$((width - 4))
    show_hint=1
    (( width < MENU_HINT_MIN_WIDTH )) && show_hint=0
    row_width=$(menu_row_width "$show_hint")
    # 反色条不超出可用内容区
    (( row_width > inner - 2 )) && row_width=$(( inner - 2 ))

    printf '\033[H'
    echo
    ui_title "$APP_TITLE"
    menu_status_block "$width"
    ui_rule "$width"

    for ((i=0; i<MENU_COUNT; i++)); do
        menu_row "$i" "$row_width" "$show_hint"
    done

    ui_rule "$width"
    if (( show_hint == 0 )); then
        printf '%s%b说明%b   %b%s%b\n' "$UI_INDENT" "$MUTED" "$RESET" \
            "$MUTED" "${MENU_HINTS[$MENU_SELECTED]}" "$RESET"
    fi
    ui_keyhint "↑↓ 选择 · Enter 确认 · 按键直达 · Q 退出"
    printf '\033[J'
}

# ── 分发与生命周期 ──

menu_exit() {
    clear
    echo
    ui_ok "已退出 ${APP_TITLE}"
    echo
    exit 0
}

menu_dispatch() {
    case "${MENU_KEYS[$MENU_SELECTED]}" in
        1) start_service ;;
        2) stop_service ;;
        3) restart_service ;;
        4) set_traffic_target ;;
        5) show_monitor ;;
        6) advanced_monitor ;;
        7) test_monitor ;;
        8) speed_test ;;
        9) show_logs ;;
        A) shortcut_management ;;
        B) check_update ;;
        U) uninstall_service ;;
        0) menu_exit ;;
    esac
    # 子功能（如高级监控）可能覆盖 INT/TERM 捕获，返回后恢复
    trap 'exit 0' INT TERM
    # 子功能可能改动配置，返回主菜单前重新载入，保证状态区与实际一致
    load_config 2>/dev/null || true
}

menu_cleanup() {
    tput cnorm 2>/dev/null
    tput rmcup 2>/dev/null
    [[ -n "$MENU_SPEED_STATE" ]] && rm -f "$MENU_SPEED_STATE"
}

show_menu() {
    local k i
    trap menu_cleanup EXIT
    trap 'exit 0' INT TERM
    trap 'MENU_RESIZED=1' WINCH
    load_config 2>/dev/null || true
    tput smcup 2>/dev/null || true
    tput civis 2>/dev/null || true
    printf '\033[H\033[J'
    render_main_menu
    while true; do
        if (( MENU_RESIZED == 1 )); then
            MENU_RESIZED=0
            printf '\033[H\033[J'
            render_main_menu
        fi
        k=$(menu_read_key)
        case "$k" in
            TIMEOUT) render_main_menu ;;    # 空闲自动刷新状态区
            EOF)     menu_exit ;;           # 输入流关闭，避免空转
            UP)      menu_move up;   render_main_menu ;;
            DOWN)    menu_move down; render_main_menu ;;
            ENTER)   menu_dispatch; printf '\033[H\033[J'; render_main_menu ;;
            ESC)     : ;;
            *)
                case "${k^^}" in
                    Q) menu_exit ;;
                    K) menu_move up;   render_main_menu; continue ;;
                    J) menu_move down; render_main_menu; continue ;;
                esac
                for ((i=0; i<MENU_COUNT; i++)); do
                    if [[ "${k^^}" == "${MENU_KEYS[$i]}" ]]; then
                        MENU_SELECTED=$i
                        menu_dispatch
                        printf '\033[H\033[J'
                        render_main_menu
                        break
                    fi
                done
                ;;
        esac
    done
}

# 非交互终端降级：静态菜单 + 逐行读取，选项与交互菜单来自同一份数据
show_menu_plain() {
    local target_summary i choice pid
    load_config 2>/dev/null || true

    echo
    ui_title "$APP_TITLE"

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        pid=$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null)
        ui_kv "服务" "${SUCCESS}● 运行中${RESET}${MUTED} · PID ${pid:-N/A}${RESET}"
    else
        ui_kv "服务" "${DANGER}○ 已停止${RESET}"
    fi
    get_target_summary target_summary
    ui_kv "目标" "$target_summary"
    ui_rule

    for ((i=0; i<MENU_COUNT; i++)); do
        case "${MENU_KEYS[$i]}" in
            U) ui_item "${MENU_KEYS[$i]}" "${MENU_LABELS[$i]}" "${MENU_HINTS[$i]}" "$DANGER" ;;
            0) ui_item "${MENU_KEYS[$i]}" "${MENU_LABELS[$i]}" "${MENU_HINTS[$i]}" "$GRAY" ;;
            *) ui_item "${MENU_KEYS[$i]}" "${MENU_LABELS[$i]}" "${MENU_HINTS[$i]}" ;;
        esac
    done

    ui_rule
    if ! IFS= read -r -p "${UI_INDENT}请选择 (1-9/A/B/U/0) > " choice; then
        echo
        exit 0
    fi
    choice="${choice//[[:space:]]/}"
    choice="${choice^^}"

    for ((i=0; i<MENU_COUNT; i++)); do
        if [[ "$choice" == "${MENU_KEYS[$i]}" ]]; then
            MENU_SELECTED=$i
            menu_dispatch
            return 0
        fi
    done
    ui_err "无效选项"
}

# ──────────────────────────────── 环境检查 ────────────────────────────────────

# 检测系统类型
detect_system_type() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID}"
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
                apt-get install -y curl procps coreutils systemd less gawk grep sed &>/dev/null
                ;;
            centos|rhel|fedora|rocky|almalinux)
                if command -v yum &>/dev/null; then
                    yum install -y curl procps-ng coreutils systemd less gawk grep sed &>/dev/null
                elif command -v dnf &>/dev/null; then
                    dnf install -y curl procps-ng coreutils systemd less gawk grep sed &>/dev/null
                fi
                ;;
            arch|manjaro)
                pacman -S --noconfirm curl procps-ng coreutils systemd less gawk grep sed &>/dev/null
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

# 检查环境、接管旧版安装并初始化
check_environment
migrate_legacy_install
init_service

# 记录一次控制台使用（USAGE_COUNT 按控制台启动次数统计）
{
    load_config || true
    USAGE_COUNT=$(( ${USAGE_COUNT:-0} + 1 ))
    if [[ -n "${LAST_URL:-}" ]]; then
        save_config "$LAST_URL" "${LAST_THREADS:-1}" "${LAST_INTERFACE:-eth0}"
    fi
}

# 主循环：交互终端使用方向键菜单，管道/重定向等非交互场景使用静态菜单
if [[ -t 0 && -t 1 ]]; then
    show_menu
else
    while true; do
        show_menu_plain
    done
fi
