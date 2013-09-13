// Copyright (c) 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/extensions/api/page_capture/page_capture_api.h"

#include <limits>

#include "base/bind.h"
#include "base/file_util.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/common/extensions/extension_messages.h"
#include "chrome/browser/printing/print_view_manager.h"
#include "content/public/browser/child_process_security_policy.h"
#include "content/public/browser/notification_details.h"
#include "content/public/browser/notification_source.h"
#include "content/public/browser/notification_types.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_view_host.h"
#include "content/public/browser/web_contents.h"
#include "chrome/common/print_messages.h"
#include "printing/units.h"

using content::BrowserThread;
using content::ChildProcessSecurityPolicy;
using content::WebContents;
using extensions::PageCaptureSaveAsMHTMLFunction;
using extensions::PageCaptureSaveAsPDFFunction;
using webkit_blob::ShareableFileReference;
using base::BinaryValue;

namespace SaveAsMHTML = extensions::api::page_capture::SaveAsMHTML;

namespace {

const char kFileTooBigError[] = "The captured file generated is too big.";
const char kMHTMLGenerationFailedError[] = "Failed to generate MHTML.";
const char kTemporaryFileError[] = "Failed to create a temporary file.";
const char kTabClosedError[] = "Cannot find the tab for thie request.";

}  // namespace

static PageCaptureSaveAsMHTMLFunction::TestDelegate* test_delegate_ = NULL;

PageCaptureSaveAsMHTMLFunction::PageCaptureSaveAsMHTMLFunction() {
}

PageCaptureSaveAsMHTMLFunction::~PageCaptureSaveAsMHTMLFunction() {
  if (mhtml_file_.get()) {
    webkit_blob::ShareableFileReference* to_release = mhtml_file_.get();
    to_release->AddRef();
    mhtml_file_ = NULL;
    BrowserThread::ReleaseSoon(BrowserThread::IO, FROM_HERE, to_release);
  }
}

void PageCaptureSaveAsMHTMLFunction::SetTestDelegate(TestDelegate* delegate) {
  test_delegate_ = delegate;
}

bool PageCaptureSaveAsMHTMLFunction::RunImpl() {
  params_ = SaveAsMHTML::Params::Create(*args_);
  EXTENSION_FUNCTION_VALIDATE(params_.get());

  AddRef();  // Balanced in ReturnFailure/ReturnSuccess()

  BrowserThread::PostTask(
      BrowserThread::FILE, FROM_HERE,
      base::Bind(&PageCaptureSaveAsMHTMLFunction::CreateTemporaryFile, this));
  return true;
}

bool PageCaptureSaveAsMHTMLFunction::OnMessageReceivedFromRenderView(
    const IPC::Message& message) {
  if (message.type() != ExtensionHostMsg_ResponseAck::ID)
    return false;

  int message_request_id;
  PickleIterator iter(message);
  if (!message.ReadInt(&iter, &message_request_id)) {
    NOTREACHED() << "malformed extension message";
    return true;
  }

  if (message_request_id != request_id())
    return false;

  // The extension process has processed the response and has created a
  // reference to the blob, it is safe for us to go away.
  Release();  // Balanced in Run()

  return true;
}

void PageCaptureSaveAsMHTMLFunction::CreateTemporaryFile() {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::FILE));
  bool success = file_util::CreateTemporaryFile(&mhtml_path_);
  BrowserThread::PostTask(
      BrowserThread::IO, FROM_HERE,
      base::Bind(&PageCaptureSaveAsMHTMLFunction::TemporaryFileCreated, this,
                 success));
}

