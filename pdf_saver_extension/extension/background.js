"use strict"
var TEST_MODE = false;

function getPdfSaverUrl() {
	return localStorage['pdfServer'] || "http://localhost:27000/";
}

function getPdfConverterUrl() {
  return localStorage['pdfConverter'] || 'http://localhost:26000/pdf_converter';
}

function getAuthenticationUrl() {
	// return "http://dev.pb4us.com/login_as_printerABCDEFG";
	return localStorage['authenticationUrl'] || "http://localhost:26000/login_as_printerABCDEFG";
}

function notifyProblem(msg) {
	console.error(msg);
	var notification = webkitNotifications.createNotification(
	  'icon.png', 'PDF Upload Problem!',  msg);
	notification.show();
}

var currentConversion;

var BookConversion = function(bookJson, serverRequestId) {
	this.bookJson = bookJson;
	this.serverRequestId = serverRequestId;
	currentConversion = this;
}

// create new tab
// load pdf_converter
// load book into pdf_converter
// for every page
//   load page
//   wait for load
//   convert page to pdf, upload
// send book complete
// close tab
BookConversion.prototype = {

	windowId: null,
	tabId: null,
	startTime: 0,
	closeTab: false,
	start: function() {
		this.startTime = Date.now();
		this.getWindow();
		this.closeTab = true;
	},
	startInTab: function(tabId) {
		this.startTime = Date.now();
		var THIS = this;
		this.closeTab = false;
		chrome.tabs.update(tabId, { url: getPdfConverterUrl() }, function() {
			THIS.didCreateTab(tabId);
		});
	},
	waitForTabToLoad: function(nextAction) {
		var THIS = this;
		chrome.tabs.get( this.tabId, function(tab) {
			if (tab.status == 'complete')
				nextAction.apply(THIS);
			else {
				console.log("waiting for tab load");
				window.setTimeout( function() { THIS.waitForTabToLoad(nextAction)}, 50);
			}
		});
	},
	getWindow: function() {
		var THIS = this;
		chrome.windows.getCurrent( function(w) {
			if (!w)
				chrome.windows.create({ width: 800, height: 800}, function(w) { THIS.didGetWindow(w.id) });
			else
				THIS.didGetWindow(w.id);
		});
	},
	didGetWindow: function(id) {
		this.windowId = id;
		this.createTab();
	},
	createTab: function() {
		var THIS = this;
		chrome.tabs.create({'windowId': this.windowId, 'url': getPdfConverterUrl() },
				function(tab) { THIS.didCreateTab(tab.id) });
	},
	didCreateTab: function(tabId) {
		this.tabId = tabId;
		this.waitForTabToLoad( this.loadContentScript );
	},
	loadContentScript: function() {
		var THIS = this;
		chrome.tabs.executeScript(this.tabId, { file: "content.js" }, function() { THIS.didLoadContentScript() });
	},
	didLoadContentScript: function() {
		this.loadBook();
	},
	loadBook: function() {
		chrome.tabs.sendMessage(this.tabId, {
			action: 'loadBookFromJson',
			bookJson: this.bookJson
		});
	},
	didLoadBook: function(message) {
		this.startPDFConversion();
	},
	startPDFConversion: function() {
		this.pageList = this.bookJson.document.pageList.slice();
		this.convertNextPage();
	},
	convertNextPage: function() {
		if (this.pageList.length == 0) {
			this.didPDFConversion();
			return;
		}
		this.pageId = this.pageList.shift();
		chrome.tabs.sendMessage(this.tabId, {
			action: 'showPage',
			pageId: this.pageId
		});
	},
	didShowPage: function(message) {
		this.pageWidth = parseInt(message.pageWidth);
		this.pageHeight = parseInt(message.pageHeight);
		this.waitForTabToLoad( this.saveAsPDF );
	},
	saveAsPDF: function() {
		var saveAsPDFOptions = {
			tabId: this.tabId,
			dpi: 1200,
			margin: [0],
			pageWidth: this.pageWidth,
			pageHeight: this.pageHeight
		};
		console.log("converting ", this.pageId, " ", this.pageWidth, "x", this.pageHeight);
		var THIS = this;
		chrome.pageCapture.saveAsPDF( saveAsPDFOptions, function(pdfBlob) {
			if ('lastError' in chrome.extension)
				THIS.fail( { message: "saveAsPDF failed" + chrome.extension.lastError.message } );
			else
				THIS.didSaveAsPDF(pdfBlob);
		});
	},
	didSaveAsPDF: function(blob) {
		this.blobToArrayBuffer(blob);
		this.pdfBlobToServer(this.pageId, blob);
	},
	blobToArrayBuffer: function(blob) {
		var fileReader = new FileReader();
		var THIS = this;
		fileReader.onload = function() {
    		THIS.pdfBlobToServer(THIS.pageId, this.result);
		};
		fileReader.onerror = function() {
			THIS.fail("Could not read file blob " + THIS.pageId);
		}
		fileReader.onprogress = function() {
			console.log("File reader progress");
		}
		fileReader.readAsArrayBuffer(blob);
	},
	pdfBlobToServer: function(pageId, blob) {
		var THIS = this;
		var xhr = new XMLHttpRequest();
		var url = getPdfSaverUrl() + "pdf_upload?request_id=" + this.serverRequestId + "&page_id=" + this.pageId;
		var timeStart = Date.now();
		xhr.onload = function (ev) {
			if (xhr.status != 200)
				THIS.fail("PDF Upload failed. " + THIS.pageId + xhr.status + "\n" + xhr.responseText);
			else
				THIS.didPdfBlobToServer();
				console.info("PDF uploaded ", Date.now() - timeStart);
			};
		xhr.onerror = function(ev) {
			THIS.fail("PDF Upload failed. PDF Upload server might be down.");
		};
		xhr.open("POST", url, true);
//		var bufferView = new Uint32Array(blob);
		xhr.send(blob);
	},
	didPdfBlobToServer: function() {
		this.convertNextPage();
	},
	fail: function(error) {
		console.error("PDF conversion failed ", this.pageId ? this.pageId : "");
		console.error(error.message);
		this.pageList = [];
//		notifyProblem(error.message);
		this.didPDFConversion(error.message);
	},
	didPDFConversion: function(error) {
		console.log("All pages have been converted");
		var xhr = new XMLHttpRequest();
		var THIS = this;
		xhr.onerror = function(ev) {
			console.error("work_complete failed. pdf_saver_server might be down.");
		};
		var url = getPdfSaverUrl() + "work_complete?request_id=" + this.serverRequestId;

		var formData = new FormData();
		formData.append('request_id', this.serverRequestId);
		formData.append('book_id', this.bookJson.id);
		if (error)
			formData.append("error", error);
		formData.append("totalTime", Date.now() - this.startTime);

		xhr.open("POST", url, true);
		xhr.send(formData);
		if (this.closeTab && this.tabId)
			chrome.tabs.remove(this.tabId);
		currentConversion = null;
	}
}

