#!/usr/bin/env bash

###############################################################################
# ClashMac Mihomo Kernel Manager
#
# 项目概述：
#   一个功能全面的 ClashMac mihomo 内核交互式管理工具
#   提供直观的菜单界面，简化内核的安装、更新、切换和维护操作
#   与 ClashMac GUI 完全分离，专注于内核管理职责
#
# 作者信息：
#   Author: Kuochiang Lu
#   Version: v1.2.0
#   Last Updated: 2026-02-02
#
# 核心功能：
#   ✅ 内核安装与更新：支持从多个 GitHub 源（如 MetaCubeX、vernesong）下载安装
#   ✅ 内核版本切换：在已备份的多个内核版本之间无缝切换
#   ✅ 备份管理：列出所有已备份的内核版本，便于查看和选择
#   ✅ 状态监控：显示当前使用的内核版本及系统运行状态
#   ✅ 健康检查：验证内核完整性和运行状况
#   ✅ 进程管理：提供杀掉 mihomo 内核进程的功能
#   ✅ 应用控制：支持重启 ClashMac 应用以应用更改
#   ✅ 交互界面：提供直观易用的菜单式交互界面
#
# 系统依赖：
#   - bash 4.0+      # 脚本运行环境
#   - curl           # 用于从 GitHub 下载内核文件
#   - tar            # 用于解压内核包
#   - grep/awk/sed   # 用于文本处理
#   - ps/kill        # 用于进程管理
#   - uname          # 用于系统信息检测
#
# 使用方式：
#   1. 赋予脚本执行权限：chmod +x clashmac_mihomo-kernel_manager.sh
#   2. 直接运行脚本：./clashmac_mihomo-kernel_manager.sh
#   3. 在交互菜单中选择所需功能（输入对应数字并按回车）
#
# 设计特点：
#   - 模块化设计，便于维护和扩展
#   - 完善的错误处理机制
#   - 清晰的用户反馈信息
#   - 与 ClashMac 应用完美集成
#   - 支持多种系统架构（arm64/amd64）
#
# 注意事项：
#   - 首次使用前请确保 ClashMac 应用已正确安装
#   - 部分操作可能需要管理员权限
#   - 切换内核版本后建议重启 ClashMac 应用
#   - 定期运行健康检查以确保内核正常工作
###############################################################################

# 脚本名称
SCRIPT_NAME="ClashMac Mihomo Kernel Manager"
# 脚本版本号
SCRIPT_VERSION="v1.2.0"

# ========================# 配置路径和默认变量# ========================
CLASHMAC_DIR="/Applications/ClashMac.app"
CLASHMAC_CORE_DIR="$HOME/Library/Application Support/clashmac/core"
ACTIVE_CORE="mihomo"   # 默认核心文件名

GITHUB_USERS=("MetaCubeX" "vernesong")  # 可选 GitHub 用户
DEFAULT_BRANCH="Prerelease-Alpha"       # 默认分支

# 颜色定义 - ANSI 转义序列
# 格式: 颜色名称='\033[样式;颜色代码m'
# 样式: 0=默认, 1=粗体, 2=淡色, 4=下划线, 5=闪烁
# 颜色代码: 30=黑, 31=红, 32=绿, 33=黄, 34=蓝, 35=紫, 36=青, 37=白

# 基础颜色
RED='\033[0;31m'      # 红色 - 用于错误和警告
GREEN='\033[0;32m'    # 绿色 - 用于成功和确认
YELLOW='\033[1;33m'   # 黄色 - 用于提示和信息
BLUE='\033[0;34m'     # 蓝色 - 用于标题和说明
CYAN='\033[0;36m'     # 青色 - 用于操作和步骤
PURPLE='\033[0;35m'   # 紫色 - 用于特殊信息
WHITE='\033[0;37m'     # 白色 - 用于强调文本

# 颜色重置
NC='\033[0m'          # Normal Color - 重置所有颜色设置

# ========================# 权限管理函数# ========================

# 请求管理员权限
request_sudo() {
    if ! sudo -n true 2>/dev/null; then
        echo -e "${PURPLE}[授权请求] 操作需要管理员权限，请输入密码${NC}"
        sudo -v
        if [ $? -ne 0 ]; then
            echo_error "授权失败，无法执行需要权限的操作"
            return 1
        fi
        # 保持sudo权限
        sudo -v -s <<EOF
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
EOF
        echo_success "权限已获取"
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
            echo "${RED}无法解析版本信息${NC}"
        fi
    else
        echo "${RED}未安装${NC}"
    fi
}

