#!/usr/bin/env bash

#
# clashmac_mihomo-kernel_helper
#
# Author: Kuochiang Lu
# Version: 1.0.0
# Last Updated: 2026-01-21
#
# 描述：
#   ClashMac mihomo Kernel Helper 是一个专注于 mihomo 内核下载、管理、切换 的命令行助手，
#   避免重复下载、支持按时间戳管理备份，并与 GUI 完全分离职责。
#
# 功能：
#   - 安装最新 mihomo 核心（支持多个 GitHub 源）
#   - 自动检测系统架构 (arm64 / amd64)
#   - 备份现有核心（不清理历史）
#   - 在备份之间切换
#   - 显示当前状态及智能核心检测
#
# 用法：
#   ./clashmac_mihomo_kernel_helper.sh help
#

SCRIPT_VERSION="v1.0.0"

# ========================
# 配置路径和默认变量
# ========================
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
NC='\033[0m'

# ========================
# 检查核心目录是否存在
# ========================
require_core_dir() {
    echo -e "${BLUE}[步骤] 检查 ClashMac 核心目录...${NC}"
    if [ ! -d "$CLASHMAC_CORE_DIR" ]; then
        echo -e "${RED}[错误] 未找到 ClashMac Core 目录:${NC}"
        echo "  $CLASHMAC_CORE_DIR"
        exit 1
    fi
    cd "$CLASHMAC_CORE_DIR" || { echo -e "${RED}[错误] 进入核心目录失败${NC}"; exit 1; }
    echo -e "${GREEN}[成功] 当前目录: $CLASHMAC_CORE_DIR${NC}"
}

# ========================
# 帮助信息
# ========================
cmd_help() {
    echo -e "${BLUE}[步骤] 显示帮助信息${NC}"
    echo
    echo -e "${BLUE}clashmac_mihomo-kernel_helper.sh${NC}"
    echo
    echo "用法:"
    echo "  sh $0 install           安装 / 更新 mihomo 核心（默认）"
    echo "  sh $0 status            显示当前核心及最新备份"
    echo "  sh $0 list              列出所有备份核心"
    echo "  sh $0 switch [suffix]   切换到备份核心"
    echo "  sh $0 help              显示帮助信息"
    echo
}

