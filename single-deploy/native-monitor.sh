#!/bin/bash

# Nockchain 原生部署监控脚本
# 用于监控原生部署的挖矿节点状态和性能

set -e

# 配置
INSTALL_DIR="$HOME/nockchain"
LOG_DIR="$INSTALL_DIR/logs"
REPORT_DIR="$INSTALL_DIR/reports"

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

# 检查安装目录
check_install_dir() {
    if [ ! -d "$INSTALL_DIR" ]; then
        error "找不到安装目录: $INSTALL_DIR"
        error "请先运行部署脚本进行安装"
        exit 1
    fi
    
    cd "$INSTALL_DIR"
}

# 获取系统信息
get_system_info() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local mem_info=$(free -h | grep Mem)
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_total=$(echo $mem_info | awk '{print $2}')
    local mem_percent=$(free | grep Mem | awk '{printf("%.1f"), $3/$2 * 100.0}')
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    echo "CPU: ${cpu_usage}% | 内存: ${mem_used}/${mem_total} (${mem_percent}%) | 磁盘: ${disk_usage}% | 负载: ${load_avg}"
}

# 获取网络信息
get_network_info() {
    local connections=$(netstat -an 2>/dev/null | grep :4001 | wc -l)
    local rx_bytes=$(cat /sys/class/net/*/statistics/rx_bytes 2>/dev/null | awk '{sum+=$1} END {printf "%.1f", sum/1024/1024}')
    local tx_bytes=$(cat /sys/class/net/*/statistics/tx_bytes 2>/dev/null | awk '{sum+=$1} END {printf "%.1f", sum/1024/1024}')
    
    echo "P2P连接: ${connections} | 接收: ${rx_bytes}MB | 发送: ${tx_bytes}MB"
}

# 检查进程状态
check_process_status() {
    local miner_pid=$(pgrep -f "nockchain.*--mine" 2>/dev/null || echo "")
    local node_pid=$(pgrep -f "nockchain" 2>/dev/null | grep -v "$miner_pid" || echo "")
    local screen_session=$(screen -list 2>/dev/null | grep nockchain-miner || echo "")
    
    if [ -n "$miner_pid" ]; then
        local cpu_usage=$(ps -p $miner_pid -o %cpu --no-headers 2>/dev/null || echo "0")
        local mem_usage=$(ps -p $miner_pid -o %mem --no-headers 2>/dev/null || echo "0")
        local runtime=$(ps -p $miner_pid -o etime --no-headers 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} 挖矿节点: 运行中 (PID: $miner_pid, CPU: ${cpu_usage}%, 内存: ${mem_usage}%, 运行时间: $runtime)"
        
        if [ -n "$screen_session" ]; then
            echo -e "  ${CYAN}Screen会话:${NC} $(echo $screen_session | awk '{print $1}')"
        fi
        return 0
    else
        echo -e "${RED}✗${NC} 挖矿节点: 未运行"
        return 1
    fi
}

# 分析挖矿日志
analyze_mining_logs() {
    local latest_log=$(ls -t $LOG_DIR/miner-*.log 2>/dev/null | head -1)
    
    if [ -z "$latest_log" ]; then
        warn "未找到挖矿日志文件"
        return 1
    fi
    
    local log_output=$(tail -100 "$latest_log" 2>/dev/null)
    
    # 统计关键信息
    local mining_lines=$(echo "$log_output" | grep -c "mining-on" 2>/dev/null || echo "0")
    local block_lines=$(echo "$log_output" | grep -c "block.*added to validated blocks" 2>/dev/null || echo "0")
    local error_lines=$(echo "$log_output" | grep -ic "error\|failed\|panic" 2>/dev/null || echo "0")
    local peer_lines=$(echo "$log_output" | grep -c "peer" 2>/dev/null || echo "0")
    
    echo "日志文件: $(basename $latest_log)"
    echo "挖矿活动: ${mining_lines} | 新区块: ${block_lines} | 错误: ${error_lines} | 节点事件: ${peer_lines}"
    
    # 获取最新区块高度
    local latest_block=$(echo "$log_output" | grep "block.*added to validated blocks" | tail -1 | awk '{print $NF}' 2>/dev/null || echo "")
    if [ -n "$latest_block" ]; then
        echo "最新区块高度: $latest_block"
    fi
    
    # 检查最近的挖矿活动
    local last_mining=$(echo "$log_output" | grep "mining-on" | tail -1 2>/dev/null || echo "")
    if [ -n "$last_mining" ]; then
        echo "最近挖矿: $(echo $last_mining | awk '{print $1, $2}')"
    fi
    
    # 检查错误
    if [ "$error_lines" -gt 5 ]; then
        warn "检测到较多错误日志 ($error_lines 条)"
        echo "最近错误:"
        echo "$log_output" | grep -i "error\|failed" | tail -3 | sed 's/^/  /'
        return 1
    fi
    
    return 0
}

