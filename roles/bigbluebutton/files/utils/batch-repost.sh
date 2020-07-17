#!/bin/bash

while read record_id; do
  if [ ! ${record_id} ]; then
    break;
  fi

  if [ -d /var/bigbluebutton/published/presentation/${record_id} ]; then
    if [ -d /var/bigbluebutton/published/presentation_video/${record_id} ]; then
      echo "${record_id} is complete"
    else
      echo "${record_id} is available for presentation only"
    fi
  else
    if [ -d /var/bigbluebutton/published/presentation_video/${record_id} ]; then
      echo "${record_id} is available for presentation_video only"
    else
      if [ -d /var/bigbluebutton/unpublished/presentation/${record_id} ]; then
        echo "${record_id} is unpublished"
      elif [ -d /var/bigbluebutton/deleted/presentation/${record_id} ]; then
        echo "${record_id} is deleted"
      else
        echo "${record_id} is not here"
        continue
      fi
    fi
  fi

  ruby ~/repost-published-event.rb -m ${record_id} > /dev/null 2>&1
done
