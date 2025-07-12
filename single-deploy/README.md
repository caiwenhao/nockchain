# Nockchain 单节点部署工具

## 📋 概述

专为单节点或小规模（1-10个节点）Nockchain挖矿部署设计的完整工具集。基于Ubuntu系统的原生部署（无Docker），提供一键安装、监控和管理功能。

## 🚀 快速开始

### 一键部署
```bash
# 1. 设置执行权限
chmod +x *.sh

# 2. 一键安装环境
./native-deploy.sh install

# 3. 生成挖矿密钥
./native-deploy.sh keygen

# 4. 编辑配置文件
nano ~/nockchain/.env
# 将生成的公钥填入 MINING_PUBKEY 字段

### 第五步：快速同步（可选但推荐）
```bash
# 1. 配置火山云快照服务
nano simple-snapshot-solution.sh

# 修改以下变量：
VOLCANO_ENDPOINT="https://tos-s3-cn-beijing.volces.com"
VOLCANO_BUCKET="your-bucket-name"
VOLCANO_ACCESS_KEY="your-access-key"
VOLCANO_SECRET_KEY="your-secret-key"

# 2. 下载最新快照（大大减少同步时间）
./simple-snapshot-solution.sh download

# 这将下载快照到 ~/.data.nockchain/0.chkjam
# 节点启动时会自动从快照开始同步
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
./native-monitor.sh logs

# 检查挖矿活动
grep "mining-on" ~/nockchain/logs/miner-*.log

# 检查区块高度
grep "block.*added to validated blocks" ~/nockchain/logs/miner-*.log | tail -5
```

## 📋 系统要求

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

## 🛠️ 工具说明

| 脚本文件 | 功能 | 用途 |
|---------|------|------|
| `native-deploy.sh` | 部署和管理 | 安装、启动、停止、状态检查 |
| `native-monitor.sh` | 监控工具 | 实时监控、健康检查、日志分析 |
| `simple-snapshot-solution.sh` | 快照管理 | 上传/下载快照，加速同步 |
| `resource-monitor.sh` | 系统监控 | CPU、内存、磁盘使用情况 |

## 🚀 部署步骤

### 第一步：环境准备
```bash
# 1. 更新系统
sudo apt update && sudo apt upgrade -y

# 2. 上传部署文件到服务器
# 方法1: 使用scp
scp -r single-deploy/ user@server:~/

# 方法2: 使用git
git clone <your-repo> && cd nockchain/single-deploy

# 3. 设置执行权限
chmod +x *.sh
```

### 第二步：一键安装
```bash
# 自动安装所有依赖和构建项目
./native-deploy.sh install

# 这个过程会：
# - 安装 Rust nightly-2025-02-14
# - 安装系统依赖 (build-essential, clang, etc.)
# - 构建 Nockchain 项目
# - 配置防火墙 (开放4001/udp端口)
# - 创建启动脚本
```

### 第三步：生成密钥
```bash
# 生成新的挖矿密钥对
./native-deploy.sh keygen

# 输出示例：
# Public Key: 2m8qPa2KpHzwwzc6M5i5ZZVxfDXpJ1DNFuC2xoSKjEdajfMSpdNeec6JCZwzBJdeStZQbusXgTfenF5BxTMAJE98U7r8usYzhrZd3vqFaSuhMfiY5W3uE1uYFCvKjWiKqBcg
# Private Key: [保密信息]
# 重要：请安全保存私钥！
```

### 第四步：配置挖矿参数
```bash
# 编辑配置文件
nano ~/nockchain/.env

# 设置挖矿公钥（替换为你生成的公钥）
MINING_PUBKEY=你的公钥

# 其他配置
RUST_LOG=info,nockchain=info,nockchain_libp2p_io=info
MINIMAL_LOG_FORMAT=true
```

## 🔧 管理命令

### native-deploy.sh 命令
| 命令 | 功能 | 说明 |
|------|------|------|
| `install` | 安装环境 | 安装Rust、系统依赖、构建项目、配置防火墙 |
| `keygen` | 生成密钥 | 生成新的挖矿密钥对 |
| `start` | 启动服务 | 启动挖矿节点服务（后台运行） |
| `stop` | 停止服务 | 停止挖矿节点服务 |
| `status` | 查看状态 | 显示服务运行状态 |
| `service` | 创建服务 | 创建systemd系统服务 |
| `logs` | 查看日志 | 查看日志或进入screen会话 |

### native-monitor.sh 命令
| 命令 | 功能 | 说明 |
|------|------|------|
| `monitor` | 实时监控 | 显示实时的挖矿状态和系统信息 |
| `status` | 快速状态 | 显示节点运行状态摘要 |
| `health` | 健康检查 | 全面的系统健康检查 |
| `logs` | 日志查看 | 查看和分析日志文件 |
| `report` | 生成报告 | 生成详细的系统报告 |

### simple-snapshot-solution.sh 命令
| 命令 | 功能 | 说明 |
|------|------|------|
| `upload` | 上传快照 | 将本地快照上传到火山云 |
| `download` | 下载快照 | 从火山云下载最新快照 |
| `list` | 列出快照 | 显示火山云上的可用快照 |
| `cleanup` | 清理快照 | 清理旧快照（保留最近N个） |

## 📊 监控和维护

### 常用监控命令
```bash
# 查看挖矿进程
pgrep -f "nockchain.*--mine"
ps aux | grep nockchain

