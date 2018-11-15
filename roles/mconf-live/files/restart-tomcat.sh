#!/bin/bash

function reinicia_tomcat {
echo "`date` - problemas com a api" >> /tmp/problemas_com_api
    service tomcat7 stop; sleep 5 ; service tomcat7 start
}

while :
do
    timeout 5 curl http://localhost:8080/bigbluebutton/api -o /tmp/verifica_api
    if [ ! "$?" == "0" ]
    then
        reinicia_tomcat
    else
        t=$(grep -c  SUCCESS /tmp/verifica_api)
        if  [ "$t" == "0"  ]
        then
            reinicia_tomcat
        else
            echo "`date` - OK" >> /tmp/problemas_com_api
        fi
    fi
    sleep 60
done
