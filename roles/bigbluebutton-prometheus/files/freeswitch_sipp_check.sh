#!/bin/sh
IP=$1
PORT=$2

R=$(/usr/bin/sipp -sn uac -m 1 -aa -nostdin -s sippcheck "${IP}:${PORT}" > /dev/null 2>&1)
CHECK_STATUS=$(($? == 0))
cat << EOF
# HELP bbb_freeswitch_sipp_status FreeSWITCH negotation health status via sipp
# TYPE bbb_freeswitch_sipp_status gauge
bbb_freeswitch_sipp_status ${CHECK_STATUS}
EOF
