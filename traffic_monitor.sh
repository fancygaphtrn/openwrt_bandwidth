#!/bin/sh
# Bandwidth Download/Upload Rate Counter
LAN_TYPE='br-lan'
SLEEP_TIME=5
# Change host to match your Home assistant IP/port
HOST='192.168.5.200:8123'
# Long lived access token from Home assistant
TOKEN='Insert long lived token from Home assistant here'

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
echo "Checking RRDIPT CHAIN in the FORWARD chain as 1"
iptables -w -L FORWARD --line-numbers -n | grep "RRDIPT" | grep "^1" > /dev/null
if [ $? -ne 0 ]; then                                                       
  echo "Checking RRDIPT CHAIN in the FORWARD chain"
  iptables -w -L FORWARD -n | grep "RRDIPT" > /dev/null                  
  if [ $? -eq 0 ]; then                                               
    echo "Delete RRDIPT CHAIN from the FORWARD chain"
    iptables -w -D FORWARD -j RRDIPT                               
  fi                                                                  
  echo "Add RRDIPT CHAIN to the FORWARD chain as 3"
  iptables -w -I FORWARD 1 -j RRDIPT                                     
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
  
  iptables -w -L RRDIPT -vxZ -t filter | fgrep RETURN | sed 's/.lan//' | awk -v st="$SLEEP_TIME"+1 '{if (NR % 2 == 1) printf "%s %d ",$8,$2 * (8 / st); else printf "%d\n",$2 * (8 / st);}' | sort | awk 'BEGIN {TU=0; TD=0; printf "{\"attributes\":{\n" } { printf "\"%s\": {\n\"host\": \"%s\",\n\"upload\": \"%d\",\n\"download\": \"%d\"\n},\n",NR,$1,$2,$3; TU=TU+$2; TD=TD+$3;} END { printf "\"9999\":{\n\"host\": \"%s\",\n\"upload\": \"%d\",\n\"download\": \"%d\"}},\n\"state\":\"%s\"}\n","Total", TU, TD, NR}' | sed -r ':L;s=\b([0-9]+)([0-9]{3})\b=\1,\2=g;t L' > /tmp/traffic_monitor.json
  if [ $? -ne 0 ]; then   
      echo "JSON output failed"
  fi  

  curl -m 10 -silent -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d @/tmp/traffic_monitor.json http://${HOST}/api/states/sensor.bw_usage > /dev/null	   

  sleep ${SLEEP_TIME}
done