# 终止Mihomo内核进程
kill_mihomo_kernel() {
    show_empty_line 1
    echo_operation "正在终止 Mihomo 内核进程..."

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
            echo_tip "需要管理员权限来终止某些进程"
            if ! request_sudo; then
                echo_error "授权失败，无法继续终止进程"
                return 1
            fi
        fi

        # 使用适当的权限终止进程
        local termination_success=true
        for pid in $pids; do
            echo_tip "尝试终止进程 ID: $pid"
            if $need_sudo; then
                if sudo kill "$pid" 2>/dev/null; then
                    echo_success "使用 sudo 终止进程 $pid"
                else
                    echo_error "即使使用 sudo 也无法终止进程 $pid"
                    termination_success=false
                fi
            else
                if kill "$pid" 2>/dev/null; then
                    echo_success "进程 $pid 已终止"
                else
                    echo_error "终止进程 $pid 失败"
                    termination_success=false
                fi
            fi
        done

        # 等待并验证进程是否已终止
        sleep 1
        if pgrep -f "$ACTIVE_CORE" >/dev/null; then
            echo_error "仍有 Mihomo 内核进程在运行"
            echo_tip "请尝试在 ClashMac GUI 中手动停止核心"
        else
            echo_success "所有 Mihomo 内核进程已终止"
            echo_tip "请在 ClashMac GUI 中手动重启核心以应用更新"
        fi
    else
        echo_tip "Mihomo 内核进程当前未运行"
    fi
}

# 重启ClashMac应用
restart_clashmac() {
    show_empty_line 1
    echo_operation "正在重启 ClashMac 应用..."

    # 检查ClashMac是否正在运行
    if pgrep -f "ClashMac" > /dev/null; then
        echo_tip "正在关闭 ClashMac 应用..."
        # 关闭ClashMac
        osascript -e 'quit app "ClashMac"' > /dev/null 2>&1

        # 等待应用完全关闭，最多等待10秒
        local wait_time=0
        while pgrep -f "ClashMac" > /dev/null && [ $wait_time -lt 10 ]; do
            sleep 1
            wait_time=$((wait_time + 1))
        done

        if pgrep -f "ClashMac" > /dev/null; then
            echo_error "ClashMac 应用未能正常关闭"
            echo_tip "尝试强制关闭..."
            # 尝试使用更强制的方式关闭
            if request_sudo && sudo kill $(pgrep -f "ClashMac") 2>/dev/null; then
                echo_success "ClashMac 应用已强制关闭"
                sleep 2
            else
                echo_error "无法关闭 ClashMac 应用"
                return 1
            fi
        else
            echo_success "ClashMac 应用已关闭"
        fi
    fi

    # 重新启动ClashMac
    echo_tip "正在启动 ClashMac 应用..."
    open -a "ClashMac" > /dev/null 2>&1

    # 等待并验证应用是否启动成功
    sleep 3
    if pgrep -f "ClashMac" > /dev/null; then
        echo_success "ClashMac 应用已重启"
    else
        echo_error "启动 ClashMac 应用失败"
        echo_tip "请手动启动 ClashMac 应用"
        return 1
    fi
}

# ========================# 核心功能函数# ========================

# 列出备份核心
list_backups() {
    echo_info "列出可用备份核心"
    show_empty_line 1

    cd "$CLASHMAC_CORE_DIR" || { echo_error "进入核心目录失败"; return 1; }

    BACKUP_FILES=$(ls -1 mihomo.backup.* 2>/dev/null)
    if [ -z "$BACKUP_FILES" ]; then
        echo_info "  无备份文件"
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
        show_empty_line 1
        i=$((i+1))
    done

    echo_complete "列出备份完成"
}