# 性能统计
show_performance_stats() {
    echo -e "\n${CYAN}=== 性能统计 ===${NC}"
    
    # CPU 信息
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//')
    local cpu_cores=$(nproc)
    echo "CPU: $cpu_model ($cpu_cores 核心)"
    
    # 内存信息
    local total_mem=$(free -h | grep Mem | awk '{print $2}')
    local available_mem=$(free -h | grep Mem | awk '{print $7}')
    echo "内存: 总计 $total_mem / 可用 $available_mem"
    
    # 磁盘信息
    local disk_info=$(df -h $INSTALL_DIR | tail -1)
    local disk_used=$(echo $disk_info | awk '{print $3}')
    local disk_avail=$(echo $disk_info | awk '{print $4}')
    echo "磁盘: 已用 $disk_used / 可用 $disk_avail"
    
    # 系统运行时间
    local uptime_info=$(uptime -p)
    echo "系统运行时间: $uptime_info"
    
    # 挖矿进程资源使用
    local miner_pid=$(pgrep -f "nockchain.*--mine" 2>/dev/null || echo "")
    if [ -n "$miner_pid" ]; then
        echo -e "\n${CYAN}挖矿进程资源使用:${NC}"
        ps -p $miner_pid -o pid,ppid,%cpu,%mem,vsz,rss,etime,cmd --no-headers 2>/dev/null | \
        awk '{printf "PID: %s | CPU: %s%% | 内存: %s%% | 虚拟内存: %.1fMB | 物理内存: %.1fMB | 运行时间: %s\n", $1, $3, $4, $5/1024, $6/1024, $7}'
    fi
}