function conversionListener(message, sender, sendResponse) {
	// console.log("background.js messageListener");
	switch(message.action) {
	case 'didShowPage':
		currentConversion.didShowPage(message);
	break;
	case 'didLoadBook':
		currentConversion.didLoadBook(message);
		console.log("book loaded");
	break;
	case 'fail':
		currentConversion.fail(message);
	break;
	case 'showPage':
	break;
	default:
		console.log("unknown message received", message);
	}
}
chrome.runtime.onMessage.addListener(conversionListener);


function convertTabToPdf(tabId, options, successCb, failCb) {
	var saveAsPDFOptions = {
		tabId: tabId,
		dpi: 1200,
		margin: [0],
		pageWidth: 612,
		pageHeight: 792
	}
	for (var p in saveAsPDFOptions) {
		if (p in options)
			saveAsPDFOptions[propName] = options[p];
	}
	try {
		chrome.pageCapture.saveAsPDF( saveAsPDFOptions, function(pdfBlob) {
			if ('lastError' in chrome.extension)
				failCb(tabId, chrome.extension.lastError.message);
			else
				successCb(tabId, pdfBlob);
		});
	}
	catch(ex) {
		console.error("exception on saveAsPDF");
		console.error(ex);
		failCb(tabId, "Unexpected error in saveAsPDF" + ex.message);
	}
}

