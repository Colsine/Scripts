## PVE Manager Status

下载并执行脚本：

```bash
curl -Lf -o /tmp/temp.sh https://raw.githubusercontent.com/Colsine/Scripts/main/PVE/pve.sh && chmod +x /tmp/temp.sh && /tmp/temp.sh remod
```
显示功耗需要的依赖:
```bash
apt update ; apt install linux-cpupower && modprobe msr && echo msr > /etc/modules-load.d/turbostat-msr.conf && chmod +s /usr/sbin/turbostat && echo 成功！
```
恢复官方设置:
```bash
apt update
apt install --reinstall pve-manager=$(dpkg -l pve-manager | tail -n 1 | awk '{print $3}')
apt install --reinstall proxmox-widget-toolkit=$(dpkg -l proxmox-widget-toolkit | tail -n 1 | awk '{print $3}')
rm -f /usr/share/perl5/PVE/API2/Nodes.pm*bak
rm -f /usr/share/pve-manager/js/pvemanagerlib.js*bak
rm -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js*bak
```
