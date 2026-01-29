#!/usr/bin/env bash

#
# Mihomo Manager for ClashMac 一个用于管理 ClashMac 中 Mihomo 内核的脚本工具
#
# Author: Kuochiang Lu
# Version: v1.1.0
# Last Updated: $(date +%Y-%m-%d)
#
# 描述：
#   ClashMac mihomo 内核交互式管理工具，提供直观的菜单界面
#   整合核心下载、管理、切换功能，与 GUI 完全分离职责
#
# 功能：
#   - 安装/更新 mihomo 核心（支持多个 GitHub 源）
#   - 在备份之间切换
#   - 列出所有备份核心
#   - 显示当前核心及系统状态
#   - 健康检查功能
#   - 杀掉 Mihomo 内核进程
#   - 重启 ClashMac 应用
#   - 直观的交互式菜单界面
#

SCRIPT_VERSION="v1.1.0"

# ========================# 配置路径和默认变量# ========================
CLASHMAC_DIR="/Applications/ClashMac.app"
CLASHMAC_CORE_DIR="$HOME/Library/Application Support/clashmac/core"
ACTIVE_CORE="mihomo"   # 默认核心文件名

GITHUB_USERS=("MetaCubeX" "vernesong")  # 可选 GitHub 用户
DEFAULT_BRANCH="Prerelease-Alpha"       # 默认分支

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# ========================# 权限管理函数# ========================

# 请求管理员权限
request_sudo() {
    if ! sudo -n true 2>/dev/null; then
        echo -e "${PURPLE}[授权请求] 操作需要管理员权限，请输入密码${NC}"
        sudo -v
        if [ $? -ne 0 ]; then
            echo -e "${RED}[错误] 授权失败，无法执行需要权限的操作${NC}"
            return 1
        fi
        # 保持sudo权限
        sudo -v -s <<EOF
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
EOF
        echo -e "${GREEN}[成功] 权限已获取${NC}"
    fi
    return 0
}

# ========================# 状态检查函数# ========================
# 检查 Mihomo 进程状态
check_mihomo_status() {
    if pgrep -x "mihomo" > /dev/null 2>&1; then
        echo "已运行"
        return 0
    else
        echo "已停止"
        return 1
    fi
}

# 获取 Mihomo 版本
get_mihomo_version() {
    if [ -x "$CLASHMAC_CORE_DIR/$ACTIVE_CORE" ]; then
        CURRENT_RAW=$("$CLASHMAC_CORE_DIR/$ACTIVE_CORE" -v 2>/dev/null | head -n1)
        if [[ "$CURRENT_RAW" =~ ^Mihomo[[:space:]]+Meta[[:space:]]+([^[:space:]]+)[[:space:]]+darwin[[:space:]]+(amd64|arm64) ]]; then
            CURRENT_VER="${BASH_REMATCH[1]}"
            echo "$CURRENT_VER"
        else
            echo "无法解析"
        fi
    else
        echo "未安装"
    fi
}