# ========================
# 列出备份核心
# ========================
list_backups() {
    require_core_dir
    echo -e "${BLUE}[步骤] 列出可用备份核心${NC}\n"

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

# ========================
# 当前核心状态
# ========================
show_status() {
    require_core_dir
    echo -e "${BLUE}[步骤] 获取当前核心状态${NC}"

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

    echo -e "${BLUE}[步骤] 获取最新备份信息${NC}"
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

# ========================
# 切换核心
# ========================
switch_core() {
    require_core_dir

    if [ -z "$1" ]; then
        echo -e "${RED}[错误] switch 必须指定版本${NC}"
        exit 1
    fi

    INPUT="$1"
    echo -e "${BLUE}[步骤] 开始切换核心... 输入参数: $INPUT${NC}"

    # 显示当前核心信息
    if [ -f "$ACTIVE_CORE" ]; then
        CURRENT_RAW=$("./$ACTIVE_CORE" -v 2>/dev/null | head -n1)
        echo "[信息] 当前核心版本: $CURRENT_RAW"
    else
        echo "[信息] 当前核心不存在"
    fi

    # 匹配备份文件
    if [[ "$INPUT" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        echo "[步骤] 按时间戳查找备份..."
        TARGET_BACKUP=$(ls -1 "$CLASHMAC_CORE_DIR"/mihomo.backup.* 2>/dev/null | grep "\.$INPUT$")
    elif [[ "$INPUT" =~ ^mihomo-darwin-(amd64|arm64)-.+$ ]]; then
        echo "[步骤] 按版本号查找备份..."
        TARGET_BACKUP=$(ls -1 "$CLASHMAC_CORE_DIR"/mihomo.backup.* 2>/dev/null | grep "$INPUT")
    else
        echo -e "${RED}[错误] 只支持版本号或时间戳格式${NC}"
        exit 1
    fi

    # 验证备份文件存在且大小合理
    if [ ! -f "$TARGET_BACKUP" ] || [ ! -s "$TARGET_BACKUP" ]; then
        echo -e "${RED}[错误] 未找到有效备份文件: $TARGET_BACKUP${NC}"
        exit 1
    fi
    echo "[信息] 匹配到备份文件: $TARGET_BACKUP"

    # 临时备份当前核心
    if [ -f "$ACTIVE_CORE" ]; then
        TMP_ROLLBACK="${ACTIVE_CORE}.rollback.$(date +%Y%m%d_%H%M%S)"
        cp "$ACTIVE_CORE" "$TMP_ROLLBACK"
        echo "[步骤] 已备份当前核心 -> $TMP_ROLLBACK"
    fi

    # 替换核心
    TMP_CORE="${ACTIVE_CORE}.tmp"
    cp "$TARGET_BACKUP" "$TMP_CORE" || { echo "[错误] 复制备份失败"; rm -f "$TMP_ROLLBACK"; exit 1; }
    mv -f "$TMP_CORE" "$ACTIVE_CORE" || { echo "[错误] 替换核心失败"; cp "$TMP_ROLLBACK" "$ACTIVE_CORE"; exit 1; }
    chmod +x "$ACTIVE_CORE"

    echo -e "${GREEN}[完成] 核心切换成功${NC}"
    echo "当前核心已替换为: $TARGET_BACKUP"

    # 删除临时回滚
    rm -f "$TMP_ROLLBACK"
    echo "[步骤] 已删除临时回滚: $TMP_ROLLBACK"

    echo -e "${YELLOW}请在 GUI 中重启内核以生效${NC}"
}

# ========================
# 安装 / 更新核心
# ========================
install_core() {
    require_core_dir
    VERSION_BRANCH="$1"

    # ---------- 1. 选择 GitHub 用户 ----------
    if [ -n "$VERSION_BRANCH" ]; then
        GITHUB_USER="MetaCubeX"
        echo -e "${BLUE}[信息] 已指定版本:${NC} $VERSION_BRANCH"
    else
        echo -e "${BLUE}[步骤] 选择 GitHub 用户下载核心: ${NC}\n"
        for i in "${!GITHUB_USERS[@]}"; do
            if [ "${GITHUB_USERS[$i]}" = "vernesong" ]; then
                echo "  $((i+1))) ${GITHUB_USERS[$i]} - Smart版本\n"
            elif [ "${GITHUB_USERS[$i]}" = "MetaCubeX" ]; then
                echo "  $((i+1))) ${GITHUB_USERS[$i]} - 官方原版\n"
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
            echo -e "${BLUE}[步骤] 选择 MetaCubeX 版本类型: ${NC}"
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
    echo "[步骤] 获取最新版本信息..."
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
    echo "[步骤] 下载并解压核心到 $ACTIVE_CORE ..."
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
    echo "[步骤] 生成备份文件 -> $(basename "$BACKUP_FILE")"

    echo -e "${GREEN}[完成] 安装完成: $VERSION${NC}"
}

# ========================
# 打印脚本版本 / 帮助 / 未知命令
# ========================
show_version() {
    echo -e "${BLUE}[步骤] 检查脚本版本... ${NC}"
    echo -e "${GREEN}[结果] 当前脚本版本: $SCRIPT_VERSION"
}

shwo_help() {
    echo -e "${BLUE}[步骤] 显示帮助信息${NC}"
    echo "clashmac_mihomo-kernel_helper - ClashMac mihomo 核心助手脚本"
    echo "用法: $0 <命令>"
    echo
    echo "命令:"
    echo "  install       安装最新 mihomo 核心"
    echo "  switch        切换备份核心"
    echo "  status        显示当前核心状态"
    echo "  version       显示脚本版本"
    echo "  help          显示帮助信息"
}

handle_unknown_command() {
    echo -e "${RED}[错误] 未知命令: $1${NC}"
    echo "请使用 help 查看可用命令"
}

# ========================
# 检查 ClashMac 应用是否安装
# ========================
check_clashmac_app() {
    echo ""
    echo -e "${BLUE}[步骤] 检查 ClashMac 应用是否安装...${NC}"
    if [ ! -d "$CLASHMAC_DIR" ]; then
        echo -e "${RED}[错误] 未找到 ClashMac 应用目录:${NC}"
        echo "  $CLASHMAC_DIR"
        echo -e "${YELLOW}[提示] 请先安装 ClashMac 应用后再运行此脚本${NC}"
        exit 1
    fi
    echo -e "${GREEN}[成功] ClashMac 应用已安装: $CLASHMAC_DIR${NC}"
}

# ========================
# 主入口
# ========================
check_clashmac_app

COMMAND="$1"
case "$COMMAND" in
    help|-h) shwo_help ;;
    version|-v) show_version ;;
    install|-i) shift; install_core "$@" ;;
    list|-ls) list_backups ;;
    switch|-rp) shift; switch_core "$@" ;;
    status|-info) show_status ;;
    *) handle_unknown_command "$COMMAND" ;;
esac
