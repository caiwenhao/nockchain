# Nockchain 挖矿节点部署文件说明

本目录包含了在Ubuntu系统上**原生部署**（无Docker）Nockchain挖矿节点的完整工具集。

## 📁 文件清单

### 📖 文档文件
- **`NOCKCHAIN_NATIVE_DEPLOYMENT_GUIDE.md`** - 详细的原生部署指南文档
- **`README_DEPLOYMENT.md`** - 本说明文件
- **`MINING_SETUP_GUIDE.md`** - 完整的挖矿部署指南

### 🛠️ 部署脚本
- **`native-deploy.sh`** - 原生部署脚本（推荐使用）
- **`native-monitor.sh`** - 原生部署监控脚本
- **`simple-snapshot-solution.sh`** - 火山云快照管理脚本
- **`key-management.sh`** - 密钥管理脚本
- **`resource-monitor.sh`** - 资源使用监控脚本



## 🚀 快速开始

### 使用原生部署脚本（推荐）

1. **下载脚本到Ubuntu服务器**
   ```bash
   # 将脚本文件上传到服务器
   chmod +x native-deploy.sh native-monitor.sh
   ```

2. **一键安装环境**
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

5. **启动挖矿服务**
   ```bash
   ./native-deploy.sh start
   ```

6. **查看运行状态**
   ```bash
   ./native-deploy.sh status
   ./native-monitor.sh status
   ```

### 手动部署

请参考 `NOCKCHAIN_NATIVE_DEPLOYMENT_GUIDE.md` 文档中的详细步骤。

### 大规模部署

如果你需要部署大规模挖矿集群（100-1000个节点），请返回上级目录使用企业级部署方案：

```bash
# 返回上级目录
cd ../

# 查看企业级部署方案
cd enterprise-deploy/
cat README.md
```

## 📊 监控和维护

### 使用监控脚本

1. **查看节点状态**
   ```bash
   ./native-monitor.sh status
   ```

2. **实时监控模式**
   ```bash
   ./native-monitor.sh monitor
   ```

3. **健康检查**
   ```bash
   ./native-monitor.sh health
   ```

4. **生成详细报告**
   ```bash
   ./native-monitor.sh report
   ```

5. **查看日志**
   ```bash
   ./native-monitor.sh logs
   ./native-monitor.sh tail  # 实时跟踪
   ```

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

# 重启挖矿服务 (如果使用systemd)
sudo systemctl restart nockchain-miner

# 停止挖矿服务
./native-deploy.sh stop
# 或者
pkill -f "nockchain.*--mine"
```

## 🔧 脚本功能说明

### native-deploy.sh 功能

| 命令 | 功能 | 说明 |
|------|------|------|
| `install` | 安装环境 | 安装Rust、系统依赖、构建项目、配置防火墙 |
| `keygen` | 生成密钥 | 生成新的挖矿密钥对 |
| `start` | 启动服务 | 启动挖矿节点服务（后台运行） |
| `stop` | 停止服务 | 停止挖矿节点服务 |
| `status` | 查看状态 | 显示服务运行状态 |
| `service` | 创建服务 | 创建systemd系统服务 |
| `logs` | 查看日志 | 查看日志或进入screen会话 |

### native-monitor.sh 功能

| 命令 | 功能 | 说明 |
|------|------|------|
| `status` | 状态概览 | 显示系统和挖矿状态概览 |
| `monitor` | 实时监控 | 进入实时监控界面 |
| `health` | 健康检查 | 检查系统健康状况 |
| `report` | 生成报告 | 生成详细的状态报告 |
| `logs` | 查看日志 | 查看最新日志 |
| `tail` | 实时日志 | 实时跟踪日志输出 |

## 🔍 故障排除

### 常见问题

1. **Rust编译问题**
   ```bash
   # 检查Rust版本
   rustc --version
   rustup show

   # 重新安装正确版本
   rustup toolchain install nightly-2025-02-14
   rustup default nightly-2025-02-14
   ```

2. **端口被占用**
   ```bash
   sudo netstat -tulpn | grep 4001
   sudo kill -9 <PID>
   ```

3. **挖矿进程无法启动**
   ```bash
   # 检查配置文件
   cat ~/nockchain/.env | grep MINING_PUBKEY

   # 检查权限
   ls -la ~/nockchain/
   ```

4. **内存不足**
   ```bash
   # 添加交换空间
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

### 日志分析

```bash
# 查找挖矿活动
grep "mining-on" ~/nockchain/logs/miner-*.log

# 查找区块信息
grep "block.*added" ~/nockchain/logs/miner-*.log

# 查找错误信息
grep -i error ~/nockchain/logs/miner-*.log

# 查找网络连接
grep -i peer ~/nockchain/logs/miner-*.log
```

## 📈 性能优化建议

### 硬件配置

- **CPU**: 推荐16核心或更多
- **内存**: 推荐32GB或更多
- **存储**: 推荐NVMe SSD
- **网络**: 推荐100Mbps+带宽

### 系统优化

```bash
# 优化网络参数
echo 'net.core.rmem_max=134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max=134217728' | sudo tee -a /etc/sysctl.conf
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 优化文件描述符限制
echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
```

### 挖矿优化

```bash
# 在 .env 文件中调整日志级别
RUST_LOG=error  # 减少日志输出，提高性能

# 调整挖矿线程数（在docker-entrypoint.sh中）
num_threads=$(($(nproc) * 3 / 2))  # 更激进的线程配置
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
   - 仅开放必要端口
   - 监控异常连接
   - 考虑使用VPN

## 📞 获取帮助

如果遇到问题，可以：

1. 查看详细的部署指南：`NOCKCHAIN_DEPLOYMENT_GUIDE.md`
2. 运行健康检查：`./monitor.sh health`
3. 生成详细报告：`./monitor.sh report`
4. 查看系统日志：`./monitor.sh logs`

## 📝 更新日志

- **v1.0** - 初始版本，包含基础部署和监控功能
- 支持Docker容器化部署
- 支持实时监控和健康检查
- 支持自动化部署脚本

---

**祝您挖矿愉快！** 🚀⛏️

> 注意：Nockchain是实验性软件，请谨慎使用于生产环境。