# 终止Mihomo内核进程
kill_mihomo_kernel() {
    echo -e "\n${CYAN}[操作] 正在终止 Mihomo 内核进程...${NC}"

    # 获取Mihomo内核进程ID
    local pids=$(pgrep -f "$ACTIVE_CORE")
    if [ -n "$pids" ]; then
        # 预先检查是否需要sudo权限
        local need_sudo=false
        for pid in $pids; do
            if ! kill -0 "$pid" 2>/dev/null; then
                need_sudo=true
                break
            fi
        done

        # 如果需要sudo权限，提前一次性请求
        if $need_sudo; then
            echo -e "${YELLOW}[提示] 需要管理员权限来终止某些进程${NC}"
            if ! request_sudo; then
                echo -e "${RED}[错误] 授权失败，无法继续终止进程${NC}"
                return 1
            fi
        fi

        # 使用适当的权限终止进程
        local termination_success=true
        for pid in $pids; do
            echo -e "${YELLOW}[提示] 尝试终止进程 ID: $pid${NC}"
            if $need_sudo; then
                if sudo kill "$pid" 2>/dev/null; then
                    echo -e "${GREEN}[成功] 使用 sudo 终止进程 $pid${NC}"
                else
                    echo -e "${RED}[错误] 即使使用 sudo 也无法终止进程 $pid${NC}"
                    termination_success=false
                fi
            else
                if kill "$pid" 2>/dev/null; then
                    echo -e "${GREEN}[成功] 进程 $pid 已终止${NC}"
                else
                    echo -e "${RED}[错误] 终止进程 $pid 失败${NC}"
                    termination_success=false
                fi
            fi
        done

        # 等待并验证进程是否已终止
        sleep 1
        if pgrep -f "$ACTIVE_CORE" >/dev/null; then
            echo -e "${RED}[错误] 仍有 Mihomo 内核进程在运行${NC}"
            echo -e "${YELLOW}[提示] 请尝试在 ClashMac GUI 中手动停止核心${NC}"
        else
            echo -e "${GREEN}[成功] 所有 Mihomo 内核进程已终止${NC}"
            echo -e "${YELLOW}[提示] 请在 ClashMac GUI 中手动重启核心以应用更新${NC}"
        fi
    else
        echo -e "${YELLOW}[提示] Mihomo 内核进程当前未运行${NC}"
    fi
}

# 重启ClashMac应用
restart_clashmac() {
    echo -e "\n${CYAN}[操作] 正在重启 ClashMac 应用...${NC}"

    # 检查ClashMac是否正在运行
    if pgrep -f "ClashMac" > /dev/null; then
        echo -e "${YELLOW}[提示] 正在关闭 ClashMac 应用...${NC}"
        # 关闭ClashMac
        osascript -e 'quit app "ClashMac"' > /dev/null 2>&1

        # 等待应用完全关闭，最多等待10秒
        local wait_time=0
        while pgrep -f "ClashMac" > /dev/null && [ $wait_time -lt 10 ]; do
            sleep 1
            wait_time=$((wait_time + 1))
        done

        if pgrep -f "ClashMac" > /dev/null; then
            echo -e "${RED}[错误] ClashMac 应用未能正常关闭${NC}"
            echo -e "${YELLOW}[提示] 尝试强制关闭...${NC}"
            # 尝试使用更强制的方式关闭
            if request_sudo && sudo kill $(pgrep -f "ClashMac") 2>/dev/null; then
                echo -e "${GREEN}[成功] ClashMac 应用已强制关闭${NC}"
                sleep 2
            else
                echo -e "${RED}[错误] 无法关闭 ClashMac 应用${NC}"
                return 1
            fi
        else
            echo -e "${GREEN}[成功] ClashMac 应用已关闭${NC}"
        fi
    fi

    # 重新启动ClashMac
    echo -e "${YELLOW}[提示] 正在启动 ClashMac 应用...${NC}"
    open -a "ClashMac" > /dev/null 2>&1

    # 等待并验证应用是否启动成功
    sleep 3
    if pgrep -f "ClashMac" > /dev/null; then
        echo -e "${GREEN}[成功] ClashMac 应用已重启${NC}"
    else
        echo -e "${RED}[错误] 启动 ClashMac 应用失败${NC}"
        echo -e "${YELLOW}[提示] 请手动启动 ClashMac 应用${NC}"
        return 1
    fi
}

# ========================# 核心功能函数# ========================