# 当前核心状态
show_status() {
    echo_info "获取当前核心状态"
    show_empty_line 1

    cd "$CLASHMAC_CORE_DIR" || { echo_error "进入核心目录失败"; return 1; }

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
            echo_info "$ACTIVE_CORE -> 当前核心版本信息: $CURRENT_RAW -> ${RED}$CURRENT_DISPLAY${NC}"
        else
            CURRENT_DISPLAY="$ACTIVE_CORE (不可执行)"
            echo_info "$ACTIVE_CORE -> 当前核心版本信息: ${RED}$CURRENT_DISPLAY${NC}"
        fi
    else
        echo_error "当前核心文件不存在"
    fi

    show_empty_line 1
    echo_info "获取最新备份信息"
    LATEST=$(ls -1t mihomo.backup.* 2>/dev/null | head -n1)
    if [ -n "$LATEST" ]; then
        if [[ "$LATEST" =~ ^(mihomo\.backup\.(mihomo-darwin-(amd64|arm64)-.+))\.([0-9]{8}_[0-9]{6})$ ]]; then
            BACKUP_VER="${BASH_REMATCH[2]}"
            BACKUP_TIMESTAMP="${BASH_REMATCH[4]}"
            echo_info "最新备份文件: $LATEST -> ${RED}$BACKUP_VER -> ${YELLOW}$BACKUP_TIMESTAMP${NC}"
        else
            BACKUP_VER="未知版本"
            BACKUP_TIMESTAMP=""
            echo_info "最新备份文件: $LATEST -> ${RED}$BACKUP_VER${NC}"
        fi
    else
        echo_warning "未找到任何备份"
    fi
}