# 查看实时日志
tail -f ~/nockchain/logs/miner-*.log

# 查看系统资源
htop
free -h

# 查看网络连接
netstat -an | grep :4001

# 重启挖矿服务
./native-deploy.sh stop
./native-deploy.sh start
```

### 性能优化
```bash
# 1. 挖矿线程优化
nano ~/nockchain/start-miner.sh
# 调整 num_threads 参数

# 线程数建议：
# 保守: CPU核心数
# 标准: CPU核心数 * 2 - 4
# 激进: CPU核心数 * 3 / 2

# 2. 系统优化
# 增加文件描述符限制
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# 3. 网络优化
# 在 .env 文件中调整日志级别
RUST_LOG=error  # 减少日志输出，提高性能
```

## 🚨 故障排除

### 常见问题

#### 1. 节点无法启动
```bash
# 检查端口占用
sudo netstat -tulpn | grep 4001

# 检查配置文件
cat ~/nockchain/.env | grep MINING_PUBKEY

# 检查权限
ls -la ~/nockchain/

# 查看错误日志
tail -50 ~/nockchain/logs/miner-*.log | grep -i error
```

#### 2. 无法连接到其他节点
```bash
# 检查防火墙
sudo ufw status

# 检查网络连接
ping 8.8.8.8

# 检查P2P端口
sudo netstat -an | grep :4001

# 查看连接日志
grep -i "peer\|connection" ~/nockchain/logs/miner-*.log
```

#### 3. 挖矿效率低
```bash
# 检查CPU使用率
htop

# 调整挖矿线程数
nano ~/nockchain/start-miner.sh
# 修改 num_threads 参数

# 检查系统负载
uptime

# 查看挖矿日志
grep "mining-on" ~/nockchain/logs/miner-*.log | tail -10
```

#### 4. 同步速度慢
```bash
# 使用快照加速
./simple-snapshot-solution.sh download

# 检查网络带宽
speedtest-cli

# 查看同步进度
grep "block.*added to validated blocks" ~/nockchain/logs/miner-*.log | tail -10
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

## ❓ 常见问题 FAQ

### Q: 需要同时启动普通节点和挖矿节点吗？
**A:** 不需要！挖矿节点已经包含了普通节点的所有功能。挖矿节点 = 普通节点 + 挖矿功能。

### Q: 如何更换挖矿公钥？
**A:** 运行 `./native-deploy.sh keygen` 生成新密钥，然后编辑 `~/nockchain/.env` 文件更新 `MINING_PUBKEY`。

### Q: 快照文件有多大？
**A:** 通常几GB到几十GB，取决于区块链的当前状态。使用快照可以将同步时间从几天减少到几小时。

### Q: 如何备份重要数据？
**A:**
```bash
# 备份密钥
nockchain-wallet export-keys

# 备份配置
cp ~/nockchain/.env ~/nockchain-config-backup.env

# 备份快照
cp ~/nockchain/.data.nockchain/*.chkjam ~/backup/
```

### Q: 如何更新Nockchain版本？
**A:**
```bash
# 停止服务
./native-deploy.sh stop

# 备份配置
cp ~/nockchain/.env ~/nockchain/.env.backup

# 重新构建
cd ~/nockchain
make build
make install-nockchain

# 重启服务
./native-deploy.sh start
```

### Q: 火山云配置在哪里？
**A:** 编辑 `simple-snapshot-solution.sh` 文件顶部的配置变量：
- `VOLCANO_ACCESS_KEY`: 火山云访问密钥
- `VOLCANO_SECRET_KEY`: 火山云密钥
- `VOLCANO_BUCKET`: 存储桶名称

---

## 📞 获取帮助

如果遇到问题，可以：

1. 查看本文档的故障排除部分
2. 运行健康检查：`./native-monitor.sh health`
3. 生成详细报告：`./native-monitor.sh report`
4. 查看系统日志：`./native-monitor.sh logs`