void PageCaptureSaveAsMHTMLFunction::TemporaryFileCreated(bool success) {
  if (BrowserThread::CurrentlyOn(BrowserThread::IO)) {
    if (success) {
      // Setup a ShareableFileReference so the temporary file gets deleted
      // once it is no longer used.
      mhtml_file_ = ShareableFileReference::GetOrCreate(
          mhtml_path_,
          ShareableFileReference::DELETE_ON_FINAL_RELEASE,
          BrowserThread::GetMessageLoopProxyForThread(BrowserThread::FILE)
              .get());
    }
    BrowserThread::PostTask(
        BrowserThread::UI, FROM_HERE,
        base::Bind(&PageCaptureSaveAsMHTMLFunction::TemporaryFileCreated, this,
                   success));
    return;
  }

  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));
  if (!success) {
    ReturnFailure(kTemporaryFileError);
    return;
  }

  if (test_delegate_)
    test_delegate_->OnTemporaryFileCreated(mhtml_path_);

  WebContents* web_contents = GetWebContents();
  if (!web_contents) {
    ReturnFailure(kTabClosedError);
    return;
  }

  web_contents->GenerateMHTML(
      mhtml_path_,
      base::Bind(&PageCaptureSaveAsMHTMLFunction::MHTMLGenerated, this));
}

void PageCaptureSaveAsMHTMLFunction::MHTMLGenerated(
    const base::FilePath& file_path,
    int64 mhtml_file_size) {
  DCHECK(mhtml_path_ == file_path);
  if (mhtml_file_size <= 0) {
    ReturnFailure(kMHTMLGenerationFailedError);
    return;
  }

  if (mhtml_file_size > std::numeric_limits<int>::max()) {
    ReturnFailure(kFileTooBigError);
    return;
  }

  ReturnSuccess(mhtml_file_size);
}

void PageCaptureSaveAsMHTMLFunction::ReturnFailure(const std::string& error) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  error_ = error;

  SendResponse(false);

  Release();  // Balanced in Run()
}

void PageCaptureSaveAsMHTMLFunction::ReturnSuccess(int64 file_size) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  WebContents* web_contents = GetWebContents();
  if (!web_contents || !render_view_host()) {
    ReturnFailure(kTabClosedError);
    return;
  }

  int child_id = render_view_host()->GetProcess()->GetID();
  ChildProcessSecurityPolicy::GetInstance()->GrantReadFile(
      child_id, mhtml_path_);

  base::DictionaryValue* dict = new base::DictionaryValue();
  SetResult(dict);
  dict->SetString("mhtmlFilePath", mhtml_path_.value());
  dict->SetInteger("mhtmlFileLength", file_size);

  SendResponse(true);

  // Note that we'll wait for a response ack message received in
  // OnMessageReceivedFromRenderView before we call Release() (to prevent the
  // blob file from being deleted).
}

WebContents* PageCaptureSaveAsMHTMLFunction::GetWebContents() {
  Browser* browser = NULL;
  content::WebContents* web_contents = NULL;

  if (!ExtensionTabUtil::GetTabById(params_->details.tab_id, profile(),
                                    include_incognito(), &browser, NULL,
                                    &web_contents, NULL)) {
    return NULL;
  }
  return web_contents;
}

/* PDF saving */

namespace SaveAsPDF = extensions::api::page_capture::SaveAsPDF;

const char kMetafileMapError[] = "Could not map metafile.";
const char kPDFGenerationError[] = "Internal pdf generation error ";

PageCaptureSaveAsPDFFunction::PageCaptureSaveAsPDFFunction() :
    tab_id_(0),
    paper_size_width_(612),
    paper_size_height_(792),
    margin_top_(0),
    margin_left_(0),
    margin_bottom_(0),
    margin_right_(0),
    dpi_(72)  {
}

PageCaptureSaveAsPDFFunction::~PageCaptureSaveAsPDFFunction() {
  // TODO release shared memory here?
  // if (pdf_file_.get()) {
  //   webkit_blob::ShareableFileReference* to_release = pdf_file_.get();
  //   to_release->AddRef();
  //   pdf_file_ = NULL;
  //   BrowserThread::ReleaseSoon(BrowserThread::IO, FROM_HERE, to_release);
  // }
}