# 切换核心
switch_core() {
    cd "$CLASHMAC_CORE_DIR" || { echo_error "进入核心目录失败"; return 1; }

    echo_info "可用备份核心:"
    list_backups

    show_empty_line 1
    echo_info "请输入要切换的备份索引或版本号/时间戳: "
    read -p "选择: " CHOICE

    if [ -z "$CHOICE" ]; then
        echo_error "选择不能为空"
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
            echo_error "无效的索引"
            return 1
        fi
    else
        # 处理版本号或时间戳
        if [[ "$CHOICE" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
            echo_info "按时间戳查找备份..."
            TARGET_BACKUP=$(ls -1 "$CLASHMAC_CORE_DIR"/mihomo.backup.* 2>/dev/null | grep "\.$CHOICE$")
        elif [[ "$CHOICE" =~ ^mihomo-darwin-(amd64|arm64)-.+$ ]]; then
            echo_info "按版本号查找备份..."
            TARGET_BACKUP=$(ls -1 "$CLASHMAC_CORE_DIR"/mihomo.backup.* 2>/dev/null | grep "$CHOICE")
        else
            echo_error "只支持索引、版本号或时间戳格式"
            return 1
        fi
    fi

    # 验证备份文件存在且大小合理
    if [ ! -f "$TARGET_BACKUP" ] || [ ! -s "$TARGET_BACKUP" ]; then
        echo_error "未找到有效备份文件: $TARGET_BACKUP"
        return 1
    fi
    echo_info "匹配到备份文件: $TARGET_BACKUP"

    # 临时备份当前核心
    if [ -f "$ACTIVE_CORE" ]; then
        TMP_ROLLBACK="${ACTIVE_CORE}.rollback.$(date +%Y%m%d_%H%M%S)"
        cp "$ACTIVE_CORE" "$TMP_ROLLBACK"
        echo_info "已备份当前核心 -> $TMP_ROLLBACK"
    fi

    # 替换核心
    TMP_CORE="${ACTIVE_CORE}.tmp"
    cp "$TARGET_BACKUP" "$TMP_CORE" || { echo_error "复制备份失败"; rm -f "$TMP_ROLLBACK"; return 1; }
    mv -f "$TMP_CORE" "$ACTIVE_CORE" || { echo_error "替换核心失败"; cp "$TMP_ROLLBACK" "$ACTIVE_CORE"; return 1; }
    chmod +x "$ACTIVE_CORE"

    echo_complete "核心切换成功"
    echo_info "当前核心已替换为: $TARGET_BACKUP"

    # 删除临时回滚
    rm -f "$TMP_ROLLBACK"
    echo_info "已删除临时回滚: $TMP_ROLLBACK"

    echo_tip "请在 GUI 中重启内核以生效, 也可以使用菜单进行操作"
}

# 安装 / 更新核心
install_core() {
    VERSION_BRANCH="$1"

    cd "$CLASHMAC_CORE_DIR" || { echo_error "进入核心目录失败"; return 1; }

    # 检测当前 mihomo 安装目录
    DETECTED_DIR=$(find $CLASHMAC_DIR -name "mihomo*" -print0 2>/dev/null | xargs -0 dirname | sort -u)

    if [ -n "$DETECTED_DIR" ]; then
        show_empty_line 1
        echo -e "${BLUE}[信息] 检测到当前 mihomo 安装目录:${NC} $DETECTED_DIR"
        echo -e "${BLUE}[信息] 默认安装目录:${NC} $CLASHMAC_CORE_DIR"

        while true; do
            read -p "是否安装到检测到的目录？(y/n，默认n): " INSTALL_TO_DETECTED
            INSTALL_TO_DETECTED=${INSTALL_TO_DETECTED:-n}

            if [[ "$INSTALL_TO_DETECTED" =~ ^[Yy]$ ]]; then
                CLASHMAC_CORE_DIR="$DETECTED_DIR"
                echo -e "${GREEN}[完成] 已选择安装目录: ${CLASHMAC_CORE_DIR}${NC}"
                break
            elif [[ "$INSTALL_TO_DETECTED" =~ ^[Nn]$ ]]; then
                echo -e "${GREEN}[完成] 已选择默认安装目录: ${CLASHMAC_CORE_DIR}${NC}"
                break
            else
                echo -e "${RED}[错误] 请输入 y 或 n${NC}"
            fi
        done
    else
        echo -e "${YELLOW}[提示] 未检测到当前 mihomo 安装目录${NC}"
        echo -e "${BLUE}[信息] 将使用默认安装目录: ${CLASHMAC_CORE_DIR}${NC}"
    fi

    # ---------- 1. 选择 GitHub 用户 ----------
    if [ -n "$VERSION_BRANCH" ]; then
        GITHUB_USER="MetaCubeX"
        echo_info "已指定版本: $VERSION_BRANCH"
    else
        echo_info "选择 GitHub 用户下载核心: "
        for i in "${!GITHUB_USERS[@]}"; do
            if [ "${GITHUB_USERS[$i]}" = "vernesong" ]; then
                echo_info "  $((i+1))) ${GITHUB_USERS[$i]} - Smart版本"
            elif [ "${GITHUB_USERS[$i]}" = "MetaCubeX" ]; then
                echo_info "  $((i+1))) ${GITHUB_USERS[$i]} - 官方原版"
            else
                echo_info "  $((i+1))) ${GITHUB_USERS[$i]}"
            fi
        done
        read -p "请选择用户（默认1）: " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#GITHUB_USERS[@]}" ]; then
            GITHUB_USER="${GITHUB_USERS[$((CHOICE-1))]}"
        else
            GITHUB_USER="${GITHUB_USERS[0]}"
        fi
        echo_info "选择 GitHub 用户: $GITHUB_USER"

        # 如果是 MetaCubeX 并且没有指定版本，询问要使用稳定版本还是测试版本
        if [ "$GITHUB_USER" = "MetaCubeX" ] && [ -z "$VERSION_BRANCH" ]; then
            show_empty_line 1
            echo_info "选择 MetaCubeX 版本类型: "
            echo_info "  1) 测试版本 (Prerelease-Alpha) - 默认"
            echo_info "  2) 稳定版本 (Tags)"
            read -p "请选择版本类型（默认1）: " VERSION_TYPE_CHOICE
            show_empty_line 1

            if [[ "$VERSION_TYPE_CHOICE" == "2" ]]; then
                echo_tip "请访问 https://github.com/MetaCubeX/mihomo/tags 查看可用的稳定版本"
                read -p "请输入要安装的稳定版本号 (例如: v1.19.19): " STABLE_VERSION
                if [ -n "$STABLE_VERSION" ]; then
                    VERSION_BRANCH="$STABLE_VERSION"
                    echo_info "已选择稳定版本: $STABLE_VERSION"
                else
                    echo_warning "未输入版本号，使用默认测试版本"
                    VERSION_BRANCH="$DEFAULT_BRANCH"
                fi
            else
                VERSION_BRANCH="$DEFAULT_BRANCH"
                echo_info "使用测试版本: $VERSION_BRANCH"
            fi
        else
            VERSION_BRANCH="$DEFAULT_BRANCH"
        fi
    fi

    # ---------- 2. 获取版本信息 ----------
    VERSION_URL="https://github.com/${GITHUB_USER}/mihomo/releases/download/$VERSION_BRANCH/version.txt"
    echo_info "版本分支: $VERSION_BRANCH, GITHUB_USER: $GITHUB_USER, VERSION_URL: $VERSION_URL"
    BASE_DOWNLOAD_URL="https://github.com/${GITHUB_USER}/mihomo/releases/download/$VERSION_BRANCH"
    echo_info "获取最新版本信息..."
    VERSION_INFO=$(curl -fsL "$VERSION_URL")
    if [ -z "$VERSION_INFO" ] || echo "$VERSION_INFO" | grep -iq "Not Found"; then
        echo_error "无法获取版本信息或版本不存在"
        return 1
    fi
    echo_info "版本信息: $VERSION_INFO"

    if [ "$VERSION_BRANCH" = "Prerelease-Alpha" ]; then
        VERSION_HASH=$(echo "$VERSION_INFO" | grep -oE 'alpha(-smart)?-[0-9a-f]+' | head -1)
    else
        VERSION_HASH=$(echo "$VERSION_INFO" | head -1)
    fi
    echo_info "解析版本号: $VERSION_HASH"

    # ---------- 3. 架构检测 ----------
    ARCH_RAW="$(uname -m)"
    case "$ARCH_RAW" in
        arm64)  MIHOMO_ARCH="arm64" ;;
        x86_64) MIHOMO_ARCH="amd64" ;;
        *)
            echo_error "不支持的架构: $ARCH_RAW"
            return 1
            ;;
    esac
    echo_info "架构检测: $MIHOMO_ARCH"

    # ---------- 4. 构造下载 URL ----------
    VERSION="mihomo-darwin-${MIHOMO_ARCH}-${VERSION_HASH}"
    echo_info "下载版本: $VERSION"
    DOWNLOAD_URL="${BASE_DOWNLOAD_URL}/${VERSION}.gz"
    echo_info "下载链接: $DOWNLOAD_URL"

    # ---------- 5. 下载并写入核心 ----------
    echo_info "下载并解压核心到 $ACTIVE_CORE ..."
    for i in {1..3}; do
        curl -fL "$DOWNLOAD_URL" | gunzip > "$ACTIVE_CORE" && break
        echo_info "下载失败，重试第 $i 次..."
        sleep 2
    done
    [ ! -f "$ACTIVE_CORE" ] && { echo_error "下载或解压失败"; return 1; }
    chmod +x "$ACTIVE_CORE"
    echo_info "当前核心已写入 -> $(basename "$ACTIVE_CORE")"

    # ---------- 6. 生成备份（首次安装也备份） ----------
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$CLASHMAC_CORE_DIR/mihomo.backup.${VERSION}.${TIMESTAMP}"
    cp -f "$ACTIVE_CORE" "$BACKUP_FILE"
    chmod +x "$BACKUP_FILE"
    echo_info "生成备份文件 -> $(basename "$BACKUP_FILE")"

    echo_complete "安装完成: $VERSION"
    echo_tip "请在 GUI 中重启内核以生效, 也可以使用菜单进行操作"
}

