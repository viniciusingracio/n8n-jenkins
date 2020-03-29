#!/bin/bash -xe

IP=$(ip addr show $(route -n | grep '^0.0.0.0' | tr -s ' ' | cut -d' ' -f 8) | grep 'inet ' | awk '{print $2}' | cut -f1 -d'/' | head -n 1)

curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $1" -d "{\"type\":\"A\",\"name\":\"${HOSTNAME}\",\"data\":\"${IP}\",\"priority\":null,\"port\":null,\"ttl\":1800,\"weight\":null,\"flags\":null,\"tag\":null}" "https://api.digitalocean.com/v2/domains/$2/records"