# 列出备份核心
list_backups() {
    echo -e "列出可用备份核心${NC}\n"

    cd "$CLASHMAC_CORE_DIR" || { echo -e "${RED}[错误] 进入核心目录失败${NC}"; return 1; }

    BACKUP_FILES=$(ls -1 mihomo.backup.* 2>/dev/null)
    if [ -z "$BACKUP_FILES" ]; then
        echo "  无备份文件"
        return
    fi

    i=1
    echo "$BACKUP_FILES" | while read -r f; do
        # 提取时间戳
        TS=$(echo "$f" | sed -E 's/^mihomo\.backup\.mihomo-darwin-(amd64|arm64)-.+\.([0-9]{8}_[0-9]{6})$/\2/')
        echo "$TS $f"
    done | sort -r | while read -r TS f; do
        # 提取版本号
        VERSION_CLEAN=$(echo "$f" | sed -E 's/^mihomo\.backup\.(mihomo-darwin-(amd64|arm64)-.+)\.[0-9]{8}_[0-9]{6}$/\1/')
        printf "%2d) ${BLUE}%s -> ${RED}%s${NC} -> ${YELLOW}%s${NC}\n" "$i" "$f" "$VERSION_CLEAN" "$TS"
        echo "$NC"
        i=$((i+1))
    done

    echo -e "${GREEN}[完成] 列出备份完成${NC}"
}

# 当前核心状态
show_status() {
    echo -e "${BLUE}获取当前核心状态${NC}"

    cd "$CLASHMAC_CORE_DIR" || { echo -e "${RED}[错误] 进入核心目录失败${NC}"; return 1; }

    if [ -f "$ACTIVE_CORE" ]; then
        if [ -x "$ACTIVE_CORE" ]; then
            CURRENT_RAW=$("./$ACTIVE_CORE" -v 2>/dev/null | head -n1)
            if [[ "$CURRENT_RAW" =~ ^Mihomo[[:space:]]+Meta[[:space:]]+([^[:space:]]+)[[:space:]]+darwin[[:space:]]+(amd64|arm64) ]]; then
                CURRENT_VER="${BASH_REMATCH[1]}"
                CURRENT_ARCH="${BASH_REMATCH[2]}"
                CURRENT_DISPLAY="mihomo-darwin-${CURRENT_ARCH}-${CURRENT_VER}"
            else
                CURRENT_DISPLAY="$ACTIVE_CORE (无法解析)"
            fi
            echo -e "[信息] $ACTIVE_CORE -> 当前核心版本信息: $CURRENT_RAW -> ${RED}$CURRENT_DISPLAY${NC}"
        else
            CURRENT_DISPLAY="$ACTIVE_CORE (不可执行)"
        fi
    else
        echo "当前核心文件不存在"
    fi

    echo -e "${BLUE}获取最新备份信息${NC}"
    LATEST=$(ls -1t mihomo.backup.* 2>/dev/null | head -n1)
    if [ -n "$LATEST" ]; then
        if [[ "$LATEST" =~ ^(mihomo\.backup\.(mihomo-darwin-(amd64|arm64)-.+))\.([0-9]{8}_[0-9]{6})$ ]]; then
            BACKUP_VER="${BASH_REMATCH[2]}"
            BACKUP_TIMESTAMP="${BASH_REMATCH[4]}"
            echo -e "[信息] 最新备份文件: $LATEST -> ${RED}$BACKUP_VER -> ${YELLOW}$BACKUP_TIMESTAMP${NC}"
        else
            BACKUP_VER="未知版本"
            BACKUP_TIMESTAMP=""
        fi
    else
        echo -e "${YELLOW}未找到任何备份${NC}"
    fi
}

