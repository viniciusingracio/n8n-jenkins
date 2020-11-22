#!/bin/bash

for sanity_file in `find /var/bigbluebutton/recording/status/sanity/ -name "*.done"`; do
  record_id=`basename ${sanity_file} | cut -d'.' -f1`
  if [ -d /var/bigbluebutton/published/presentation/${record_id} ]; then
    # already published, so shouldn't keep any fail flag
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation.fail
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation.fail
    sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation/${record_id}
    sudo -u bigbluebutton touch /var/bigbluebutton/recording/status/published/${record_id}-presentation.done
  else
    if [ -d /var/bigbluebutton/unpublished/presentation/${record_id} ] || [ -d /var/bigbluebutton/deleted/presentation/${record_id} ]; then
      sudo -u bigbluebutton rm -f ${sanity_file}
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation.fail
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation.fail
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.fail
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation_video.fail
      sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation/${record_id}
      sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
      sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/publish/${record_id}
    elif [ -d /var/bigbluebutton/recording/raw/${record_id} ]; then
      echo "Queue size for presentation"
      # echo "Pending for presentation: ${record_id}"
      if [ -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation.fail ] || [ -f /var/bigbluebutton/recording/status/published/${record_id}-presentation.fail ]; then
        echo "Rebuild presentation: ${record_id}"
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation.done
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation.done
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation.fail
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation.fail
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.fail
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation_video.fail
        sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation/${record_id}
        sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_video/${record_id}
        sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
        sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/publish/presentation/${record_id}
        sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/publish/presentation_video/${record_id}
      fi
    else
      echo "No raw files available for presentation: ${record_id}"
    fi
  fi
  if [ -f /var/bigbluebutton/recording/status/published/${record_id}-presentation.done ] && [ ! -d /var/bigbluebutton/published/presentation_video/${record_id} ]; then
    if [ -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.done ]; then
      if [ -f /var/bigbluebutton/recording/process/presentation_recorder/${record_id}/video.mp4 ]; then
        echo "Queue size for presentation_video"
        # echo "Pending for presentation_video: ${record_id}"
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.fail
      else
        echo "Queue size for presentation_recorder"
        # echo "Pending for presentation_recorder: ${record_id}"
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.fail
        sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.done
        sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
      fi
    elif [ -d /var/bigbluebutton/published/presentation/${record_id} ]; then
      echo "Queue size for presentation_recorder"
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.fail
      # echo "Pending for presentation_recorder: ${record_id}"
    else
      # echo "No presentation available for presentation_video: ${record_id}"
      sudo -u bigbluebutton rm -f ${sanity_file}
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.fail
      sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
    fi
  fi
done | sort | uniq -c | sort -n -r

# remove invalid unicode character that breaks sanity
for sanity_file in `find /var/bigbluebutton/recording/status/sanity/ -name "*.fail"`; do
  record_id=`basename ${sanity_file} | cut -d'.' -f1`
  if [ ! -f /var/bigbluebutton/recording/raw/${record_id}/events.xml.orig ]; then
    sudo -u bigbluebutton cp /var/bigbluebutton/recording/raw/${record_id}/events.xml /var/bigbluebutton/recording/raw/${record_id}/events.xml.orig
  fi

  sudo -u bigbluebutton sed -i 's:\xEF\xBF\xBE::g' /var/bigbluebutton/recording/raw/${record_id}/events.xml
  sudo -u bigbluebutton rm -f ${sanity_file}
done

# cleanup recordings unpublished/deleted
for processed_fail in `find /var/bigbluebutton/recording/status/processed/ -name "*-presentation_video.fail" -o -name "*-presentation_recorder.fail"`; do
  record_id=`basename ${processed_fail} | cut -d'.' -f1 | sed 's/-presentation_\(video\|recorder\)//g'`
  if [ -d /var/bigbluebutton/unpublished/presentation/${record_id} ] || [ -d /var/bigbluebutton/deleted/presentation/${record_id} ]; then
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.fail
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation_video.fail
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.fail
    sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
  elif [ -d /var/bigbluebutton/published/presentation/${record_id} ] && [ ! -f /var/bigbluebutton/recording/status/sanity/${record_id}.done ]; then
    # trigger rebuild of presentation_video
    sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
    sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_video/${record_id}
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.done
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.fail
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.done
    sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation_video.fail
    sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/publish/presentation_video/${record_id}
    sudo -u bigbluebutton touch /var/bigbluebutton/recording/status/sanity/${record_id}.done
  fi
