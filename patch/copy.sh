DEST=/Users/atotic/chromium2/pookio_patch
SRC=/Users/atotic/chromium2/src

echo "copying .h|.cc"
cp  $SRC/chrome/browser/extensions/api/page_capture/page_capture_api.h $DEST
cp  $SRC/chrome/browser/extensions/api/page_capture/page_capture_api.cc $DEST
cp  $SRC/chrome/browser/extensions/extension_function_histogram_value.h $DEST
cp  $SRC/chrome/browser/printing/print_view_manager.h $DEST
cp  $SRC/chrome/browser/printing/print_view_manager.cc $DEST
cp  $SRC/chrome/common/print_messages.h $DEST
cp  $SRC/chrome/common/extensions/api/page_capture.json $DEST
cp  $SRC/chrome/renderer/printing/print_web_view_helper.cc $DEST
cp  $SRC/chrome/renderer/printing/print_web_view_helper.h $DEST

pushd /Users/atotic/chromium2/src
svn diff > $DEST/pookio.patch
popd