# 切换核心
switch_core() {
    cd "$CLASHMAC_CORE_DIR" || { echo -e "${RED}[错误] 进入核心目录失败${NC}"; return 1; }

    echo -e "${BLUE}可用备份核心:${NC}"
    list_backups

    echo -e "${BLUE}请输入要切换的备份索引或版本号/时间戳: ${NC}"
    read -p "选择: " CHOICE

    if [ -z "$CHOICE" ]; then
        echo -e "${RED}[错误] 选择不能为空${NC}"
        return 1
    fi

    # 处理索引选择
    if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
        # 获取所有备份并排序
        BACKUP_FILES=($(ls -1t mihomo.backup.* 2>/dev/null | sort -r))
        INDEX=$((CHOICE-1))

        if [ $INDEX -ge 0 ] && [ $INDEX -lt ${#BACKUP_FILES[@]} ]; then
            TARGET_BACKUP=${BACKUP_FILES[$INDEX]}
        else
            echo -e "${RED}[错误] 无效的索引${NC}"
            return 1
        fi
    else
        # 处理版本号或时间戳
        if [[ "$CHOICE" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
            echo "按时间戳查找备份..."
            TARGET_BACKUP=$(ls -1 "$CLASHMAC_CORE_DIR"/mihomo.backup.* 2>/dev/null | grep "\.$CHOICE$")
        elif [[ "$CHOICE" =~ ^mihomo-darwin-(amd64|arm64)-.+$ ]]; then
            echo "按版本号查找备份..."
            TARGET_BACKUP=$(ls -1 "$CLASHMAC_CORE_DIR"/mihomo.backup.* 2>/dev/null | grep "$CHOICE")
        else
            echo -e "${RED}[错误] 只支持索引、版本号或时间戳格式${NC}"
            return 1
        fi
    fi

    # 验证备份文件存在且大小合理
    if [ ! -f "$TARGET_BACKUP" ] || [ ! -s "$TARGET_BACKUP" ]; then
        echo -e "${RED}[错误] 未找到有效备份文件: $TARGET_BACKUP${NC}"
        return 1
    fi
    echo "[信息] 匹配到备份文件: $TARGET_BACKUP"

    # 临时备份当前核心
    if [ -f "$ACTIVE_CORE" ]; then
        TMP_ROLLBACK="${ACTIVE_CORE}.rollback.$(date +%Y%m%d_%H%M%S)"
        cp "$ACTIVE_CORE" "$TMP_ROLLBACK"
        echo "已备份当前核心 -> $TMP_ROLLBACK"
    fi

    # 替换核心
    TMP_CORE="${ACTIVE_CORE}.tmp"
    cp "$TARGET_BACKUP" "$TMP_CORE" || { echo "[错误] 复制备份失败"; rm -f "$TMP_ROLLBACK"; return 1; }
    mv -f "$TMP_CORE" "$ACTIVE_CORE" || { echo "[错误] 替换核心失败"; cp "$TMP_ROLLBACK" "$ACTIVE_CORE"; return 1; }
    chmod +x "$ACTIVE_CORE"

    echo -e "${GREEN}[完成] 核心切换成功${NC}"
    echo "当前核心已替换为: $TARGET_BACKUP"

    # 删除临时回滚
    rm -f "$TMP_ROLLBACK"
    echo "已删除临时回滚: $TMP_ROLLBACK"

    echo -e "${YELLOW}请在 GUI 中重启内核以生效, 也可以使用菜单进行操作${NC}"
}

# 安装 / 更新核心
install_core() {
    VERSION_BRANCH="$1"

    cd "$CLASHMAC_CORE_DIR" || { echo -e "${RED}[错误] 进入核心目录失败${NC}"; return 1; }

    # ---------- 1. 选择 GitHub 用户 ----------
    if [ -n "$VERSION_BRANCH" ]; then
        GITHUB_USER="MetaCubeX"
        echo -e "${BLUE}[信息] 已指定版本:${NC} $VERSION_BRANCH"
    else
        echo -e "${BLUE}选择 GitHub 用户下载核心: ${NC}"
        for i in "${!GITHUB_USERS[@]}"; do
            if [ "${GITHUB_USERS[$i]}" = "vernesong" ]; then
                echo "  $((i+1))) ${GITHUB_USERS[$i]} - Smart版本"
            elif [ "${GITHUB_USERS[$i]}" = "MetaCubeX" ]; then
                echo "  $((i+1))) ${GITHUB_USERS[$i]} - 官方原版"
            else
                echo "  $((i+1))) ${GITHUB_USERS[$i]}"
            fi
        done
        read -p "请选择用户（默认1）: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#GITHUB_USERS[@]}" ]; then
            GITHUB_USER="${GITHUB_USERS[$((CHOICE-1))]}"
        else
            GITHUB_USER="${GITHUB_USERS[0]}"
        fi
        echo "[信息] 选择 GitHub 用户: $GITHUB_USER"

        # 如果是 MetaCubeX 并且没有指定版本，询问要使用稳定版本还是测试版本
        if [ "$GITHUB_USER" = "MetaCubeX" ] && [ -z "$VERSION_BRANCH" ]; then
            echo
            echo -e "${BLUE}选择 MetaCubeX 版本类型: ${NC}"
            echo "  1) 测试版本 (Prerelease-Alpha) - 默认"
            echo "  2) 稳定版本 (Tags)"
            read -p "请选择版本类型（默认1）: " VERSION_TYPE_CHOICE
            echo

            if [[ "$VERSION_TYPE_CHOICE" == "2" ]]; then
                echo -e "${YELLOW}[提示] 请访问 https://github.com/MetaCubeX/mihomo/tags 查看可用的稳定版本${NC}"
                read -p "请输入要安装的稳定版本号 (例如: v1.19.19): " STABLE_VERSION
                if [ -n "$STABLE_VERSION" ]; then
                    VERSION_BRANCH="$STABLE_VERSION"
                    echo -e "${BLUE}[信息] 已选择稳定版本:${NC} $STABLE_VERSION"
                else
                    echo -e "${YELLOW}[警告] 未输入版本号，使用默认测试版本${NC}"
                    VERSION_BRANCH="$DEFAULT_BRANCH"
                fi
            else
                VERSION_BRANCH="$DEFAULT_BRANCH"
                echo -e "${BLUE}[信息] 使用测试版本:${NC} $VERSION_BRANCH"
            fi
        else
            VERSION_BRANCH="$DEFAULT_BRANCH"
        fi
    fi

    # ---------- 2. 获取版本信息 ----------
    VERSION_URL="https://github.com/${GITHUB_USER}/mihomo/releases/download/$VERSION_BRANCH/version.txt"
    echo "[信息] 版本分支: $VERSION_BRANCH, GITHUB_USER: $GITHUB_USER, VERSION_URL: $VERSION_URL"
    BASE_DOWNLOAD_URL="https://github.com/${GITHUB_USER}/mihomo/releases/download/$VERSION_BRANCH"
    echo "获取最新版本信息..."
    VERSION_INFO=$(curl -fsL "$VERSION_URL")
    if [ -z "$VERSION_INFO" ] || echo "$VERSION_INFO" | grep -iq "Not Found"; then
        echo -e "${RED}[错误] 无法获取版本信息或版本不存在${NC}"
        return 1
    fi
    echo "[信息] 版本信息: $VERSION_INFO"

    if [ "$VERSION_BRANCH" = "Prerelease-Alpha" ]; then
        VERSION_HASH=$(echo "$VERSION_INFO" | grep -oE 'alpha(-smart)?-[0-9a-f]+' | head -1)
    else
        VERSION_HASH=$(echo "$VERSION_INFO" | head -1)
    fi
    echo "[信息] 解析版本号: $VERSION_HASH"

    # ---------- 3. 架构检测 ----------
    ARCH_RAW="$(uname -m)"
    case "$ARCH_RAW" in
        arm64)  MIHOMO_ARCH="arm64" ;;
        x86_64) MIHOMO_ARCH="amd64" ;;
        *)
            echo -e "${RED}[错误] 不支持的架构: $ARCH_RAW${NC}"
            return 1
            ;;
    esac
    echo "[信息] 架构检测: $MIHOMO_ARCH"

    # ---------- 4. 构造下载 URL ----------
    VERSION="mihomo-darwin-${MIHOMO_ARCH}-${VERSION_HASH}"
    echo "[信息] 下载版本: $VERSION"
    DOWNLOAD_URL="${BASE_DOWNLOAD_URL}/${VERSION}.gz"
    echo "[信息] 下载链接: $DOWNLOAD_URL"

    # ---------- 5. 下载并写入核心 ----------
    echo "下载并解压核心到 $ACTIVE_CORE ..."
    for i in {1..3}; do
        curl -fL "$DOWNLOAD_URL" | gunzip > "$ACTIVE_CORE" && break
        echo "下载失败，重试第 $i 次..."
        sleep 2
    done
    [ ! -f "$ACTIVE_CORE" ] && { echo -e "${RED}[错误] 下载或解压失败${NC}"; return 1; }
    chmod +x "$ACTIVE_CORE"
    echo -e "${GREEN}[信息] 当前核心已写入 -> $(basename "$ACTIVE_CORE")${NC}"

    # ---------- 6. 生成备份（首次安装也备份） ----------
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$CLASHMAC_CORE_DIR/mihomo.backup.${VERSION}.${TIMESTAMP}"
    cp -f "$ACTIVE_CORE" "$BACKUP_FILE"
    chmod +x "$BACKUP_FILE"
    echo "生成备份文件 -> $(basename "$BACKUP_FILE")"

    echo -e "${GREEN}[完成] 安装完成: $VERSION${NC}"

    echo -e "${YELLOW}请在 GUI 中重启内核以生效, 也可以使用菜单进行操作${NC}"
}

