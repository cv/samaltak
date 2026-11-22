Object subclass: #GitHubClient
	instanceVariableNames: 'account http'
	classVariableNames: ''
	package: 'System-Net'!

GitHubClient comment: 'I talk to the GitHub REST API for a GitHubAccount (its apiURL and token) over one kept-alive HTTPClient connection. Paths are the API''s (with their query); each request sends Authorization: Bearer <token> (none without a token), Accept: application/vnd.github+json, X-GitHub-Api-Version: 2022-11-28 and User-Agent, and a JSON body; the answer is the parsed JSON (nil for an empty body). A non-2xx status signals GitHubError with the status and the API''s message, as does a lost connection or a malformed body (status nil).

I refuse, before sending anything (GitHubError, status nil), a request that would create, move or delete a branch other than one under the account''s branchPrefix, or the base branch: a git/refs write outside refs/heads/<branchPrefix>, a contents write or a merge into such a branch, merging a pull request.

	client := GitHubClient on: GitHubAccount default.
	client get: (client repositoryPath: ''git/ref/heads/main'').
	client post: (client repositoryPath: ''git/blobs'') json: (Dictionary new at: ''content'' put: ''hi''; at: ''encoding'' put: ''utf-8''; yourself).
	client patch: path json: aDictionary.
	client delete: (client repositoryPath: ''git/refs/heads/agent/x'').
	client close'!

!GitHubClient methodsFor: 'initialization'!
setAccount: aGitHubAccount
	account := aGitHubAccount
! !

!GitHubClient methodsFor: 'accessing'!
account
	^account
!
repositoryPath: aString
	"The API path of aString in the account's repository: '/repos/<owner>/<name>/', aString."
	account repository isNil ifTrue: [^GitHubError refuse: 'No GitHub repository: configure GitHubAccount default'].
	^'/repos/', account repository, '/', aString
! !

!GitHubClient methodsFor: 'requests'!
get: aPath
	^self request: 'GET' path: aPath json: nil
!
post: aPath json: anObject
	^self request: 'POST' path: aPath json: anObject
!
patch: aPath json: anObject
	^self request: 'PATCH' path: aPath json: anObject
!
put: aPath json: anObject
	^self request: 'PUT' path: aPath json: anObject
!
delete: aPath
	^self request: 'DELETE' path: aPath json: nil
!
request: method path: aPath json: anObjectOrNil
	"Send the request; answer the response's parsed JSON, nil if it has no body."
	| headers body response where |
	where := method, ' ', aPath.
	self check: method path: aPath json: anObjectOrNil.
	headers := self headers.
	anObjectOrNil isNil ifFalse: [
		body := (JSON render: anObjectOrNil) utf8Encoded.
		headers at: 'Content-Type' put: 'application/json'].
	response := [self http request: method url: account apiURL, aPath headers: headers body: body do: nil]
		on: HTTPError do: [:e | ^GitHubError status: nil message: e messageText asString request: where].
	response isSuccess ifFalse: [^GitHubError status: response status message: (self class messageOf: response) request: where].
	response body isEmpty ifTrue: [^nil].
	^[response json] on: Error do: [:e | GitHubError status: nil message: 'not JSON: ', e messageText asString request: where]
!
close
	http isNil ifFalse: [http close].
	http := nil
! !

!GitHubClient methodsFor: 'private'!
http
	^http ifNil: [http := HTTPClient new]
!
headers
	| headers |
	headers := Dictionary new.
	account hasToken ifTrue: [headers at: 'Authorization' put: 'Bearer ', account token].
	headers
		at: 'Accept' put: 'application/vnd.github+json';
		at: 'X-GitHub-Api-Version' put: '2022-11-28';
		at: 'User-Agent' put: 'Samaltak'.
	^headers
