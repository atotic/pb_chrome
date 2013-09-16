HOME=/home/atotic
DEST=$HOME/pb4us/pb_chrome/bin/linux
SRC=$HOME/chromium/src/out/Release

mkdir -p $DEST/locales
cp $SRC/chrome $DEST
cp $SRC/chrome.pak $DEST
cp $SRC/chrome_100_percent.pak $DEST
cp $SRC/resources.pak $DEST
cp $SRC/locales/* $DEST/locales

tar cvzf chrome.ubuntu1304.tar.gz linux
echo "test binary"
echo ./linux/chrome --disable-setuid-sandbox --no-sandbox