# 检查 ClashMac + mihomo 内核状态
health_check_core() {
    echo -e "${GREEN}========== 健康检查开始 ==========${NC}"
    # 0. ClashMac App 检查
    echo -e "${BLUE}========== ClashMac 安装检查 ==========${NC}"
    if [ ! -d "$CLASHMAC_DIR" ]; then
        echo -e "${RED}[错误] 未找到 ClashMac 应用目录:${NC}"
        echo "  $CLASHMAC_DIR"
        echo -e "${YELLOW}[提示] 请先安装 ClashMac 应用后再运行此脚本${NC}"
        return 1
    fi
    echo -e "${GREEN}[成功] ClashMac 应用已安装: $CLASHMAC_DIR${NC}"

    # 1. Core 目录检查
    echo -e "${BLUE}========== ClashMac 核心目录检查 ==========${NC}"

    if [ ! -d "$CLASHMAC_CORE_DIR" ]; then
        echo -e "${RED}[错误] 未找到 ClashMac Core 目录:${NC}"
        echo "  $CLASHMAC_CORE_DIR"
        return 1
    fi
    cd "$CLASHMAC_CORE_DIR" || { echo -e "${RED}[错误] 进入核心目录失败${NC}"; return 1; }
    echo -e "${GREEN}[成功] 当前目录: $CLASHMAC_CORE_DIR${NC}"

    echo -e "${BLUE}========== ClashMac 内核健康检查 ==========${NC}"

    # 2. 核心文件是否存在
    if [ ! -f "$ACTIVE_CORE" ]; then
        echo -e "${RED}[×] 未找到 mihomo 核心文件${NC}"
        echo "    预期路径: $CLASHMAC_CORE_DIR/$ACTIVE_CORE"
        return 1
    fi
    echo -e "${GREEN}[✓] 核心文件存在${NC}"

    # 3. 是否可执行
    if [ ! -x "$ACTIVE_CORE" ]; then
        echo -e "${RED}[×] mihomo 不可执行${NC}"
        echo "    建议执行: chmod +x $CLASHMAC_CORE_DIR/$ACTIVE_CORE"
        return 1
    fi
    echo -e "${GREEN}[✓] 可执行权限正常${NC}"

    # 4. 架构检查（macOS 专用）
    ARCH_RAW="$(uname -m)"
    FILE_INFO="$(file "$ACTIVE_CORE")"

    if [[ "$ARCH_RAW" == "arm64" && "$FILE_INFO" != *"arm64"* ]]; then
        echo -e "${RED}[×] 架构不匹配${NC}"
        echo "    系统架构: arm64"
        echo "    核心信息: $FILE_INFO"
        return 1
    fi

    if [[ "$ARCH_RAW" == "x86_64" && "$FILE_INFO" != *"x86_64"* && "$FILE_INFO" != *"amd64"* ]]; then
        echo -e "${RED}[×] 架构不匹配${NC}"
        echo "    系统架构: x86_64"
        echo "    核心信息: $FILE_INFO"
        return 1
    fi

    echo -e "${GREEN}[✓] 架构匹配 ($ARCH_RAW)${NC}"

    # 5. 版本信息可读性（不启动服务）
    VERSION_INFO=$("./$ACTIVE_CORE" -v 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}[×] 无法读取版本信息${NC}"
        echo "    该核心可能已损坏"
        return 1
    fi

    echo -e "${GREEN}[✓] 版本信息可读取 ${NC}"

    # 6. Core 目录写权限（ClashMac 切换/更新必需）
    if [ ! -w "$CLASHMAC_CORE_DIR" ]; then
        echo -e "${RED}[×] core 目录无写权限${NC}"
        echo "    ClashMac 可能无法更新或切换内核"
        return 1
    fi
    echo -e "${GREEN}[✓] core 目录写权限正常${NC}"

    echo -e "${GREEN}========== 健康检查通过 ==========${NC}"

    echo ""
}

