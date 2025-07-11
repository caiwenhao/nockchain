#!/bin/bash

# Nockchain 1000节点集群管理系统
# 用于监控、维护和管理大规模挖矿集群

set -e

# 配置
CLUSTER_CONFIG="$HOME/nockchain-cluster"
SERVERS_LIST="$CLUSTER_CONFIG/servers.txt"
MASTER_KEY_DIR="$HOME/nockchain-master-keys"
MONITORING_LOG="$CLUSTER_CONFIG/monitoring.log"
DASHBOARD_PORT=8080

# SSH配置
SSH_USER="ubuntu"
SSH_KEY="$HOME/.ssh/nockchain_deploy_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $1"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1"; }

# 初始化集群配置
init_cluster() {
    log "初始化集群配置..."
    
    mkdir -p "$CLUSTER_CONFIG"
    
    if [ ! -f "$SERVERS_LIST" ]; then
        warn "服务器列表不存在，创建示例文件: $SERVERS_LIST"
        cat > "$SERVERS_LIST" << 'EOF'
# Nockchain 集群服务器列表
# 格式: IP地址,节点名称,区域,状态
# 示例:
# 192.168.1.100,node001,region1,active
# 192.168.1.101,node002,region1,active
EOF
        info "请编辑 $SERVERS_LIST 添加你的服务器信息"
        return
    fi
    
    log "集群配置初始化完成"
}

