# openwrt_bandwidth
Per user bandwidth reporting to Home Assistant for OpenWRT


traffic_monitor is an init file that should be placed in /etc/init.d

traffic_monitor.sh is the script and should be in /root

both files should be executable chmod +x file

You will need to create a long lived token in Home assisant and put in traffic_monitor.sh
