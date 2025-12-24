 (cd "$(git rev-parse --show-toplevel)" && git apply --3way <<'EOF' 
diff --git a/install.sh b/install.sh
index caa07b2aeb352c3d9e5155011d88368c92ada05d..cd6909870ba6ac0d62c6948914c3bb4e2c429c52 100644
--- a/install.sh
+++ b/install.sh
@@ -1,136 +1,151 @@
 #!/bin/bash
 
 # ═══════════════════════════════════════════════════════════════════════════════════
 # 米粒儿VPS流量消耗管理工具 - 一键安装脚本
 # 官方TG群：https://t.me/mlkjfx6
 # GitHub：https://github.com/charmtv/VPS
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
 
+# 系统信息
+OS_NAME=""
+INIT_SYSTEM="local"
+
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
 
 # 检测系统类型
 detect_system() {
     if [[ -f /etc/os-release ]]; then
         source /etc/os-release
         OS_ID="${ID}"
         OS_VERSION="${VERSION_ID}"
         OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"
+        OS_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
         info_msg "检测到系统：$PRETTY_NAME"
     else
         error_exit "不支持的操作系统，仅支持Linux系统"
     fi
 }
 
+# 检测初始化系统（systemd/local）
+detect_init_system() {
+    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null; then
+        INIT_SYSTEM="systemd"
+        info_msg "检测到 systemd，后台服务将使用 systemd 管理"
+    else
+        INIT_SYSTEM="local"
+        warning_msg "未检测到 systemd，将使用本地守护模式运行（功能会自动适配）"
+    fi
+}
+
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
-    local required_commands=("curl" "wget" "systemctl" "nproc" "free" "df" "ps" "grep" "awk" "sed")
+    local required_commands=("curl" "wget" "nproc" "free" "df" "ps" "grep" "awk" "sed")
     
     # 检查缺失的命令
     for cmd in "${required_commands[@]}"; do
         if ! command -v "$cmd" &>/dev/null; then
             case "$cmd" in
                 "curl") packages_to_install+=("curl") ;;
                 "wget") packages_to_install+=("wget") ;;
-                "systemctl") packages_to_install+=("systemd") ;;
                 "nproc"|"free"|"df"|"ps") packages_to_install+=("procps") ;;
                 "grep"|"awk"|"sed") packages_to_install+=("coreutils") ;;
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
@@ -155,59 +170,57 @@ install_dependencies() {
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
     
+    # 检测初始化系统，允许在无 systemd 的环境下使用本地守护模式
+    detect_init_system
+
     # 更新包管理器并安装依赖
     update_package_manager
     install_dependencies
     
-    # 检查systemd
-    if ! command -v systemctl &>/dev/null; then
-        error_exit "系统不支持systemd，无法使用此工具"
-    fi
-    
     # 检查网络连接
     if ! curl -s --max-time 10 --connect-timeout 5 https://www.google.com &>/dev/null; then
         warning_msg "网络连接可能有问题，但继续安装..."
     fi
     
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
@@ -271,77 +284,82 @@ debian13_optimization() {
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
     
-    # 验证systemd服务支持
-    if ! systemctl --version &>/dev/null; then
-        warning_msg "systemd未正确安装，后台服务功能可能受影响"
+    # 验证systemd服务支持（仅在检测到 systemd 时提示）
+    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
+        if ! systemctl --version &>/dev/null; then
+            warning_msg "systemd 未正确安装，后台服务功能可能受影响"
+        fi
+    else
+        warning_msg "当前环境未启用 systemd，工具将以本地守护模式运行"
     fi
     
     # 特殊系统优化
     debian13_optimization
     
     success_msg "最终验证通过"
 }
 
 # 显示安装完成信息
 show_completion() {
     echo
     echo -e "${SUCCESS}🎉 米粒儿VPS流量消耗管理工具安装完成！${RESET}"
     echo
-    echo -e "${INFO}系统信息：${WHITE}$OS_NAME${RESET}"
+    echo -e "${INFO}系统信息：${WHITE}${OS_NAME}${RESET}"
+    echo -e "${INFO}运行模式：${WHITE}$([[ "$INIT_SYSTEM" == "systemd" ]] && echo "systemd 服务管理" || echo "本地守护模式")${RESET}"
     echo
     echo -e "${PRIMARY}使用方法：${RESET}"
     echo -e "  ${WHITE}• 快捷启动：${PRIMARY}$SHORTCUT_NAME${RESET}"
     echo -e "  ${WHITE}• 完整路径：${INFO}bash $INSTALL_DIR/$SCRIPT_NAME${RESET}"
     echo
     echo -e "${PRIMARY}功能特点：${RESET}"
     echo -e "  ${WHITE}• 智能多线程流量消耗${RESET}"
     echo -e "  ${WHITE}• 实时流量监控与统计（已增强兼容性）${RESET}"
     echo -e "  ${WHITE}• 自动网络接口选择${RESET}"
-    echo -e "  ${WHITE}• 系统服务后台运行${RESET}"
+    echo -e "  ${WHITE}• 系统服务后台运行或本地守护${RESET}"
     echo -e "  ${WHITE}• 全系统兼容（特别优化Debian 13）${RESET}"
     echo
     echo -e "${PRIMARY}官方支持：${RESET}"
     echo -e "  ${WHITE}• TG群：${INFO}https://t.me/mlkjfx6${RESET}"
     echo -e "  ${WHITE}• GitHub：${INFO}$REPO_URL${RESET}"
     echo
     echo -e "${WARNING}现在就可以输入 '${PRIMARY}$SHORTCUT_NAME${WARNING}' 开始使用！${RESET}"
     echo -e "${INFO}如果遇到问题，脚本会自动安装必要依赖并提供详细错误提示${RESET}"
     echo
 }
 
 # 主安装流程
 main() {
     show_header
     
     echo -e "${INFO}正在安装米粒儿VPS流量消耗管理工具（增强版）...${RESET}"
     echo -e "${INFO}GitHub项目：${WHITE}$REPO_URL${RESET}"
     echo -e "${INFO}本版本特别优化了Debian 13系统兼容性${RESET}"
     echo
     
     check_environment
     download_script
     create_global_shortcut
     verify_installation
     final_verification
 
EOF
)
