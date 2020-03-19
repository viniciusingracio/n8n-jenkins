#!/bin/bash

echo "$(date) Start restart sequence"

/usr/bin/ruby /usr/local/bigbluebutton/core/scripts/utils/abort-if-meetings-running.rb
if [ $? -eq 1 ]; then
  echo "End all running sessions"

  /usr/bin/ruby /usr/local/bigbluebutton/core/scripts/utils/end-all.rb || echo "Failed to retrieve running sessions, keep going..."
  sleep 30
fi

RUNNING_KURENTO_HEALTH_MONITOR=false
docker inspect --format='{{.State.Running}}' kurento-health-monitor
if [ $? -eq 0 ]; then
  RUNNING_KURENTO_HEALTH_MONITOR=true
  docker stop kurento-health-monitor
fi

bbb-conf --restart

docker inspect --format='{{.State.Running}}' webrtc-sfu
if [ $? -eq 0 ]; then
  echo "bbb-webrtc-sfu is running within Docker"
  echo "Stop bbb-webrtc-sfu and kurento from packages"
  systemctl stop bbb-webrtc-sfu kurento-media-server
  systemctl disable bbb-webrtc-sfu kurento-media-server

  for NAME in `docker ps -a --format '{{.Names}}' | grep '^kurento_'`; do
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
  if [ $RUNNING_KURENTO_HEALTH_MONITOR ]; then
    docker start kurento-health-monitor
  fi
  echo "Restart the other Docker containers"
  docker restart webrtc-sfu mcs-bfcp mcs-sip sfu-phone

  systemctl stop red5 bbb-transcode-akka
  systemctl disable red5 bbb-transcode-akka
fi

echo "$(date) Restart sequence finished!"
