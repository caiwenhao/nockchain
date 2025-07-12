#!/bin/bash

# Nockchain LLVM 依赖修复脚本 - Ubuntu 22.04 专用
# 解决 llvm-dev 包依赖问题并验证环境

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

show_banner() {
    echo -e "${BLUE}"
    echo "    ╔═══════════════════════════════════════╗"
    echo "    ║     Nockchain LLVM 依赖修复工具       ║"
    echo "    ║       Ubuntu 22.04 专用版本           ║"
    echo "    ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查系统版本
check_system() {
    log "检查系统环境..."

    if ! grep -q "Ubuntu" /etc/os-release; then
        error "此脚本仅支持 Ubuntu 系统"
        exit 1
    fi

    local ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
    log "检测到 Ubuntu 版本: $ubuntu_version"

    if [[ "$ubuntu_version" != "22.04" ]]; then
        warn "此脚本专为 Ubuntu 22.04 设计，其他版本可能需要调整"
    fi
}

# 方案1: 安装替代包组合 (已验证成功的方案)
install_alternative_packages() {
    log "方案1: 使用替代包组合 (推荐方案)..."

    # 更新包列表
    sudo apt update

    # 修复可能的包依赖问题
    sudo apt --fix-broken install -y || true
    sudo apt autoremove -y || true

    # 安装基础编译工具 (避开有问题的 llvm-dev)
    if sudo apt install -y \
        clang \
        libc6-dev \
        libclang-dev \
        libclang-common-14-dev \
        pkg-config; then
        log "✅ 成功安装替代包组合"
        return 0
    else
        warn "❌ 替代包安装失败"
        return 1
    fi
}

# 方案2: 尝试修复依赖冲突
fix_package_conflicts() {
    log "方案2: 尝试修复包依赖冲突..."

    # 清理包缓存
    sudo apt autoclean

    # 尝试安装 LLVM 14 (跳过有问题的 llvm-14-dev)
    if sudo apt install -y clang-14 libclang-14-dev; then
        log "✅ 成功安装 LLVM 14"
        # 创建符号链接
        sudo ln -sf /usr/bin/clang-14 /usr/bin/clang 2>/dev/null || true
        sudo ln -sf /usr/bin/clang++-14 /usr/bin/clang++ 2>/dev/null || true
        return 0
    else
        warn "❌ LLVM 14 安装失败"
        return 1
    fi
}

# 方案3: 使用官方 LLVM 仓库
install_from_official_repo() {
    log "方案3: 使用官方 LLVM 仓库..."

    # 添加 LLVM 官方仓库密钥
    log "添加 LLVM 官方仓库密钥..."
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | sudo tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc

    # 添加仓库
    log "添加 LLVM 仓库..."
    echo "deb http://apt.llvm.org/jammy/ llvm-toolchain-jammy-19 main" | sudo tee /etc/apt/sources.list.d/llvm.list

    # 更新包列表
    sudo apt update

    # 安装 LLVM 19
    if sudo apt install -y clang-19 llvm-19-dev libclang-19-dev; then
        log "✅ 成功从官方仓库安装 LLVM 19"
        # 创建符号链接
        sudo ln -sf /usr/bin/clang-19 /usr/bin/clang
        sudo ln -sf /usr/bin/clang++-19 /usr/bin/clang++
        return 0
    else
        warn "❌ LLVM 19 安装失败"
        return 1
    fi
}

# 验证 LLVM/Clang 环境
verify_installation() {
    log "验证 LLVM/Clang 环境..."

    if command -v clang &> /dev/null; then
        local clang_version=$(clang --version | head -n1)
        log "✅ Clang 已安装: $clang_version"
    else
        error "❌ Clang 未找到"
        return 1
    fi

    if command -v llvm-config &> /dev/null; then
        local llvm_version=$(llvm-config --version)
        log "✅ LLVM 已安装: $llvm_version"
    else
        warn "⚠️  llvm-config 未找到，但 clang 可用 (这对 Nockchain 编译是足够的)"
    fi

    # 测试编译功能
    log "测试编译功能..."
    echo 'int main(){return 0;}' > /tmp/test.c
    if clang /tmp/test.c -o /tmp/test; then
        log "✅ 编译测试通过"
        rm -f /tmp/test.c /tmp/test
        return 0
    else
        error "❌ 编译测试失败"
        rm -f /tmp/test.c /tmp/test
        return 1
    fi
}

# 显示环境信息
show_environment() {
    log "当前环境信息:"
    echo "  - Clang: $(command -v clang || echo '未安装')"
    echo "  - Clang++: $(command -v clang++ || echo '未安装')"
    echo "  - LLVM Config: $(command -v llvm-config || echo '未安装')"
    echo "  - GCC: $(command -v gcc || echo '未安装')"
    echo "  - Make: $(command -v make || echo '未安装')"
    echo "  - Pkg-config: $(command -v pkg-config || echo '未安装')"
}

# 主函数
main() {
    show_banner
    check_system

    # 首先检查是否已经有可用的环境
    log "检查当前环境..."
    show_environment

    if verify_installation; then
        info "🎉 LLVM/Clang 环境已经可用！"
        info "✅ 你的系统已准备好编译 Nockchain"
        exit 0
    fi

    log "开始修复 LLVM 依赖问题..."

    # 尝试方案1 (已验证成功的方案)
    if install_alternative_packages; then
        if verify_installation; then
            info "🎉 修复成功！使用方案1 (替代包组合)"
            exit 0
        fi
    fi

    # 尝试方案2
    if fix_package_conflicts; then
        if verify_installation; then
            info "🎉 修复成功！使用方案2 (LLVM 14)"
            exit 0
        fi
    fi

    # 尝试方案3
    if install_from_official_repo; then
        if verify_installation; then
            info "🎉 修复成功！使用方案3 (官方仓库 LLVM 19)"
            exit 0
        fi
    fi

    error "❌ 所有修复方案都失败了"
    error "请手动检查系统包依赖或联系技术支持"
    error "你也可以尝试手动运行:"
    error "sudo apt install -y clang libclang-dev build-essential pkg-config"
    exit 1
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
