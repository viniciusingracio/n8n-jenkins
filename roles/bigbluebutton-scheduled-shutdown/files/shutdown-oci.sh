#!/bin/bash

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

INSTANCE_ID=$(curl -s http://169.254.169.254/opc/v1/instance/id)
/usr/local/bin/oci compute instance action --action SOFTSTOP --instance-id ${INSTANCE_ID} --auth instance_principal
