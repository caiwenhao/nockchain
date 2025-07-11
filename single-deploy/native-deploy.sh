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
    sudo apt install -y \
        curl \
        wget \
        git \
        build-essential \
        clang \
        llvm-dev \
        libclang-dev \
        pkg-config \
        make \
        htop \
        net-tools \
        ufw \
        screen \
        tmux
    
    log "系统依赖安装完成"
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

# 克隆或更新项目
setup_project() {
    log "设置项目目录..."
    
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
        cp .env_example .env
        log "已创建 .env 配置文件"
    fi
    
    # 构建项目
    log "开始编译，这可能需要几分钟..."
    make build
    
    # 安装组件
    log "安装 hoonc 编译器..."
    make install-hoonc
    
    log "安装 nockchain 主程序..."
    make install-nockchain
    
    log "安装 nockchain-wallet 钱包..."
    make install-nockchain-wallet
    
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
    
    cd "$INSTALL_DIR"
    
    info "正在生成新的密钥对..."
    nockchain-wallet keygen
    
    warn "请将上面显示的公钥复制到 .env 文件中的 MINING_PUBKEY 变量"
    info "编辑命令: nano $INSTALL_DIR/.env"
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
num_threads=$((total_threads > 4 ? total_threads * 2 - 4 : total_threads))

echo "启动 Nockchain 挖矿节点..."
echo "使用 $num_threads 个挖矿线程 (总CPU核心: $total_threads)"
echo "挖矿公钥: $MINING_PUBKEY"
echo "日志级别: $RUST_LOG"
echo "================================"

# 创建日志目录
mkdir -p logs

# 启动挖矿
nockchain --mining-pubkey "${MINING_PUBKEY}" --mine --num-threads $num_threads 2>&1 | tee logs/miner-$(date +%Y%m%d-%H%M%S).log
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

# 创建日志目录
mkdir -p logs

# 启动节点
nockchain 2>&1 | tee logs/node-$(date +%Y%m%d-%H%M%S).log
EOF

    # 创建后台启动脚本
    cat > start-miner-daemon.sh << 'EOF'
#!/bin/bash

cd "$(dirname "$0")"

# 检查是否已经在运行
if pgrep -f "nockchain.*--mine" > /dev/null; then
    echo "挖矿节点已在运行中"
    exit 1
fi

echo "在后台启动挖矿节点..."

# 使用 screen 在后台运行
screen -dmS nockchain-miner bash -c './start-miner.sh'

echo "挖矿节点已在后台启动"
echo "查看状态: screen -r nockchain-miner"
echo "停止挖矿: screen -S nockchain-miner -X quit"
EOF

    # 创建停止脚本
    cat > stop-miner.sh << 'EOF'
#!/bin/bash

echo "停止 Nockchain 挖矿节点..."

# 停止 screen 会话
screen -S nockchain-miner -X quit 2>/dev/null

# 强制停止进程
pkill -f "nockchain.*--mine" 2>/dev/null

echo "挖矿节点已停止"
EOF

    # 创建状态检查脚本
    cat > check-status.sh << 'EOF'
#!/bin/bash

echo "=== Nockchain 节点状态 ==="
echo "时间: $(date)"
echo ""

# 检查进程
if pgrep -f "nockchain.*--mine" > /dev/null; then
    echo "✓ 挖矿节点: 运行中"
    echo "  PID: $(pgrep -f 'nockchain.*--mine')"
else
    echo "✗ 挖矿节点: 未运行"
fi

if pgrep -f "nockchain" | grep -v "nockchain.*--mine" > /dev/null; then
    echo "✓ 普通节点: 运行中"
else
    echo "✗ 普通节点: 未运行"
fi

echo ""
echo "=== 系统资源 ==="
echo "CPU 使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "内存使用: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "磁盘使用: $(df -h / | tail -1 | awk '{print $5}')"

echo ""
echo "=== 网络连接 ==="
echo "P2P 连接数: $(netstat -an 2>/dev/null | grep :4001 | wc -l)"

echo ""
echo "=== 最新日志 (最近5行) ==="
if [ -f logs/miner-*.log ]; then
    tail -5 logs/miner-*.log | tail -5
else
    echo "未找到日志文件"
fi
EOF

    # 设置执行权限
    chmod +x start-miner.sh start-node.sh start-miner-daemon.sh stop-miner.sh check-status.sh
    
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

# 启动挖矿
start_mining() {
    log "启动挖矿节点..."
    
    cd "$INSTALL_DIR"
    
    # 检查是否设置了挖矿公钥
    source .env
    if [ -z "$MINING_PUBKEY" ] || [ "$MINING_PUBKEY" = "请在此处填入您的挖矿公钥" ]; then
        error "请先设置挖矿公钥！"
        info "1. 生成密钥: $0 keygen"
        info "2. 编辑配置: nano $INSTALL_DIR/.env"
        exit 1
    fi
    
    # 启动挖矿
    ./start-miner-daemon.sh
    
    log "挖矿节点已启动"
    info "查看状态: ./check-status.sh"
    info "查看日志: screen -r nockchain-miner"
    info "停止挖矿: ./stop-miner.sh"
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
            info "3. $0 start     # 启动挖矿服务"
            ;;
        keygen)
            generate_keys
            ;;
        start)
            start_mining
            ;;
        stop)
            cd "$INSTALL_DIR"
            ./stop-miner.sh
            ;;
        status)
            show_status
            ;;
        service)
            create_service
            ;;
        logs)
            cd "$INSTALL_DIR"
            if screen -list | grep -q nockchain-miner; then
                screen -r nockchain-miner
            else
                echo "挖矿节点未在后台运行"
                echo "查看历史日志:"
                ls -la logs/
            fi
            ;;
        *)
            echo "用法: $0 [install|keygen|start|stop|status|service|logs]"
            echo ""
            echo "命令说明:"
            echo "  install - 安装和配置环境 (默认)"
            echo "  keygen  - 生成挖矿密钥"
            echo "  start   - 启动挖矿服务"
            echo "  stop    - 停止挖矿服务"
            echo "  status  - 查看服务状态"
            echo "  service - 创建系统服务"
            echo "  logs    - 查看日志"
            exit 1
            ;;
    esac
}

main "$@"
