#!/bin/bash

API_ENTRYPOINT=$(cat /var/lib/tomcat7/webapps/bigbluebutton/WEB-INF/classes/bigbluebutton.properties | grep '^bigbluebutton.web.serverURL=' | cut -d'=' -f2 | awk '{print $1"/bigbluebutton/api"}')

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
