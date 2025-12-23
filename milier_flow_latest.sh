#!/usr/bin/env bash
# 米粒儿 VPS 流量消耗管理工具（整合终版）

#################### 基础配置 ####################
CONFIG_FILE="/root/milier_config.conf"
LOG_FILE="/root/milier_flow.log"
PID_FILE="/root/milier.pid"
DEFAULT_URL="https://speed.cloudflare.com/__down?bytes=104857600"

PRIMARY="\e[38;5;39m"
SUCCESS="\e[38;5;46m"
WARNING="\e[38;5;226m"
DANGER="\e[38;5;196m"
INFO="\e[38;5;117m"
WHITE="\e[97m"
GRAY="\e[90m"
RESET="\e[0m"

#################### 工具函数 ####################
require_root() {
    [[ $EUID -ne 0 ]] && echo -e "${DANGER}需要 root 权限运行${RESET}" && exit 1
}

detect_iface() {
    ls /sys/class/net | grep -Ev 'lo|docker|veth|br-' | head -n1
}

is_systemd() {
    command -v systemctl &>/dev/null
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}

save_config() {
cat > "$CONFIG_FILE" <<EOF
URL="$URL"
THREADS="$THREADS"
MAX_TOTAL_GB="$MAX_TOTAL_GB"
BASE_RX="$BASE_RX"
BASE_TX="$BASE_TX"
INTERFACE="$INTERFACE"
EOF
}

bytes_to_gb() {
    awk "BEGIN{printf \"%.2f\", $1/1024/1024/1024}"
}

#################### 后台核心 ####################
flow_guard() {
    trap 'pkill -P $$; exit 0' EXIT INT TERM

    while true; do
        ping -c1 1.1.1.1 &>/dev/null || { sleep 5; continue; }

        RX_NOW=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo 0)
        TX_NOW=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo 0)

        USED_BYTES=$((RX_NOW + TX_NOW - BASE_RX - BASE_TX))
        LIMIT_BYTES=$((MAX_TOTAL_GB * 1024 * 1024 * 1024))

        if [[ "$MAX_TOTAL_GB" -gt 0 && "$USED_BYTES" -ge "$LIMIT_BYTES" ]]; then
            echo "$(date) 达到流量上限 ${MAX_TOTAL_GB}GB，自动停止" >> "$LOG_FILE"
            is_systemd && systemctl stop milier_flow
            exit 0
        fi
        sleep 1
    done
}

downloader() {
    while true; do
        curl -s --connect-timeout 10 -m 30 -o /dev/null "$URL"
    done
}

#################### 启停服务 ####################
start_service() {
    load_config
    INTERFACE=${INTERFACE:-$(detect_iface)}
    THREADS=${THREADS:-$(($(nproc) * 2))}
    URL=${URL:-$DEFAULT_URL}

    [[ "$MAX_TOTAL_GB" -le 0 ]] && echo -e "${WARNING}未设置流量上限${RESET}" && return

    BASE_RX=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    BASE_TX=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)

    save_config

    if is_systemd; then
cat >/etc/systemd/system/milier_flow.service <<EOF
[Unit]
Description=Milier Flow Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $0 _run
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl restart milier_flow
    else
        nohup bash "$0" _run >>"$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
    fi
}

stop_service() {
    is_systemd && systemctl stop milier_flow
    [[ -f "$PID_FILE" ]] && kill "$(cat $PID_FILE)" 2>/dev/null && rm -f "$PID_FILE"
}

#################### 后台入口 ####################
if [[ "$1" == "_run" ]]; then
    load_config
    flow_guard &
    for ((i=1;i<=THREADS;i++)); do downloader & done
    wait
    exit 0
fi

#################### 菜单功能 ####################
set_flow_limit() {
    read -p "请输入最大流量（GB，0=不限制）：" MAX_TOTAL_GB
    [[ ! "$MAX_TOTAL_GB" =~ ^[0-9]+$ ]] && return
    save_config
}

show_logs() {
    [[ -f "$LOG_FILE" ]] && less "$LOG_FILE"
}

#################### 主菜单 ####################
show_menu() {
    clear
    load_config

    RX_NOW=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX_NOW=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    USED_BYTES=$((RX_NOW + TX_NOW - BASE_RX - BASE_TX))

    USED_GB=$(bytes_to_gb "$USED_BYTES")
    LEFT_GB=$(awk "BEGIN{printf \"%.2f\", $MAX_TOTAL_GB - $USED_GB}")

    echo
    echo -e "${PRIMARY}        米粒儿 VPS 流量管理工具${RESET}"
    echo -e "${GRAY}──────────────────────────────────${RESET}"
    echo -e "${INFO}已用流量：${WHITE}${USED_GB} GB${RESET}"
    [[ "$MAX_TOTAL_GB" -gt 0 ]] && \
    echo -e "${INFO}剩余流量：${WHITE}${LEFT_GB} GB${RESET}"
    echo
    echo -e "${SUCCESS}1) 启动流量消耗${RESET}"
    echo -e "${DANGER}2) 停止流量消耗${RESET}"
    echo -e "${WARNING}3) 设置流量上限${RESET}"
    echo -e "${INFO}4) 查看日志${RESET}"
    echo -e "${GRAY}0) 退出${RESET}"
    echo
    read -p "请选择操作 [0-4]：" c

    case "$c" in
        1) start_service ;;
        2) stop_service ;;
        3) set_flow_limit ;;
        4) show_logs ;;
        0) exit 0 ;;
    esac
}

#################### 程序入口 ####################
require_root
while true; do show_menu; done
