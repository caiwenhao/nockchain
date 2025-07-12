#!/bin/bash

# Nockchain 一体化部署脚本
# 打包 → 分发 → 远程部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

show_banner() {
    echo -e "${BLUE}"
    echo "    ╔═══════════════════════════════════════╗"
    echo "    ║     Nockchain 一体化部署工具          ║"
    echo "    ║   打包 → 分发 → 远程部署              ║"
    echo "    ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

# 配置
PACKAGE_NAME="nockchain-$(date +%Y%m%d-%H%M%S)"
TEMP_DIR="/tmp/$PACKAGE_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 服务器列表 (可以通过参数或配置文件指定)
SERVERS_FILE="${SCRIPT_DIR}/servers.txt"
DEFAULT_USER="root"
REMOTE_DIR="/root/nockchain"

# 显示用法
show_usage() {
    echo "用法: $0 [选项] [服务器列表]"
    echo ""
    echo "选项:"
    echo "  -u USER     SSH 用户名 (默认: $DEFAULT_USER)"
    echo "  -d DIR      远程安装目录 (默认: $REMOTE_DIR)"
    echo "  -f FILE     服务器列表文件 (默认: $SERVERS_FILE)"
    echo "  -h          显示帮助"
    echo ""
    echo "服务器列表格式:"
    echo "  方法1: 命令行参数: $0 server1 server2 server3"
    echo "  方法2: 文件 servers.txt，每行一个服务器IP/域名"
    echo ""
    echo "示例:"
    echo "  $0 192.168.1.100 192.168.1.101"
    echo "  $0 -u ubuntu -d /home/ubuntu/nockchain server1.com server2.com"
}

# 解析命令行参数
parse_args() {
    SERVERS=()
    SSH_USER="$DEFAULT_USER"
    INSTALL_DIR="$REMOTE_DIR"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -d|--dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -f|--file)
                SERVERS_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                error "未知选项: $1"
                show_usage
                exit 1
                ;;
            *)
                SERVERS+=("$1")
                shift
                ;;
        esac
    done
    
    # 如果没有命令行指定服务器，尝试从文件读取
    if [ ${#SERVERS[@]} -eq 0 ] && [ -f "$SERVERS_FILE" ]; then
        log "从文件读取服务器列表: $SERVERS_FILE"
        while IFS= read -r line; do
            # 跳过空行和注释
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            SERVERS+=("$line")
        done < "$SERVERS_FILE"
    fi
    
    if [ ${#SERVERS[@]} -eq 0 ]; then
        error "未指定服务器列表"
        show_usage
        exit 1
    fi
    
    log "目标服务器 (${#SERVERS[@]}台): ${SERVERS[*]}"
    log "SSH 用户: $SSH_USER"
    log "安装目录: $INSTALL_DIR"
}

# 检查本地环境
check_local_environment() {
    log "检查本地环境..."
    
    # 检查是否有已编译的二进制文件
    if [ ! -d "$HOME/.cargo/bin" ]; then
        error "未找到 ~/.cargo/bin 目录"
        error "请先运行 ./native-deploy.sh install 完成编译"
        exit 1
    fi
    
    local missing_files=()
    for binary in nockchain hoonc; do
        if [ ! -f "$HOME/.cargo/bin/$binary" ]; then
            missing_files+=("$binary")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        error "缺少二进制文件: ${missing_files[*]}"
        error "请先运行 ./native-deploy.sh install 完成编译"
        exit 1
    fi
    
    # 检查 SSH 连接
    log "测试 SSH 连接..."
    local failed_servers=()
    for server in "${SERVERS[@]}"; do
        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_USER@$server" "echo 'SSH OK'" &>/dev/null; then
            failed_servers+=("$server")
        fi
    done
    
    if [ ${#failed_servers[@]} -gt 0 ]; then
        error "无法连接到服务器: ${failed_servers[*]}"
        error "请检查 SSH 密钥配置"
        exit 1
    fi
    
    log "✅ 本地环境检查通过"
}

# 创建部署包
create_package() {
    log "创建部署包..."
    
    # 清理并创建临时目录
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"/{bin,scripts}
    
    # 复制二进制文件
    cp "$HOME/.cargo/bin"/nockchain* "$TEMP_DIR/bin/" 2>/dev/null || true
    cp "$HOME/.cargo/bin"/hoonc "$TEMP_DIR/bin/" 2>/dev/null || true
    
    # 复制配置文件
    local project_root="$(dirname "$SCRIPT_DIR")"
    cp "$project_root/.env_example" "$TEMP_DIR/.env_example" 2>/dev/null || true
    
    # 创建远程安装脚本
    cat > "$TEMP_DIR/remote-install.sh" << 'EOF'
#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

INSTALL_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "开始安装 Nockchain..."

# 创建目录
mkdir -p "$HOME/.cargo/bin"
mkdir -p "$INSTALL_DIR"/{logs,.data.nockchain}

# 安装二进制文件
if [ -d "$SCRIPT_DIR/bin" ]; then
    cp "$SCRIPT_DIR/bin"/* "$HOME/.cargo/bin/"
    chmod +x "$HOME/.cargo/bin"/nockchain*
    chmod +x "$HOME/.cargo/bin"/hoonc
    log "✅ 二进制文件安装完成"
fi

# 复制配置
if [ -f "$SCRIPT_DIR/.env_example" ]; then
    cp "$SCRIPT_DIR/.env_example" "$INSTALL_DIR/"
fi

# 更新 PATH
if ! grep -q ".cargo/bin" ~/.bashrc; then
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
fi

# 创建启动脚本
cat > "$INSTALL_DIR/start-miner.sh" << 'INNER_EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi
export RUST_BACKTRACE=${RUST_BACKTRACE:-full}
export RUST_LOG=${RUST_LOG:-info}
mkdir -p logs
pkill -f nockchain || true
rm -f .data.nockchain/*.lock 2>/dev/null || true
nockchain 2>&1 | tee logs/node-$(date +%Y%m%d-%H%M%S).log
INNER_EOF

chmod +x "$INSTALL_DIR/start-miner.sh"

# 生成密钥
log "生成挖矿密钥..."
export PATH="$HOME/.cargo/bin:$PATH"
cd "$INSTALL_DIR"

if nockchain-wallet keygen > keygen_output.txt 2>&1; then
    pubkey=$(grep -o '[0-9a-zA-Z]\{88\}' keygen_output.txt | head -1)
    if [ -n "$pubkey" ]; then
        cat > .env << INNER_EOF
MINING_PUBKEY=$pubkey
RUST_BACKTRACE=full
RUST_LOG=info
MINIMAL_LOG_FORMAT=true
INNER_EOF
        log "✅ 密钥生成成功: $pubkey"
    fi
    rm -f keygen_output.txt
fi

# 配置防火墙
if command -v ufw &>/dev/null; then
    ufw --force enable
    ufw allow ssh
    ufw allow 4001/udp
    log "✅ 防火墙配置完成"
fi

log "🎉 Nockchain 安装完成！"
log "启动命令: cd $INSTALL_DIR && ./start-miner.sh"
EOF

    chmod +x "$TEMP_DIR/remote-install.sh"
    
    # 创建压缩包
    cd "$(dirname "$TEMP_DIR")"
    tar -czf "${PACKAGE_NAME}.tar.gz" "$(basename "$TEMP_DIR")"
    
    log "✅ 部署包创建完成: ${PACKAGE_NAME}.tar.gz"
}

# 分发并部署到服务器
deploy_to_servers() {
    log "开始分发和部署..."
    
    local package_path="$(dirname "$TEMP_DIR")/${PACKAGE_NAME}.tar.gz"
    local success_count=0
    local failed_servers=()
    
    for server in "${SERVERS[@]}"; do
        log "部署到服务器: $server"
        
        if deploy_to_single_server "$server" "$package_path"; then
            log "✅ $server 部署成功"
            ((success_count++))
        else
            error "❌ $server 部署失败"
            failed_servers+=("$server")
        fi
        echo ""
    done
    
    # 清理临时文件
    rm -rf "$TEMP_DIR" "$package_path"
    
    # 显示结果
    info "部署完成！"
    info "成功: $success_count/${#SERVERS[@]} 台服务器"
    
    if [ ${#failed_servers[@]} -gt 0 ]; then
        warn "失败的服务器: ${failed_servers[*]}"
        exit 1
    fi
}

# 部署到单个服务器
deploy_to_single_server() {
    local server="$1"
    local package_path="$2"
    
    {
        # 上传包
        scp "$package_path" "$SSH_USER@$server:/tmp/"
        
        # 远程执行安装
        ssh "$SSH_USER@$server" "
            cd /tmp
            tar -xzf $(basename "$package_path")
            cd $(basename "$package_path" .tar.gz)
            ./remote-install.sh '$INSTALL_DIR'
            rm -rf /tmp/$(basename "$package_path")*
        "
    } &>/dev/null
}

# 主函数
main() {
    show_banner
    parse_args "$@"
    check_local_environment
    create_package
    deploy_to_servers
    
    info "🎉 所有服务器部署完成！"
    info ""
    info "在各服务器上启动挖矿:"
    for server in "${SERVERS[@]}"; do
        info "ssh $SSH_USER@$server 'cd $INSTALL_DIR && ./start-miner.sh'"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
