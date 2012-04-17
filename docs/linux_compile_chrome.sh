# COMPILING CHROME
# general linux tools
sudo apt-get install subversion git g++

# install/configure depot_tools
svn co http://src.chromium.org/svn/trunk/tools/depot_tools
echo export PATH="$PATH":`pwd`/depot_tools >> .bashrc

# checkout chromium
mkdir chromium
cd chromium
gclient config http://src.chromium.org/svn/releases/18.0.976.0
gclient sync

# apply the patch
cd ~/chromium/src
cp ~/pb/pb_chrome/pdf_saver.patch .
patch -p0 < pdf_saver.patch

# build chromium
# dependency install is interactive, fonts, gold linker
./build/install-build-deps.sh 
./build/gyp_chromium -D disable_nacl=1
make chrome -j2 BUILDTYPE=Release
