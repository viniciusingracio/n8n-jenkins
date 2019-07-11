#!/bin/bash

echo "$(date) Start restart sequence"

/usr/bin/ruby /usr/local/bigbluebutton/core/scripts/utils/abort-if-meetings-running.rb
if [ $? -eq 1 ]; then
  echo "End all running sessions"

  /usr/bin/ruby /usr/local/bigbluebutton/core/scripts/utils/end-all.rb || echo "Failed to retrieve running sessions, keep going..."
  sleep 30
fi

echo "Restart Mconf"

SERVLET_DIR=
if [ -f "/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties" ]; then
  SERVLET_DIR="/usr/share/bbb-web"
else
  SERVLET_DIR="/var/lib/tomcat7/webapps/bigbluebutton"
fi
API_ENTRYPOINT=$(cat ${SERVLET_DIR}/WEB-INF/classes/bigbluebutton.properties | grep '^bigbluebutton.web.serverURL=' | cut -d'=' -f2 | awk '{print $1"/bigbluebutton/api"}')

for i in `seq 1 20`; do
  echo "Restart (attempt $i)..."
  bbb-conf --restart

  echo "Wait a moment for bbb-web to boot"
  sleep 30

  if curl -S "${API_ENTRYPOINT}/create" | grep checksumError > /dev/null 2>&1; then
    echo "Successfully restarted!"
    break
  fi
  echo "Check failed"
done

docker inspect --format='{{.State.Running}}' webrtc-sfu
if [ $? -eq 0 ]; then
  echo "bbb-webrtc-sfu is running within Docker"
  echo "Stop bbb-webrtc-sfu and kurento from packages"
  systemctl stop bbb-webrtc-sfu kurento

  for NAME in `docker ps -f "name=kurento_*" --format '{{.Names}}'`; do
    echo "Restart $NAME"
    docker restart $NAME
    echo "Wait $NAME to be healthy"
    for i in `seq 1 20`; do
      if docker inspect --format='{{.State.Health.Status}}' $NAME | grep -q '^healthy$'; then
        break
      fi
      sleep 1
    done
    echo "$NAME is ready to connect"
  done
  echo "Restart the other Docker containers"
  docker restart webrtc-sfu mcs-sip sfu-phone
fi

echo "$(date) Restart sequence finished!"