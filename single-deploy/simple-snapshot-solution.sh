#!/bin/bash

# Nockchain 简化快照方案 - 基于火山云对象存储
# 1. 主节点同步完成后上传快照
# 2. 新节点启动前下载快照

set -e

# 配置变量 - 请根据实际情况修改
VOLCANO_ENDPOINT="https://tos-s3-cn-beijing.volces.com"  # 火山云对象存储端点
VOLCANO_BUCKET="nockchain-snapshots"                     # 存储桶名称
VOLCANO_ACCESS_KEY=""                                    # 访问密钥
VOLCANO_SECRET_KEY=""                                    # 密钥

# 动态检测 Nockchain 数据目录
detect_nockchain_dir() {
    # 检测用户和设置安装目录
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

        local found_dir=""
        for dir in "${possible_dirs[@]}"; do
            if [ -d "$dir" ] && [ -d "$dir/.data.nockchain" ]; then
                found_dir="$dir"
                break
            fi
        done

        if [ -n "$found_dir" ]; then
            INSTALL_DIR="$found_dir"
        else
            warn "找不到 Nockchain 安装目录，使用默认路径"
            INSTALL_DIR="$HOME/nockchain"
        fi
    fi

    NOCKCHAIN_DATA_DIR="$INSTALL_DIR/.data.nockchain"
}

# 初始化目录检测
detect_nockchain_dir

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

# 检查配置
check_config() {
    if [ -z "$VOLCANO_ACCESS_KEY" ] || [ -z "$VOLCANO_SECRET_KEY" ]; then
        error "请先配置火山云访问密钥"
        echo "编辑脚本，设置 VOLCANO_ACCESS_KEY 和 VOLCANO_SECRET_KEY"
        exit 1
    fi
}

# 安装AWS CLI（兼容火山云对象存储）
install_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log "安装 AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    fi
    
    # 配置AWS CLI用于火山云
    aws configure set aws_access_key_id "$VOLCANO_ACCESS_KEY"
    aws configure set aws_secret_access_key "$VOLCANO_SECRET_KEY"
    aws configure set default.region "cn-beijing"
    aws configure set default.output "json"
}

