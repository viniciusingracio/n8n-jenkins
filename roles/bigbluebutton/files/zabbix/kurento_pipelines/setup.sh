#!/bin/bash -e

cd "$( dirname "${BASH_SOURCE[0]}" )"

export PATH=/opt/node-v8.9.0/bin:$PATH
npm install
