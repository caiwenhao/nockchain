#!/bin/bash

# Nockchain 密钥管理脚本
# 用于批量生成和管理挖矿密钥对

set -e

# 配置
KEYS_DIR="$HOME/nockchain-keys"
BACKUP_DIR="$HOME/nockchain-keys-backup"
NOCKCHAIN_DIR="$HOME/nockchain"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# 创建密钥目录
create_key_directories() {
    mkdir -p "$KEYS_DIR" "$BACKUP_DIR"
    chmod 700 "$KEYS_DIR" "$BACKUP_DIR"  # 只有所有者可以访问
}

# 生成单个密钥对
generate_single_key() {
    local node_name="$1"
    local key_file="$KEYS_DIR/${node_name}.key"
    local info_file="$KEYS_DIR/${node_name}.info"
    
    if [ -f "$key_file" ]; then
        warn "密钥文件已存在: $key_file"
        read -p "是否覆盖？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    log "为节点 '$node_name' 生成密钥对..."
    
    # 切换到nockchain目录生成密钥
    cd "$NOCKCHAIN_DIR"
    
    # 生成密钥并捕获输出
    local keygen_output=$(nockchain-wallet keygen 2>&1)
    
    # 提取公钥
    local public_key=$(echo "$keygen_output" | grep "Public Key:" | cut -d' ' -f3)
    
    if [ -z "$public_key" ]; then
        error "无法提取公钥，密钥生成可能失败"
        echo "原始输出:"
        echo "$keygen_output"
        return 1
    fi
    
    # 保存密钥信息
    cat > "$info_file" << EOF
# Nockchain 挖矿密钥信息
# 节点名称: $node_name
# 生成时间: $(date)
# ==========================================

PUBLIC_KEY=$public_key

# 完整输出:
$keygen_output

# 安全提醒:
# 1. 请安全保存私钥和助记词
# 2. 定期备份密钥文件
# 3. 不要在公共场所暴露私钥
EOF
    
    # 创建简化的配置文件
    echo "MINING_PUBKEY=$public_key" > "$key_file"
    
    chmod 600 "$key_file" "$info_file"  # 只有所有者可以读写
    
    log "密钥对生成完成:"
    info "  节点名称: $node_name"
    info "  公钥: $public_key"
    info "  配置文件: $key_file"
    info "  详细信息: $info_file"
}

# 批量生成密钥对
generate_batch_keys() {
    local count="$1"
    local prefix="${2:-node}"
    
    log "批量生成 $count 个密钥对，前缀: $prefix"
    
    for i in $(seq 1 $count); do
        local node_name="${prefix}${i}"
        echo ""
        generate_single_key "$node_name"
    done
    
    echo ""
    log "批量生成完成！"
    list_keys
}

# 列出所有密钥
list_keys() {
    echo -e "\n${CYAN}=== 已生成的密钥对 ===${NC}"
    
    if [ ! -d "$KEYS_DIR" ] || [ -z "$(ls -A "$KEYS_DIR" 2>/dev/null)" ]; then
        warn "未找到任何密钥文件"
        return
    fi
    
    echo "密钥目录: $KEYS_DIR"
    echo ""
    
    local count=0
    for key_file in "$KEYS_DIR"/*.key; do
        if [ -f "$key_file" ]; then
            local node_name=$(basename "$key_file" .key)
            local public_key=$(grep "MINING_PUBKEY=" "$key_file" | cut -d'=' -f2)
            local created=$(stat -c %y "$key_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
            
            echo "节点: $node_name"
            echo "  公钥: $public_key"
            echo "  创建时间: $created"
            echo ""
            
            ((count++))
        fi
    done
    
    info "总计: $count 个密钥对"
}

# 导出密钥配置
export_key_config() {
    local node_name="$1"
    local target_dir="$2"
    
    if [ -z "$node_name" ]; then
        error "请指定节点名称"
        return 1
    fi
    
    local key_file="$KEYS_DIR/${node_name}.key"
    if [ ! -f "$key_file" ]; then
        error "未找到节点 '$node_name' 的密钥文件"
        return 1
    fi
    
    if [ -z "$target_dir" ]; then
        target_dir="$HOME/nockchain"
    fi
    
    local target_env="$target_dir/.env"
    
    log "导出节点 '$node_name' 的密钥配置到 $target_env"
    
    # 读取公钥
    local public_key=$(grep "MINING_PUBKEY=" "$key_file" | cut -d'=' -f2)
    
    # 创建或更新.env文件
    if [ -f "$target_env" ]; then
        # 备份现有文件
        cp "$target_env" "${target_env}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 更新MINING_PUBKEY
        if grep -q "MINING_PUBKEY=" "$target_env"; then
            sed -i "s/MINING_PUBKEY=.*/MINING_PUBKEY=$public_key/" "$target_env"
        else
            echo "MINING_PUBKEY=$public_key" >> "$target_env"
        fi
    else
        # 创建新的.env文件
        cat > "$target_env" << EOF
# Nockchain 配置文件
# 节点: $node_name
# 生成时间: $(date)

MINING_PUBKEY=$public_key
RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info
MINIMAL_LOG_FORMAT=true
EOF
    fi
    
    log "配置导出完成"
    info "  节点: $node_name"
    info "  公钥: $public_key"
    info "  配置文件: $target_env"
}

