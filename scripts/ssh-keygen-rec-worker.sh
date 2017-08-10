#!/bin/bash

ssh-keygen -t rsa -b 4096 -C "rec-worker@mconf.com" -f ./rec_worker -N ''
