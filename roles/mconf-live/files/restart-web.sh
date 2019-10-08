#!/bin/bash

function restart_web {
echo "`date` - problemas com a api" >> /tmp/problemas_com_api
    systemctl restart bbb-web
}

while :
do
    timeout 5 curl http://localhost:8090/bigbluebutton/api -o /tmp/verifica_api
    if [ ! "$?" == "0" ]
    then
        restart_web
    else
        t=$(grep -c  SUCCESS /tmp/verifica_api)
        if  [ "$t" == "0"  ]
        then
            restart_web
        else
            echo "`date` - OK" >> /tmp/problemas_com_api
        fi
    fi
    sleep 60
done
