# Nockchain 原生挖矿节点部署指南 (Ubuntu)

## 📋 概述

Nockchain 是一个轻量级区块链，专为重量级可验证应用设计。本指南将帮助您在 Ubuntu 系统上进行**原生部署**（无Docker）Nockchain 挖矿节点。

## 🔧 系统要求

### 最低配置
- **操作系统**: Ubuntu 20.04 LTS 或更高版本
- **CPU**: 4核心 (推荐8核心或更多用于挖矿)
- **内存**: 8GB RAM (推荐16GB或更多)
- **存储**: 50GB 可用空间 (SSD推荐)
- **网络**: 稳定的互联网连接，至少10Mbps

### 推荐配置 (挖矿优化)
- **CPU**: 16核心或更多 (支持超线程)
- **内存**: 32GB RAM
- **存储**: 100GB+ NVMe SSD
- **网络**: 100Mbps+ 带宽

## 🚀 快速部署 (一键脚本)

### 使用自动化部署脚本

1. **下载部署脚本**
```bash
# 将 native-deploy.sh 上传到服务器
chmod +x native-deploy.sh
```

2. **一键安装**
```bash
./native-deploy.sh install
```

3. **生成挖矿密钥**
```bash
./native-deploy.sh keygen
```

4. **编辑配置文件**
```bash
nano ~/nockchain/.env
# 将生成的公钥填入 MINING_PUBKEY 字段
```

5. **启动挖矿**
```bash
./native-deploy.sh start
```

6. **查看状态**
```bash
./native-deploy.sh status
```

## 🛠️ 手动部署步骤

### 1. 安装系统依赖

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装必要依赖
sudo apt install -y \
    curl \
    wget \
    git \
    build-essential \
    clang \
    llvm-dev \
    libclang-dev \
    pkg-config \
    make \
    screen \
    tmux \
    htop \
    net-tools \
    ufw
```

### 2. 安装 Rust

```bash
# 安装 rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env

# 安装指定的 nightly 版本
rustup toolchain install nightly-2025-02-14
rustup default nightly-2025-02-14
rustup component add miri

# 添加到 PATH
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 3. 获取项目源码

```bash
# 方法1: 如果有Git仓库
git clone <your-nockchain-repo> ~/nockchain
cd ~/nockchain

# 方法2: 手动复制源码到 ~/nockchain 目录
mkdir -p ~/nockchain
# 将项目文件复制到此目录
```

### 4. 构建项目

```bash
cd ~/nockchain

# 复制环境配置
cp .env_example .env

# 构建项目
make build

# 安装组件
make install-hoonc
make install-nockchain-wallet
make install-nockchain
```

### 5. 生成挖矿密钥

```bash
# 生成新的密钥对
nockchain-wallet keygen

# 将公钥添加到 .env 文件
nano .env
# 修改 MINING_PUBKEY=你的公钥
```

### 6. 配置防火墙

```bash
# 开放 P2P 端口
sudo ufw allow ssh
sudo ufw allow 4001/udp comment "Nockchain P2P"
sudo ufw --force enable
```

### 7. 启动挖矿节点

#### 方法1: 前台运行（测试用）
```bash
cd ~/nockchain
source .env
export RUST_LOG MINIMAL_LOG_FORMAT MINING_PUBKEY

# 计算挖矿线程数
total_threads=$(nproc)
num_threads=$((total_threads > 4 ? total_threads * 2 - 4 : total_threads))

# 启动挖矿
nockchain --mining-pubkey "${MINING_PUBKEY}" --mine --num-threads $num_threads
```

#### 方法2: 后台运行（推荐）
```bash
cd ~/nockchain

# 使用 screen 在后台运行
screen -dmS nockchain-miner bash -c 'source .env && export RUST_LOG MINIMAL_LOG_FORMAT MINING_PUBKEY && nockchain --mining-pubkey "${MINING_PUBKEY}" --mine --num-threads $(($(nproc) > 4 ? $(nproc) * 2 - 4 : $(nproc))) 2>&1 | tee logs/miner-$(date +%Y%m%d-%H%M%S).log'

# 查看后台会话
screen -r nockchain-miner

# 退出会话但保持运行: Ctrl+A, D
```

#### 方法3: 系统服务（生产环境推荐）
```bash
# 创建系统服务
sudo tee /etc/systemd/system/nockchain-miner.service > /dev/null <<EOF
[Unit]
Description=Nockchain Miner Service
After=network.target

[Service]
Type=simple
User=$(whoami)
Group=$(whoami)
WorkingDirectory=$HOME/nockchain
ExecStart=$HOME/nockchain/start-miner.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
sudo systemctl daemon-reload
sudo systemctl enable nockchain-miner
sudo systemctl start nockchain-miner

# 查看服务状态
sudo systemctl status nockchain-miner
sudo journalctl -u nockchain-miner -f
```

## 📊 监控和维护

### 使用监控脚本

1. **下载监控脚本**
```bash
# 将 native-monitor.sh 上传到服务器
chmod +x native-monitor.sh
```

2. **查看节点状态**
```bash
./native-monitor.sh status
```

3. **实时监控**
```bash
./native-monitor.sh monitor
```

4. **健康检查**
```bash
./native-monitor.sh health
```

5. **生成报告**
```bash
./native-monitor.sh report
```

### 手动监控命令

