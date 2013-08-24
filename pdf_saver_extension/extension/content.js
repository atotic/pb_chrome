// content.js
function backgroundListener(message, sender, response) {
	// console.log("content.js backgroundListener", message.action);
	switch(message.action) {
	case 'loadBook':
	case 'loadBookFromJson':
	case 'showPage':
		window.postMessage(message, "*");
	break;
	default:
		console.log("content.js did not handle ", message.action);
	}
}
chrome.runtime.onMessage.addListener( backgroundListener);

function pageListener(event) {
	// console.log("content.js pageListener");
	switch(event.data.action) {
	case 'didShowPage':
	case 'didLoadBook':
	case 'fail':
	default:
		// console.log("content.js forwarding to background.js", event.data);
		chrome.runtime.sendMessage(event.data);
	}
}
window.addEventListener('message', pageListener, false);

console.log("content.js loaded");
