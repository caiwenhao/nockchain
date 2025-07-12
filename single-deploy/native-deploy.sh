#!/bin/bash

# Nockchain 原生部署脚本 (无Docker)
# 适用于 Ubuntu 20.04+ 系统

set -e

# 配置变量
INSTALL_DIR="$HOME/nockchain"
SERVICE_USER="$(whoami)"
RUST_VERSION="nightly-2025-02-14"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# 显示横幅
show_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
    ╔═══════════════════════════════════════╗
    ║      Nockchain 原生部署工具           ║
    ║    Native Deployment (No Docker)     ║
    ╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 检查系统
check_system() {
    log "检查系统环境..."
    
    if ! grep -q "Ubuntu" /etc/os-release; then
        error "此脚本仅支持 Ubuntu 系统"
        exit 1
    fi
    
    # 检查权限 - 允许root用户运行
    if [ "$EUID" -eq 0 ]; then
        warn "正在以 root 用户运行脚本"
        warn "建议使用普通用户运行以提高安全性"
        # 如果是root用户，调整安装目录到/opt
        if [ "$INSTALL_DIR" = "$HOME/nockchain" ]; then
            INSTALL_DIR="/opt/nockchain"
            SERVICE_USER="root"
        fi
    fi
    
    # 检查系统资源
    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    local cpu_cores=$(nproc)
    
    log "系统检查完成 - 内存: ${total_mem}MB, CPU核心: ${cpu_cores}"
    
    if [ "$total_mem" -lt 4096 ]; then
        warn "系统内存少于 4GB，可能影响挖矿性能"
    fi
    
    if [ "$cpu_cores" -lt 4 ]; then
        warn "CPU 核心数少于 4，可能影响挖矿效率"
    fi
}

# 安装系统依赖
install_dependencies() {
    log "安装系统依赖..."

    sudo apt update

    # 先安装基础依赖
    sudo apt install -y \
        curl \
        wget \
        git \
        build-essential \
        pkg-config \
        make \
        htop \
        net-tools \
        ufw \
        screen \
        tmux

    # 安装 LLVM (Ubuntu 22.04 兼容方案)
    install_llvm_ubuntu22

    log "系统依赖安装完成"
}

# Ubuntu 22.04 LLVM 安装函数
install_llvm_ubuntu22() {
    log "安装 LLVM 开发环境 (Ubuntu 22.04 优化)..."

    # 检查 Ubuntu 版本
    local ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
    log "检测到 Ubuntu 版本: $ubuntu_version"

    # 检查是否已经有可用的 clang
    if command -v clang &> /dev/null; then
        local clang_version=$(clang --version | head -n1)
        log "检测到已安装的 Clang: $clang_version"
        log "跳过 LLVM 安装，使用现有环境"
        return 0
    fi

    if [[ "$ubuntu_version" == "22.04" ]]; then
        log "使用 Ubuntu 22.04 优化的 LLVM 安装方案..."

        # 方案1: 尝试安装可用的 LLVM 版本 (跳过有问题的 llvm-14-dev)
        if sudo apt install -y clang-14 libclang-14-dev; then
            log "成功安装 LLVM 14 (跳过 llvm-14-dev)"
            # 创建符号链接以兼容通用包名
            sudo ln -sf /usr/bin/clang-14 /usr/bin/clang 2>/dev/null || true
            sudo ln -sf /usr/bin/clang++-14 /usr/bin/clang++ 2>/dev/null || true
        else
            warn "LLVM 14 安装失败，尝试使用官方 LLVM 仓库..."
            install_llvm_from_official_repo
        fi
    else
        # 其他版本使用标准安装
        sudo apt install -y clang llvm-dev libclang-dev
    fi
}