# ========================# 菜单和交互函数# ========================

# 显示主菜单
show_menu() {
    clear
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN} ClashMac mihomo 内核交互式管理工具${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo "-------------------------------------"

    # Mihomo 状态
    MIHOMO_STATUS=$(check_mihomo_status)
    if [ "$MIHOMO_STATUS" = "已运行" ]; then
        echo -e "Mihomo Status：${GREEN}$MIHOMO_STATUS${NC}"
    else
        echo -e "Mihomo Status：${RED}$MIHOMO_STATUS${NC}"
    fi

    # Mihomo 版本
    MIHOMO_VERSION=$(get_mihomo_version)
    echo -e "Mihomo Kernel：${GREEN}$MIHOMO_VERSION${NC}"

    echo ""
    echo -e "1. ${GREEN}安装/更新 Mihomo 核心${NC}"
    echo -e "2. ${GREEN}切换核心版本${NC}"
    echo -e "3. ${GREEN}列出所有备份核心${NC}"
    echo -e "4. ${GREEN}查看当前核心状态${NC}"
    echo -e "5. ${GREEN}运行健康检查${NC}"
    echo -e "6. ${RED}杀掉 Mihomo 内核进程${NC}"
    echo -e "7. ${RED}重启 ClashMac 应用${NC}"
    echo -e "0. ${GREEN}退出脚本${NC}"
    echo ""
    echo "-------------------------------------"
}

