#!/bin/bash -xe

while read record_id; do
  if [ ! ${record_id} ]; then
    break;
  fi

  if [ ! -d /var/bigbluebutton/published/presentation/${record_id} ]; then
    continue;
  fi

  rm -vf /var/bigbluebutton/recording/status/processed/${record_id}-presentation_recorder.*
  rm -vf /var/bigbluebutton/recording/status/published/${record_id}-presentation_video.*
  rm -vrf /var/bigbluebutton/recording/process/presentation_recorder/${record_id}
  rm -vrf /var/bigbluebutton/published/presentation_video/${record_id}

  rm -vf /var/bigbluebutton/recording/status/processed/${record_id}-presentation.* /var/bigbluebutton/recording/status/published/${record_id}-presentation.fail
  touch /var/bigbluebutton/recording/status/published/${record_id}-presentation.done

  if [ -d /var/bigbluebutton/published/presentation_export/${record_id} ]; then
    rm -vf /var/bigbluebutton/recording/status/processed/${record_id}-presentation_export.* /var/bigbluebutton/recording/status/published/${record_id}-presentation_export.fail
    touch /var/bigbluebutton/recording/status/published/${record_id}-presentation_export.done
  fi

  touch /var/bigbluebutton/recording/status/sanity/${record_id}.done
done
