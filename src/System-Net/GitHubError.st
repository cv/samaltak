Error subclass: #GitHubError
	instanceVariableNames: 'status apiMessage request'
	classVariableNames: ''
	package: 'System-Net'!

GitHubError comment: 'I am a GitHub REST API request that failed or was refused (GitHubClient): status is the HTTP status, nil when no response came (no connection, a malformed body) or the request was refused before it was sent (a ref outside the account''s branchPrefix, nothing to commit); apiMessage is the API''s message (the body''s message and its errors) or the reason; request is ''METHOD /path''. My messageText says all three and never holds the token: no header is part of me.

	[GitHubClient default get: ''/repos/owner/repo/git/ref/heads/nope'']
		on: GitHubError do: [:e | e status -> e apiMessage]   "404 -> ''Not Found''"'!

!GitHubError methodsFor: 'accessing'!
status
	^status
!
apiMessage
	^apiMessage
!
request
	^request
!
setStatus: anIntegerOrNil message: aString request: aRequestOrNil
	status := anIntegerOrNil.
	apiMessage := aString.
	request := aRequestOrNil
! !

!GitHubError class methodsFor: 'signalling'!
status: anIntegerOrNil message: aString request: aRequestOrNil
	"Signal a failed request: 'GitHub 404: Not Found (GET /repos/o/r/...)'."
	| text |
	text := String new: 80 streamContents: [:s |
		s nextPutAll: 'GitHub'.
		anIntegerOrNil isNil ifFalse: [s space; print: anIntegerOrNil].
		s nextPutAll: ': '; nextPutAll: aString.
		aRequestOrNil isNil ifFalse: [s nextPutAll: ' ('; nextPutAll: aRequestOrNil; nextPut: $)]].
	^self new setStatus: anIntegerOrNil message: aString request: aRequestOrNil; signal: text
!
refuse: aString
	"Signal a request refused before it was sent (status nil)."
	^self status: nil message: aString request: nil
! !
