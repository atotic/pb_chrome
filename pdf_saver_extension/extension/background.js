function getServerUrl() {
	var s = localStorage['pdfServer'] || "http://localhost:27000/";
	return s;
}

function notifyProblem(msg) {
	console.error(msg);
	var notification = webkitNotifications.createNotification(
	  'icon.png', 'PDF Upload Problem!',  msg);
//	notification.show();
}

// Globals holding tab loading status
window.tabErrors = {}; // tabId => error mappings
window.tabCompletion = {};

function convertTabToPdf(tabId, options, successCb, failCb) {
	var saveAsPDFOptions = {
		tabId: tabId,
		dpi: 300,
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

function tabIndex(tabId) {
	return tabId + "";
}

function startPdfConversion(json) {
	// open new tab
	// load the url
	// when document ready, do saveAsPdf
	// in callback, post data back to server
	function pdfDone(tabId, blob) {
		console.log("pdfDone");
		chrome.tabs.remove(tabId);
		var xhr = new XMLHttpRequest();
		var url = getServerUrl() + "pdf_done?id=" + json.id;
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
	}

	function pdfFail(tabId, message) {
		console.log("pdfFail " + message);
		if (tabId)
			chrome.tabs.remove(tabId);
		var xhr = new XMLHttpRequest();
		var url = getServerUrl() + "pdf_fail?id=" + json.id
		xhr.open("POST", url, true);
		xhr.onerror = function(ev) {
			notifyProblem("Double failure: pdfFail xhr failed. Message was " + message);
		};
		xhr.send(message);
	}

	function generatePdf( tabId ) {
		var tabIndex = tabIndex(tabId);
		if (tabIndex in window.tabErrors) {
			var err = window.tabErrors[tabIndex];
			delete window.tabErrors[tabIndex];
			pdfFail(tabId, err);
			return;
		}
		else if (!(tabIndex in window.tabCompletion)) {
			// loading still incomplete
			console.log("waiting for tab completion");
			setTimeout(function() { generatePdf(tab) }, 100);
			return;
		}
		convertTabToPdf(tabId, json, pdfDone, pdfFail);
	}

	function createTab(windowId) {
		chrome.tabs.create({'windowId': windowId, 'url': json.html_file_url},
			function(tab) { generatePdf(tabId) });
	}
	// Must create new window if no windows are available
	try {
		chrome.windows.getCurrent( function(w) {
			if (!w)
				chrome.windows.create({ width: 800, height: 800}, function(w) {
					createTab(w.id)
				} );
			else
				createTab(w.id);
		});
	}
	catch (e)
	{
		console.log("getCurrent threw exception");
		pdfFail("unexpected error", e.message);
	}
}

var debugMe =1;
function pollForWork() {
/*	if (debugMe != 0)
		return;
	debugMe = 1;*/
	var xhr = new XMLHttpRequest();
	var url = getServerUrl() + "poll_pdf_work";
	xhr.open("GET", url, true);
	xhr.onload = function(ev) {
		if (xhr.status == 200)
			startPdfConversion(JSON.parse(xhr.responseText));
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
//setInterval(pollForWork, 1000);

chrome.browserAction.onClicked.addListener(function(tab) {
	convertTabToPdf( tab.id, {},
		function(tabId, blob) {
			console.log("successful conversion", blob);
			var xhr = new XMLHttpRequest();
			var url = getServerUrl() + "pdf_test?title=" + tab.url;
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

// Get called by detect_failure.js
chrome.extension.onRequest.addListener( function(request, sender, sendResponse) {
	window.tabErrors[ tabIndex(sender.tab.id) ] =  request;
});

chrome.webNavigation.onErrorOccurred.addListener( function(details) {
	console.log("Received error for " + details.tabId + " " + details.error);
	window.tabErrors[ tabIndex(details.tabId) ] = details.error;
});
chrome.webNavigation.onCompleted.addListener( function(details) {
	window.tabCompletion[ tabIndex(details.tabId) ] = true;
});
