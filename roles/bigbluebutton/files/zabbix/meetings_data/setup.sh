#!/bin/bash -e

cd "$( dirname "${BASH_SOURCE[0]}" )"

if ! gem list -i "^bundler$" > /dev/null; then sudo gem install bundler; fi

sudo bundle install
