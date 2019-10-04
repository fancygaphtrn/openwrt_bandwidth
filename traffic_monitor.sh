#!/bin/sh
# Bandwidth Download/Upload Rate Counter
LAN_TYPE='br-lan'
SLEEP_TIME=5
# Long lived access token from Home assistant
TOKEN=''

if [ -f /tmp/traffic_monitor.lock ];
then
  if [ ! -d /proc/$(cat /tmp/traffic_monitor.lock) ]; then
    echo "WARNING : Lockfile detected but process $(cat /tmp/traffic_monitor.lock) does not exist. Reinitialising lock file!"
    rm -f /tmp/traffic_monitor.lock
  else
    echo "WARNING : Process is already running as $(cat /tmp/traffic_monitor.lock), aborting!"
    exit
  fi
fi

echo $$ > /tmp/traffic_monitor.lock
echo "Monitoring network ${LAN_TYPE}"

echo "Remove RRDIPT from the forward chain"
iptables -w -D FORWARD -j RRDIPT                               

echo "Remove RRDIPT Chain"
iptables -w -F RRDIPT                               
iptables -w -X RRDIPT                               

#Create the RRDIPT CHAIN (it doesn't matter if it already exists).       
iptables -w -N RRDIPT 2> /dev/null                                          
                                                                               
#Add the RRDIPT CHAIN to the FORWARD chain (if non existing).               
echo "Add RRDIPT CHAIN to the FORWARD chain 1"
iptables -w -L FORWARD --line-numbers -n | grep "RRDIPT" | grep "1" > /dev/null
if [ $? -ne 0 ]; then                                                       
  echo "Add RRDIPT CHAIN to the FORWARD chain 2"
  iptables -w -L FORWARD -n | grep "RRDIPT" > /dev/null                  
  if [ $? -eq 0 ]; then                                               
    echo "Add RRDIPT CHAIN to the FORWARD chain 3"
    iptables -w -D FORWARD -j RRDIPT                               
  fi                                                                  
echo "Add RRDIPT CHAIN to the FORWARD chain 4"
iptables -w -I FORWARD -j RRDIPT                                       
fi                                                                          

while :
do
                                                                                    
  #For each host in the ARP table                                             
  #grep ${LAN_TYPE} /proc/net/arp | while read IP TYPE FLAGS MAC MASK IFACE   
  ip -f inet neigh show dev ${LAN_TYPE} nud reachable | while read IP TAIL
  do                                                                           
    #Add iptable rules (if non existing).                               
    iptables -w -nL RRDIPT | grep "${IP}[[:space:]]" > /dev/null                     
    if [ $? -ne 0 ]; then                                               
      echo "Add iptables -w rules dest ${IP}"
      iptables -w -I RRDIPT -d ${IP} -j RETURN                       
      echo "Add iptables -w rules src ${IP}"
      iptables -w -I RRDIPT -s ${IP} -j RETURN                       
    fi                                                                  
  done                                                                        

  iptables -w -L RRDIPT -vxZ -t filter | fgrep RETURN | awk -v st="$SLEEP_TIME" 'BEGIN { printf "{\"attributes\":{\n" } { if (NR % 2 == 1) printf "\"%s\": {\n\"host\": \"%s\",\n\"upload\": \"%d\",\n",NR,$8,$2 * (8 / st); else printf "\"download\": \"%d\"\n},\n",$2 * (8 / st);} END { printf "\"9999\":{\n\"host\": \"\",\n\"upload\": \"\",\n\"download\": \"\"}},\n\"state\":\"%s\"}\n",NR/2 }' | sed -r ':L;s=\b([0-9]+)([0-9]{3})\b=\1,\2=g;t L' > /tmp/traffic_monitor.json
  if [ $? -ne 0 ]; then   
      echo "JSON output failed"
  fi  

  curl -silent -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d @/tmp/traffic_monitor.json http://192.168.5.200:8123/api/states/sensor.bw_usage > /dev/null	   

  sleep ${SLEEP_TIME}
done
