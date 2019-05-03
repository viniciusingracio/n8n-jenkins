#!/bin/bash

SERVLET_DIR=
if [ -f "/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties" ]; then
  SERVLET_DIR="/usr/share/bbb-web"
else
  SERVLET_DIR="/var/lib/tomcat7/webapps/bigbluebutton"
fi
API_ENTRYPOINT=$(cat ${SERVLET_DIR}/WEB-INF/classes/bigbluebutton.properties | grep '^bigbluebutton.web.serverURL=' | cut -d'=' -f2 | awk '{print $1"/bigbluebutton/api"}')

for i in `seq 1 20`; do
  echo "$(date) Restarting (attempt $i)..."
  bbb-conf --restart

  echo "$(date) Wait a moment for tomcat to boot"
  sleep 30

  if curl -S "${API_ENTRYPOINT}/create" | grep checksumError > /dev/null 2>&1; then
    echo "$(date) Successfully restarted!"
    exit 0
  fi
  echo "$(date) Check failed"
done
