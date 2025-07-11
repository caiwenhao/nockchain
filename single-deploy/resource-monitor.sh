#!/bin/bash

# Nockchain 资源使用监控脚本
# 监控磁盘和网络使用情况

set -e

# 配置
DATA_DIR="$HOME/nockchain/.data.nockchain"
LOG_DIR="$HOME/nockchain/logs"
MONITOR_LOG="$HOME/nockchain-resource-monitor.log"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $1"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1"; }

# 获取磁盘使用情况
get_disk_usage() {
    echo -e "${CYAN}=== 磁盘使用情况 ===${NC}"
    
    # 总体磁盘使用
    echo "系统磁盘使用:"
    df -h / | tail -1 | awk '{printf "  总计: %s | 已用: %s | 可用: %s | 使用率: %s\n", $2, $3, $4, $5}'
    
    # Nockchain数据目录
    if [ -d "$DATA_DIR" ]; then
        echo ""
        echo "Nockchain数据目录: $DATA_DIR"
        local total_size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
        echo "  总大小: $total_size"
        
        # 快照文件详情
        if ls "$DATA_DIR"/*.chkjam &>/dev/null; then
            echo "  快照文件:"
            for file in "$DATA_DIR"/*.chkjam; do
                if [ -f "$file" ]; then
                    local size=$(du -h "$file" | cut -f1)
                    local modified=$(stat -c %y "$file" | cut -d' ' -f1,2 | cut -d'.' -f1)
                    echo "    $(basename "$file"): $size (修改时间: $modified)"
                fi
            done
        else
            echo "  快照文件: 未找到"
        fi
    else
        echo "Nockchain数据目录: 不存在"
    fi
    
    # 日志文件大小
    if [ -d "$LOG_DIR" ]; then
        echo ""
        echo "日志文件:"
        local log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
        echo "  日志总大小: $log_size"
        
        # 最大的几个日志文件
        if ls "$LOG_DIR"/*.log &>/dev/null; then
            echo "  最大日志文件:"
            du -h "$LOG_DIR"/*.log 2>/dev/null | sort -hr | head -3 | while read size file; do
                echo "    $(basename "$file"): $size"
            done
        fi
    fi
}

# 获取网络使用情况
get_network_usage() {
    echo -e "\n${CYAN}=== 网络使用情况 ===${NC}"
    
    # P2P连接数
    local p2p_connections=$(netstat -an 2>/dev/null | grep :4001 | wc -l)
    echo "P2P连接数: $p2p_connections"
    
    # 网络接口统计
    echo ""
    echo "网络接口统计:"
    
    # 获取主要网络接口
    local main_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$main_interface" ]; then
        echo "  主接口: $main_interface"
        
        # 读取网络统计
        local rx_bytes=$(cat /sys/class/net/$main_interface/statistics/rx_bytes 2>/dev/null || echo "0")
        local tx_bytes=$(cat /sys/class/net/$main_interface/statistics/tx_bytes 2>/dev/null || echo "0")
        local rx_packets=$(cat /sys/class/net/$main_interface/statistics/rx_packets 2>/dev/null || echo "0")
        local tx_packets=$(cat /sys/class/net/$main_interface/statistics/tx_packets 2>/dev/null || echo "0")
        
        # 转换为人类可读格式
        local rx_mb=$((rx_bytes / 1024 / 1024))
        local tx_mb=$((tx_bytes / 1024 / 1024))
        
        echo "    接收: ${rx_mb}MB ($rx_packets 包)"
        echo "    发送: ${tx_mb}MB ($tx_packets 包)"
        echo "    总计: $((rx_mb + tx_mb))MB"
    fi
    
    # 实时网络速度（如果有iftop）
    if command -v iftop &> /dev/null; then
        echo ""
        echo "实时网络速度 (5秒采样):"
        timeout 5 iftop -t -s 5 2>/dev/null | tail -3 | head -1 || echo "  无法获取实时速度"
    fi
}

# 获取进程资源使用
get_process_usage() {
    echo -e "\n${CYAN}=== 进程资源使用 ===${NC}"
    
    # 查找Nockchain进程
    local nockchain_pids=$(pgrep -f nockchain || echo "")
    
    if [ -n "$nockchain_pids" ]; then
        echo "Nockchain进程:"
        echo "$nockchain_pids" | while read pid; do
            if [ -n "$pid" ]; then
                local cmd=$(ps -p $pid -o cmd --no-headers 2>/dev/null | cut -c1-50)
                local cpu=$(ps -p $pid -o %cpu --no-headers 2>/dev/null)
                local mem=$(ps -p $pid -o %mem --no-headers 2>/dev/null)
                local vsz=$(ps -p $pid -o vsz --no-headers 2>/dev/null)
                local rss=$(ps -p $pid -o rss --no-headers 2>/dev/null)
                
                # 转换内存单位
                local vsz_mb=$((vsz / 1024))
                local rss_mb=$((rss / 1024))
                
                echo "  PID $pid: CPU ${cpu}% | 内存 ${mem}% | 虚拟内存 ${vsz_mb}MB | 物理内存 ${rss_mb}MB"
                echo "    命令: $cmd"
            fi
        done
    else
        echo "未找到Nockchain进程"
    fi
}

# 获取I/O统计
get_io_stats() {
    echo -e "\n${CYAN}=== 磁盘I/O统计 ===${NC}"
    
    # 系统I/O统计
    if [ -f /proc/diskstats ]; then
        echo "磁盘I/O统计:"
        
        # 获取主要磁盘设备
        local main_disk=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
        local disk_name=$(basename "$main_disk")
        
        if grep -q "$disk_name" /proc/diskstats; then
            local stats=$(grep "$disk_name" /proc/diskstats | head -1)
            local reads=$(echo $stats | awk '{print $4}')
            local writes=$(echo $stats | awk '{print $8}')
            local read_sectors=$(echo $stats | awk '{print $6}')
            local write_sectors=$(echo $stats | awk '{print $10}')
            
            # 扇区转换为MB (通常1扇区=512字节)
            local read_mb=$((read_sectors * 512 / 1024 / 1024))
            local write_mb=$((write_sectors * 512 / 1024 / 1024))
            
            echo "  设备: $disk_name"
            echo "    读取: $reads 次 (${read_mb}MB)"
            echo "    写入: $writes 次 (${write_mb}MB)"
        fi
    fi
    
    # 如果有iostat命令
    if command -v iostat &> /dev/null; then
        echo ""
        echo "实时I/O统计 (1秒采样):"
        iostat -x 1 2 | tail -n +4 | head -5 2>/dev/null || echo "  无法获取实时I/O统计"
    fi
}

# 预测资源需求
predict_resource_needs() {
    echo -e "\n${CYAN}=== 资源需求预测 ===${NC}"
    
    # 当前区块高度
    local current_height=0
    if [ -d "$LOG_DIR" ]; then
        local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            current_height=$(grep "block.*added to validated blocks" "$latest_log" | tail -1 | awk '{print $NF}' 2>/dev/null || echo "0")
        fi
    fi
    
    echo "当前区块高度: $current_height"
    
    # 数据增长预测
    if [ -d "$DATA_DIR" ] && [ "$current_height" -gt 0 ]; then
        local current_size_kb=$(du -sk "$DATA_DIR" 2>/dev/null | cut -f1)
        local current_size_mb=$((current_size_kb / 1024))
        
        if [ "$current_size_mb" -gt 0 ]; then
            local mb_per_block=$((current_size_mb / current_height))
            
            echo ""
            echo "数据增长预测:"
            echo "  当前数据大小: ${current_size_mb}MB"
            echo "  平均每区块: ${mb_per_block}MB"
            
            # 预测未来增长
            local blocks_per_day=$((24 * 60 * 60 / 20))  # 假设20秒一个区块
            local daily_growth_mb=$((blocks_per_day * mb_per_block))
            local monthly_growth_mb=$((daily_growth_mb * 30))
            
            echo "  预计日增长: ${daily_growth_mb}MB"
            echo "  预计月增长: ${monthly_growth_mb}MB ($(echo "scale=1; $monthly_growth_mb/1024" | bc 2>/dev/null || echo "?")GB)"
        fi
    fi
    
    # 网络带宽建议
    echo ""
    echo "网络带宽建议:"
    echo "  最低要求: 10Mbps下载 / 5Mbps上传"
    echo "  推荐配置: 50Mbps下载 / 20Mbps上传"
    echo "  企业级: 100Mbps+下载 / 50Mbps+上传"
}

# 生成资源报告
generate_report() {
    local report_file="$HOME/nockchain-resource-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "Nockchain 资源使用报告"
        echo "生成时间: $(date)"
        echo "========================================"
        echo ""
        
        get_disk_usage
        get_network_usage  
        get_process_usage
        get_io_stats
        predict_resource_needs
        
    } > "$report_file"
    
    log "资源报告已生成: $report_file"
}

# 实时监控模式
real_time_monitor() {
    log "开始实时资源监控 (按 Ctrl+C 退出)"
    
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                Nockchain 实时资源监控                        ║${NC}"
        echo -e "${BLUE}║                  $(date +'%Y-%m-%d %H:%M:%S')                    ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
        
        get_disk_usage
        get_network_usage
        get_process_usage
        
        echo -e "\n${YELLOW}下次更新: 30秒后...${NC}"
        sleep 30
    done
}

# 记录历史数据
log_historical_data() {
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    # 获取关键指标
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    local data_size="0"
    if [ -d "$DATA_DIR" ]; then
        data_size=$(du -sm "$DATA_DIR" 2>/dev/null | cut -f1)
    fi
    
    local p2p_connections=$(netstat -an 2>/dev/null | grep :4001 | wc -l)
    local nockchain_processes=$(pgrep -f nockchain | wc -l)
    
    # 记录到日志文件
    echo "$timestamp,$disk_usage,$data_size,$p2p_connections,$nockchain_processes" >> "$MONITOR_LOG"
}

# 显示帮助
show_help() {
    echo "Nockchain 资源监控工具"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "可用命令:"
    echo "  status    - 显示当前资源状态 (默认)"
    echo "  monitor   - 实时监控模式"
    echo "  report    - 生成详细资源报告"
    echo "  log       - 记录历史数据到日志"
    echo "  predict   - 显示资源需求预测"
    echo "  help      - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 status   # 查看当前状态"
    echo "  $0 monitor  # 开始实时监控"
    echo "  $0 report   # 生成报告"
}

# 主函数
main() {
    case "${1:-status}" in
        status)
            get_disk_usage
            get_network_usage
            get_process_usage
            ;;
        monitor)
            real_time_monitor
            ;;
        report)
            generate_report
            ;;
        log)
            log_historical_data
            log "历史数据已记录到: $MONITOR_LOG"
            ;;
        predict)
            predict_resource_needs
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