done

for published_fail in `find /var/bigbluebutton/recording/status/published/ -name "*-presentation_video.fail" -o -name "*-presentation_recorder.fail"`; do
  record_id=`basename ${published_fail} | cut -d'.' -f1 | sed 's/-presentation_\(video\|recorder\)//g'`

  # limit scope to recordings in which the presentation format has been processed in the same server
  # scenario with multiple recw servers
  if [ -f /var/log/bigbluebutton/presentation/process-${record_id}.log ]; then
    if [ -d /var/bigbluebutton/published/presentation/${record_id} ] && [ ! -f /var/bigbluebutton/recording/status/sanity/${record_id}.done ]; then
      # trigger rebuild of presentation_video
      sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
      sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_video/${record_id}
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.done
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.fail
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.done
      sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation_video.fail
      sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/publish/presentation_video/${record_id}
      sudo -u bigbluebutton touch /var/bigbluebutton/recording/status/sanity/${record_id}.done
    fi
  fi
done

for published_path in `ls -1 /var/bigbluebutton/published/presentation/`; do
  record_id=`basename ${published_path}`

  # limit scope to recordings in which the presentation format has been processed in the same server
  # scenario with multiple recw servers
  if [ -f /var/log/bigbluebutton/presentation/process-${record_id}.log ]; then
    if [ -d /var/bigbluebutton/published/presentation/${record_id} ] && [ ! -d /var/bigbluebutton/published/presentation_video/${record_id} ]; then
      # trigger rebuild of presentation_video
      # sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
      # sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/process/presentation_video/${record_id}
      # sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_video.done
      # sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.fail
      # sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.done
      # sudo -u bigbluebutton rm -f /var/bigbluebutton/recording/status/published/${record_id}-presentation_video.fail
      # sudo -u bigbluebutton rm -rf /var/bigbluebutton/recording/publish/presentation_video/${record_id}
      # sudo -u bigbluebutton touch /var/bigbluebutton/recording/status/sanity/${record_id}.done
      echo "Rebuild presentation_video"
    fi
  fi
done | sort | uniq -c | sort -n -r

ls -ahlt /var/bigbluebutton/recording/status/sanity* | grep ".done$" | tac | head

if [ `ruby -e 'require "date"; diff = (Time.now() - File.mtime("/var/log/bigbluebutton/mconf-presentation-recorder-worker.log")).to_i; if diff < 3600 * 6; puts "1"; else; puts "0"; end'` == "0" ]; then
  echo "Restarting mconf-presentation-recorder because it's inactive for more than 6 hours"

  sudo systemctl stop mconf-presentation-recorder.service mconf-presentation-recorder.target mconf-presentation-recorder.timer

  docker ps --filter name=record_* -aq | xargs -r docker rm -f
  docker ps --filter name=nginx_* -aq | xargs -r docker rm -f

  docker network ls --filter name=record_* --format "{{.Name}}" | cut -d'_' -f2 | xargs -I{} -r docker network disconnect -f record_{} nginx_{}
  docker network ls --filter name=record_* --format "{{.Name}}" | cut -d'_' -f2 | xargs -I{} -r docker network disconnect -f record_{} record_{}
  docker network ls --filter name=record_* -q | xargs -r docker network rm

  sudo rm -r /var/bigbluebutton/recording/process/presentation_recorder/*

  sudo systemctl restart mconf-presentation-recorder.timer
fi

echo "Workers generating presentation_video: `docker ps --filter name=record_* -aq | wc -l`"
docker ps --filter name=record_*

function check_webhooks_logs {
  docker inspect webhooks | grep log | cut -d"\"" -f4 | sudo ruby -e 'require "date"; diff = (Time.now() - File.mtime(gets.chomp)).to_i; if diff < 3600 * 6; puts "1"; else; puts "0"; end'
}

if [ `check_webhooks_logs` == "0" ]; then
  echo "Restarting webhooks because it's inactive for more than 6 hours"

  docker restart webhooks
  sleep 10
  if [ `check_webhooks_logs` == "0" ]; then
    echo "No luck, restarting docker daemon"
    sudo systemctl restart docker
    sleep 10
    if [ `check_webhooks_logs` == "0" ]; then
      echo "Heal it with fire"
    fi
  fi
fi

docker logs webhooks --tail 4

echo "Last presentation being processed: `ls -t /var/bigbluebutton/recording/process/presentation/ | head -n 1`"
