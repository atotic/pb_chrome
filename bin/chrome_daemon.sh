# daemonizing chrome

export DISPLAY=:1
DAEMON=/usr/bin/daemon
LOGDIR=/Users/atotic/pb4us/pb_data/development/log/chrome
CHROME_BIN=/Users/atotic/pb4us/pb_chrome/bin/mac/Chromium.app/Contents/MacOS/Chromium
CHROME_PROFILE=/Users/atotic/pb4us/pb_data/development/log/chrome

$DAEMON --user=deploy --errlog=${LOGDIR}errlog.log --dbglog=${LOGDIR}dbglog.log --output=${LOGDIR}output.log --stdout=${LOGDIR}stdout.log --stderr=${LOGDIR}stderr.log -- $CHROME_BIN --user-data-dir=${CHROME_PROFILE} --disable-setuid-sandbox "$@"