# 集群状态概览
cluster_overview() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  Nockchain 集群状态概览                      ║${NC}"
    echo -e "${CYAN}║                    $(date +'%Y-%m-%d %H:%M:%S')                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    if [ ! -f "$SERVERS_LIST" ]; then
        error "服务器列表文件不存在: $SERVERS_LIST"
        return 1
    fi
    
    local total_servers=$(grep -v '^#' "$SERVERS_LIST" | grep -v '^$' | wc -l)
    echo "总服务器数: $total_servers"
    
    # 快速状态检查
    local online=0
    local mining=0
    local syncing=0
    local offline=0
    
    echo ""
    echo "正在检查节点状态..."
    
    while IFS=',' read -r ip node_name region status; do
        if [[ "$ip" =~ ^#.*$ ]] || [ -z "$ip" ]; then
            continue
        fi
        
        local ssh_cmd="ssh"
        if [ -n "$SSH_KEY" ]; then
            ssh_cmd="ssh -i $SSH_KEY"
        fi
        ssh_cmd="$ssh_cmd $SSH_OPTS $SSH_USER@$ip"
        
        # 检查连接性
        if $ssh_cmd "exit" 2>/dev/null; then
            ((online++))
            
            # 检查挖矿状态
            if $ssh_cmd "pgrep -f 'nockchain.*--mine' > /dev/null" 2>/dev/null; then
                ((mining++))
                echo "✓ $node_name ($ip): 挖矿中"
            elif $ssh_cmd "pgrep -f 'nockchain' > /dev/null" 2>/dev/null; then
                ((syncing++))
                echo "⚡ $node_name ($ip): 同步中"
            else
                echo "⚠ $node_name ($ip): 在线但未运行"
            fi
        else
            ((offline++))
            echo "✗ $node_name ($ip): 离线"
        fi
    done < "$SERVERS_LIST"
    
    echo ""
    echo -e "${CYAN}=== 集群统计 ===${NC}"
    echo "在线节点: $online/$total_servers"
    echo "挖矿节点: $mining"
    echo "同步节点: $syncing"
    echo "离线节点: $offline"
    echo "集群健康度: $(( (online * 100) / total_servers ))%"
}

# 批量执行命令
batch_execute() {
    local command="$1"
    if [ -z "$command" ]; then
        error "请指定要执行的命令"
        return 1
    fi
    
    log "在所有节点执行命令: $command"
    
    local success=0
    local failed=0
    
    while IFS=',' read -r ip node_name region status; do
        if [[ "$ip" =~ ^#.*$ ]] || [ -z "$ip" ]; then
            continue
        fi
        
        local ssh_cmd="ssh"
        if [ -n "$SSH_KEY" ]; then
            ssh_cmd="ssh -i $SSH_KEY"
        fi
        ssh_cmd="$ssh_cmd $SSH_OPTS $SSH_USER@$ip"
        
        echo "[$node_name] 执行: $command"
        if $ssh_cmd "$command" 2>/dev/null; then
            echo "[$node_name] ✓ 成功"
            ((success++))
        else
            echo "[$node_name] ✗ 失败"
            ((failed++))
        fi
    done < "$SERVERS_LIST"
    
    log "批量执行完成: 成功 $success, 失败 $failed"
}

# 收集挖矿统计
collect_mining_stats() {
    log "收集挖矿统计数据..."
    
    local stats_file="$CLUSTER_CONFIG/mining_stats_$(date +%Y%m%d_%H%M%S).csv"
    echo "节点名称,IP地址,状态,区块高度,P2P连接,CPU使用率,内存使用率,挖矿线程" > "$stats_file"
    
    while IFS=',' read -r ip node_name region status; do
        if [[ "$ip" =~ ^#.*$ ]] || [ -z "$ip" ]; then
            continue
        fi
        
        local ssh_cmd="ssh"
        if [ -n "$SSH_KEY" ]; then
            ssh_cmd="ssh -i $SSH_KEY"
        fi
        ssh_cmd="$ssh_cmd $SSH_OPTS $SSH_USER@$ip"
        
        echo "收集 $node_name 的数据..."
        
        # 收集各种统计数据
        local node_status="OFFLINE"
        local block_height="0"
        local p2p_connections="0"
        local cpu_usage="0"
        local mem_usage="0"
        local mining_threads="0"
        
        if $ssh_cmd "exit" 2>/dev/null; then
            if $ssh_cmd "pgrep -f 'nockchain.*--mine' > /dev/null" 2>/dev/null; then
                node_status="MINING"
            elif $ssh_cmd "pgrep -f 'nockchain' > /dev/null" 2>/dev/null; then
                node_status="SYNCING"
            else
                node_status="ONLINE"
            fi
            
            # 获取区块高度
            block_height=$($ssh_cmd "grep 'block.*added to validated blocks' ~/nockchain/logs/miner-*.log 2>/dev/null | tail -1 | awk '{print \$NF}'" 2>/dev/null || echo "0")
            
            # 获取P2P连接数
            p2p_connections=$($ssh_cmd "netstat -an 2>/dev/null | grep :4001 | wc -l" 2>/dev/null || echo "0")
            
            # 获取CPU使用率
            cpu_usage=$($ssh_cmd "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" 2>/dev/null || echo "0")
            
            # 获取内存使用率
            mem_usage=$($ssh_cmd "free | grep Mem | awk '{printf(\"%.1f\"), \$3/\$2 * 100.0}'" 2>/dev/null || echo "0")
            
            # 获取挖矿线程数
            mining_threads=$($ssh_cmd "pgrep -f 'nockchain.*--mine' | wc -l" 2>/dev/null || echo "0")
        fi
        
        echo "$node_name,$ip,$node_status,$block_height,$p2p_connections,$cpu_usage,$mem_usage,$mining_threads" >> "$stats_file"
        
    done < "$SERVERS_LIST"
    
    log "统计数据收集完成: $stats_file"
    
    # 生成汇总报告
    generate_summary_report "$stats_file"
}

# 生成汇总报告
generate_summary_report() {
    local stats_file="$1"
    local report_file="${stats_file%.csv}_report.txt"
    
    {
        echo "Nockchain 集群挖矿报告"
        echo "生成时间: $(date)"
        echo "========================================"
        echo ""
        
        # 统计各种状态的节点数量
        local total=$(tail -n +2 "$stats_file" | wc -l)
        local mining=$(tail -n +2 "$stats_file" | grep ",MINING," | wc -l)
        local syncing=$(tail -n +2 "$stats_file" | grep ",SYNCING," | wc -l)
        local online=$(tail -n +2 "$stats_file" | grep ",ONLINE," | wc -l)
        local offline=$(tail -n +2 "$stats_file" | grep ",OFFLINE," | wc -l)
        
        echo "节点状态统计:"
        echo "  总节点数: $total"
        echo "  挖矿节点: $mining"
        echo "  同步节点: $syncing"
        echo "  在线节点: $online"
        echo "  离线节点: $offline"
        echo ""
        
        # 计算平均值
        if [ $mining -gt 0 ]; then
            local avg_height=$(tail -n +2 "$stats_file" | grep ",MINING," | cut -d',' -f4 | awk '{sum+=$1} END {printf("%.0f", sum/NR)}')
            local avg_connections=$(tail -n +2 "$stats_file" | grep ",MINING," | cut -d',' -f5 | awk '{sum+=$1} END {printf("%.1f", sum/NR)}')
            local avg_cpu=$(tail -n +2 "$stats_file" | grep ",MINING," | cut -d',' -f6 | awk '{sum+=$1} END {printf("%.1f", sum/NR)}')
            local avg_mem=$(tail -n +2 "$stats_file" | grep ",MINING," | cut -d',' -f7 | awk '{sum+=$1} END {printf("%.1f", sum/NR)}')
            
            echo "挖矿节点平均指标:"
            echo "  平均区块高度: $avg_height"
            echo "  平均P2P连接: $avg_connections"
            echo "  平均CPU使用: $avg_cpu%"
            echo "  平均内存使用: $avg_mem%"
            echo ""
        fi
        
        # 列出问题节点
        echo "需要关注的节点:"
        tail -n +2 "$stats_file" | while IFS=',' read -r name ip status height connections cpu mem threads; do
            if [ "$status" = "OFFLINE" ]; then
                echo "  $name ($ip): 离线"
            elif [ "$status" = "ONLINE" ] && [ "$threads" = "0" ]; then
                echo "  $name ($ip): 在线但未挖矿"
            elif [ "$connections" = "0" ] && [ "$status" = "MINING" ]; then
                echo "  $name ($ip): 挖矿但无P2P连接"
            fi
        done
        
    } > "$report_file"
    
    log "汇总报告生成完成: $report_file"
    
    # 显示报告内容
    echo ""
    cat "$report_file"
}

# 批量重启挖矿
batch_restart_mining() {
    log "批量重启挖矿服务..."
    
    local restart_command="cd ~/nockchain && ./stop-miner.sh && sleep 5 && ./start-miner-daemon.sh"
    
    batch_execute "$restart_command"
}

# 批量更新
batch_update() {
    log "批量更新节点..."
    
    local update_command="cd ~/nockchain && git pull && make build && make install-nockchain"
    
    batch_execute "$update_command"
}

# 创建Web监控面板
create_web_dashboard() {
    log "创建Web监控面板..."
    
    local dashboard_dir="$CLUSTER_CONFIG/dashboard"
    mkdir -p "$dashboard_dir"
    
    # 创建简单的HTML监控页面
    cat > "$dashboard_dir/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Nockchain 集群监控</title>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="30">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .stats { display: flex; gap: 20px; margin: 20px 0; }
        .stat-box { background: #ecf0f1; padding: 15px; border-radius: 5px; flex: 1; text-align: center; }
        .nodes { margin: 20px 0; }
        .node { padding: 10px; margin: 5px 0; border-radius: 5px; }
        .mining { background: #2ecc71; color: white; }
        .syncing { background: #f39c12; color: white; }
        .offline { background: #e74c3c; color: white; }
        .online { background: #3498db; color: white; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Nockchain 集群监控面板</h1>
        <p>最后更新: <span id="timestamp"></span></p>
    </div>
    
    <div class="stats">
        <div class="stat-box">
            <h3>总节点数</h3>
            <div id="total-nodes">-</div>
        </div>
        <div class="stat-box">
            <h3>挖矿节点</h3>
            <div id="mining-nodes">-</div>
        </div>
        <div class="stat-box">
            <h3>在线率</h3>
            <div id="online-rate">-</div>
        </div>
        <div class="stat-box">
            <h3>平均高度</h3>
            <div id="avg-height">-</div>
        </div>
    </div>
    
    <div class="nodes" id="nodes-list">
        <!-- 节点列表将通过JavaScript动态加载 -->
    </div>
    
    <script>
        function updateTimestamp() {
            document.getElementById('timestamp').textContent = new Date().toLocaleString();
        }
        
        function loadNodeData() {
            // 这里可以通过AJAX加载实际的节点数据
            // 现在显示静态示例
            updateTimestamp();
        }
        
        // 页面加载时更新数据
        loadNodeData();
        
        // 每30秒更新一次时间戳
        setInterval(updateTimestamp, 30000);
    </script>
</body>
</html>
EOF
    
    # 启动简单的HTTP服务器
    cd "$dashboard_dir"
    python3 -m http.server $DASHBOARD_PORT > /dev/null 2>&1 &
    local server_pid=$!
    
    echo "$server_pid" > "$CLUSTER_CONFIG/dashboard.pid"
    
    log "Web监控面板已启动"
    info "访问地址: http://localhost:$DASHBOARD_PORT"
    info "停止服务: kill $server_pid"
}

# 显示帮助
show_help() {
    echo "Nockchain 1000节点集群管理系统"
    echo ""
    echo "用法: $0 [命令] [参数]"
    echo ""
    echo "命令说明:"
    echo "  init              - 初始化集群配置"
    echo "  overview          - 显示集群状态概览"
    echo "  stats             - 收集详细挖矿统计"
    echo "  restart           - 批量重启挖矿服务"
    echo "  update            - 批量更新节点"
    echo "  execute <命令>    - 在所有节点执行命令"
    echo "  dashboard         - 启动Web监控面板"
    echo "  help              - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 overview                    # 查看集群状态"
    echo "  $0 stats                       # 收集统计数据"
    echo "  $0 execute 'df -h'             # 检查所有节点磁盘使用"
    echo "  $0 restart                     # 重启所有挖矿服务"
}

# 主函数
main() {
    case "${1:-help}" in
        init)
            init_cluster
            ;;
        overview)
            cluster_overview
            ;;
        stats)
            collect_mining_stats
            ;;
        restart)
            batch_restart_mining
            ;;
        update)
            batch_update
            ;;
        execute)
            if [ -z "$2" ]; then
                error "请指定要执行的命令"
                exit 1
            fi
            batch_execute "$2"
            ;;
        dashboard)
            create_web_dashboard
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
