# daemonizing chrome

export DISPLAY=:1
DAEMON=/usr/bin/daemon
LOGDIR=/home/deploy/pb/pb_data/production/log/chrome/
CHROME_BIN=/home/deploy/pb/pb_chrome/bin/linux_64/chrome
CHROME_PROFILE=/home/deploy/pb/pb_chrome/chromium_profile

$DAEMON  "$@" --unsafe --user=deploy --name='chrome_daemon' --errlog=${LOGDIR}errlog.log --dbglog=${LOGDIR}dbglog.log --output=${LOGDIR}output.log --stdout=${LOGDIR}stdout.log --stderr=${LOGDIR}stderr.log -- $CHROME_BIN --user-data-dir=${CHROME_PROFILE} --no-sandbox