# 实时监控模式
real_time_monitor() {
    echo -e "${BLUE}开始实时监控 (按 Ctrl+C 退出)${NC}\n"
    
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                  Nockchain 实时监控 (原生)                   ║${NC}"
        echo -e "${CYAN}║                  $(date +'%Y-%m-%d %H:%M:%S')                    ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
        
        echo -e "\n${YELLOW}=== 进程状态 ===${NC}"
        check_process_status
        
        echo -e "\n${YELLOW}=== 系统资源 ===${NC}"
        get_system_info
        
        echo -e "\n${YELLOW}=== 网络状态 ===${NC}"
        get_network_info
        
        echo -e "\n${YELLOW}=== 挖矿状态 ===${NC}"
        analyze_mining_logs
        
        echo -e "\n${YELLOW}=== 最新日志 (最近3条) ===${NC}"
        local latest_log=$(ls -t $LOG_DIR/miner-*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            tail -3 "$latest_log" 2>/dev/null | sed 's/^/  /' || echo "  无法读取日志"
        else
            echo "  未找到日志文件"
        fi
        
        echo -e "\n${CYAN}下次更新: 10秒后...${NC}"
        sleep 10
    done
}

# 生成报告
generate_report() {
    mkdir -p "$REPORT_DIR"
    local report_file="$REPORT_DIR/nockchain-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Nockchain 原生部署挖矿节点状态报告"
        echo "生成时间: $(date)"
        echo "安装目录: $INSTALL_DIR"
        echo "========================================"
        echo ""
        
        echo "进程状态:"
        check_process_status
        echo ""
        
        echo "系统信息:"
        get_system_info
        echo ""
        
        echo "网络信息:"
        get_network_info
        echo ""
        
        echo "挖矿分析:"
        analyze_mining_logs
        echo ""
        
        echo "性能统计:"
        show_performance_stats
        echo ""
        
        echo "环境配置:"
        if [ -f "$INSTALL_DIR/.env" ]; then
            echo "配置文件内容:"
            cat "$INSTALL_DIR/.env" | grep -v "MINING_PUBKEY" | sed 's/^/  /'
            echo "  MINING_PUBKEY=***已隐藏***"
        else
            echo "未找到配置文件"
        fi
        echo ""
        
        echo "最近日志 (最近50条):"
        local latest_log=$(ls -t $LOG_DIR/miner-*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            tail -50 "$latest_log" 2>/dev/null | sed 's/^/  /'
        else
            echo "  未找到日志文件"
        fi
        
    } > "$report_file"
    
    log "报告已生成: $report_file"
    
    # 显示报告摘要
    echo -e "\n${CYAN}=== 报告摘要 ===${NC}"
    head -20 "$report_file" | tail -15
}

# 健康检查
health_check() {
    local issues=0
    
    echo -e "${BLUE}=== 健康检查 ===${NC}"
    
    # 检查进程状态
    if ! check_process_status >/dev/null 2>&1; then
        error "挖矿进程未运行"
        ((issues++))
    else
        log "挖矿进程运行正常"
    fi
    
    # 检查系统资源
    local mem_percent=$(free | grep Mem | awk '{printf("%.0f"), $3/$2 * 100.0}')
    local disk_percent=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$mem_percent" -gt 90 ]; then
        warn "内存使用率过高: ${mem_percent}%"
        ((issues++))
    fi
    
    if [ "$disk_percent" -gt 85 ]; then
        warn "磁盘使用率过高: ${disk_percent}%"
        ((issues++))
    fi
    
    # 检查日志文件
    if [ ! -d "$LOG_DIR" ] || [ -z "$(ls -A $LOG_DIR 2>/dev/null)" ]; then
        warn "未找到日志文件"
        ((issues++))
    fi
    
    # 检查配置文件
    if [ ! -f "$INSTALL_DIR/.env" ]; then
        error "未找到配置文件 .env"
        ((issues++))
    else
        source "$INSTALL_DIR/.env"
        if [ -z "$MINING_PUBKEY" ]; then
            error "挖矿公钥未设置"
            ((issues++))
        fi
    fi
    
    # 检查网络连接
    local connections=$(netstat -an 2>/dev/null | grep :4001 | wc -l)
    if [ "$connections" -eq 0 ]; then
        warn "未检测到P2P网络连接"
        ((issues++))
    fi
    
    # 检查挖矿日志
    if ! analyze_mining_logs >/dev/null 2>&1; then
        warn "挖矿日志分析发现异常"
        ((issues++))
    fi
    
    echo ""
    if [ $issues -eq 0 ]; then
        log "健康检查通过，系统运行正常 ✓"
        return 0
    else
        error "发现 $issues 个问题，请检查详细信息 ✗"
        return 1
    fi
}

# 显示帮助
show_help() {
    echo "Nockchain 原生部署监控工具"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "可用命令:"
    echo "  status    - 显示当前状态 (默认)"
    echo "  monitor   - 实时监控模式"
    echo "  health    - 健康检查"
    echo "  report    - 生成详细报告"
    echo "  logs      - 查看最新日志"
    echo "  tail      - 实时跟踪日志"
    echo "  help      - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 status   # 查看状态"
    echo "  $0 monitor  # 开始实时监控"
    echo "  $0 health   # 执行健康检查"
    echo "  $0 tail     # 实时查看日志"
}

# 主函数
main() {
    check_install_dir
    
    case "${1:-status}" in
        status)
            echo -e "${CYAN}=== Nockchain 挖矿节点状态 (原生部署) ===${NC}"
            echo "时间: $(date)"
            echo "安装目录: $INSTALL_DIR"
            echo ""
            
            echo -e "${YELLOW}进程状态:${NC}"
            check_process_status
            echo ""
            
            echo -e "${YELLOW}系统资源:${NC}"
            get_system_info
            echo ""
            
            echo -e "${YELLOW}网络状态:${NC}"
            get_network_info
            echo ""
            
            echo -e "${YELLOW}挖矿状态:${NC}"
            analyze_mining_logs
            ;;
        monitor)
            real_time_monitor
            ;;
        health)
            health_check
            ;;
        report)
            generate_report
            ;;
        logs)
            local latest_log=$(ls -t $LOG_DIR/miner-*.log 2>/dev/null | head -1)
            if [ -n "$latest_log" ]; then
                echo "显示最新日志: $(basename $latest_log)"
                echo "================================"
                tail -50 "$latest_log"
            else
                error "未找到日志文件"
            fi
            ;;
        tail)
            local latest_log=$(ls -t $LOG_DIR/miner-*.log 2>/dev/null | head -1)
            if [ -n "$latest_log" ]; then
                echo "实时跟踪日志: $(basename $latest_log)"
                echo "按 Ctrl+C 退出"
                echo "================================"
                tail -f "$latest_log"
            else
                error "未找到日志文件"
            fi
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

# 信号处理
trap 'echo -e "\n${YELLOW}监控已停止${NC}"; exit 0' SIGINT SIGTERM

main "$@"
