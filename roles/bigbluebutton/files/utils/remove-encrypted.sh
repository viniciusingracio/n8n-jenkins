#!/bin/bash -xe

encrypted_days=7

if [ -d /var/bigbluebutton/published/mconf_encrypted/ ]; then
    find /var/bigbluebutton/published/mconf_encrypted/ -maxdepth 1 -mtime +$encrypted_days -exec rm -rf {} \;
fi

if [ -d /var/bigbluebutton/unpublished/mconf_encrypted/ ]; then
    find /var/bigbluebutton/unpublished/mconf_encrypted/ -maxdepth 1 -mtime +$encrypted_days -exec rm -rf {} \;
fi

if [ -d /var/bigbluebutton/deleted/mconf_encrypted/ ]; then
    find /var/bigbluebutton/deleted/mconf_encrypted/ -maxdepth 1 -mtime +$encrypted_days -exec rm -rf {} \;
fi
