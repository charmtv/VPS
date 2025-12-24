 (cd "$(git rev-parse --show-toplevel)" && git apply --3way <<'EOF' 
diff --git a/milier_flow_latest.sh b/milier_flow_latest.sh
index 6b1469d1802f71a16597487140b3dbca3a49d785..1a254c8a45ef81785911f614be5fb238f39dff73 100644
--- a/milier_flow_latest.sh
+++ b/milier_flow_latest.sh
@@ -1,40 +1,43 @@
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
+PID_FILE="/root/milier_flow.pid"
+GUARD_PID_FILE="/root/milier_guard.pid"
 DEFAULT_SHORTCUT="xh"
+INIT_SYSTEM=""
 
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
@@ -93,133 +96,152 @@ detect_network_interface() {
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
 
+# 检测初始化系统
+detect_init_system() {
+    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null; then
+        INIT_SYSTEM="systemd"
+    else
+        INIT_SYSTEM="local"
+    fi
+}
+
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
+    local target_bytes="$4" duration_secs="$5"
+
     cat > "$CONFIG_FILE" << EOF
 # ═══════════════════════════════════════════════════════════════════
 # 米粒儿配置文件 - $(date '+%Y-%m-%d %H:%M:%S')
 # ═══════════════════════════════════════════════════════════════════
 LAST_URL="$1"
 LAST_THREADS="$2"
 LAST_INTERFACE="$3"
+LAST_GUARD_BYTES="$target_bytes"
+LAST_GUARD_DURATION="$duration_secs"
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
-    if systemctl is-active --quiet $SERVICE_NAME; then
-        local pid=$(systemctl show -p MainPID --value $SERVICE_NAME 2>/dev/null)
-        local uptime=$(systemctl show -p ActiveEnterTimestamp --value $SERVICE_NAME 2>/dev/null | cut -d' ' -f2-3)
-        printf "${SUCCESS}服务状态：${WHITE}%-8s${RESET}    ${SUCCESS}进程PID：${WHITE}%-8s${RESET}\n" "运行中" "${pid:-"N/A"}"
-        [[ -n "$uptime" ]] && printf "${INFO}启动时间：${WHITE}%s${RESET}\n" "$uptime"
+    if is_engine_running; then
+        if [[ "$INIT_SYSTEM" == "systemd" ]]; then
+            local pid=$(systemctl show -p MainPID --value $SERVICE_NAME 2>/dev/null)
+            local uptime=$(systemctl show -p ActiveEnterTimestamp --value $SERVICE_NAME 2>/dev/null | cut -d' ' -f2-3)
+            printf "${SUCCESS}服务状态：${WHITE}%-8s${RESET}    ${SUCCESS}进程PID：${WHITE}%-8s${RESET}\n" "运行中" "${pid:-"N/A"}"
+            [[ -n "$uptime" ]] && printf "${INFO}启动时间：${WHITE}%s${RESET}\n" "$uptime"
+        else
+            local pid=$(cat "$PID_FILE" 2>/dev/null)
+            printf "${SUCCESS}服务状态：${WHITE}%-8s${RESET}    ${SUCCESS}模式：${WHITE}本地守护${RESET}\n" "运行中"
+            [[ -n "$pid" ]] && printf "${INFO}当前PID：${WHITE}%s${RESET}\n" "$pid"
+        fi
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
@@ -274,109 +296,248 @@ cd "$script_dir"
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
+write_env_file() {
+    local url="$1" threads="$2"
+    cat > /root/milier_env.conf << EOF
+MILIER_URL="$url"
+MILIER_THREADS="$threads"
+EOF
+}
+
+start_local_engine() {
+    local url="$1" threads="$2"
+    stop_local_engine "quiet"
+
+    echo "$(date '+%Y-%m-%d %H:%M:%S'): [启动] ${threads}线程开始下载${url}" | tee -a "$LOG_FILE"
+    nohup bash -c '
+        url="$1"; threads="$2"; log="$3";
+        echo "$(date '+%Y-%m-%d %H:%M:%S'): [守护] 本地模式启动" >> "$log"
+        for ((i=1;i<=threads;i++)); do
+            bash -c "while true; do curl -s -m 30 --connect-timeout 10 -o /dev/null \"$url\"; sleep 0.1; done" >>"$log" 2>&1 &
+        done
+        wait
+    ' _ "$url" "$threads" "$LOG_FILE" >>"$LOG_FILE" 2>&1 &
+
+    echo $! > "$PID_FILE"
+    disown
+}
+
+stop_local_engine() {
+    local silent="$1"
+    if [[ -f "$PID_FILE" ]]; then
+        local pid=$(cat "$PID_FILE" 2>/dev/null)
+        if [[ -n "$pid" ]]; then
+            kill "$pid" 2>/dev/null
+        fi
+        pkill -f "curl.*cloudflare" 2>/dev/null
+        rm -f "$PID_FILE"
+        [[ "$silent" == "quiet" ]] || echo -e "${SUCCESS}✅ 本地服务已停止${RESET}"
+    fi
+}
+
+stop_guard() {
+    if [[ -f "$GUARD_PID_FILE" ]]; then
+        local guard_pid=$(cat "$GUARD_PID_FILE" 2>/dev/null)
+        if [[ -n "$guard_pid" ]]; then
+            kill "$guard_pid" 2>/dev/null
+        fi
+        rm -f "$GUARD_PID_FILE"
+    fi
+}
+
+start_guard() {
+    local target_bytes="$1" duration_secs="$2" interface="$3"
+    [[ -z "$target_bytes" && -z "$duration_secs" ]] && return
+
+    stop_guard
+    ( 
+        local start_time=$(date +%s)
+        local rx_prev=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
+        local tx_prev=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)
+        local start_total=$((rx_prev + tx_prev))
+
+        while true; do
+            sleep 5
+            local now=$(date +%s)
+            local rx_now=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "$rx_prev")
+            local tx_now=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "$tx_prev")
+            local rx_delta=$((rx_now - rx_prev))
+            local tx_delta=$((tx_now - tx_prev))
+            ((rx_delta < 0)) && rx_delta=0
+            ((tx_delta < 0)) && tx_delta=0
+            rx_prev=$rx_now; tx_prev=$tx_now
+            local total_bytes=$((rx_now + tx_now))
+            local consumed=$((total_bytes - start_total))
+            ((consumed < 0)) && consumed=0
+
+            if [[ -n "$target_bytes" && $consumed -ge $target_bytes ]]; then
+                echo "$(date '+%Y-%m-%d %H:%M:%S'): 达到设定流量阈值，自动暂停" | tee -a "$LOG_FILE"
+                stop_engine "from_guard"
+                rm -f "$GUARD_PID_FILE"
+                exit 0
+            fi
+
+            if [[ -n "$duration_secs" ]]; then
+                local elapsed=$((now - start_time))
+                if [[ $elapsed -ge $duration_secs ]]; then
+                    echo "$(date '+%Y-%m-%d %H:%M:%S'): 达到设定运行时长，自动暂停" | tee -a "$LOG_FILE"
+                    stop_engine "from_guard"
+                    rm -f "$GUARD_PID_FILE"
+                    exit 0
+                fi
+            fi
+        done
+    ) &
+    echo $! > "$GUARD_PID_FILE"
+}
+
+stop_engine() {
+    local caller="$1"
+    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
+        systemctl stop $SERVICE_NAME 2>/dev/null
+    else
+        stop_local_engine "quiet"
+    fi
+
+    [[ "$caller" == "from_guard" ]] || stop_guard
+}
+
+start_engine() {
+    local url="$1" threads="$2"
+    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
+        systemctl stop $SERVICE_NAME 2>/dev/null
+        write_env_file "$url" "$threads"
+        systemctl daemon-reload
+        systemctl start $SERVICE_NAME
+    else
+        write_env_file "$url" "$threads"
+        start_local_engine "$url" "$threads"
+    fi
+}
+
+is_engine_running() {
+    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
+        systemctl is-active --quiet $SERVICE_NAME
+        return
+    fi
+
+    if [[ -f "$PID_FILE" ]]; then
+        local pid=$(cat "$PID_FILE" 2>/dev/null)
+        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
+            return 0
+        fi
+    fi
+
+    return 1
+}
+
 init_service() {
-    if [[ -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
+    if [[ "$INIT_SYSTEM" == "systemd" && -f "/etc/systemd/system/$SERVICE_NAME.service" ]]; then
         return 0
     fi
-    
+
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
+    write_env_file "$default_url" "$default_threads"
 
-    # 创建 systemd 服务
-    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
+    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
+        # 创建 systemd 服务
+        cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
 [Unit]
 Description=米粒儿 VPS 流量消耗后台服务
 After=network.target
 StartLimitBurst=3
 StartLimitIntervalSec=60
 
 [Service]
 Type=simple
 WorkingDirectory=/root
-Environment="MILIER_URL=$default_url"
-Environment="MILIER_THREADS=$default_threads"
+EnvironmentFile=-/root/milier_env.conf
 ExecStart=/bin/bash -c '\
-URL="\$MILIER_URL"; THREADS="\$MILIER_THREADS"; LOG_FILE="$LOG_FILE"; \
+URL="\${MILIER_URL:-$default_url}"; THREADS="\${MILIER_THREADS:-$default_threads}"; LOG_FILE="$LOG_FILE"; \
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
 
-    systemctl daemon-reload
-    check_command "系统配置失败" || return 1
+        systemctl daemon-reload
+        check_command "系统配置失败" || return 1
+    else
+        echo -e "${INFO}检测到非systemd环境，使用本地守护模式运行${RESET}"
+    fi
 
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
@@ -608,163 +769,342 @@ while true; do
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
-systemctl stop $SERVICE_NAME 2>/dev/null
-systemctl disable $SERVICE_NAME 2>/dev/null
-rm -f /etc/systemd/system/$SERVICE_NAME.service
-systemctl daemon-reload
-rm -f "$MONITOR_SCRIPT" "$UNINSTALL_SCRIPT" "$LOG_FILE" "$CONFIG_FILE"
+if command -v systemctl &>/dev/null; then
+    systemctl stop $SERVICE_NAME 2>/dev/null
+    systemctl disable $SERVICE_NAME 2>/dev/null
+    rm -f /etc/systemd/system/$SERVICE_NAME.service
+    systemctl daemon-reload
+else
+    if [[ -f "$PID_FILE" ]]; then
+        kill "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
+    fi
+    pkill -f "curl.*cloudflare" 2>/dev/null
+fi
+rm -f "$MONITOR_SCRIPT" "$UNINSTALL_SCRIPT" "$LOG_FILE" "$CONFIG_FILE" "$PID_FILE" "$GUARD_PID_FILE" /root/milier_env.conf
 
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
-    save_config "$default_url" "$default_threads" "$interface"
+    save_config "$default_url" "$default_threads" "$interface" "" ""
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
     
+    read -p "自定义流量上限(GB，回车跳过)：" target_gb
+    local target_bytes=""
+    if [[ -n "$target_gb" ]]; then
+        if [[ "$target_gb" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
+            target_bytes=$(awk "BEGIN{printf \"%.0f\", $target_gb*1024*1024*1024}" 2>/dev/null)
+        else
+            echo -e "${WARNING}输入的流量上限无效，将忽略${RESET}"
+        fi
+    fi
+
+    read -p "设置运行时长(分钟，回车跳过)：" duration_minutes
+    local duration_secs=""
+    if [[ -n "$duration_minutes" ]]; then
+        if [[ "$duration_minutes" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
+            duration_secs=$(awk "BEGIN{printf \"%.0f\", $duration_minutes*60}" 2>/dev/null)
+        else
+            echo -e "${WARNING}输入的时长无效，将忽略${RESET}"
+        fi
+    fi
+
     # 确认配置
     echo
     echo -e "${PRIMARY}配置确认${RESET}"
     echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
     printf "${INFO}%-12s${WHITE}%s${RESET}\n" "下载URL：" "$url"
     printf "${INFO}%-12s${WHITE}%s${RESET}\n" "线程数量：" "$threads"
+    [[ -n "$target_bytes" ]] && printf "${INFO}%-12s${WHITE}%s GB${RESET}\n" "流量上限：" "$target_gb"
+    [[ -n "$duration_secs" ]] && printf "${INFO}%-12s${WHITE}%s 分钟${RESET}\n" "运行时长：" "$duration_minutes"
     echo -e "${GRAY}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
     echo
     read -p "确认启动？(Y/n)：" confirm
     [[ "$confirm" =~ ^[Nn]$ ]] && return
-    
-    export MILIER_URL="$url" MILIER_THREADS="$threads"
-    systemctl stop $SERVICE_NAME 2>/dev/null
-    systemctl start $SERVICE_NAME
-    
+
+    start_engine "$url" "$threads"
+
     if check_command "服务启动失败"; then
         interface=$(detect_network_interface)
-        save_config "$url" "$threads" "$interface"
+        save_config "$url" "$threads" "$interface" "$target_bytes" "$duration_secs"
         echo -e "${SUCCESS}✅ 服务启动成功${RESET}"
+        if [[ -n "$interface" ]]; then
+            start_guard "$target_bytes" "$duration_secs" "$interface"
+            if [[ -n "$target_bytes" || -n "$duration_secs" ]]; then
+                echo -e "${INFO}已开启自动暂停守护：流量上限=${target_gb:-未设}GB 时长=${duration_minutes:-未设}分钟${RESET}"
+            fi
+        fi
     fi
-    
+
     read -p "按回车返回菜单..."
 }
 
 # 停止服务
 stop_service() {
     echo -e "${WARNING}正在停止服务...${RESET}"
-    systemctl stop $SERVICE_NAME
-    if check_command "停止失败"; then
-        pkill -f "curl.*cloudflare" 2>/dev/null
-        echo -e "${SUCCESS}✅ 服务已停止${RESET}"
-    fi
+    stop_engine
+    pkill -f "curl.*cloudflare" 2>/dev/null
+    echo -e "${SUCCESS}✅ 服务已停止${RESET}"
     read -p "按回车返回菜单..."
 }
 
 # 重启服务
 restart_service() {
     echo -e "${WARNING}正在重启服务...${RESET}"
-    systemctl restart $SERVICE_NAME
-    if check_command "重启失败"; then
-        echo -e "${SUCCESS}✅ 服务已重启${RESET}"
+    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
+        systemctl restart $SERVICE_NAME
+    else
+        stop_local_engine "quiet"
+        load_config
+        start_local_engine "${LAST_URL:-https://speed.cloudflare.com/__down?bytes=104857600}" "${LAST_THREADS:-4}"
     fi
+    stop_guard
+    echo -e "${SUCCESS}✅ 服务已重启${RESET}"
+    read -p "按回车返回菜单..."
+}
+
+show_config_summary() {
+    clear
+    echo -e "${PRIMARY}配置与运行概览${RESET}"
+    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
+    echo
+
+    # 服务状态概览
+    if is_engine_running; then
+        if [[ "$INIT_SYSTEM" == "systemd" ]]; then
+            local pid=$(systemctl show -p MainPID --value $SERVICE_NAME 2>/dev/null)
+            local active_time=$(systemctl show -p ActiveEnterTimestamp --value $SERVICE_NAME 2>/dev/null | cut -d' ' -f2-3)
+            printf "${SUCCESS}服务状态：${WHITE}运行中${RESET}    ${INFO}PID：${WHITE}%s${RESET}\n" "${pid:-N/A}"
+            [[ -n "$active_time" ]] && printf "${INFO}启动时间：${WHITE}%s${RESET}\n" "$active_time"
+        else
+            local pid=$(cat "$PID_FILE" 2>/dev/null)
+            printf "${SUCCESS}服务状态：${WHITE}运行中${RESET}    ${INFO}模式：${WHITE}本地守护${RESET}\n"
+            [[ -n "$pid" ]] && printf "${INFO}当前PID：${WHITE}%s${RESET}\n" "$pid"
+        fi
+    else
+        echo -e "${WARNING}⚠️  服务未运行${RESET}"
+    fi
+
+    # 配置详情
+    echo
+    echo -e "${ACCENT}最近使用的配置${RESET}"
+    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
+    if [[ -f "$CONFIG_FILE" ]]; then
+        load_config
+        printf "${INFO}%-12s${WHITE}%s${RESET}\n" "下载URL：" "${LAST_URL:-未记录}"
+        printf "${INFO}%-12s${WHITE}%s 线程${RESET}\n" "线程数：" "${LAST_THREADS:-未记录}"
+        printf "${INFO}%-12s${WHITE}%s${RESET}\n" "网络接口：" "${LAST_INTERFACE:-未记录}"
+        if [[ -n "$LAST_GUARD_BYTES" || -n "$LAST_GUARD_DURATION" ]]; then
+            local guard_limit_msg="$( [[ -n "$LAST_GUARD_BYTES" ]] && awk "BEGIN{printf \"%.2fGB\", $LAST_GUARD_BYTES/1024/1024/1024}" 2>/dev/null )"
+            local guard_time_msg="$( [[ -n "$LAST_GUARD_DURATION" ]] && awk "BEGIN{printf \"%.0f分钟\", $LAST_GUARD_DURATION/60}" 2>/dev/null )"
+            printf "${INFO}%-12s${WHITE}%s ${RESET}\n" "自动暂停：" "${guard_limit_msg:-未设流量}${guard_time_msg:+ / $guard_time_msg}"
+        fi
+        [[ -n "$LAST_USED" ]] && printf "${INFO}%-12s${WHITE}%s${RESET}\n" "最近使用：" "$LAST_USED"
+        [[ -n "$USAGE_COUNT" ]] && printf "${INFO}%-12s${WHITE}%s 次${RESET}\n" "累计使用：" "$USAGE_COUNT"
+    else
+        echo -e "${WARNING}未找到配置文件：$CONFIG_FILE${RESET}"
+    fi
+
+    # 快捷键信息
+    echo
+    echo -e "${SECONDARY}快捷键信息${RESET}"
+    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
+    if [[ -f "$SHORTCUT_CONFIG" ]]; then
+        source "$SHORTCUT_CONFIG"
+        printf "${INFO}%-12s${WHITE}%s${RESET}\n" "快捷键：" "${SHORTCUT_NAME:-$DEFAULT_SHORTCUT}"
+        printf "${INFO}%-12s${WHITE}%s${RESET}\n" "路径：" "${SHORTCUT_PATH:-/usr/local/bin/$DEFAULT_SHORTCUT}"
+        [[ -n "$CREATED_TIME" ]] && printf "${INFO}%-12s${WHITE}%s${RESET}\n" "创建时间：" "$CREATED_TIME"
+    else
+        echo -e "${WARNING}未配置快捷键${RESET}"
+    fi
+
+    # 日志文件信息
+    echo
+    echo -e "${INFO}日志文件${RESET}"
+    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
+    if [[ -f "$GUARD_PID_FILE" ]]; then
+        local guard_pid=$(cat "$GUARD_PID_FILE" 2>/dev/null)
+        printf "${INFO}%-12s${WHITE}%s${RESET}\n" "守护状态：" "运行中 (PID: ${guard_pid:-未知})"
+    else
+        printf "${INFO}%-12s${WHITE}%s${RESET}\n" "守护状态：" "未启动"
+    fi
+    if [[ -f "$LOG_FILE" ]]; then
+        local log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null)
+        printf "${INFO}%-12s${WHITE}%s${RESET}\n" "位置：" "$LOG_FILE"
+        [[ -n "$log_size" ]] && printf "${INFO}%-12s${WHITE}%s${RESET}\n" "大小：" "$(format_file_size "$log_size")"
+        echo -e "${GRAY}最近三行：${RESET}"
+        tail -n 3 "$LOG_FILE" 2>/dev/null
+    else
+        echo -e "${WARNING}未找到日志文件${RESET}"
+    fi
+
+    echo
+    echo -e "${GRAY}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
+    read -p "按回车返回菜单..."
+}
+
+generate_health_report() {
+    clear
+    echo -e "${PRIMARY}生成健康报告${RESET}"
+    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
+    echo
+
+    local report_file="/root/milier_health_report.txt"
+    local now=$(date '+%Y-%m-%d %H:%M:%S')
+
+    detect_system_type
+    detect_init_system
+    load_config
+
+    local guard_status="未启动"
+    local guard_pid_msg=""
+    if [[ -f "$GUARD_PID_FILE" ]]; then
+        local guard_pid=$(cat "$GUARD_PID_FILE" 2>/dev/null)
+        guard_status="运行中"
+        guard_pid_msg=" (PID: ${guard_pid:-未知})"
+    fi
+
+    local guard_limit_msg="$( [[ -n "$LAST_GUARD_BYTES" ]] && awk "BEGIN{printf \"%.2f GB\", $LAST_GUARD_BYTES/1024/1024/1024}" 2>/dev/null )"
+    local guard_time_msg="$( [[ -n "$LAST_GUARD_DURATION" ]] && awk "BEGIN{printf \"%.0f 分钟\", $LAST_GUARD_DURATION/60}" 2>/dev/null )"
+
+    local service_state="未运行"
+    if is_engine_running; then
+        service_state="运行中"
+        [[ "$INIT_SYSTEM" == "systemd" ]] && service_state+=" (systemd)" || service_state+=" (本地守护)"
+    fi
+
+    local os_line="${OS_NAME:-未知} (${OS_ID:-未知} ${OS_VERSION:-""})"
+    local latest_log="$(tail -n 5 "$LOG_FILE" 2>/dev/null)"
+
+    cat > "$report_file" << EOF
+══════════════════════════════════════════════════════════════════════
+米粒儿运行健康报告 - $now
+══════════════════════════════════════════════════════════════════════
+系统信息：
+  操作系统：$os_line
+  初始化系统：${INIT_SYSTEM:-未知}
+
+服务状态：
+  运行状态：$service_state
+  上次URL：${LAST_URL:-未记录}
+  线程数：${LAST_THREADS:-未记录}
+  网络接口：${LAST_INTERFACE:-未记录}
+
+守护与限额：
+  自动暂停：${guard_limit_msg:-未设流量}${guard_time_msg:+ / $guard_time_msg}
+  守护进程：$guard_status${guard_pid_msg}
+
+日志摘录：
+${latest_log:-暂无日志}
+══════════════════════════════════════════════════════════════════════
+EOF
+
+    echo -e "${SUCCESS}✅ 健康报告已生成：${WHITE}$report_file${RESET}"
+    echo -e "${INFO}可将文件发送给支持人员进行诊断${RESET}"
+    echo
     read -p "按回车返回菜单..."
 }
 
 # 显示监控
 show_monitor() {
     echo -e "${INFO}正在启动实时流量监控...${RESET}"
     
     # 检查服务状态（非强制要求）
-    if ! systemctl is-active --quiet $SERVICE_NAME; then
+    if ! is_engine_running; then
         echo -e "${WARNING}⚠️  流量消耗服务未运行，但监控功能仍可使用${RESET}"
     else
-        echo -e "${SUCCESS}✅ 流量消耗服务运行中${RESET}"
+        local mode_label=$([[ "$INIT_SYSTEM" == "systemd" ]] && echo "systemd" || echo "本地守护")
+        echo -e "${SUCCESS}✅ 流量消耗服务运行中（${mode_label}）${RESET}"
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
@@ -1455,113 +1795,111 @@ show_menu() {
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
 
-    # 操作菜单 - 竖排布局
+    # 操作菜单 - 分组栅格布局
     echo -e "${PRIMARY}操作菜单${RESET}"
     echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
-    echo -e "${SUCCESS}1) 启动流量消耗服务${RESET}"
-    echo -e "${DANGER}2) 停止流量消耗服务${RESET}"
-    echo -e "${INFO}3) 实时流量监控${RESET}"
-    echo -e "${WARNING}4) 重启流量服务${RESET}"
-    echo -e "${INFO}5) 查看服务日志${RESET}"
-    echo -e "${SECONDARY}6) 快捷键管理${RESET}"
-    echo -e "${ACCENT}8) 测试监控功能${RESET}"
-    echo -e "${SECONDARY}9) 高级监控${RESET}"
-    echo -e "${WARNING}A) 检查更新${RESET}"
-    echo -e "${DANGER}7) 卸载全部服务${RESET}"
-    echo -e "${GRAY}0) 退出程序${RESET}"
+    printf "${SUCCESS}1) 启动服务${RESET}        ${DANGER}2) 停止服务${RESET}        ${INFO}3) 实时监控${RESET}\n"
+    printf "${WARNING}4) 重启服务${RESET}        ${INFO}5) 查看日志${RESET}       ${SECONDARY}6) 快捷键管理${RESET}\n"
+    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
+    printf "${ACCENT}8) 测试监控${RESET}       ${SECONDARY}9) 高级监控${RESET}       ${LINK}10) 配置概览${RESET}\n"
+    printf "${INFO}11) 健康报告${RESET}      ${WARNING}A) 检查更新${RESET}      ${DANGER}7) 卸载全部服务${RESET}\n"
+    echo -e "${GRAY}├─────────────────────────────────────────────────────────────────────────────┤${RESET}"
+    printf "${GRAY}0) 退出程序${RESET}\n"
     echo -e "${GRAY}└─────────────────────────────────────────────────────────────────────────────┘${RESET}"
     echo
-    
-    read -p "请选择操作 [0-9,A]：" choice
+
+    read -p "请选择操作 [0-11,A]：" choice
     
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
+        10) show_config_summary ;;
+        11) generate_health_report ;;
         [Aa]) check_update ;;
-        0) 
+        0)
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
-            echo -e "${DANGER}❌ 无效选项，请输入 0-9 或 A${RESET}"
+            echo -e "${DANGER}❌ 无效选项，请输入 0-11 或 A${RESET}"
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
-    local required_commands=("curl" "systemctl" "nproc" "free" "df" "ps" "grep" "awk" "sed" "less")
+    local required_commands=("curl" "nproc" "free" "df" "ps" "grep" "awk" "sed" "less")
     
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
@@ -1574,52 +1912,51 @@ install_missing_deps() {
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
-    
+    detect_init_system
+
     # 检查并安装缺失的依赖
     install_missing_deps
-    
+
     # 检查关键系统文件
     if [[ ! -d "/sys/class/net" ]]; then
         echo -e "${DANGER}❌ 系统网络接口目录不存在${RESET}"
         exit 1
     fi
-    
-    # 检查systemd支持
-    if ! systemctl --version &>/dev/null; then
-        echo -e "${DANGER}❌ 系统不支持systemd${RESET}"
-        exit 1
+
+    if [[ "$INIT_SYSTEM" != "systemd" ]]; then
+        echo -e "${WARNING}⚠️  当前环境未检测到systemd，将使用本地守护模式运行${RESET}"
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
 
EOF
)