# 主程序
main() {
    # 首先运行健康检查
    health_check_core || {
        echo -e "${RED}[错误] 健康检查失败，可能无法正常使用所有功能${NC}"
        read -p "按回车键继续..."
    }

    # 主循环
    while true; do
        show_menu
        read -p "请选择操作 (0-7): " CHOICE

        case "$CHOICE" in
            1)
                echo -e "${BLUE}开始安装/更新 Mihomo 核心...${NC}"
                install_core
                read -p "按回车键继续..."
                ;;
            2)
                echo -e "${BLUE}开始切换核心版本...${NC}"
                switch_core
                read -p "按回车键继续..."
                ;;
            3)
                echo -e "${BLUE}列出所有备份核心...${NC}"
                list_backups
                read -p "按回车键继续..."
                ;;
            4)
                echo -e "${BLUE}查看当前核心状态...${NC}"
                show_status
                read -p "按回车键继续..."
                ;;
            5)
                echo -e "${BLUE}运行健康检查...${NC}"
                health_check_core
                read -p "按回车键继续..."
                ;;
            6)
                echo -e "${BLUE}杀掉 Mihomo 内核进程中 ...${NC}"
                kill_mihomo_kernel
                read -p "按回车键继续..."
                ;;
            7)
                echo -e "${BLUE}重启应用中 ...${NC}"
                restart_clashmac
                read -p "按回车键继续..."
                ;;
            0)
                echo -e "${GREEN}[信息] 退出脚本${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[错误] 无效的选择，请重新输入${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 启动主程序
main