# 获取当前区块高度
get_current_height() {
    local log_dir="$HOME/nockchain/logs"
    if [ -d "$log_dir" ]; then
        local latest_log=$(ls -t $log_dir/node-*.log $log_dir/miner-*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            grep "block.*added to validated blocks" "$latest_log" | tail -1 | awk '{print $NF}' || echo "0"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# 查找最新快照文件
find_latest_snapshot() {
    if [ -f "$NOCKCHAIN_DATA_DIR/0.chkjam" ]; then
        echo "$NOCKCHAIN_DATA_DIR/0.chkjam"
    elif [ -f "$NOCKCHAIN_DATA_DIR/1.chkjam" ]; then
        echo "$NOCKCHAIN_DATA_DIR/1.chkjam"
    else
        echo ""
    fi
}

# 上传快照到火山云
upload_snapshot() {
    log "开始上传快照到火山云对象存储..."
    
    check_config
    install_aws_cli
    
    # 查找快照文件
    local snapshot_file=$(find_latest_snapshot)
    if [ -z "$snapshot_file" ]; then
        error "未找到快照文件，请确保节点已完成同步"
        exit 1
    fi
    
    # 获取当前高度和时间戳
    local height=$(get_current_height)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_name="nockchain_snapshot_${height}_${timestamp}.chkjam"
    
    log "找到快照文件: $snapshot_file"
    log "当前区块高度: $height"
    log "上传文件名: $snapshot_name"
    
    # 生成元数据
    local file_size=$(stat -c%s "$snapshot_file")
    local checksum=$(sha256sum "$snapshot_file" | cut -d' ' -f1)
    
    local metadata_file="/tmp/${snapshot_name}.meta"
    cat > "$metadata_file" << EOF
{
    "height": $height,
    "timestamp": "$timestamp",
    "size": $file_size,
    "checksum": "$checksum",
    "created": "$(date -Iseconds)",
    "filename": "$snapshot_name"
}
EOF
    
    # 上传快照文件
    log "上传快照文件..."
    aws s3 cp "$snapshot_file" "s3://$VOLCANO_BUCKET/$snapshot_name" \
        --endpoint-url="$VOLCANO_ENDPOINT" \
        --storage-class STANDARD
    
    # 上传元数据
    log "上传元数据文件..."
    aws s3 cp "$metadata_file" "s3://$VOLCANO_BUCKET/${snapshot_name}.meta" \
        --endpoint-url="$VOLCANO_ENDPOINT" \
        --content-type "application/json"
    
    # 更新最新快照链接
    log "更新最新快照链接..."
    aws s3 cp "s3://$VOLCANO_BUCKET/$snapshot_name" "s3://$VOLCANO_BUCKET/latest.chkjam" \
        --endpoint-url="$VOLCANO_ENDPOINT"
    
    aws s3 cp "s3://$VOLCANO_BUCKET/${snapshot_name}.meta" "s3://$VOLCANO_BUCKET/latest.meta" \
        --endpoint-url="$VOLCANO_ENDPOINT"
    
    # 清理临时文件
    rm -f "$metadata_file"
    
    log "快照上传完成！"
    info "快照文件: s3://$VOLCANO_BUCKET/$snapshot_name"
    info "文件大小: $(du -h "$snapshot_file" | cut -f1)"
    info "区块高度: $height"
    info "校验和: $checksum"
}

# 从火山云下载快照
download_snapshot() {
    log "从火山云对象存储下载快照..."
    
    check_config
    install_aws_cli
    
    # 创建数据目录
    mkdir -p "$NOCKCHAIN_DATA_DIR"
    
    # 检查是否已有快照文件
    if [ -f "$NOCKCHAIN_DATA_DIR/0.chkjam" ] || [ -f "$NOCKCHAIN_DATA_DIR/1.chkjam" ]; then
        warn "检测到已存在快照文件"
        echo "现有文件:"
        ls -la "$NOCKCHAIN_DATA_DIR"/*.chkjam 2>/dev/null || true
        echo ""
        read -p "是否覆盖现有快照？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "取消下载"
            return 0
        fi
    fi
    
    # 下载最新快照元数据
    local temp_meta="/tmp/latest_snapshot.meta"
    log "获取最新快照信息..."
    
    if aws s3 cp "s3://$VOLCANO_BUCKET/latest.meta" "$temp_meta" \
        --endpoint-url="$VOLCANO_ENDPOINT" 2>/dev/null; then
        
        log "最新快照信息:"
        cat "$temp_meta" | jq . 2>/dev/null || cat "$temp_meta"
        echo ""
        
        # 提取快照文件名
        local snapshot_filename=$(cat "$temp_meta" | jq -r '.filename' 2>/dev/null || echo "latest.chkjam")
        
    else
        warn "无法获取快照元数据，使用默认文件名"
        local snapshot_filename="latest.chkjam"
    fi
    
    # 下载快照文件
    local temp_snapshot="/tmp/downloaded_snapshot.chkjam"
    log "下载快照文件: $snapshot_filename"
    
    aws s3 cp "s3://$VOLCANO_BUCKET/$snapshot_filename" "$temp_snapshot" \
        --endpoint-url="$VOLCANO_ENDPOINT"
    
    # 验证文件完整性
    if [ -f "$temp_meta" ]; then
        local expected_checksum=$(cat "$temp_meta" | jq -r '.checksum' 2>/dev/null)
        if [ -n "$expected_checksum" ] && [ "$expected_checksum" != "null" ]; then
            log "验证文件完整性..."
            local actual_checksum=$(sha256sum "$temp_snapshot" | cut -d' ' -f1)
            if [ "$expected_checksum" = "$actual_checksum" ]; then
                log "✓ 文件完整性验证通过"
            else
                error "✗ 文件完整性验证失败"
                error "期望: $expected_checksum"
                error "实际: $actual_checksum"
                rm -f "$temp_snapshot" "$temp_meta"
                exit 1
            fi
        fi
    fi
    
    # 安装快照文件
    log "安装快照文件..."
    cp "$temp_snapshot" "$NOCKCHAIN_DATA_DIR/0.chkjam"
    
    # 清理临时文件
    rm -f "$temp_snapshot" "$temp_meta"
    
    log "快照下载完成！"
    info "快照位置: $NOCKCHAIN_DATA_DIR/0.chkjam"
    info "文件大小: $(du -h "$NOCKCHAIN_DATA_DIR/0.chkjam" | cut -f1)"
    
    # 显示使用说明
    echo ""
    info "现在可以启动Nockchain节点，它将从快照开始同步："
    info "cd ~/nockchain && ./start-node.sh"
    info "或者启动挖矿: cd ~/nockchain && ./start-miner.sh"
}

# 列出可用快照
list_snapshots() {
    log "列出火山云上的可用快照..."
    
    check_config
    install_aws_cli
    
    echo "可用快照文件:"
    aws s3 ls "s3://$VOLCANO_BUCKET/" --endpoint-url="$VOLCANO_ENDPOINT" | grep "\.chkjam$" | sort -k1,2
    
    echo ""
    echo "元数据文件:"
    aws s3 ls "s3://$VOLCANO_BUCKET/" --endpoint-url="$VOLCANO_ENDPOINT" | grep "\.meta$" | sort -k1,2
}

# 清理旧快照
cleanup_old_snapshots() {
    local keep_count=${1:-5}
    log "清理旧快照，保留最近 $keep_count 个..."
    
    check_config
    install_aws_cli
    
    # 获取所有快照文件（按时间排序）
    local snapshots=$(aws s3 ls "s3://$VOLCANO_BUCKET/" --endpoint-url="$VOLCANO_ENDPOINT" | grep "nockchain_snapshot_.*\.chkjam$" | sort -k1,2 -r | tail -n +$((keep_count + 1)) | awk '{print $4}')
    
    if [ -n "$snapshots" ]; then
        echo "将删除以下旧快照:"
        echo "$snapshots"
        echo ""
        read -p "确认删除？(y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "$snapshots" | while read -r snapshot; do
                log "删除: $snapshot"
                aws s3 rm "s3://$VOLCANO_BUCKET/$snapshot" --endpoint-url="$VOLCANO_ENDPOINT"
                aws s3 rm "s3://$VOLCANO_BUCKET/${snapshot}.meta" --endpoint-url="$VOLCANO_ENDPOINT" 2>/dev/null || true
            done
            log "清理完成"
        fi
    else
        log "没有需要清理的旧快照"
    fi
}

# 显示帮助
show_help() {
    echo "Nockchain 简化快照方案 - 基于火山云对象存储"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令说明:"
    echo "  upload    - 上传当前节点快照到火山云"
    echo "  download  - 从火山云下载最新快照"
    echo "  list      - 列出火山云上的可用快照"
    echo "  cleanup   - 清理旧快照（保留最近5个）"
    echo "  help      - 显示此帮助信息"
    echo ""
    echo "使用流程:"
    echo "1. 主节点同步完成后: $0 upload"
    echo "2. 新节点启动前: $0 download"
    echo "3. 然后正常启动节点即可"
    echo ""
    echo "配置说明:"
    echo "请编辑脚本顶部的火山云配置变量："
    echo "- VOLCANO_ACCESS_KEY: 火山云访问密钥"
    echo "- VOLCANO_SECRET_KEY: 火山云密钥"
    echo "- VOLCANO_BUCKET: 存储桶名称"
}

# 主函数
main() {
    case "${1:-help}" in
        upload)
            upload_snapshot
            ;;
        download)
            download_snapshot
            ;;
        list)
            list_snapshots
            ;;
        cleanup)
            cleanup_old_snapshots ${2:-5}
            ;;
        help)
            show_help
            ;;
        *)
            show_help
            ;;
    esac
}

main "$@"
