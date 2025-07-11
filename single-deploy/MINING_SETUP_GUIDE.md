# Nockchain 挖矿完整部署指南

## 🎯 概述

本指南将帮助你从零开始部署Nockchain挖矿节点，包括所有必需的准备工作和详细步骤。

## 📋 准备清单

### 1. 硬件要求

#### 最低配置
- **CPU**: 4核心
- **内存**: 8GB RAM
- **存储**: 50GB SSD
- **网络**: 10Mbps 稳定连接

#### 推荐配置（挖矿优化）
- **CPU**: 16核心或更多（支持超线程）
- **内存**: 32GB RAM
- **存储**: 100GB+ NVMe SSD
- **网络**: 100Mbps+ 带宽

### 2. 系统要求

- **操作系统**: Ubuntu 20.04 LTS 或更高版本
- **用户权限**: 非root用户，但有sudo权限
- **网络**: 能够访问互联网和开放P2P端口

### 3. 必需文件

从你的开发环境复制以下文件到服务器：

```bash
# 核心部署脚本
native-deploy.sh
native-monitor.sh
simple-snapshot-solution.sh

# 项目源码（整个目录）
nockchain/
├── Cargo.toml
├── Makefile
├── scripts/
├── crates/
├── hoon/
└── 其他源码文件
```

## 🚀 部署步骤

### 第一步：准备服务器环境

```bash
# 1. 更新系统
sudo apt update && sudo apt upgrade -y

# 2. 创建工作目录
mkdir -p ~/nockchain-mining
cd ~/nockchain-mining

# 3. 上传文件到服务器
# 方法1: 使用scp
scp -r /path/to/nockchain user@server:~/nockchain-mining/
scp native-deploy.sh native-monitor.sh simple-snapshot-solution.sh user@server:~/nockchain-mining/

# 方法2: 使用git（如果有仓库）
git clone <your-nockchain-repo> nockchain
```

### 第二步：执行自动化部署

```bash
# 1. 设置执行权限
chmod +x native-deploy.sh native-monitor.sh simple-snapshot-solution.sh

# 2. 一键安装环境
./native-deploy.sh install

# 这个过程会：
# - 安装Rust nightly-2025-02-14
# - 安装系统依赖
# - 构建Nockchain项目
# - 配置防火墙
# - 创建启动脚本
```

### 第三步：生成挖矿密钥

```bash
# 生成新的挖矿密钥对
./native-deploy.sh keygen

# 输出示例：
# Public Key: EHmKL2U3vXfS5GYAY5aVnGdukfDWwvkQPCZXnjvZVShsSQi3UAuA4tQQpVwGJMzc9FfpTY8pLDkqhBGfWutiF4prrCktUH9oAWJxkXQBzAavKDc95NR3DjmYwnnw8GuugnK
# Private Key: [保密信息]
# Chain Code: [保密信息]
# Seed Phrase: [12个单词的助记词]

# 重要：请安全保存私钥和助记词！
```

### 第四步：配置挖矿参数

```bash
# 编辑配置文件
nano ~/nockchain/.env

# 设置挖矿公钥（替换为你生成的公钥）
MINING_PUBKEY=EHmKL2U3vXfS5GYAY5aVnGdukfDWwvkQPCZXnjvZVShsSQi3UAuA4tQQpVwGJMzc9FfpTY8pLDkqhBGfWutiF4prrCktUH9oAWJxkXQBzAavKDc95NR3DjmYwnnw8GuugnK

# 其他配置
RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info
MINIMAL_LOG_FORMAT=true
```

### 第五步：快速同步（可选但推荐）

如果有可用的快照，可以快速同步：

```bash
# 配置快照下载（如果你有快照服务）
# 编辑 simple-snapshot-solution.sh 中的火山云配置

# 下载最新快照
./simple-snapshot-solution.sh download

# 这将大大减少初始同步时间
```

### 第六步：启动挖矿

```bash
# 方法1: 前台运行（测试用）
cd ~/nockchain
./start-miner.sh

# 方法2: 后台运行（推荐）
./native-deploy.sh start

# 方法3: 系统服务（生产环境）
./native-deploy.sh service  # 创建系统服务
sudo systemctl start nockchain-miner
```

### 第七步：监控挖矿状态

```bash
# 查看实时状态
./native-monitor.sh monitor

# 查看简要状态
./native-monitor.sh status

# 查看日志
./native-monitor.sh tail

# 检查挖矿活动
grep "mining-on" ~/nockchain/logs/miner-*.log

# 检查区块高度
grep "block.*added to validated blocks" ~/nockchain/logs/miner-*.log | tail -5
```

## 🔧 配置优化

### 1. 挖矿线程优化

```bash
# 编辑启动脚本，调整线程数
nano ~/nockchain/start-miner.sh

# 线程数计算建议：
# 保守: CPU核心数
# 标准: CPU核心数 * 2 - 4  
# 激进: CPU核心数 * 3 / 2

# 例如16核CPU：
# 保守: 16线程
# 标准: 28线程 (16*2-4)
# 激进: 24线程 (16*3/2)
```

### 2. 系统性能优化

```bash
# 网络参数优化
echo 'net.core.rmem_max=134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max=134217728' | sudo tee -a /etc/sysctl.conf
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 文件描述符优化
echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
```

