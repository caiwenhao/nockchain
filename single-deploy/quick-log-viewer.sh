#!/bin/bash

# Nockchain 快速日志查看工具

set -e

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# 检测安装目录
detect_install_dir() {
    if [ "$USER" = "root" ] || [ "$EUID" -eq 0 ]; then
        INSTALL_DIR="/opt/nockchain"
    else
        INSTALL_DIR="$HOME/nockchain"
    fi
    
    # 如果检测的目录不存在，尝试其他可能的位置
    if [ ! -d "$INSTALL_DIR" ]; then
        local possible_dirs=(
            "/opt/nockchain"
            "$HOME/nockchain"
            "/root/nockchain"
        )
        
        for dir in "${possible_dirs[@]}"; do
            if [ -d "$dir" ] && [ -d "$dir/logs" ]; then
                INSTALL_DIR="$dir"
                break
            fi
        done
    fi
    
    if [ ! -d "$INSTALL_DIR" ]; then
        error "找不到 Nockchain 安装目录"
        exit 1
    fi
    
    cd "$INSTALL_DIR"
}

# 显示帮助信息
show_help() {
    echo "Nockchain 快速日志查看工具"
    echo ""
    echo "用法: $0 [命令] [参数]"
    echo ""
    echo "命令:"
    echo "  tail [行数]     显示最新日志 (默认100行)"
    echo "  follow          实时跟踪日志"
    echo "  mining          查看挖矿相关日志"
    echo "  errors          查看错误日志"
    echo "  blocks          查看区块相关日志"
    echo "  peers           查看网络连接日志"
    echo "  list            列出所有日志文件"
    echo "  size            显示日志文件大小"
    echo "  clean           清理旧日志文件"
    echo ""
    echo "示例:"
    echo "  $0 tail 500     # 显示最新500行日志"
    echo "  $0 follow       # 实时查看日志"
    echo "  $0 mining       # 查看挖矿活动"
    echo "  $0 errors       # 查看错误信息"
}

# 获取最新日志文件
get_latest_log() {
    if ls logs/miner-*.log 1> /dev/null 2>&1; then
        ls -t logs/miner-*.log 2>/dev/null | head -1
    else
        echo ""
    fi
}

# 显示最新日志
show_tail() {
    local lines=${1:-100}
    local latest_log=$(get_latest_log)
    
    if [ -z "$latest_log" ]; then
        error "未找到日志文件"
        return 1
    fi
    
    info "显示最新 $lines 行日志: $latest_log"
    echo "----------------------------------------"
    tail -$lines "$latest_log"
}

# 实时跟踪日志
follow_log() {
    local latest_log=$(get_latest_log)
    
    if [ -z "$latest_log" ]; then
        error "未找到日志文件"
        return 1
    fi
    
    info "实时跟踪日志: $latest_log"
    info "按 Ctrl+C 退出"
    echo "----------------------------------------"
    tail -f "$latest_log"
}

# 查看挖矿相关日志
show_mining() {
    local latest_log=$(get_latest_log)
    
    if [ -z "$latest_log" ]; then
        error "未找到日志文件"
        return 1
    fi
    
    info "挖矿相关日志:"
    echo "----------------------------------------"
    grep -i "mining\|mine\|miner" "$latest_log" | tail -20
}

# 查看错误日志
show_errors() {
    local latest_log=$(get_latest_log)
    
    if [ -z "$latest_log" ]; then
        error "未找到日志文件"
        return 1
    fi
    
    info "错误日志:"
    echo "----------------------------------------"
    grep -i "error\|failed\|panic\|fatal" "$latest_log" | tail -20
}

# 查看区块相关日志
show_blocks() {
    local latest_log=$(get_latest_log)
    
    if [ -z "$latest_log" ]; then
        error "未找到日志文件"
        return 1
    fi
    
    info "区块相关日志:"
    echo "----------------------------------------"
    grep -i "block\|height" "$latest_log" | tail -20
}

# 查看网络连接日志
show_peers() {
    local latest_log=$(get_latest_log)
    
    if [ -z "$latest_log" ]; then
        error "未找到日志文件"
        return 1
    fi
    
    info "网络连接日志:"
    echo "----------------------------------------"
    grep -i "peer\|connection\|network" "$latest_log" | tail -20
}

# 列出日志文件
list_logs() {
    info "日志文件列表:"
    echo "----------------------------------------"
    if [ -d "logs" ]; then
        ls -lah logs/
    else
        warn "日志目录不存在"
    fi
}

# 显示日志文件大小
show_size() {
    info "日志文件大小:"
    echo "----------------------------------------"
    if [ -d "logs" ]; then
        du -h logs/* 2>/dev/null | sort -hr
        echo ""
        echo "总大小: $(du -sh logs/ | cut -f1)"
    else
        warn "日志目录不存在"
    fi
}

# 清理旧日志
clean_logs() {
    warn "清理7天前的日志文件..."
    if [ -d "logs" ]; then
        find logs/ -name "*.log" -mtime +7 -delete 2>/dev/null || true
        log "清理完成"
        show_size
    else
        warn "日志目录不存在"
    fi
}

# 主函数
main() {
    detect_install_dir
    
    case "${1:-tail}" in
        tail)
            show_tail "$2"
            ;;
        follow|f)
            follow_log
            ;;
        mining|mine)
            show_mining
            ;;
        errors|error)
            show_errors
            ;;
        blocks|block)
            show_blocks
            ;;
        peers|peer|network)
            show_peers
            ;;
        list|ls)
            list_logs
            ;;
        size)
            show_size
            ;;
        clean)
            clean_logs
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"