# 检查 ClashMac + mihomo 内核状态
health_check_core() {
    echo_success "========== 健康检查开始 =========="
    # 0. ClashMac App 检查
    if [ ! -d "$CLASHMAC_DIR" ]; then
        echo_error "未找到 ClashMac 应用目录: $CLASHMAC_DIR"
        echo_tip "请先安装 ClashMac 应用后再运行此脚本"
        return 1
    fi
    echo_success "ClashMac 应用已安装: $CLASHMAC_DIR"

    # 1. Core 目录检查
    if [ ! -d "$CLASHMAC_CORE_DIR" ]; then
        echo_error "未找到 ClashMac Core 目录:"
        echo_info "  $CLASHMAC_CORE_DIR"
        return 1
    fi
    cd "$CLASHMAC_CORE_DIR" || { echo_error "进入核心目录失败"; return 1; }
    echo_success "当前目录: $CLASHMAC_CORE_DIR"

    # 2. 核心文件是否存在
    if [ ! -f "$ACTIVE_CORE" ]; then
        echo_error "[×] 未找到 mihomo 核心文件"
        echo_info "    预期路径: $CLASHMAC_CORE_DIR/$ACTIVE_CORE"
        return 1
    fi
    echo_success "[✓] 核心文件存在"

    # 3. 是否可执行
    if [ ! -x "$ACTIVE_CORE" ]; then
        echo_error "[×] mihomo 不可执行"
        echo_info "    建议执行: chmod +x $CLASHMAC_CORE_DIR/$ACTIVE_CORE"
        return 1
    fi
    echo_success "[✓] 可执行权限正常"

    # 4. 架构检查（macOS 专用）
    ARCH_RAW="$(uname -m)"
    FILE_INFO="$(file "$ACTIVE_CORE")"

    if [[ "$ARCH_RAW" == "arm64" && "$FILE_INFO" != *"arm64"* ]]; then
        echo_error "[×] 架构不匹配"
        echo_info "    系统架构: arm64"
        echo_info "    核心信息: $FILE_INFO"
        return 1
    fi

    if [[ "$ARCH_RAW" == "x86_64" && "$FILE_INFO" != *"x86_64"* && "$FILE_INFO" != *"amd64"* ]]; then
        echo_error "[×] 架构不匹配"
        echo_info "    系统架构: x86_64"
        echo_info "    核心信息: $FILE_INFO"
        return 1
    fi

    echo_success "[✓] 架构匹配 ($ARCH_RAW)"

    # 5. 版本信息可读性（不启动服务）
    VERSION_INFO=$("./$ACTIVE_CORE" -v 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo_error "[×] 无法读取版本信息"
        echo_info "    该核心可能已损坏"
        return 1
    fi

    echo_success "[✓] 版本信息可读取"

    # 6. Core 目录写权限（ClashMac 切换/更新必需）
    if [ ! -w "$CLASHMAC_CORE_DIR" ]; then
        echo_error "[×] core 目录无写权限"
        echo_info "    ClashMac 可能无法更新或切换内核"
        return 1
    fi
    echo_success "[✓] core 目录写权限正常"

    echo_success "========== 健康检查通过 =========="
    show_empty_line 1
}


# ========================
# 输出空行
# ========================
show_empty_line() {
    local count=${1:-1}  # 默认输出1行空行，可通过参数指定数量
    for ((i=1; i<=count; i++)); do
        echo
    done
}

# 日志输出函数
echo_info() {
    echo -e "${BLUE}[信息] $1${NC}"
}

echo_success() {
    echo -e "${GREEN}[成功] $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}[警告] $1${NC}"
}

echo_error() {
    echo -e "${RED}[错误] $1${NC}"
}

echo_tip() {
    echo -e "${YELLOW}[提示] $1${NC}"
}

echo_complete() {
    echo -e "${GREEN}[完成] $1${NC}"
}

echo_operation() {
    echo -e "${CYAN}[操作] $1${NC}"
}

# ========================
# 显示标题信息
# ========================
show_title() {
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${CYAN}      ClashMac Mihomo Kernel 交互式管理工具    ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${BLUE}Version: ${WHITE}${SCRIPT_VERSION}${NC}            ${NC}"
    show_empty_line 1
}

# ========================# 菜单和交互函数# ========================

# 显示主菜单
show_menu() {
    clear
    show_title

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

    show_empty_line 1
    echo -e "1. ${GREEN}安装/更新 Mihomo 核心${NC}"
    echo -e "2. ${GREEN}切换核心版本${NC}"
    echo -e "3. ${GREEN}列出所有备份核心${NC}"
    echo -e "4. ${GREEN}查看当前核心状态${NC}"
    echo -e "5. ${GREEN}运行健康检查${NC}"
    echo -e "6. ${RED}杀掉 Mihomo 内核进程${NC}"
    echo -e "7. ${RED}重启 ClashMac 应用${NC}"
    echo -e "0. ${GREEN}退出脚本${NC}"
    show_empty_line 1
    echo "-------------------------------------"
}

# 主程序
main() {
    # 初始化标题
    show_title

    # 首先运行健康检查
    health_check_core || {
        echo_error "健康检查失败，当前无法正常使用所有功能"
        read -p "按回车键继续..."
        return 1
    }

    # 主循环
    while true; do
        show_menu
        read -p "请选择操作 (0-7): " CHOICE

        case "$CHOICE" in
            1)
                echo_info "开始安装/更新 Mihomo 核心..."
                install_core
                read -p "按回车键继续..."
                ;;
            2)
                echo_info "开始切换核心版本..."
                switch_core
                read -p "按回车键继续..."
                ;;
            3)
                echo_info "列出所有备份核心..."
                list_backups
                read -p "按回车键继续..."
                ;;
            4)
                echo_info "查看当前核心状态..."
                show_status
                read -p "按回车键继续..."
                ;;
            5)
                echo_info "运行健康检查..."
                health_check_core
                read -p "按回车键继续..."
                ;;
            6)
                echo_info "杀掉 Mihomo 内核进程中 ..."
                kill_mihomo_kernel
                read -p "按回车键继续..."
                ;;
            7)
                echo_info "重启应用中 ..."
                restart_clashmac
                read -p "按回车键继续..."
                ;;
            0)
                echo_info "退出脚本"
                exit 0
                ;;
            *)
                echo_error "无效的选择，请重新输入"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 启动主程序
main