### 3. 日志级别调整

```bash
# 在 .env 文件中调整日志级别
# 高性能模式（减少日志输出）
RUST_LOG=error

# 调试模式（详细日志）
RUST_LOG=debug,nockchain=debug,nockchain_libp2p_io=debug

# 平衡模式（推荐）
RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info
```

## 📊 监控和维护

### 1. 挖矿状态检查

```bash
# 创建监控脚本
cat > ~/check-mining.sh << 'EOF'
#!/bin/bash

echo "=== 挖矿状态检查 ==="
echo "时间: $(date)"

# 检查进程
if pgrep -f "nockchain.*--mine" > /dev/null; then
    echo "✓ 挖矿进程运行中"
    echo "PID: $(pgrep -f 'nockchain.*--mine')"
else
    echo "✗ 挖矿进程未运行"
fi

# 检查最近挖矿活动
echo ""
echo "最近挖矿活动:"
grep "mining-on" ~/nockchain/logs/miner-*.log | tail -3

# 检查区块高度
echo ""
echo "最新区块:"
grep "block.*added to validated blocks" ~/nockchain/logs/miner-*.log | tail -1

# 检查网络连接
echo ""
echo "P2P连接数: $(netstat -an | grep :4001 | wc -l)"

# 检查系统资源
echo ""
echo "系统资源:"
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "内存: $(free -h | grep Mem | awk '{print $3"/"$2}')"
EOF

chmod +x ~/check-mining.sh
```

### 2. 自动重启脚本

```bash
# 创建自动重启脚本
cat > ~/auto-restart.sh << 'EOF'
#!/bin/bash

# 检查挖矿进程是否运行
if ! pgrep -f "nockchain.*--mine" > /dev/null; then
    echo "[$(date)] 挖矿进程未运行，正在重启..." >> ~/mining-restart.log
    
    cd ~/nockchain
    ./start-miner-daemon.sh
    
    echo "[$(date)] 挖矿进程已重启" >> ~/mining-restart.log
fi
EOF

chmod +x ~/auto-restart.sh

# 添加到定时任务
crontab -e
# 添加以下行（每5分钟检查一次）
*/5 * * * * /home/$(whoami)/auto-restart.sh
```

### 3. 性能监控

```bash
# 创建性能监控脚本
cat > ~/performance-monitor.sh << 'EOF'
#!/bin/bash

LOG_FILE="~/mining-performance.log"

while true; do
    timestamp=$(date)
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    mem_usage=$(free | grep Mem | awk '{printf("%.1f"), $3/$2 * 100.0}')
    
    # 获取挖矿进程的资源使用
    miner_pid=$(pgrep -f "nockchain.*--mine")
    if [ -n "$miner_pid" ]; then
        miner_cpu=$(ps -p $miner_pid -o %cpu --no-headers)
        miner_mem=$(ps -p $miner_pid -o %mem --no-headers)
        
        echo "[$timestamp] 系统CPU: ${cpu_usage}% | 系统内存: ${mem_usage}% | 挖矿CPU: ${miner_cpu}% | 挖矿内存: ${miner_mem}%" >> $LOG_FILE
    else
        echo "[$timestamp] 挖矿进程未运行" >> $LOG_FILE
    fi
    
    sleep 300  # 每5分钟记录一次
done
EOF

chmod +x ~/performance-monitor.sh
```

## 🚨 故障排除

### 常见问题

1. **编译失败**
```bash
# 检查Rust版本
rustc --version
rustup show

# 重新安装正确版本
rustup toolchain install nightly-2025-02-14
rustup default nightly-2025-02-14
```

2. **挖矿进程无法启动**
```bash
# 检查配置
cat ~/nockchain/.env | grep MINING_PUBKEY

# 检查端口占用
sudo netstat -tulpn | grep 4001

# 查看错误日志
tail -50 ~/nockchain/logs/miner-*.log
```

3. **无法连接到网络**
```bash
# 检查防火墙
sudo ufw status

# 检查网络连接
ping 8.8.8.8

# 检查P2P连接
netstat -an | grep :4001
```

4. **挖矿效率低**
```bash
# 检查CPU使用率
htop

# 调整挖矿线程数
nano ~/nockchain/start-miner.sh

# 检查系统负载
uptime
```

## 💰 挖矿收益

### 查看余额

```bash
# 查看挖矿地址余额
nockchain-wallet --nockchain-socket ./nockchain.sock list-notes-by-pubkey -p YOUR_MINING_PUBKEY
```

### 备份密钥

```bash
# 导出密钥（重要！）
nockchain-wallet export-keys

# 保存到安全位置
cp keys.export ~/keys-backup-$(date +%Y%m%d).export
```

## 🔐 安全建议

1. **密钥安全**
   - 安全保存私钥和助记词
   - 定期备份密钥文件
   - 不要在公共场所暴露私钥

2. **系统安全**
   - 定期更新系统
   - 使用防火墙
   - 监控异常活动

3. **网络安全**
   - 仅开放必要端口
   - 使用强密码
   - 考虑使用VPN

---

按照这个指南，你就可以成功部署并运行Nockchain挖矿节点了！🚀⛏️
