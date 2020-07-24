#!/bin/sh
IP=$1
PORT=$2
VIDEO_PORT=$3

R=$(timeout 5 /usr/bin/sipp -sn uac -m 1 -aa -i ${IP} -mp ${VIDEO_PORT} -nostdin -s sippcheck "${IP}:${PORT}" > /dev/null 2>&1)
CHECK_STATUS=$(($? == 0))
cat << EOF
# HELP bbb_freeswitch_sipp_status FreeSWITCH negotation health status via sipp
# TYPE bbb_freeswitch_sipp_status gauge
bbb_freeswitch_sipp_status ${CHECK_STATUS}
EOF
