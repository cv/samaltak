Error subclass: #HTTPError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Net'!

HTTPError comment: 'I am a failed HTTP exchange: no connection, the connection lost or cancelled (HTTPClient>>close), a malformed response. An HTTP error status is not an HTTPError: it is an HTTPResponse.'!