**祝您挖矿愉快！** 🚀⛏️

> 注意：Nockchain是实验性软件，请谨慎使用于生产环境。

# 5. 启动挖矿
./native-deploy.sh start

# 6. 监控状态
./native-monitor.sh status
```

### 多节点部署（2-10个节点）
```bash
# 1. 批量生成密钥
./key-management.sh batch 5 miner  # 生成5个密钥

# 2. 查看生成的密钥
./key-management.sh list

# 3. 为每个节点导出配置
./key-management.sh export miner1 /path/to/node1/nockchain
./key-management.sh export miner2 /path/to/node2/nockchain
# ... 依此类推

# 4. 在每个服务器上部署
scp -r single-deploy/ user@server1:~/
ssh user@server1 "cd single-deploy && ./native-deploy.sh install && ./native-deploy.sh start"
```

## 📊 监控和维护

### 基础监控
```bash
# 查看节点状态
./native-monitor.sh status

# 实时监控
./native-monitor.sh monitor

# 健康检查
./native-monitor.sh health

# 生成报告
./native-monitor.sh report
```

### 资源监控
```bash
# 查看资源使用
./resource-monitor.sh status

# 实时资源监控
./resource-monitor.sh monitor

# 生成资源报告
./resource-monitor.sh report
```

### 快照管理
```bash
# 配置火山云存储（编辑脚本中的配置）
nano simple-snapshot-solution.sh

# 上传快照（主节点同步完成后）
./simple-snapshot-solution.sh upload

# 下载快照（新节点启动前）
./simple-snapshot-solution.sh download

# 查看可用快照
./simple-snapshot-solution.sh list
```

## 🔧 常用操作

### 节点管理
```bash
# 启动挖矿
./native-deploy.sh start

# 停止挖矿
./native-deploy.sh stop

# 查看状态
./native-deploy.sh status

# 查看日志
./native-deploy.sh logs
```

### 密钥管理
```bash
# 生成单个密钥
./key-management.sh generate node1

# 批量生成密钥
./key-management.sh batch 3 miner

# 列出所有密钥
./key-management.sh list

# 备份密钥
./key-management.sh backup

# 验证密钥
./key-management.sh verify node1
```

## 🔍 故障排除

### 常见问题
1. **编译失败** - 检查Rust版本和依赖
2. **挖矿无法启动** - 检查密钥配置和端口占用
3. **网络连接问题** - 检查防火墙和P2P端口
4. **同步缓慢** - 使用快照服务加速

### 日志查看
```bash
# 查看挖矿日志
tail -f ~/nockchain/logs/miner-*.log

# 查看错误日志
grep -i error ~/nockchain/logs/*.log

# 查看网络连接
grep -i peer ~/nockchain/logs/*.log
```

## 📈 性能优化

### 系统优化
```bash
# 网络参数优化
echo 'net.core.rmem_max=134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max=134217728' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 文件描述符优化
echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
```

### 挖矿优化
```bash
# 调整挖矿线程数（在.env文件中）
# 保守: CPU核心数
# 标准: CPU核心数 * 2 - 4
# 激进: CPU核心数 * 3 / 2

# 调整日志级别（减少I/O）
RUST_LOG=error  # 高性能模式
```

## 🔐 安全建议

1. **密钥安全**
   - 定期备份密钥文件
   - 使用强密码保护
   - 不要在公共场所暴露私钥

2. **系统安全**
   - 定期更新系统
   - 配置防火墙
   - 使用非root用户

3. **网络安全**
   - 仅开放必要端口（4001/udp）
   - 监控异常连接
   - 考虑使用VPN

## 📞 获取帮助

### 查看详细文档
- `NOCKCHAIN_NATIVE_DEPLOYMENT_GUIDE.md` - 完整部署指南
- `MINING_SETUP_GUIDE.md` - 挖矿设置指南
- `SIMPLE_SNAPSHOT_GUIDE.md` - 快照服务指南

### 脚本帮助
```bash
# 查看脚本帮助
./native-deploy.sh help
./native-monitor.sh help
./key-management.sh help
./resource-monitor.sh help
./simple-snapshot-solution.sh help
```

## 🏭 大规模部署

如果你需要部署大规模挖矿集群（100-1000个节点），请使用企业级部署方案：

```bash
# 返回上级目录
cd ../

# 查看企业级部署
cd enterprise-deploy/
cat README.md
```

---

**适用场景**: 单节点挖矿、小规模集群（1-10个节点）、测试环境、个人挖矿

**祝您挖矿愉快！** 🚀⛏️