!
check: method path: aPath json: anObject
	"Refuse a request that would update a branch that is not mine (see my comment)."
	| path i |
	method = 'GET' ifTrue: [^self].
	path := aPath copyUpTo: $?.
	i := path indexOfSubCollection: '/git/refs'.
	i > 0 ifTrue: [
		^self checkRef: (path size = (i + 8)
			ifTrue: [(anObject isKindOf: Dictionary) ifTrue: [anObject at: 'ref' ifAbsent: [nil]] ifFalse: [nil]]
			ifFalse: ['refs', (path copyFrom: i + 9 to: path size)])
			request: method, ' ', aPath].
	(path includesSubstring: '/contents/') ifTrue: [
		^self checkRef: ((anObject isKindOf: Dictionary) ifTrue: [(anObject at: 'branch' ifAbsent: [nil]) ifNotNil: [:b | 'refs/heads/', b]] ifFalse: [nil])
			request: method, ' ', aPath].
	(path endsWith: '/merges') ifTrue: [
		^self checkRef: ((anObject isKindOf: Dictionary) ifTrue: [(anObject at: 'base' ifAbsent: [nil]) ifNotNil: [:b | 'refs/heads/', b]] ifFalse: [nil])
			request: method, ' ', aPath].
	((path endsWith: '/merge') or: [(path includesSubstring: '/branches/') and: [path endsWith: '/rename']])
		ifTrue: [^GitHubError status: nil message: 'refused: I do not merge pull requests or rename branches' request: method, ' ', aPath]
!
checkRef: aRefOrNil request: aString
	((aRefOrNil isString and: [aRefOrNil beginsWith: 'refs/heads/'])
		and: [(account ownsBranch: (aRefOrNil copyFrom: 12 to: aRefOrNil size))
		and: [GitHubAccount isBranchName: (aRefOrNil copyFrom: 12 to: aRefOrNil size)]])
			ifFalse: [^GitHubError status: nil message: 'refused: ', aRefOrNil printString, ' is not a branch under ', account branchPrefix printString, ' (other than ', account baseBranch printString, ')' request: aString]
! !

!GitHubClient methodsFor: 'printing'!
printOn: aStream
	"Never the token."
	aStream nextPutAll: 'a GitHubClient on '; nextPutAll: (account repository ifNil: [account apiURL])
! !

!GitHubClient class methodsFor: 'instance creation'!
on: aGitHubAccount
	^self new setAccount: aGitHubAccount
!
default
	^self on: GitHubAccount default
! !

!GitHubClient class methodsFor: 'errors'!
messageOf: anHTTPResponse
	"The API's message in an error response's body, with its errors, or the body's start."
	| json text errors |
	json := [anHTTPResponse json] on: Error do: [:e | e return: nil].
	(json isKindOf: Dictionary) ifFalse: [
		text := [anHTTPResponse string trimBoth] on: Error do: [:e | e return: ''].
		^text isEmpty ifTrue: ['HTTP ', anHTTPResponse status printString] ifFalse: [text copyFrom: 1 to: (text size min: 300)]].
	text := (json at: 'message' ifAbsent: [nil]) ifNil: ['HTTP ', anHTTPResponse status printString].
	errors := json at: 'errors' ifAbsent: [nil].
	(errors isKindOf: SequenceableCollection) ifFalse: [^text asString].
	errors isEmpty ifTrue: [^text asString].
	^String new: 100 streamContents: [:s |
		s nextPutAll: text asString; nextPutAll: ' ('.
		errors
			do: [:each |
				(each isKindOf: Dictionary)
					ifTrue: [
						s nextPutAll: ((each at: 'message' ifAbsent: [nil]) ifNil: [
							String new: 20 streamContents: [:t |
								t nextPutAll: ((each at: 'code' ifAbsent: ['error']) ifNil: ['error']) asString.
								(each at: 'field' ifAbsent: [nil]) ifNotNil: [:f | t nextPutAll: ' '; nextPutAll: f asString]]]) asString]
					ifFalse: [s nextPutAll: each asString]]
			separatedBy: [s nextPutAll: '; '].
		s nextPut: $)]
! !
