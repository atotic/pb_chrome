HOME=/Users/atotic
DEST=$HOME/pb4us/pb_chrome/bin/mac
SRC=$HOME/chromium/src/out/Release

rm -rf $DEST
mkdir -p $DEST
cp -R $SRC/Chromium.app $DEST

tar cvzf chrome.mac.tar.gz mac
echo "to test binary"
echo ./mac/Chromium.app/Contents/MacOS/Chromium --disable-setuid-sandbox --no-sandbox
