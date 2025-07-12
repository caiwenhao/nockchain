# Nockchain 一体化部署指南

## 🎯 概述

`deploy-to-servers.sh` 是一个一体化脚本，可以自动完成：
1. **打包** - 打包已编译的二进制文件
2. **分发** - 传输到远程服务器
3. **部署** - 远程自动安装和配置

## 📋 前提条件

### 编译服务器 (当前服务器)
- ✅ 已运行 `./native-deploy.sh install` 完成编译
- ✅ 二进制文件在 `~/.cargo/bin/` 目录
- ✅ 配置了到目标服务器的 SSH 密钥认证

### 目标服务器
- ✅ Ubuntu 22.04 LTS
- ✅ SSH 访问权限
- ✅ 4GB+ RAM

## 🚀 快速使用

### 方法1: 命令行指定服务器

```bash
# 给脚本执行权限
chmod +x deploy-to-servers.sh

# 部署到指定服务器
./deploy-to-servers.sh 192.168.1.100 192.168.1.101 192.168.1.102
```

### 方法2: 使用服务器列表文件

```bash
# 创建服务器列表
cp servers.txt.example servers.txt
nano servers.txt  # 编辑添加你的服务器

# 部署到列表中的所有服务器
./deploy-to-servers.sh
```

### 方法3: 自定义参数

```bash
# 指定 SSH 用户和安装目录
./deploy-to-servers.sh -u ubuntu -d /home/ubuntu/nockchain server1 server2

# 使用自定义服务器列表文件
./deploy-to-servers.sh -f my-servers.txt
```

## 📝 服务器列表格式

创建 `servers.txt` 文件：

```
# 服务器列表
192.168.1.100
192.168.1.101
server1.example.com
server2.example.com
```

## ⚡ 脚本功能

### 自动完成的任务

1. **环境检查**
   - 验证本地二进制文件
   - 测试 SSH 连接

2. **打包**
   - 收集二进制文件
   - 创建安装脚本
   - 生成部署包

3. **分发**
   - 上传到所有目标服务器
   - 并行处理提高效率

4. **远程部署**
   - 安装二进制文件到 `~/.cargo/bin/`
   - 创建项目目录
   - 生成挖矿密钥
   - 配置防火墙
   - 创建启动脚本

## 🔧 命令行选项

```
用法: ./deploy-to-servers.sh [选项] [服务器列表]

选项:
  -u USER     SSH 用户名 (默认: root)
  -d DIR      远程安装目录 (默认: /root/nockchain)
  -f FILE     服务器列表文件 (默认: servers.txt)
  -h          显示帮助
```

## 📊 部署结果

脚本会显示每台服务器的部署状态：

```
✅ 192.168.1.100 部署成功
✅ 192.168.1.101 部署成功
❌ 192.168.1.102 部署失败

部署完成！
成功: 2/3 台服务器
```

## 🚀 启动挖矿

部署完成后，在各服务器上启动：

```bash
# 方法1: 直接 SSH 启动
ssh root@192.168.1.100 'cd /root/nockchain && ./start-miner.sh'

# 方法2: 登录服务器启动
ssh root@192.168.1.100
cd /root/nockchain
./start-miner.sh
```

## 🔍 故障排除

### 常见问题

**Q: SSH 连接失败？**
```bash
# 检查 SSH 密钥
ssh-copy-id root@server-ip

# 测试连接
ssh root@server-ip "echo 'SSH OK'"
```

**Q: 二进制文件缺失？**
```bash
# 重新编译
./native-deploy.sh install

# 检查文件
ls -la ~/.cargo/bin/nockchain*
```

**Q: 部分服务器失败？**
- 检查网络连接
- 确认服务器系统版本
- 查看 SSH 权限

### 手动验证

在目标服务器上验证安装：

```bash
# 检查二进制文件
which nockchain
nockchain --version

# 检查配置
cd /root/nockchain
cat .env

# 测试启动
./start-miner.sh
```

## 💡 最佳实践

1. **批量部署前先测试**
   ```bash
   # 先部署到一台服务器测试
   ./deploy-to-servers.sh test-server
   ```

2. **使用 screen 或 tmux 运行**
   ```bash
   ssh root@server "cd /root/nockchain && screen -S nockchain -d -m ./start-miner.sh"
   ```

3. **监控部署状态**
   ```bash
   # 检查所有服务器状态
   for server in server1 server2 server3; do
       echo "=== $server ==="
       ssh root@$server "pgrep -f nockchain && echo 'Running' || echo 'Stopped'"
   done
   ```

## 🎉 总结

这个一体化脚本让你可以：
- ⚡ **一键部署** - 从编译服务器到多台目标服务器
- 🔄 **批量处理** - 同时部署到多台服务器
- 🛡️ **自动配置** - 包括密钥生成、防火墙等
- 📊 **状态反馈** - 清晰显示每台服务器的部署结果

**完美适合大规模挖矿集群的快速部署！** 🚀
