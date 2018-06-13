#!/bin/bash -e

find -maxdepth 1 -type d -name '[0-9]*' \
     -exec bash -c "ls {}/fd/ | wc -l | tr '\n' ' '" \; \
     -printf "fds (PID = %P), command: " \
     -exec bash -c "tr '\0' ' ' < {}/cmdline" \; \
     -exec echo \; | sort -rn | head
