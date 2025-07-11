# Nockchain 单节点部署工具集

## 📋 概述

本目录包含了专为单节点或小规模（1-10个节点）Nockchain挖矿部署设计的完整工具集。所有工具都基于Ubuntu系统的原生部署（无Docker）。

## 📁 文件说明

### 📖 文档文件
- **`README.md`** - 本说明文件
- **`README_DEPLOYMENT.md`** - 详细的部署文件说明
- **`NOCKCHAIN_NATIVE_DEPLOYMENT_GUIDE.md`** - 完整的原生部署指南
- **`MINING_SETUP_GUIDE.md`** - 挖矿节点设置指南
- **`SIMPLE_SNAPSHOT_GUIDE.md`** - 快照服务使用指南

### 🛠️ 核心脚本
- **`native-deploy.sh`** - 主要部署脚本（一键安装）
- **`native-monitor.sh`** - 节点监控脚本
- **`key-management.sh`** - 密钥管理工具
- **`simple-snapshot-solution.sh`** - 火山云快照管理
- **`resource-monitor.sh`** - 系统资源监控

## 🚀 快速开始

### 单节点部署
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