function pollForWork() {
	if (currentConversion)	// just one conversion at a time
		return;
	var xhr = new XMLHttpRequest();
	var url = getPdfSaverUrl() + "get_work";
	xhr.open("GET", url, true);
	xhr.onload = function(ev) {
		if (xhr.status == 200) {
			var task = JSON.parse(xhr.responseText);
			var c = new BookConversion(task.book_json, task.task_id);
			c.start();
		}
		else if (xhr.status == 204)
			;
		else {
			notifyProblem("Error getting work " + xhr.status);
		}
	}
	xhr.onerror = function(ev) {
		notifyProblem("Error getting work " + xhr.status);
	}
	xhr.send();
}

// Logs in as a printer user
var Authorizer = {
	start: function() {
		chrome.windows.getCurrent( function(w) {
		if (!w)
			chrome.windows.create({ width: 800, height: 800}, function(w) { Authorizer.didGetWindow(w.id) });
		else
			Authorizer.didGetWindow(w.id);
		});
	},
	didGetWindow: function(id) {
		chrome.tabs.create({'windowId': this.id, 'url': getAuthenticationUrl() },
				function(tab) { Authorizer.didCreateTab(tab.id) });
	},
	didCreateTab: function(tabId) {
		window.setTimeout(function() {chrome.tabs.remove(tabId)}, 5000);
	}
}
function authorize() {
	var xhr = new XMLHttpRequest();
	xhr.open("GET", getAuthenticationUrl(), true);
	xhr.onerror = function(ev) {
		notifyProblem("Could not authenticate as printer");
	}
	xhr.send();
}
// Refresh authorization every hour
Authorizer.start();
setInterval(function() {Authorizer.start()}, 3600000);

if (!TEST_MODE) setInterval(pollForWork, 1000);

var BUTTON_MODE = "SaveCurrent"; // "TestWork";	// SaveCurrent LoadPDFConverter TestWork

switch(BUTTON_MODE) {
case "SaveCurrent":
	chrome.browserAction.onClicked.addListener(function(tab) {
		convertTabToPdf( tab.id, {},
			function(tabId, blob) {
				console.log("successful conversion", blob);
				var xhr = new XMLHttpRequest();
				var url = getPdfSaverUrl() + "pdf_upload?request_id=test&page_id=test";
				xhr.open("POST", url, true);
				xhr.onload = function (ev) {
					if (xhr.status != 200) {
						notifyProblem("PDF Upload failed. " + xhr.status + "\n" + xhr.responseText);
					}
					else
						console.info("PDF uploaded")
				};
				xhr.onerror = function(ev) {
					notifyProblem("PDF Upload failed. PDF Upload server might be down.");
				};
				xhr.send(blob);

			},
			function(tabId, message) {
				console.log("failed conversion", message);
			});
	});
break;
case "LoadPDFConverter":
	chrome.browserAction.onClicked.addListener(function(tab) {
		chrome.tabs.update(tab.id, { url: getPdfConverterUrl() }, function( tab ) {
			chrome.tabs.executeScript(tab.id, { file: "content.js" }, function() {
			console.log("background.js sendMessage");
			chrome.tabs.sendMessage(tab.id, { action: 'loadBook', bookId: 1});
		});
		});
	});
break;
case "TestWork":
	chrome.browserAction.onClicked.addListener(function(tab) {
//		chrome.tabs.update(tab.id, { url: 'http://dev.pb4us.com/pdf_converter' });
		var tabId = tab.id;
		var xhr = new XMLHttpRequest();
		var url = getPdfSaverUrl() + "get_work?book_id=2";
		xhr.open("GET", url, true);
		xhr.onload = function(ev) {
			if (xhr.status == 200) {
				var task = JSON.parse(xhr.responseText);
				var c = new BookConversion(task.book_json, task.task_id);
				c.startInTab(tabId);
			}
			else if (xhr.status == 204)
				;
			else {
				notifyProblem("Error getting work " + xhr.status);
			}
		}
		xhr.onerror = function(ev) {
			notifyProblem("Error getting work " + xhr.status);
		}
		xhr.send();
	});
break;
}

