Object subclass: #HTTPResponse
	instanceVariableNames: 'status headers body'
	classVariableNames: ''
	package: 'System-Net'!

HTTPResponse comment: 'I am the response to an HTTPClient request: the status code, the headers (lowercase names; repeated headers joined with ", ") and the body bytes (empty when the body was streamed to a block).'!

!HTTPResponse methodsFor: 'initialization'!
setStatus: anInteger headers: aDictionary
	status := anInteger.
	headers := aDictionary.
	body := ByteArray new
!
body: aByteArray
	body := aByteArray
! !

!HTTPResponse methodsFor: 'accessing'!
status
	^status
!
headers
	^headers
!
headerAt: aString
	"The value of the header named aString (any case), or nil."
	^headers at: aString asLowercase ifAbsent: [nil]
!
body
	^body
!
string
	"The body decoded from UTF-8."
	^body utf8Decoded
!
json
	"The body parsed as JSON (JSONError if it is not)."
	^JSON parse: self string
!
isSuccess
	^status between: 200 and: 299
! !

!HTTPResponse methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an HTTPResponse '; print: status
! !
