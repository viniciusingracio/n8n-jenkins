#!/bin/bash -xe

encrypted_days=7

if [ -d /var/bigbluebutton/deleted/mconf_encrypted/ ]; then
    find /var/bigbluebutton/deleted/mconf_encrypted/ -maxdepth 1 -mtime +$encrypted_days -exec rm -rf {} \;
fi
