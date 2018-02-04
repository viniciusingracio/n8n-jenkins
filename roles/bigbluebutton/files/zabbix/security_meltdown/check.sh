#!/bin/bash -e

/bin/sh /etc/zabbix/scripts/security_meltdown/spectre-meltdown-checker.sh | perl -pe 's/\e([^\[\]]|\[.*?[a-zA-Z]|\].*?\a)//g' | grep '^CVE-\|^> STATUS:'
