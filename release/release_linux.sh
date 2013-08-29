#!/bin/bash
# extract with tar zxvf chromium_mac.tar.gz
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC=~/chromium/src/out/Release/
DEST=$DIR/chromium_linux.tar.gz
tar zcvf $DEST -C $SRC chrome chrome.pak resources.pak locales