```bash
# 检查挖矿进程
pgrep -f "nockchain.*--mine"
ps aux | grep nockchain

# 查看系统资源
htop
free -h
df -h

# 查看网络连接
netstat -an | grep :4001
ss -tuln | grep :4001

# 查看日志
tail -f ~/nockchain/logs/miner-*.log

# 查看挖矿状态
grep "mining-on" ~/nockchain/logs/miner-*.log | tail -5

# 查看区块高度
grep "block.*added to validated blocks" ~/nockchain/logs/miner-*.log | tail -5
```

## 🔧 高级配置

### 网络配置

```bash
# 指定固定端口和公网IP
nockchain --bind /ip4/你的公网IP/udp/4001/quic-v1 --mining-pubkey 你的公钥 --mine

# NAT 环境下的配置
nockchain --bind /ip4/0.0.0.0/udp/4001/quic-v1 --mining-pubkey 你的公钥 --mine
```

### 日志配置

在 `.env` 文件中配置：
```bash
# 基础信息
RUST_LOG=info

# 调试信息
RUST_LOG=debug

# 仅错误
RUST_LOG=error

# 分模块配置
RUST_LOG=nockchain=info,libp2p=warn,nockchain_libp2p_io=info

# 简化日志格式
MINIMAL_LOG_FORMAT=true
```

### 性能优化

```bash
# 1. 系统参数优化
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'net.core.rmem_max=134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max=134217728' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 2. 文件描述符限制
echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf

# 3. 挖矿线程优化
# 保守配置: CPU核心数
num_threads=$(nproc)

# 标准配置: CPU核心数 * 2 - 4
num_threads=$(($(nproc) * 2 - 4))

# 激进配置: CPU核心数 * 3 / 2
num_threads=$(($(nproc) * 3 / 2))
```

## 🚨 故障排除

### 常见问题

1. **编译失败**
```bash
# 检查 Rust 版本
rustc --version
rustup show

# 重新安装正确版本
rustup toolchain install nightly-2025-02-14
rustup default nightly-2025-02-14
```

2. **挖矿进程无法启动**
```bash
# 检查配置文件
cat ~/.env | grep MINING_PUBKEY

# 检查端口占用
sudo netstat -tulpn | grep 4001

# 检查权限
ls -la ~/nockchain/
```

3. **无法连接到其他节点**
```bash
# 检查防火墙
sudo ufw status

# 检查网络连接
ping 8.8.8.8

# 检查日志中的连接信息
grep -i "peer\|connection" ~/nockchain/logs/miner-*.log
```

4. **挖矿效率低**
```bash
# 检查CPU使用率
htop

# 调整挖矿线程数
# 在启动命令中修改 --num-threads 参数

# 检查系统负载
uptime
```

### 日志分析

```bash
# 查找挖矿活动
grep "mining-on" ~/nockchain/logs/miner-*.log

# 查找新区块
grep "block.*added to validated blocks" ~/nockchain/logs/miner-*.log

# 查找错误
grep -i "error\|failed\|panic" ~/nockchain/logs/miner-*.log

# 查找网络事件
grep -i "peer\|connection" ~/nockchain/logs/miner-*.log
```

## 📈 性能监控

### 系统监控

```bash
# CPU 和内存监控
watch -n 5 'echo "=== $(date) ==="; echo "CPU:"; top -bn1 | grep "Cpu(s)"; echo "Memory:"; free -h; echo "Nockchain Process:"; ps aux | grep nockchain | grep -v grep'

# 网络监控
watch -n 10 'echo "=== Network Stats ==="; netstat -an | grep :4001 | wc -l; echo "P2P Connections"; ss -tuln | grep :4001'

# 磁盘监控
watch -n 30 'df -h /'
```

### 挖矿监控

```bash
# 挖矿活动监控
watch -n 30 'echo "=== Mining Activity ==="; tail -20 ~/nockchain/logs/miner-*.log | grep "mining-on" | tail -5'

# 区块监控
watch -n 60 'echo "=== Block Height ==="; grep "block.*added to validated blocks" ~/nockchain/logs/miner-*.log | tail -5'
```

## 🔐 安全建议

1. **密钥安全**
   - 定期备份密钥文件
   - 使用强密码保护密钥
   - 不要在公共场所暴露私钥

2. **系统安全**
   - 定期更新系统和依赖
   - 配置防火墙规则
   - 使用非 root 用户运行
   - 定期检查系统日志

3. **网络安全**
   - 仅开放必要端口 (4001/udp)
   - 监控异常连接
   - 考虑使用 VPN 或专用网络

## 📞 维护操作

### 日常维护

```bash
# 重启挖矿服务
sudo systemctl restart nockchain-miner

# 查看服务状态
sudo systemctl status nockchain-miner

# 查看实时日志
sudo journalctl -u nockchain-miner -f

# 停止挖矿服务
sudo systemctl stop nockchain-miner

# 手动停止进程
pkill -f "nockchain.*--mine"
screen -S nockchain-miner -X quit
```

### 更新升级

```bash
cd ~/nockchain

# 备份配置
cp .env .env.backup

# 更新代码
git pull origin main

# 重新构建
make build
make install-hoonc
make install-nockchain
make install-nockchain-wallet

# 重启服务
sudo systemctl restart nockchain-miner
```

### 数据备份

```bash
# 备份密钥
nockchain-wallet export-keys

# 备份配置
cp ~/nockchain/.env ~/nockchain-config-backup.env

# 备份日志
tar -czf nockchain-logs-$(date +%Y%m%d).tar.gz ~/nockchain/logs/
```

---

**注意**: Nockchain 是实验性软件，许多部分未经审计。请谨慎使用，我们不对软件行为做任何保证。

**祝您挖矿愉快！** 🚀⛏️
