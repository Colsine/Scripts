#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

# 提示用户输入新的 SSH 端口
read -p "请输入新的 SSH 端口: " NEW_PORT

# 检查端口号是否合法
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1 ] || [ "$NEW_PORT" -gt 65535 ]; then
  echo "端口号无效，请输入 1 到 65535 之间的数字。"
  exit 1
fi

# 修改 sshd_config 文件
SSH_CONFIG="/etc/ssh/sshd_config"
if grep -q "^#Port 22" "$SSH_CONFIG"; then
  sed -i "s/#Port 22/Port $NEW_PORT/" "$SSH_CONFIG"
elif grep -q "^Port 22" "$SSH_CONFIG"; then
  sed -i "s/^Port 22/Port $NEW_PORT/" "$SSH_CONFIG"
else
  echo "Port $NEW_PORT" >> "$SSH_CONFIG"
fi
echo "SSH 配置已修改，端口更改为 $NEW_PORT"

# 更新防火墙（适用于 ufw）
if command -v ufw &> /dev/null; then
  ufw allow "$NEW_PORT"/tcp
  ufw delete allow 22/tcp
  ufw reload
  echo "ufw 防火墙规则已更新。"
fi

# 更新防火墙（适用于 firewalld）
if command -v firewall-cmd &> /dev/null; then
  firewall-cmd --permanent --add-port="$NEW_PORT"/tcp
  firewall-cmd --permanent --remove-port=22/tcp
  firewall-cmd --reload
  echo "firewalld 防火墙规则已更新。"
fi

# 重启 SSH 服务
systemctl restart sshd
echo "SSH 服务已重启。"

# 提示用户测试新端口
echo "请使用以下命令测试新的 SSH 端口："
echo "ssh -p $NEW_PORT username@server_ip"
