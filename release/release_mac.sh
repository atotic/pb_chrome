#!/bin/bash
# extract with tar zxvf chromium_mac.tar.gz
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC=~/chromium/src/out/Release/
DEST=$DIR/chromium_mac.tar.gz
tar zcvf $DEST -C $SRC Chromium.app