bool PageCaptureSaveAsPDFFunction::RunImpl() {
  params_ = SaveAsPDF::Params::Create(*args_);
  EXTENSION_FUNCTION_VALIDATE(params_.get());

  AddRef();  // Balanced in ReturnFailure/ReturnSuccess()

  tab_id_ = params_->details.tab_id;
  if (params_->details.page_width)
    paper_size_width_ = *(params_->details.page_width);
  if (params_->details.page_height)
    paper_size_height_ = *(params_->details.page_height);
  if (params_->details.dpi)
      dpi_ = *(params_->details.dpi);

  std::vector<int> * margins = params_->details.margin.get();
  if (margins) {
    switch(margins->size()) {
      case 0:
        break;
      case 1:
        margin_top_ = margin_right_ = margin_bottom_ = margin_left_= margins->at(0);
        break;
      case 2:
        margin_left_ = margin_right_ = margins->at(0);
        margin_top_ = margin_bottom_ = margins->at(1);
        break;
      case 3:
        margin_top_ = margins->at(0);
        margin_left_ = margin_right_ = margins->at(1);
        margin_bottom_ = margins->at(2);
        break;
      case 4:
        margin_top_ =  margins->at(0);
        margin_left_ =  margins->at(1);
        margin_bottom_ =  margins->at(2);
        margin_right_ =  margins->at(3);
        break;
    }
  }
  BrowserThread::PostTask(
      BrowserThread::FILE, FROM_HERE,
      base::Bind(&PageCaptureSaveAsPDFFunction::CreateTemporaryFile, this));
  return true;
}
void PageCaptureSaveAsPDFFunction::CreateTemporaryFile() {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::FILE));
  bool success = file_util::CreateTemporaryFile( &mpdf_path_);
  BrowserThread::PostTask( BrowserThread::UI, FROM_HERE,
      base::Bind( &PageCaptureSaveAsPDFFunction::TemporaryFileCreated, this, success));
}

void PageCaptureSaveAsPDFFunction::TemporaryFileCreated(bool success) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));
  // If we were returning a blob, we'd set up shareable file reference just like MHTML
  if (!success) {
    ReturnFailure(kTemporaryFileError);
    return;
  }
  RequestPDF();
}

void PageCaptureSaveAsPDFFunction::RequestPDF() {
  WebContents* web_contents = GetWebContents();
  if (!web_contents) {
    ReturnFailure(kTabClosedError);
    return;
  }

  printing::PrintViewManager* print_view_manager =
            printing::PrintViewManager::FromWebContents(web_contents);

  PrintMsg_PrintToPDF_Params params;
  int child_id = render_view_host()->GetProcess()->GetID();
  ChildProcessSecurityPolicy::GetInstance()->GrantCreateReadWriteFile(
      child_id, mpdf_path_);
  FillPDFParams(params);

  print_view_manager->PrintToPDF(params,
    base::Bind(&PageCaptureSaveAsPDFFunction::DidPrintToPDF, this));
}

void PageCaptureSaveAsPDFFunction::DidPrintToPDF(const PrintHostMsg_DidPrintToPDF_Params& didParams) {

  if (didParams.pdf_error_code == 0) {
    ReturnSuccess(didParams.pdf_file_path);
  }
  else {
    std::stringstream ss;
    ss << kPDFGenerationError << didParams.pdf_error_code;
    ReturnFailure(ss.str());
  }
}


void PageCaptureSaveAsPDFFunction::ReturnSuccess(const std::string& pdfPath) {
    base::StringValue * result = new base::StringValue(pdfPath);
    SetResult(result);

    BrowserThread::PostTask( BrowserThread::UI, FROM_HERE,
        base::Bind(&PageCaptureSaveAsPDFFunction::SendResponse, this, true));
    Release();
    // Old code when we were sending the entire file buffer
    // if (didParams.metafile_data_size <= 0) {
    //   ReturnFailure(kMHTMLGenerationFailedError);
    //   return;
    // }

    // if (didParams.metafile_data_size > (256 * 1024 * 1024)) {
    //   ReturnFailure(kFileTooBigError);
    //   return;
    // }
    // scoped_ptr<base::SharedMemory> shared_buf(new base::SharedMemory(didParams.metafile_data_handle, true));
    // if (!shared_buf->Map(didParams.metafile_data_size)) {
    //   NOTREACHED() << "Could not map shared memory";
    //   ReturnFailure(kMetafileMapError);
    //   return ;
    // }
    // BinaryValue* pdf_value = BinaryValue::CreateWithCopiedBuffer((char*)shared_buf->memory(),  didParams.metafile_data_size);
    // SetResult(pdf_value);
}

