# Reinstall
## Run Script
```bash
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/Colsine/Scripts/main/Reinstall/InstallNET.sh') -d 12 -v 64 -p "自定义root密码" -port "自定义ssh端口" -a -firmware
```
## 参数说明
```bash
-firmware      额外的驱动支持 
-d             Debian系统 后面是系统版本号，例：9、10 ... 
-c             Centos系统 后面是系统版本号，例：6.9、6.10 ... 
-u             Ubuntu系统 后面是系统版本号，例：16.04、18.04 ... 
-v             系统位数，64位或32位，只写数字 
-a             auto，全自动无人值守安装 
-mirror        后面是指定镜像源地址 
-p             后面写自定义密码 
–ip-addr       ifconfig -a 后获取到的 例：194.87.xxx.xxx 
–ip-gate       route -n 后获取到的 例 194.87.xxx.xxx 
–ip-mask       255.255.xxx.xx
```
