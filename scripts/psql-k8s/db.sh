#!/bin/bash

# set -xe

source .env

echo "Setting up access to Kubernetes"
mkdir -p ~/.kube
./doctl auth init -t $DO_KEY
./doctl kubernetes cluster kubeconfig show $KUBE_CLUSTER > ~/.kube/config
./kubectl port-forward $KUBE_SERVICE $KUBE_PORT &

echo 'Waiting for port-forward to be active'
while ! netstat -tna | grep 'LISTEN\>' | grep -q ':5432\>'; do
    echo -n '.'
    sleep 1
done
echo 'Done waiting'

psql -h 127.0.0.1 -U $DB_USER -d $DB_NAME "$@"
