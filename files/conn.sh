#!/bin/bash

SERVER=google.com

COUNTER=0

for i in `seq 1 20`; do
  ( time $(echo -e "GET http://$SERVER HTTP/1.0\n\n" | nc -w 10 $SERVER 80 > /dev/null 2>&1) ) |& grep '^real' | grep '0m0' > /dev/null
  if [ "$?" == "1" ]; then
    echo "Attempt $i failed"
    let COUNTER=COUNTER+1
  else
    echo "Attempt $i succeeded"
  fi
  sleep 1
done

echo "$COUNTER of 20 attempts failed"