# 备份所有密钥
backup_keys() {
    local backup_name="nockchain-keys-backup-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "备份所有密钥到: $backup_path"
    
    mkdir -p "$backup_path"
    
    if [ -d "$KEYS_DIR" ] && [ -n "$(ls -A "$KEYS_DIR" 2>/dev/null)" ]; then
        cp -r "$KEYS_DIR"/* "$backup_path/"
        
        # 创建备份信息文件
        cat > "$backup_path/backup_info.txt" << EOF
Nockchain 密钥备份
备份时间: $(date)
备份路径: $backup_path
原始路径: $KEYS_DIR

包含文件:
$(ls -la "$backup_path")

重要提醒:
1. 请将此备份存储在安全位置
2. 考虑使用加密存储
3. 定期验证备份完整性
EOF
        
        # 创建压缩包
        cd "$BACKUP_DIR"
        tar -czf "${backup_name}.tar.gz" "$backup_name"
        
        log "备份完成"
        info "  备份目录: $backup_path"
        info "  压缩包: $BACKUP_DIR/${backup_name}.tar.gz"
        info "  文件数量: $(ls -1 "$backup_path"/*.key 2>/dev/null | wc -l) 个密钥文件"
    else
        warn "没有找到需要备份的密钥文件"
    fi
}

# 验证密钥
verify_key() {
    local node_name="$1"
    
    if [ -z "$node_name" ]; then
        error "请指定节点名称"
        return 1
    fi
    
    local key_file="$KEYS_DIR/${node_name}.key"
    local info_file="$KEYS_DIR/${node_name}.info"
    
    echo -e "${CYAN}=== 验证密钥: $node_name ===${NC}"
    
    if [ ! -f "$key_file" ]; then
        error "密钥文件不存在: $key_file"
        return 1
    fi
    
    if [ ! -f "$info_file" ]; then
        warn "信息文件不存在: $info_file"
    fi
    
    # 检查文件权限
    local key_perms=$(stat -c %a "$key_file")
    local info_perms=$(stat -c %a "$info_file" 2>/dev/null || echo "N/A")
    
    echo "文件状态:"
    echo "  密钥文件: $key_file (权限: $key_perms)"
    echo "  信息文件: $info_file (权限: $info_perms)"
    
    # 检查公钥格式
    local public_key=$(grep "MINING_PUBKEY=" "$key_file" | cut -d'=' -f2)
    if [ -n "$public_key" ]; then
        echo "  公钥长度: ${#public_key} 字符"
        echo "  公钥: $public_key"
        
        # 简单的格式验证
        if [[ ${#public_key} -gt 50 && "$public_key" =~ ^[A-Za-z0-9]+$ ]]; then
            log "✓ 公钥格式看起来正确"
        else
            warn "⚠ 公钥格式可能有问题"
        fi
    else
        error "✗ 无法读取公钥"
    fi
    
    # 检查创建时间
    local created=$(stat -c %y "$key_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
    echo "  创建时间: $created"
}

# 显示帮助
show_help() {
    echo "Nockchain 密钥管理工具"
    echo ""
    echo "用法: $0 [命令] [参数]"
    echo ""
    echo "命令说明:"
    echo "  generate <节点名>        - 生成单个密钥对"
    echo "  batch <数量> [前缀]      - 批量生成密钥对"
    echo "  list                     - 列出所有密钥"
    echo "  export <节点名> [目录]   - 导出密钥配置到.env文件"
    echo "  backup                   - 备份所有密钥"
    echo "  verify <节点名>          - 验证密钥文件"
    echo "  help                     - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 generate miner1       # 生成名为miner1的密钥对"
    echo "  $0 batch 5 node          # 生成5个密钥对: node1, node2, ..., node5"
    echo "  $0 export miner1         # 导出miner1的配置到~/nockchain/.env"
    echo "  $0 list                  # 列出所有密钥"
    echo "  $0 backup                # 备份所有密钥"
}

# 主函数
main() {
    create_key_directories
    
    case "${1:-help}" in
        generate)
            if [ -z "$2" ]; then
                error "请指定节点名称"
                echo "用法: $0 generate <节点名>"
                exit 1
            fi
            generate_single_key "$2"
            ;;
        batch)
            if [ -z "$2" ]; then
                error "请指定生成数量"
                echo "用法: $0 batch <数量> [前缀]"
                exit 1
            fi
            generate_batch_keys "$2" "$3"
            ;;
        list)
            list_keys
            ;;
        export)
            if [ -z "$2" ]; then
                error "请指定节点名称"
                echo "用法: $0 export <节点名> [目录]"
                exit 1
            fi
            export_key_config "$2" "$3"
            ;;
        backup)
            backup_keys
            ;;
        verify)
            if [ -z "$2" ]; then
                error "请指定节点名称"
                echo "用法: $0 verify <节点名>"
                exit 1
            fi
            verify_key "$2"
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
