#!/usr/bin/env bash

###############################################################################
# ClashMac Mihomo Kernel Installer
#
# 项目概述：
#   这是一个轻量级的 ClashMac mihomo 内核安装脚本，专注于提供核心安装功能
#   与完整版本的 Helper 工具相比，该脚本仅包含 install_core() 函数及其必要依赖
#
# 作者信息：
#   Author: Kuochiang Lu
#   Version: 1.3.3
#   Last Updated: 2026-02-02
#
# 核心功能：
#   ✅ 多源安装支持：可从多个 GitHub 源（如 MetaCubeX、vernesong）下载内核
#   ✅ 智能架构适配：自动检测系统架构 (arm64/amd64) 并下载对应版本
#   ✅ 完整备份机制：安装前自动备份现有内核，保障系统安全
#   ✅ 版本灵活选择：支持安装指定版本或最新版本
#
# 系统依赖：
#   - curl          # 用于从 GitHub 下载内核文件
#   - tar           # 用于解压下载的内核包
#   - grep/awk/sed  # 用于文本处理和信息提取
#   - bash          # 脚本运行环境（需 bash 4.0+）
#
# 典型应用场景：
#   - 集成到其他自动化脚本中
#   - 需要轻量级内核安装解决方案
#   - 仅需安装功能，无需完整管理工具
#
# 使用说明：
#   该脚本设计为被其他脚本调用，主要接口为 install_core() 函数
#   可通过传入参数指定要安装的内核版本
#
# 注意事项：
#   - 请确保脚本具有执行权限 (chmod +x script.sh)
#   - 运行脚本可能需要管理员权限
#   - 首次使用前建议确认 ClashMac 应用已正确安装
###############################################################################

SCRIPT_NAME="ClashMac-Mihomo-Kernel-Installer"
SCRIPT_VERSION="1.3.3" # 脚本版本

# ========================
# 配置路径和默认变量
# ========================
CLASHMAC_DIR="/Applications/ClashMac.app"
CLASHMAC_CORE_DIR="$HOME/Library/Application Support/clashmac/core"
ACTIVE_CORE="mihomo"   # 默认核心文件

GITHUB_USERS=("MetaCubeX" "vernesong")  # 可选 GitHub 用户
DEFAULT_BRANCH="Prerelease-Alpha"       # 默认分支

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========================
# 输出空行
# ========================
show_empty_line() {
    local count=${1:-1}  # 默认输出1行空行，可通过参数指定数量
    for ((i=1; i<=count; i++)); do
        echo
    done
}

# ========================
# 安装 / 更新核心
# ========================
install_core() {
    VERSION_BRANCH="$1"
    show_empty_line 1
    echo -e "${GREEN}========== 安装 / 更新核心开始 ==========${NC}"

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

    # 在脚本执行前检查核心目录
    if [ ! -d "$CLASHMAC_CORE_DIR" ]; then
        echo -e "${YELLOW}[提示] 核心目录不存在，请检查安装软件版本...${NC}"
        echo -e "${RED}[错误] 核心目录: ${CLASHMAC_CORE_DIR} ${NC}";
        return 1;
    fi

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
    # 在下载前切换到核心目录
    cd "$CLASHMAC_CORE_DIR" || { echo -e "${RED}[错误] 进入核心目录失败${NC}"; return 1; }
    echo "下载并解压核心到 $ACTIVE_CORE ..."
    for i in {1..3}; do
        curl -fL "$DOWNLOAD_URL" | gunzip > "$ACTIVE_CORE" && break
        echo "下载失败，重试第 $i 次..."
        sleep 2
    done
    sleep 3
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
}

# =============================
# 检查 ClashMac + mihomo 内核状态
# =============================
health_check_core() {
    echo -e "${GREEN}========== 健康检查开始 ==========${NC}"
    # 0. ClashMac App 检查
    if [ ! -d "$CLASHMAC_DIR" ]; then
        echo -e "${RED}[错误] 未找到 ClashMac 应用目录:${NC}"
        echo "          $CLASHMAC_DIR"
        echo -e "${YELLOW}[提示] 请先安装 ClashMac 应用后再运行此脚本${NC}"
        return 1
    fi
    echo -e "${GREEN}[成功] ClashMac 应用已安装: $CLASHMAC_DIR${NC}"

    # 1. Core 目录检查
    if [ ! -d "$CLASHMAC_CORE_DIR" ]; then
        echo -e "${RED}[错误] 未找到 ClashMac Core 目录:${NC}"
        echo "  $CLASHMAC_CORE_DIR"
        return 1
    fi
    cd "$CLASHMAC_CORE_DIR" || { echo -e "${RED}[错误] 进入核心目录失败${NC}"; return 1; }
    echo -e "${GREEN}[成功] 当前目录: $CLASHMAC_CORE_DIR${NC}"

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
}

# ========================
# 显示标题信息
# ========================
show_title() {
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}      ClashMac Mihomo Kernel Installer      ${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}Version: ${YELLOW}${SCRIPT_VERSION}            ${NC}"

    show_empty_line 1
}

# ========================
# 处理未知命令
# ========================
handle_unknown_command() {
    echo -e "${RED}[错误] 未知命令: $1${NC}"
    echo -e "${YELLOW}[提示] 你可以使用 '-i' 或 'install' 来安装/更新内核${NC}"
}

# ========================
# 显示使用帮助
# ========================
show_usage() {
    show_empty_line 1
    echo -e "${BLUE}用法:${NC} $0 [命令] [参数]"
    show_empty_line 1
    echo -e "${BLUE}可用命令:${NC}"
    echo -e "  ${GREEN}install${NC}, ${GREEN}-i${NC}    安装/更新 mihomo 内核"
    echo -e "  ${GREEN}check${NC}, ${GREEN}-c${NC}     运行健康检查"
    echo -e "  ${GREEN}help${NC}, ${GREEN}-h${NC}      显示帮助信息"
    show_empty_line 1
    echo -e "${BLUE}示例:${NC}"
    echo -e "  安装最新内核:"
    echo -e "    $0 install"
    echo -e "  运行健康检查:"
    echo -e "    $0 check"
    show_empty_line 1
}

# ========================
# 主程序函数
# ========================
main() {
    show_title

    # 检查是否有命令行参数
    if [ $# -eq 0 ]; then
        # 无参数时执行默认操作：先运行健康检查，然后提示用户
        health_check_core
        HEALTH_STATUS=$?

        show_empty_line 1
        echo -e "${YELLOW}[提示] 未指定命令，默认执行健康检查${NC}"
        show_usage
        return $HEALTH_STATUS
    fi

    # 解析命令行参数
    local COMMAND="$1"
    shift

    # 处理命令
    case "$COMMAND" in
        install|-i)
            install_core "$@"
            ;;
        check|-c)
            health_check_core
            ;;
        help|-h|--help)
            show_usage
            ;;
        *)
            handle_unknown_command "$COMMAND"
            ;;
    esac
}

# ========================
# 脚本入口点
# ========================
# 如果脚本直接执行，则调用 main 函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi