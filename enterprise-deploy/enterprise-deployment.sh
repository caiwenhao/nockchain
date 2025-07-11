#!/bin/bash

# Nockchain 企业级1000节点部署脚本
# 专为大规模挖矿集群设计

set -e

# 配置变量
TOTAL_NODES=1000
NODES_PER_BATCH=50
MASTER_KEY_DIR="$HOME/nockchain-master-keys"
DEPLOYMENT_LOG="$HOME/nockchain-deployment.log"
SERVERS_LIST="$HOME/servers.txt"  # 服务器IP列表文件

# 火山云快照配置
VOLCANO_ENDPOINT="https://tos-s3-cn-beijing.volces.com"
VOLCANO_BUCKET="nockchain-snapshots"
VOLCANO_ACCESS_KEY=""  # 需要配置
VOLCANO_SECRET_KEY=""  # 需要配置

# SSH配置
SSH_USER="ubuntu"
SSH_KEY="$HOME/.ssh/nockchain_deploy_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1" | tee -a "$DEPLOYMENT_LOG"; }

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════╗
    ║           Nockchain 企业级1000节点部署系统                ║
    ║         Enterprise 1000-Node Deployment System          ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 检查前置条件
check_prerequisites() {
    log "检查部署前置条件..."
    
    # 检查服务器列表文件
    if [ ! -f "$SERVERS_LIST" ]; then
        error "服务器列表文件不存在: $SERVERS_LIST"
        info "请创建包含服务器IP的文件，每行一个IP地址"
        exit 1
    fi
    
    local server_count=$(wc -l < "$SERVERS_LIST")
    if [ "$server_count" -lt "$TOTAL_NODES" ]; then
        error "服务器数量不足: 需要$TOTAL_NODES个，实际$server_count个"
        exit 1
    fi
    
    # 检查SSH密钥
    if [ ! -f "$SSH_KEY" ]; then
        warn "SSH密钥不存在: $SSH_KEY"
        info "将使用默认SSH配置"
        SSH_KEY=""
    fi
    
    # 检查必要工具
    for tool in parallel aws; do
        if ! command -v $tool &> /dev/null; then
            error "缺少必要工具: $tool"
            info "请安装: sudo apt install $tool"
            exit 1
        fi
    done
    
    log "前置条件检查完成"
}

# 策略选择
choose_strategy() {
    echo -e "${CYAN}=== 选择部署策略 ===${NC}"
    echo "1. 单一密钥策略 (所有节点使用同一个挖矿地址)"
    echo "2. 分组密钥策略 (每10个节点一个密钥，共100个密钥)"
    echo "3. 独立密钥策略 (每个节点独立密钥，共1000个密钥)"
    echo ""
    read -p "请选择策略 (1-3): " strategy
    
    case $strategy in
        1)
            STRATEGY="single"
            KEY_COUNT=1
            log "选择策略: 单一密钥 (1个密钥)"
            ;;
        2)
            STRATEGY="grouped"
            KEY_COUNT=100
            NODES_PER_KEY=10
            log "选择策略: 分组密钥 (100个密钥，每个管理10个节点)"
            ;;
        3)
            STRATEGY="individual"
            KEY_COUNT=1000
            log "选择策略: 独立密钥 (1000个密钥)"
            ;;
        *)
            error "无效选择"
            exit 1
            ;;
    esac
}

# 生成主密钥
generate_master_keys() {
    log "生成主密钥集合..."
    
    mkdir -p "$MASTER_KEY_DIR"
    chmod 700 "$MASTER_KEY_DIR"
    
    # 创建密钥生成脚本
    cat > "$MASTER_KEY_DIR/generate_keys.sh" << 'EOF'
#!/bin/bash
cd ~/nockchain
for i in $(seq 1 $1); do
    echo "生成密钥 $i/$1..."
    output=$(nockchain-wallet keygen 2>&1)
    pubkey=$(echo "$output" | grep "Public Key:" | cut -d' ' -f3)
    
    if [ -n "$pubkey" ]; then
        echo "KEY_$i=$pubkey" >> /tmp/generated_keys.txt
        echo "$output" > "/tmp/key_${i}_full.txt"
        echo "密钥 $i 生成完成: $pubkey"
    else
        echo "密钥 $i 生成失败"
    fi
done
EOF
    
    chmod +x "$MASTER_KEY_DIR/generate_keys.sh"
    
    # 在本地生成密钥
    log "开始生成 $KEY_COUNT 个密钥..."
    
    cd ~/nockchain
    rm -f /tmp/generated_keys.txt
    
    for i in $(seq 1 $KEY_COUNT); do
        info "生成密钥 $i/$KEY_COUNT..."
        
        output=$(nockchain-wallet keygen 2>&1)
        pubkey=$(echo "$output" | grep "Public Key:" | cut -d' ' -f3)
        
        if [ -n "$pubkey" ]; then
            echo "KEY_$i=$pubkey" >> "$MASTER_KEY_DIR/keys.txt"
            echo "$output" > "$MASTER_KEY_DIR/key_${i}_full.txt"
            
            # 创建单独的配置文件
            cat > "$MASTER_KEY_DIR/key_${i}.env" << ENVEOF
MINING_PUBKEY=$pubkey
RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info
MINIMAL_LOG_FORMAT=true
ENVEOF
            
        else
            error "密钥 $i 生成失败"
        fi
        
        # 每生成10个密钥显示一次进度
        if [ $((i % 10)) -eq 0 ]; then
            log "已生成 $i/$KEY_COUNT 个密钥"
        fi
    done
    
    log "主密钥生成完成: $KEY_COUNT 个密钥"
    info "密钥文件保存在: $MASTER_KEY_DIR"
}

# 创建部署包
create_deployment_package() {
    log "创建部署包..."
    
    local package_dir="$HOME/nockchain-deployment-package"
    rm -rf "$package_dir"
    mkdir -p "$package_dir"
    
    # 复制核心文件
    cp native-deploy.sh "$package_dir/"
    cp native-monitor.sh "$package_dir/"
    cp simple-snapshot-solution.sh "$package_dir/"
    cp -r nockchain "$package_dir/" 2>/dev/null || true
    
    # 创建自动部署脚本
    cat > "$package_dir/auto-deploy.sh" << 'EOF'
#!/bin/bash
set -e

NODE_ID="$1"
MINING_PUBKEY="$2"

log() { echo "[$(date +'%H:%M:%S')] $1"; }

log "开始部署节点 $NODE_ID..."

# 设置执行权限
chmod +x native-deploy.sh native-monitor.sh simple-snapshot-solution.sh

# 安装环境
log "安装基础环境..."
./native-deploy.sh install

# 配置挖矿密钥
log "配置挖矿密钥: $MINING_PUBKEY"
cat > ~/nockchain/.env << ENVEOF
MINING_PUBKEY=$MINING_PUBKEY
RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info
MINIMAL_LOG_FORMAT=true
ENVEOF

# 下载快照（如果可用）
log "尝试下载快照..."
if ./simple-snapshot-solution.sh download 2>/dev/null; then
    log "快照下载成功"
else
    log "快照下载失败，将进行完整同步"
fi

# 启动挖矿
log "启动挖矿节点..."
./native-deploy.sh start

log "节点 $NODE_ID 部署完成"
EOF
    
    chmod +x "$package_dir/auto-deploy.sh"
    
    # 创建压缩包
    cd "$HOME"
    tar -czf nockchain-deployment-package.tar.gz -C "$package_dir" .
    
    log "部署包创建完成: $HOME/nockchain-deployment-package.tar.gz"
}

# 分配密钥给节点
assign_keys_to_nodes() {
    log "分配密钥给节点..."
    
    local assignment_file="$MASTER_KEY_DIR/node_assignments.txt"
    rm -f "$assignment_file"
    
    local node_index=1
    
    while IFS= read -r server_ip; do
        case $STRATEGY in
            "single")
                local key_id=1
                ;;
            "grouped")
                local key_id=$(( (node_index - 1) / NODES_PER_KEY + 1 ))
                ;;
            "individual")
                local key_id=$node_index
                ;;
        esac
        
        local pubkey=$(grep "KEY_$key_id=" "$MASTER_KEY_DIR/keys.txt" | cut -d'=' -f2)
        
        echo "$server_ip,node_$node_index,$key_id,$pubkey" >> "$assignment_file"
        
        ((node_index++))
        if [ $node_index -gt $TOTAL_NODES ]; then
            break
        fi
    done < "$SERVERS_LIST"
    
    log "密钥分配完成: $assignment_file"
}

# 批量部署
batch_deploy() {
    log "开始批量部署 $TOTAL_NODES 个节点..."
    
    local assignment_file="$MASTER_KEY_DIR/node_assignments.txt"
    local batch_count=0
    local total_batches=$(( (TOTAL_NODES + NODES_PER_BATCH - 1) / NODES_PER_BATCH ))
    
    # 创建部署函数
    deploy_single_node() {
        local line="$1"
        IFS=',' read -r server_ip node_id key_id pubkey <<< "$line"
        
        local ssh_cmd="ssh"
        if [ -n "$SSH_KEY" ]; then
            ssh_cmd="ssh -i $SSH_KEY"
        fi
        ssh_cmd="$ssh_cmd $SSH_OPTS $SSH_USER@$server_ip"
        
        echo "[$(date +'%H:%M:%S')] 部署节点 $node_id 到服务器 $server_ip..."
        
        # 上传部署包
        if [ -n "$SSH_KEY" ]; then
            scp -i "$SSH_KEY" $SSH_OPTS "$HOME/nockchain-deployment-package.tar.gz" "$SSH_USER@$server_ip:~/"
        else
            scp $SSH_OPTS "$HOME/nockchain-deployment-package.tar.gz" "$SSH_USER@$server_ip:~/"
        fi
        
        # 远程执行部署
        $ssh_cmd << REMOTE_SCRIPT
set -e
cd ~
tar -xzf nockchain-deployment-package.tar.gz
./auto-deploy.sh "$node_id" "$pubkey"
REMOTE_SCRIPT
        
        if [ $? -eq 0 ]; then
            echo "[$(date +'%H:%M:%S')] ✓ 节点 $node_id 部署成功"
            echo "$server_ip,$node_id,SUCCESS,$(date)" >> "$MASTER_KEY_DIR/deployment_results.txt"
        else
            echo "[$(date +'%H:%M:%S')] ✗ 节点 $node_id 部署失败"
            echo "$server_ip,$node_id,FAILED,$(date)" >> "$MASTER_KEY_DIR/deployment_results.txt"
        fi
    }
    
    export -f deploy_single_node
    export SSH_USER SSH_KEY SSH_OPTS MASTER_KEY_DIR
    
    # 分批并行部署
    while IFS= read -r line; do
        echo "$line"
    done < "$assignment_file" | parallel -j "$NODES_PER_BATCH" deploy_single_node
    
    log "批量部署完成"
}

# 检查部署状态
check_deployment_status() {
    log "检查部署状态..."
    
    local results_file="$MASTER_KEY_DIR/deployment_results.txt"
    if [ ! -f "$results_file" ]; then
        warn "未找到部署结果文件"
        return
    fi
    
    local total_deployed=$(wc -l < "$results_file")
    local successful=$(grep ",SUCCESS," "$results_file" | wc -l)
    local failed=$(grep ",FAILED," "$results_file" | wc -l)
    
    echo -e "\n${CYAN}=== 部署状态统计 ===${NC}"
    echo "总计部署: $total_deployed 个节点"
    echo "成功部署: $successful 个节点"
    echo "部署失败: $failed 个节点"
    echo "成功率: $(( successful * 100 / total_deployed ))%"
    
    if [ $failed -gt 0 ]; then
        echo -e "\n${YELLOW}失败的节点:${NC}"
        grep ",FAILED," "$results_file" | while IFS=',' read -r ip node_id status timestamp; do
            echo "  $node_id ($ip) - $timestamp"
        done
    fi
}

# 批量监控
batch_monitor() {
    log "启动批量监控..."
    
    local assignment_file="$MASTER_KEY_DIR/node_assignments.txt"
    local monitor_results="$MASTER_KEY_DIR/monitor_results_$(date +%Y%m%d_%H%M%S).txt"
    
    # 创建监控函数
    monitor_single_node() {
        local line="$1"
        IFS=',' read -r server_ip node_id key_id pubkey <<< "$line"
        
        local ssh_cmd="ssh"
        if [ -n "$SSH_KEY" ]; then
            ssh_cmd="ssh -i $SSH_KEY"
        fi
        ssh_cmd="$ssh_cmd $SSH_OPTS $SSH_USER@$server_ip"
        
        # 检查节点状态
        local status=$($ssh_cmd "pgrep -f 'nockchain.*--mine' > /dev/null && echo 'RUNNING' || echo 'STOPPED'" 2>/dev/null || echo "UNREACHABLE")
        local height=$($ssh_cmd "grep 'block.*added to validated blocks' ~/nockchain/logs/miner-*.log 2>/dev/null | tail -1 | awk '{print \$NF}'" 2>/dev/null || echo "0")
        local connections=$($ssh_cmd "netstat -an 2>/dev/null | grep :4001 | wc -l" 2>/dev/null || echo "0")
        
        echo "$server_ip,$node_id,$status,$height,$connections,$(date)" >> "$monitor_results"
        echo "[$node_id] $server_ip: $status (高度: $height, 连接: $connections)"
    }
    
    export -f monitor_single_node
    export SSH_USER SSH_KEY SSH_OPTS monitor_results
    
    # 并行监控
    cat "$assignment_file" | parallel -j 50 monitor_single_node
    
    log "监控结果保存到: $monitor_results"
}

# 显示帮助
show_help() {
    echo "Nockchain 企业级1000节点部署工具"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令说明:"
    echo "  prepare   - 准备部署 (生成密钥、创建部署包)"
    echo "  deploy    - 执行批量部署"
    echo "  status    - 检查部署状态"
    echo "  monitor   - 批量监控节点"
    echo "  help      - 显示此帮助信息"
    echo ""
    echo "部署流程:"
    echo "1. 准备服务器列表文件: $SERVERS_LIST"
    echo "2. 运行: $0 prepare"
    echo "3. 运行: $0 deploy"
    echo "4. 运行: $0 status"
    echo "5. 运行: $0 monitor"
}

# 主函数
main() {
    show_banner
    
    case "${1:-help}" in
        prepare)
            check_prerequisites
            choose_strategy
            generate_master_keys
            create_deployment_package
            assign_keys_to_nodes
            log "准备工作完成！现在可以运行: $0 deploy"
            ;;
        deploy)
            check_prerequisites
            batch_deploy
            check_deployment_status
            ;;
        status)
            check_deployment_status
            ;;
        monitor)
            batch_monitor
            ;;
        help)
            show_help
            ;;
        *)
            error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
