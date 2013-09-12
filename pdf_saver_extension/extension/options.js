
function setStatus(message) {
	var status = document.getElementById("status");
	status.innerText = message;
	setTimeout(function() { status.innerText = ""; }, 750);
}

function setError(message) {
	var err = document.getElementById("error");
	err.innerText = message;
	setTimeout( function() { err.innerText = ""; }, 6000);
}

// Saves options to localStorage.
function getForm() {
	return {
		pdfServer: document.getElementById("pdf_saver"),
		pdfConverter: document.getElementById('pdf_converter'),
		authUrl: document.getElementById('authentication_url'),
		buttonMode: document.getElementById('button_mode'),
		pollForWork: document.getElementById('poll_for_work')
	}
}

function saveOptions() {
	var form = getForm();
	localStorage["pdfServer"] = form.pdfServer.value;
	localStorage["pdfConverter"] = form.pdfConverter.value;
	localStorage['authenticationUrl'] = form.authUrl.value;
	localStorage['buttonMode'] = form.buttonMode.value;
	if (form.pollForWork.getAttribute('checked'))
		localStorage.removeItem('pollForWork');
	else
		localStorage['pollForWork'] = 'off';
	setStatus('options saved');
	validateOptions();
}

function validateUrl(url, option) {
	var request = new XMLHttpRequest();
	request.open('GET', url , false);
	try {
		request.send(null);
	}
	catch(err) {
		request.status = -1;
	}

	if (request.status != 200) {
		setError("Server could not be reached " + request.status + " "+ url);
		return false;
	}
	return true;
}
function validateOptions() {
	if ( validateUrl( localStorage["pdfServer"] + 'test') )
		if ( validateUrl( localStorage['pdfConverter']) )
			if ( validateUrl( localStorage['authenticationUrl']) )
				setStatus('servers have been validated');
}

// Restores select box state to saved value from localStorage.
function restoreOptions() {
	var form = getForm();
	form.pdfServer.value = localStorage["pdfServer"] || "http://localhost:27000/";
	form.pdfConverter.value = localStorage['pdfConverter'] || "http://localhost:26000/pdf_converter";
  	form.authUrl.value = localStorage['authenticationUrl'] || "http://localhost:26000/login_as_printerABCDEFG";
  	form.buttonMode.value = localStorage['buttonMode'] || "SaveCurrent";
  	if (localStorage['pollForWork'] != "off")
		form.pollForWork.setAttribute('checked');
}

restoreOptions();
document.getElementById('save').addEventListener('click', saveOptions);