# 从官方 LLVM 仓库安装
install_llvm_from_official_repo() {
    log "尝试使用基础 clang 包..."

    # 简化安装，只安装基础的 clang 包
    if sudo apt install -y clang libclang-dev; then
        log "成功安装基础 clang 环境"
        return 0
    else
        warn "基础 clang 安装也失败，但可能系统已有可用的编译器"
        return 1
    fi
}

# 安装 Rust
install_rust() {
    if command -v rustc &> /dev/null; then
        local current_version=$(rustc --version | awk '{print $2}')
        log "Rust 已安装，版本: $current_version"
        
        # 检查是否是正确的版本
        if rustup toolchain list | grep -q "$RUST_VERSION"; then
            log "正确的 Rust 版本已安装"
            return
        fi
    fi
    
    log "安装 Rust $RUST_VERSION..."
    
    # 安装 rustup
    if ! command -v rustup &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source ~/.cargo/env
    fi
    
    # 安装指定版本
    rustup toolchain install $RUST_VERSION
    rustup default $RUST_VERSION
    rustup component add miri
    
    # 更新 PATH
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    
    log "Rust 安装完成"
}

# 快速设置项目（跳过编译）
setup_project_skip_build() {
    log "快速设置项目目录（跳过编译）..."

    # 检查是否已有安装目录
    if [ -d "$INSTALL_DIR" ]; then
        if [ -f "$INSTALL_DIR/Makefile" ] && [ -f "$INSTALL_DIR/Cargo.toml" ]; then
            log "检测到已存在的项目目录: $INSTALL_DIR"
            cd "$INSTALL_DIR"
            return
        else
            warn "安装目录存在但不包含项目文件，将重新设置"
            rm -rf "$INSTALL_DIR"
        fi
    fi

    # 获取脚本所在目录的上级目录（项目根目录）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    # 检查是否在项目目录中运行脚本
    if [ -f "$PROJECT_ROOT/Makefile" ] && [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
        log "从项目源码复制必要文件: $PROJECT_ROOT"

        # 创建安装目录
        mkdir -p "$INSTALL_DIR"

        # 只复制必要的文件，跳过源码
        cp "$PROJECT_ROOT/.env_example" "$INSTALL_DIR/" 2>/dev/null || true
        cp "$PROJECT_ROOT/Makefile" "$INSTALL_DIR/" 2>/dev/null || true
        cp "$PROJECT_ROOT/Cargo.toml" "$INSTALL_DIR/" 2>/dev/null || true

        # 创建必要的目录
        mkdir -p "$INSTALL_DIR/logs"
        mkdir -p "$INSTALL_DIR/.data.nockchain"

        cd "$INSTALL_DIR"
        log "快速项目设置完成"
        return
    fi

    error "未找到项目源码，无法进行快速设置"
    error "请确保在项目目录中运行此脚本"
    exit 1
}

# 克隆或更新项目
setup_project() {
    log "设置项目目录..."

    # 获取脚本所在目录的上级目录（项目根目录）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    # 检查是否在项目目录中运行脚本
    if [ -f "$PROJECT_ROOT/Makefile" ] && [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
        log "检测到项目源码在: $PROJECT_ROOT"

        # 如果安装目录就是项目根目录，直接使用
        if [ "$PROJECT_ROOT" = "$INSTALL_DIR" ]; then
            log "使用当前项目目录作为安装目录"
            cd "$INSTALL_DIR"
            return
        fi

        # 否则复制项目到安装目录
        if [ -d "$INSTALL_DIR" ]; then
            warn "项目目录已存在，是否要重新复制？(y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                rm -rf "$INSTALL_DIR"
            else
                cd "$INSTALL_DIR"
                if [ -f "Makefile" ]; then
                    log "使用现有项目目录"
                    return
                else
                    warn "现有目录不包含项目文件，将重新复制"
                    rm -rf "$INSTALL_DIR"
                fi
            fi
        fi

        log "复制项目源码到 $INSTALL_DIR..."
        mkdir -p "$(dirname "$INSTALL_DIR")"
        cp -r "$PROJECT_ROOT" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        log "项目复制完成"
        return
    fi

    # 传统的Git克隆方式
    if [ -d "$INSTALL_DIR" ]; then
        warn "项目目录已存在，是否要重新克隆？(y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            cd "$INSTALL_DIR"
            git pull origin main 2>/dev/null || log "无法更新项目，继续使用现有版本"
            return
        fi
    fi

    # 这里需要替换为实际的仓库地址
    if [ -n "${REPO_URL:-}" ]; then
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        warn "请手动将 Nockchain 源码复制到 $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
        info "或者设置环境变量 REPO_URL 指向你的仓库"
        return
    fi

    cd "$INSTALL_DIR"
    log "项目设置完成"
}

# 构建项目
build_project() {
    log "构建 Nockchain 项目..."

    cd "$INSTALL_DIR"

    # 复制环境配置
    if [ ! -f .env ]; then
        if [ -f .env_example ]; then
            cp .env_example .env
            log "已创建 .env 配置文件"
        else
            # 如果当前目录没有 .env_example，尝试从脚本所在目录的上级目录复制
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
            if [ -f "$PROJECT_ROOT/.env_example" ]; then
                cp "$PROJECT_ROOT/.env_example" .env
                log "从项目根目录复制了 .env 配置文件"
            else
                warn "找不到 .env_example 文件，创建默认配置..."
                cat > .env << 'ENVEOF'
RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info,libp2p=info,libp2p_quic=info
MINIMAL_LOG_FORMAT=true
MINING_PUBKEY=2qwq9dQRZfpFx8BDicghpMRnYGKZsZGxxhh9m362pzpM9aeo276pR1yHZPS41y3CW3vPKxeYM8p8fzZS8GXmDGzmNNCnVNekjrSYogqfEFMqwhHh5iCjaKPaDTwhupWqiXj6
ENVEOF
                log "已创建默认 .env 配置文件"
            fi
        fi
    fi
    
    # 检查是否有Makefile
    if [ ! -f "Makefile" ]; then
        error "找不到 Makefile，请确保项目源码已正确复制"
        error "当前目录: $(pwd)"
        error "目录内容: $(ls -la)"
        exit 1
    fi

    # 构建项目
    log "开始编译，这可能需要几分钟..."
    if ! make build; then
        error "项目构建失败"
        exit 1
    fi

    # 安装组件
    log "安装 hoonc 编译器..."
    if ! make install-hoonc; then
        warn "hoonc 安装失败，但继续安装其他组件"
    fi

    log "安装 nockchain 主程序..."
    if ! make install-nockchain; then
        error "nockchain 安装失败"
        exit 1
    fi

    log "安装 nockchain-wallet 钱包..."
    if ! make install-nockchain-wallet; then
        warn "nockchain-wallet 安装失败，但继续"
    fi
    
    # 确保二进制文件在 PATH 中
    if ! command -v nockchain &> /dev/null; then
        export PATH="$HOME/.cargo/bin:$PATH"
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    fi
    
    log "项目构建完成"
}

# 生成密钥
generate_keys() {
    log "生成挖矿密钥..."

    # 检查安装目录是否存在
    if [ ! -d "$INSTALL_DIR" ]; then
        error "安装目录不存在: $INSTALL_DIR"
        error "请先运行: $0 install"
        exit 1
    fi

    cd "$INSTALL_DIR"

    # 检查 nockchain-wallet 是否已安装
    if ! command -v nockchain-wallet &> /dev/null; then
        error "nockchain-wallet 未找到"
        error "请先运行: $0 install"
        exit 1
    fi

    info "正在生成新的密钥对..."
    if nockchain-wallet keygen; then
        echo ""
        warn "请将上面显示的公钥复制到 .env 文件中的 MINING_PUBKEY 变量"
        info "编辑命令: nano $INSTALL_DIR/.env"
        echo ""
        info "完成后可以启动挖矿: $0 start"
    else
        error "密钥生成失败"
        exit 1
    fi
}

# 配置防火墙
configure_firewall() {
    log "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        sudo ufw --force enable
        sudo ufw allow ssh
        sudo ufw allow 4001/udp comment "Nockchain P2P"
        log "防火墙配置完成"
    else
        warn "未找到 ufw，请手动配置防火墙开放端口 4001/udp"
    fi
}

# 创建启动脚本
create_scripts() {
    log "创建启动脚本..."
    
    cd "$INSTALL_DIR"
    
    # 创建挖矿启动脚本
    cat > start-miner.sh << 'EOF'
#!/bin/bash

cd "$(dirname "$0")"
source .env

# 检查挖矿公钥
if [ -z "$MINING_PUBKEY" ] || [ "$MINING_PUBKEY" = "请在此处填入您的挖矿公钥" ]; then
    echo "错误: 请先设置 MINING_PUBKEY 环境变量"
    echo "编辑 .env 文件并设置你的挖矿公钥"
    exit 1
fi

export RUST_LOG
export MINIMAL_LOG_FORMAT
export MINING_PUBKEY

# 计算挖矿线程数
get_cpu_count() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sysctl -n hw.logicalcpu
    else
        nproc
    fi
}

total_threads=$(get_cpu_count)
num_threads=$((total_threads > 4 ? total_threads - 4 : total_threads))

echo "启动 Nockchain 挖矿节点..."
echo "使用 $num_threads 个挖矿线程 (总CPU核心: $total_threads)"
echo "挖矿公钥: $MINING_PUBKEY"
echo "日志级别: $RUST_LOG"
echo "================================"

# 创建必要目录
mkdir -p logs
mkdir -p .socket

# 预清理：检查并停止已运行的进程
if pgrep -f "nockchain.*--mine" > /dev/null; then
    echo "检测到已运行的挖矿进程，正在停止..."
    pkill -f "nockchain.*--mine" 2>/dev/null
    sleep 2
fi

# 清理 socket 文件
if [ -d ".socket" ]; then
    echo "清理旧的 socket 文件..."
    rm -f .socket/*.sock
fi

# 清理可能的锁文件
if [ -f ".data.nockchain/LOCK" ]; then
    echo "清理数据库锁文件..."
    rm -f .data.nockchain/LOCK
fi

echo "预清理完成，开始启动挖矿..."

# 启动挖矿
# 尝试多个可能的 nockchain 路径
NOCKCHAIN_BIN=""
for path in "/usr/local/bin/nockchain" "$HOME/.cargo/bin/nockchain" "$(which nockchain 2>/dev/null)" "./target/release/nockchain"; do
    if [ -x "$path" ]; then
        NOCKCHAIN_BIN="$path"
        break
    fi
done

if [ -z "$NOCKCHAIN_BIN" ]; then
    echo "错误: 找不到 nockchain 可执行文件"
    echo "请确保 nockchain 已正确安装"
    exit 1
fi

echo "使用 nockchain 路径: $NOCKCHAIN_BIN"
"$NOCKCHAIN_BIN" --mining-pubkey "${MINING_PUBKEY}" --mine --num-threads $num_threads 2>&1 | tee logs/miner-$(date +%Y%m%d-%H%M%S).log
EOF

    # 创建普通节点启动脚本
    cat > start-node.sh << 'EOF'
#!/bin/bash

cd "$(dirname "$0")"
source .env

export RUST_LOG
export MINIMAL_LOG_FORMAT

echo "启动 Nockchain 普通节点..."
echo "日志级别: $RUST_LOG"
echo "================================"

# 创建必要目录
mkdir -p logs
mkdir -p .socket

# 预清理：检查并停止已运行的进程
if pgrep -f "nockchain" > /dev/null; then
    echo "检测到已运行的 nockchain 进程，正在停止..."
    pkill -f "nockchain" 2>/dev/null
    sleep 2
fi

# 清理 socket 文件
if [ -d ".socket" ]; then
    echo "清理旧的 socket 文件..."
    rm -f .socket/*.sock
fi

# 清理可能的锁文件
if [ -f ".data.nockchain/LOCK" ]; then
    echo "清理数据库锁文件..."
    rm -f .data.nockchain/LOCK
fi

echo "预清理完成，开始启动节点..."

# 启动节点
# 尝试多个可能的 nockchain 路径
NOCKCHAIN_BIN=""
for path in "/usr/local/bin/nockchain" "$HOME/.cargo/bin/nockchain" "$(which nockchain 2>/dev/null)" "./target/release/nockchain"; do
    if [ -x "$path" ]; then
        NOCKCHAIN_BIN="$path"
        break
    fi
done

if [ -z "$NOCKCHAIN_BIN" ]; then
    echo "错误: 找不到 nockchain 可执行文件"
    echo "请确保 nockchain 已正确安装"
    exit 1
fi

echo "使用 nockchain 路径: $NOCKCHAIN_BIN"
"$NOCKCHAIN_BIN" 2>&1 | tee logs/node-$(date +%Y%m%d-%H%M%S).log
EOF



    # 创建状态检查脚本
    cat > check-status.sh << 'EOF'
#!/bin/bash

# Nockchain 节点状态检查脚本
# 用法: ./check-status.sh [日志行数]
# 示例: ./check-status.sh 100  # 显示最近100行日志

# 显示帮助信息
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "用法: $0 [日志行数]"
    echo ""
    echo "参数:"
    echo "  日志行数    显示的日志行数 (默认: 5)"
    echo ""
    echo "示例:"
    echo "  $0          # 显示最近5行日志"
    echo "  $0 100      # 显示最近100行日志"
    echo "  $0 1000     # 显示最近1000行日志"
    echo ""
    echo "其他有用命令:"
    echo "  tail -f logs/miner-*.log    # 实时查看日志"
    echo "  grep 'mining-on' logs/miner-*.log | tail -10    # 查看挖矿活动"
    exit 0
fi

echo "=== Nockchain 节点状态 ==="
echo "时间: $(date)"
echo ""

# 检查进程
if pgrep -f "nockchain.*--mine" > /dev/null; then
    echo "✓ 挖矿节点: 运行中"
    echo "  PID: $(pgrep -f 'nockchain.*--mine')"
    echo "  运行时间: $(ps -o etime= -p $(pgrep -f 'nockchain.*--mine') 2>/dev/null | tr -d ' ' || echo '未知')"
else
    echo "✗ 挖矿节点: 未运行"
fi

echo ""
echo "=== 核心功能状态 ==="

# 检查区块同步状态
check_block_sync() {
    if ls logs/miner-*.log 1> /dev/null 2>&1; then
        latest_log=$(ls -t logs/miner-*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            # 获取最新区块信息
            latest_block=$(grep "added to validated blocks at" "$latest_log" | tail -1)
            if [ -n "$latest_block" ]; then
                block_height=$(echo "$latest_block" | grep -o "at [0-9]*" | grep -o "[0-9]*")
                block_hash=$(echo "$latest_block" | awk '{print $4}')
                block_time=$(echo "$latest_block" | awk '{print $2}' | tr -d '()')

                # 检查最近是否有新区块（5分钟内）
                recent_blocks=$(grep "added to validated blocks" "$latest_log" | tail -10)
                if echo "$recent_blocks" | grep -q "$(date +%H:%M -d '5 minutes ago')\|$(date +%H:%M -d '4 minutes ago')\|$(date +%H:%M -d '3 minutes ago')\|$(date +%H:%M -d '2 minutes ago')\|$(date +%H:%M -d '1 minute ago')\|$(date +%H:%M)"; then
                    echo "✓ 区块同步: 正常"
                else
                    echo "⚠ 区块同步: 可能延迟"
                fi
                echo "  当前高度: $block_height"
                echo "  最新区块: ${block_hash:0:20}..."
                echo "  同步时间: $block_time"
            else
                echo "✗ 区块同步: 无区块数据"
            fi
        else
            echo "✗ 区块同步: 无日志文件"
        fi
    else
        echo "✗ 区块同步: 无日志文件"
    fi
}

# 检查挖矿活动
check_mining_activity() {
    if ls logs/miner-*.log 1> /dev/null 2>&1; then
        latest_log=$(ls -t logs/miner-*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            # 检查最近的挖矿活动
            recent_mining=$(grep "%mining-on" "$latest_log" | tail -5)
            if [ -n "$recent_mining" ]; then
                mining_count=$(echo "$recent_mining" | wc -l)
                last_mining=$(echo "$recent_mining" | tail -1 | awk '{print $2}' | tr -d '()')
                echo "✓ 挖矿活动: 正常"
                echo "  最近挖矿: $last_mining"
                echo "  活动次数: $mining_count (最近5次)"
            else
                echo "✗ 挖矿活动: 无挖矿记录"
            fi
        else
            echo "✗ 挖矿活动: 无日志文件"
        fi
    else
        echo "✗ 挖矿活动: 无日志文件"
    fi
}

# 检查网络连接
check_network_status() {
    if ls logs/miner-*.log 1> /dev/null 2>&1; then
        latest_log=$(ls -t logs/miner-*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            # 检查P2P连接
            p2p_connections=$(netstat -an 2>/dev/null | grep :4001 | wc -l)

            # 检查最近的网络活动
            recent_network=$(grep -i "peer\|connection" "$latest_log" | tail -3)

            if [ "$p2p_connections" -gt 0 ]; then
                echo "✓ 网络连接: 正常"
                echo "  P2P连接数: $p2p_connections"
            else
                echo "⚠ 网络连接: 连接较少"
                echo "  P2P连接数: $p2p_connections"
            fi

            # 显示最近的网络活动
            if [ -n "$recent_network" ]; then
                echo "  最近活动: $(echo "$recent_network" | tail -1 | awk '{print $2}' | tr -d '()')"
            fi
        else
            echo "✗ 网络连接: 无日志文件"
        fi
    else
        echo "✗ 网络连接: 无日志文件"
    fi
}

# 检查时间锁状态
check_timelock_status() {
    if ls logs/miner-*.log 1> /dev/null 2>&1; then
        latest_log=$(ls -t logs/miner-*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            # 检查最近的时间锁检查
            recent_timelock=$(grep "timelock check" "$latest_log" | tail -5)
            if [ -n "$recent_timelock" ]; then
                failed_count=$(echo "$recent_timelock" | grep "failed" | wc -l)
                last_timelock=$(echo "$recent_timelock" | tail -1 | awk '{print $2}' | tr -d '()')

                if [ "$failed_count" -gt 0 ]; then
                    echo "✓ 时间锁: 正常 (遵守网络规则)"
                    echo "  最近检查: $last_timelock"
                    echo "  失败次数: $failed_count (正常现象)"
                else
                    echo "⚠ 时间锁: 无失败记录"
                    echo "  最近检查: $last_timelock"
                fi
            else
                echo "⚠ 时间锁: 无检查记录"
            fi
        else
            echo "✗ 时间锁: 无日志文件"
        fi
    else
        echo "✗ 时间锁: 无日志文件"
    fi
}

# 执行所有检查
check_block_sync
check_mining_activity
check_network_status
check_timelock_status

echo ""
echo "=== 系统资源 ==="
echo "CPU 使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "内存使用: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "磁盘使用: $(df -h / | tail -1 | awk '{print $5}')"
echo "系统负载: $(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')"

# 日志行数参数（默认10行，可通过参数调整）
LOG_LINES=${1:-10}

echo ""
echo "=== 最新日志 (最近${LOG_LINES}行) ==="
if ls logs/miner-*.log 1> /dev/null 2>&1; then
    latest_log=$(ls -t logs/miner-*.log 2>/dev/null | head -1)
    if [ -n "$latest_log" ]; then
        echo "日志文件: $(basename "$latest_log")"
        echo "文件大小: $(du -h "$latest_log" | cut -f1) | 最后修改: $(stat -c %y "$latest_log" 2>/dev/null | cut -d. -f1 || echo "未知")"
        echo "----------------------------------------"
        tail -${LOG_LINES} "$latest_log"
        echo "----------------------------------------"
        echo ""
        echo "💡 更多操作:"
        echo "   ./check-status.sh 100     # 查看更多日志"
        echo "   tail -f $latest_log       # 实时日志"
        echo "   ./quick-log-viewer.sh mining  # 查看挖矿日志"
    else
        echo "未找到日志文件"
    fi
else
    echo "未找到日志文件"
    echo "提示: 请确保挖矿节点已启动并生成日志"
fi
EOF

    # 设置执行权限
    chmod +x start-miner.sh start-node.sh check-status.sh
    
    log "启动脚本创建完成"
}

# 创建系统服务
create_service() {
    log "创建系统服务..."
    
    sudo tee /etc/systemd/system/nockchain-miner.service > /dev/null <<EOF
[Unit]
Description=Nockchain Miner Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.cargo/bin
Environment=HOME=$HOME
ExecStart=$INSTALL_DIR/start-miner.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable nockchain-miner
    
    log "系统服务创建完成"
    info "启动服务: sudo systemctl start nockchain-miner"
    info "查看状态: sudo systemctl status nockchain-miner"
    info "查看日志: sudo journalctl -u nockchain-miner -f"
}



# 清理 Nockchain 相关文件
cleanup_nockchain() {
    log "清理 Nockchain 相关文件..."

    cd "$INSTALL_DIR"

    # 停止所有相关进程
    pkill -f "nockchain" 2>/dev/null || true
    sleep 2

    # 清理 socket 文件
    if [ -d ".socket" ]; then
        log "清理 socket 文件..."
        rm -f .socket/*.sock
        log "Socket 文件已清理"
    fi

    # 清理锁文件
    if [ -f ".data.nockchain/LOCK" ]; then
        log "清理数据库锁文件..."
        rm -f .data.nockchain/LOCK
        log "锁文件已清理"
    fi

    # 清理临时文件
    rm -f .data.nockchain/*.tmp 2>/dev/null || true

    log "清理完成"
}

# 显示状态
show_status() {
    cd "$INSTALL_DIR" 2>/dev/null || {
        error "找不到安装目录: $INSTALL_DIR"
        exit 1
    }
    
    ./check-status.sh
}

# 主函数
main() {
    show_banner
    
    case "${1:-install}" in
        install)
            check_system
            install_dependencies
            install_rust
            setup_project
            build_project
            configure_firewall
            create_scripts
            info "安装完成！接下来请运行:"
            info "1. $0 keygen    # 生成挖矿密钥"
            info "2. nano $INSTALL_DIR/.env  # 编辑配置文件"
            info "3. cd $INSTALL_DIR && ./start-miner.sh  # 启动挖矿"
            info "   或者: $0 service && sudo systemctl start nockchain-miner  # 系统服务方式"
            ;;
        install-skip-build)
            log "快速安装模式 (跳过编译)"
            check_system
            # 跳过 install_dependencies 和 install_rust（假设已安装）
            setup_project_skip_build
            configure_firewall
            create_scripts
            info "快速安装完成！接下来请运行:"
            info "1. $0 keygen    # 生成挖矿密钥"
            info "2. nano $INSTALL_DIR/.env  # 编辑配置文件"
            info "3. cd $INSTALL_DIR && ./start-miner.sh  # 启动挖矿"
            info "   或者: $0 service && sudo systemctl start nockchain-miner  # 系统服务方式"
            warn "注意: 此模式假设 Rust 环境和 nockchain 二进制文件已存在"
            ;;
        update-scripts)
            log "更新附属脚本"
            check_system
            create_scripts
            info "脚本更新完成！"
            info "新的启动脚本已生成到: $INSTALL_DIR"
            ;;
        keygen)
            check_system  # 确保 INSTALL_DIR 被正确设置
            generate_keys
            ;;

        stop)
            check_system  # 确保 INSTALL_DIR 被正确设置
            log "停止 Nockchain 挖矿节点..."

            cd "$INSTALL_DIR"

            # 停止 screen 会话
            screen -S nockchain-miner -X quit 2>/dev/null

            # 强制停止进程
            pkill -f "nockchain.*--mine" 2>/dev/null
            pkill -f "nockchain" 2>/dev/null

            # 等待进程完全停止
            sleep 2

            # 清理 socket 文件
            if [ -d ".socket" ]; then
                log "清理 socket 文件..."
                rm -f .socket/*.sock
                log "Socket 文件已清理"
            fi

            # 清理可能的锁文件
            if [ -f ".data.nockchain/LOCK" ]; then
                log "清理数据库锁文件..."
                rm -f .data.nockchain/LOCK
            fi

            log "挖矿节点已停止并清理完成"
            ;;
        status)
            check_system  # 确保 INSTALL_DIR 被正确设置
            show_status
            ;;
        service)
            check_system  # 确保 INSTALL_DIR 被正确设置
            create_service
            ;;
        logs)
            check_system  # 确保 INSTALL_DIR 被正确设置
            cd "$INSTALL_DIR"
            echo "查看 Nockchain 日志文件:"
            echo ""
            if [ -d "logs" ] && [ "$(ls -A logs/)" ]; then
                echo "可用的日志文件:"
                ls -la logs/
                echo ""
                echo "查看最新挖矿日志:"
                latest_log=$(ls -t logs/miner-*.log 2>/dev/null | head -1)
                if [ -n "$latest_log" ]; then
                    echo "文件: $latest_log"
                    echo "最近20行:"
                    tail -20 "$latest_log"
                else
                    echo "未找到挖矿日志文件"
                fi
            else
                echo "日志目录为空或不存在"
            fi
            ;;
        cleanup)
            check_system  # 确保 INSTALL_DIR 被正确设置
            cleanup_nockchain
            ;;
        help|*)
            echo "用法: $0 [命令]"
            echo ""
            echo "安装命令:"
            echo "  install           - 完整安装和配置环境 (默认)"
            echo "  install-skip-build - 快速安装 (跳过编译，适用于已编译环境)"
            echo "  update-scripts    - 仅更新附属脚本 (不重新编译)"
            echo ""
            echo "管理命令:"
            echo "  keygen   - 生成挖矿密钥"
            echo "  stop     - 停止挖矿服务"
            echo "  cleanup  - 清理 socket 文件和锁文件"
            echo "  status   - 查看服务状态"
            echo "  service  - 创建系统服务"
            echo "  logs     - 查看日志"
            echo "  help     - 显示此帮助信息"
            echo ""
            echo "启动挖矿方式:"
            echo "  方式1: cd $INSTALL_DIR && ./start-miner.sh"
            echo "  方式2: sudo systemctl start nockchain-miner"
            echo ""
            echo "使用场景:"
            echo "  首次部署:     $0 install"
            echo "  快速部署:     $0 install-skip-build"
            echo "  更新脚本:     $0 update-scripts"
            echo "  生成密钥:     $0 keygen"
            echo "  启动挖矿:     cd $INSTALL_DIR && ./start-miner.sh"
            exit 1
            ;;
    esac
}

main "$@"
