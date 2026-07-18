### 修改SSH端口
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Colsine/Scripts/main/Linux/change_ssh_port.sh)"
```

### 设置UFW和Fail2Ban
```bash
curl -fsSL -o setup.sh https://raw.githubusercontent.com/Colsine/Scripts/refs/heads/main/Linux/setup_server_security.sh && sudo bash setup.sh && rm -f setup.sh
```
```bash
wget https://raw.githubusercontent.com/Colsine/Scripts/refs/heads/main/Linux/setup_server_security.sh
sudo bash setup_server_security.sh
```

### 修改DNS
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Colsine/Scripts/refs/heads/main/Linux/dns_optimizer.sh)"
```
