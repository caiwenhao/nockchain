#!/bin/bash

# Nockchain 路径检测测试工具

set -e

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

show_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
    ╔═══════════════════════════════════════╗
    ║      Nockchain 路径检测测试           ║
    ║       Path Detection Test             ║
    ╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 检查实际的安装目录
check_actual_install() {
    echo "🔍 检查实际的 Nockchain 安装位置..."
    echo ""
    
    local possible_dirs=(
        "/opt/nockchain"
        "$HOME/nockchain"
        "/root/nockchain"
    )
    
    local found_dirs=()
    for dir in "${possible_dirs[@]}"; do
        if [ -d "$dir" ]; then
            echo "检查目录: $dir"
            if [ -f "$dir/Makefile" ]; then
                log "  ✓ 找到 Makefile"
            else
                warn "  ! 缺少 Makefile"
            fi
            
            if [ -d "$dir/.data.nockchain" ]; then
                log "  ✓ 找到数据目录"
            else
                warn "  ! 缺少数据目录"
            fi
            
            if [ -d "$dir/logs" ]; then
                log "  ✓ 找到日志目录"
            else
                warn "  ! 缺少日志目录"
            fi
            
            if [ -f "$dir/Makefile" ] && [ -d "$dir/.data.nockchain" ]; then
                found_dirs+=("$dir")
                log "  → 有效的 Nockchain 安装"
            fi
            echo ""
        fi
    done
    
    if [ ${#found_dirs[@]} -eq 0 ]; then
        error "未找到有效的 Nockchain 安装"
        return 1
    else
        info "找到 ${#found_dirs[@]} 个有效的 Nockchain 安装:"
        for dir in "${found_dirs[@]}"; do
            echo "  - $dir"
        done
        return 0
    fi
}

# 测试脚本路径检测
test_script_detection() {
    local script_name="$1"
    local test_command="$2"
    
    echo "🧪 测试 $script_name 路径检测..."
    
    if [ ! -f "$script_name" ]; then
        error "$script_name 文件不存在"
        return 1
    fi
    
    # 运行测试命令并捕获输出
    local output
    if output=$(timeout 10s bash -c "$test_command" 2>&1); then
        log "$script_name 路径检测成功"
        echo "  输出预览: $(echo "$output" | head -2 | tr '\n' ' ')"
    else
        error "$script_name 路径检测失败"
        echo "  错误信息: $(echo "$output" | head -2 | tr '\n' ' ')"
        return 1
    fi
    echo ""
}

# 测试所有脚本
test_all_scripts() {
    echo "📋 测试所有脚本的路径检测..."
    echo ""
    
    local scripts=(
        "native-deploy.sh:./native-deploy.sh status"
        "native-monitor.sh:./native-monitor.sh status"
        "resource-monitor.sh:./resource-monitor.sh disk"
        "simple-snapshot-solution.sh:./simple-snapshot-solution.sh list"
    )
    
    local success_count=0
    local total_count=${#scripts[@]}
    
    for script_info in "${scripts[@]}"; do
        local script_name="${script_info%%:*}"
        local test_command="${script_info##*:}"
        
        if test_script_detection "$script_name" "$test_command"; then
            ((success_count++))
        fi
    done
    
    echo "📊 测试结果: $success_count/$total_count 脚本通过路径检测测试"
    
    if [ $success_count -eq $total_count ]; then
        log "所有脚本路径检测正常！"
        return 0
    else
        warn "部分脚本路径检测存在问题"
        return 1
    fi
}

# 显示修复建议
show_fix_suggestions() {
    echo "💡 如果路径检测有问题，请尝试以下修复方法:"
    echo ""
    
    echo "1. 确认 Nockchain 安装位置:"
    echo "   ls -la /opt/nockchain"
    echo "   ls -la ~/nockchain"
    echo ""
    
    echo "2. 检查当前用户:"
    echo "   whoami"
    echo "   echo \$USER"
    echo ""
    
    echo "3. 重新运行部署脚本:"
    echo "   ./native-deploy.sh install"
    echo ""
    
    echo "4. 手动设置环境变量:"
    echo "   export NOCKCHAIN_INSTALL_DIR=/opt/nockchain"
    echo ""
    
    echo "5. 检查权限:"
    echo "   ls -la /opt/nockchain"
    echo "   sudo chown -R \$USER:\$USER /opt/nockchain"
    echo ""
}

# 显示当前环境信息
show_environment() {
    echo "🌍 当前环境信息:"
    echo ""
    
    echo "用户信息:"
    echo "  当前用户: $(whoami)"
    echo "  用户ID: $UID"
    echo "  是否root: $([ "$EUID" -eq 0 ] && echo "是" || echo "否")"
    echo "  HOME目录: $HOME"
    echo ""
    
    echo "系统信息:"
    echo "  操作系统: $(uname -s)"
    echo "  内核版本: $(uname -r)"
    echo "  当前目录: $(pwd)"
    echo ""
}

# 主函数
main() {
    show_banner
    
    case "${1:-all}" in
        install)
            check_actual_install
            ;;
        scripts)
            test_all_scripts
            ;;
        env)
            show_environment
            ;;
        fix)
            show_fix_suggestions
            ;;
        all|*)
            show_environment
            check_actual_install
            test_all_scripts
            show_fix_suggestions
            ;;
    esac
}

main "$@"