void PageCaptureSaveAsPDFFunction::ReturnFailure(const std::string& error) {
  DCHECK(BrowserThread::CurrentlyOn(BrowserThread::UI));

  error_ = error;

  SendResponse(false);

  Release();  // Balanced in Run()
}


WebContents* PageCaptureSaveAsPDFFunction::GetWebContents() {
  Browser* browser = NULL;
  content::WebContents* web_contents = NULL;

  if (!ExtensionTabUtil::GetTabById(params_->details.tab_id, profile(),
                                    include_incognito(), &browser, NULL,
                                    &web_contents, NULL)) {
    return NULL;
  }
  return web_contents;
}

void PageCaptureSaveAsPDFFunction::FillPDFParams(PrintMsg_PrintToPDF_Params &pdfParams) {

  pdfParams.pdf_file_path = mpdf_path_.value();
  // Specifies dots per inch. // double
  pdfParams.params.dpi = printing::kPointsPerInch;
  // Desired apparent dpi on paper., int
  pdfParams.params.desired_dpi =dpi_;
  // Minimum shrink factor. See PrintSettings::min_shrink for more information.
  // Maximum shrink factor. See PrintSettings::max_shrink for more information., double
  pdfParams.params.min_shrink = pdfParams.params.max_shrink = 1.0;
  // The x-offset of the printable area, in pixels according to dpi., int
  pdfParams.params.margin_left = margin_left_;
  // The y-offset of the printable area, in pixels according to dpi., int
  pdfParams.params.margin_top = margin_top_;
  // Physical size of the page, including non-printable margins,
  // in pixels according to dpi., content_size
  pdfParams.params.page_size = gfx::Size(paper_size_width_, paper_size_height_);
  // In pixels according to dpi_x and dpi_y., gfx::Size
  pdfParams.params.content_size = gfx::Size( paper_size_width_ - margin_left_ - margin_right_,
    paper_size_height_ - margin_top_ - margin_bottom_);
  // Physical printable area of the page in pixels according to dpi. gfx::Rect
  pdfParams.params.printable_area.SetRect(0,0, pdfParams.params.content_size.width(),  pdfParams.params.content_size.height());
  // True if print backgrounds is requested by the user., bool
  pdfParams.params.should_print_backgrounds = true;
    // Does the printer support alpha blending?
  pdfParams.params.supports_alpha_blend = true;

  /*
  int document_cookie;
  bool selection_only;
  int32 preview_ui_id;
  int preview_request_id;
  bool is_first_request;
  WebKit::WebPrintScalingOption print_scaling_option;
  bool print_to_pdf;
  bool display_header_footer;
  string16 date;
  string16 title;
  string16 url;

  // Cookie for the document to ensure correctness.
  IPC_STRUCT_TRAITS_MEMBER(document_cookie)
  // Should only print currently selected text.
  IPC_STRUCT_TRAITS_MEMBER(selection_only)
  // *** Parameters below are used only for print preview. ***
  // The print preview ui associated with this request.
  IPC_STRUCT_TRAITS_MEMBER(preview_ui_id)
  // The id of the preview request.
  IPC_STRUCT_TRAITS_MEMBER(preview_request_id)
  // True if this is the first preview request.
  IPC_STRUCT_TRAITS_MEMBER(is_first_request)
  // Specifies the page scaling option for preview printing.
  IPC_STRUCT_TRAITS_MEMBER(print_scaling_option)
  // True if print to pdf is requested.
  IPC_STRUCT_TRAITS_MEMBER(print_to_pdf)
  // Specifies if the header and footer should be rendered.
  IPC_STRUCT_TRAITS_MEMBER(display_header_footer)
  // Date string to be printed as header if requested by the user.
  IPC_STRUCT_TRAITS_MEMBER(date)
  // Title string to be printed as header if requested by the user.
  IPC_STRUCT_TRAITS_MEMBER(title)
  // URL string to be printed as footer if requested by the user.
  IPC_STRUCT_TRAITS_MEMBER(url)
  */
}


