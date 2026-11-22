Object subclass: #GitHubTestServer
	instanceVariableNames: 'server token repository blobs trees commits refs pulls failures nextId'
	classVariableNames: ''
	package: 'Tests-Net'!

GitHubTestServer comment: 'I am a fake GitHub REST API for tests, over an HTTPTestServer (plain HTTP on 127.0.0.1): one repository (''test/repo'') in memory, its blobs, trees (path -> {mode. sha}, flat), commits, branches and pull requests, and the requests that GitHubClient and SourceFiler''s GitHub store make: GET git/ref/heads/<branch>, git/commits/<sha>, git/trees/<sha>?recursive=1 (directories as tree entries too), git/blobs/<sha> (base64 in lines of 60, as GitHub), POST git/blobs, git/trees (base_tree; sha null removes a path), git/commits, git/refs (422 when it exists), pulls. Every request must carry Authorization: Bearer <token> (else 401 Bad credentials) and the JSON Accept and API version headers (else 400). fail: ''POST git/commits'' status: 500 message: ''...'' makes the next request starting so fail.

	gh := GitHubTestServer token: ''t'' files: (Dictionary new at: ''src/A/B.st'' put: ''...''; yourself).
	gh url.   "the account''s apiUrl"
	gh textAt: ''src/A/B.st'' onBranch: ''agent/x''.
	gh stop'!

!GitHubTestServer methodsFor: 'initialization'!
setToken: aString files: aDictionary
	| tree |
	token := aString.
	repository := 'test/repo'.
	blobs := Dictionary new.
	trees := Dictionary new.
	commits := Dictionary new.
	refs := Dictionary new.
	pulls := OrderedCollection new.
	failures := Dictionary new.
	nextId := 0.
	tree := Dictionary new.
	aDictionary keysAndValuesDo: [:path :text | tree at: path put: (Array with: '100644' with: (self addBlob: text utf8Encoded))].
	refs at: 'main' put: (self addCommit: (self addTree: tree) parents: #() message: 'Initial').
	server := HTTPTestServer on: [:request | self handle: request]
! !

!GitHubTestServer methodsFor: 'accessing'!
url
	^server url
!
repository
	^repository
!
requests
	^server requests
!
requestsTo: aString
	"The requests whose method and path (after /repos/test/repo/) start with aString: 'POST git/blobs'."
	^server requests select: [:r | (r method, ' ', (self restOf: r path)) beginsWith: aString]
!
refs
	"Branch name -> commit sha."
	^refs
!
pulls
	^pulls
!
commitAt: aSha
	"{tree sha. parent shas. message}"
	^commits at: aSha
!
treeOfBranch: aBranch
	^trees at: (commits at: (refs at: aBranch)) first
!
textAt: aPath onBranch: aBranch
	"The file's text at the branch's head, nil if it has none."
	| entry |
	entry := (self treeOfBranch: aBranch) at: aPath ifAbsent: [^nil].
	^(blobs at: entry last) utf8Decoded
!
fail: aString status: anInteger message: aMessage
	"The next request whose method and path start with aString (as requestsTo:) gets this error."
	failures at: aString put: (Array with: anInteger with: aMessage)
!
stop
	server stop
! !

!GitHubTestServer methodsFor: 'objects'!
newSha
	nextId := nextId + 1.
	^(nextId printString: 16) asLowercase padLeftTo: 40 with: $0
!
addBlob: bytes
	| sha |
	sha := self newSha.
	blobs at: sha put: bytes.
	^sha
!
addTree: aDictionary
	| sha |
	sha := self newSha.
	trees at: sha put: aDictionary.
	^sha
!
addCommit: aTreeSha parents: shas message: aString
	| sha |
	sha := self newSha.
	commits at: sha put: (Array with: aTreeSha with: shas with: aString).
	^sha
! !

!GitHubTestServer methodsFor: 'serving'!
restOf: aPath
	| prefix |
	prefix := '/repos/', repository, '/'.
	^(aPath beginsWith: prefix) ifTrue: [aPath copyFrom: prefix size + 1 to: aPath size] ifFalse: [aPath]
!
handle: aRequest
	| rest key failure |
	(aRequest headerAt: 'authorization') = ('Bearer ', token) ifFalse: [^self status: 401 message: 'Bad credentials'].
	((aRequest headerAt: 'accept') = 'application/vnd.github+json' and: [(aRequest headerAt: 'x-github-api-version') = '2022-11-28'])
		ifFalse: [^self status: 400 message: 'Missing the GitHub Accept or API version header'].
	(aRequest path beginsWith: '/repos/', repository, '/') ifFalse: [^self status: 404 message: 'Not Found'].
	rest := self restOf: aRequest path.
	key := aRequest method, ' ', rest.
	failure := failures keys detect: [:k | key beginsWith: k] ifNone: [nil].
	failure isNil ifFalse: [
		| f |
		f := failures at: failure.
		failures removeKey: failure.
		^self status: f first message: f last].
	^[self route: aRequest method rest: rest request: aRequest]
		on: Error do: [:e | e return: (self status: 500 message: 'fake server: ', e messageText asString)]
!
route: method rest: rest request: aRequest
	method = 'GET' ifTrue: [
		(rest beginsWith: 'git/ref/heads/') ifTrue: [^self getRef: (rest copyFrom: 15 to: rest size)].
		(rest beginsWith: 'git/commits/') ifTrue: [^self getCommit: (rest copyFrom: 13 to: rest size)].
		(rest beginsWith: 'git/trees/') ifTrue: [^self getTree: ((rest copyFrom: 11 to: rest size) copyUpTo: $?)].
		(rest beginsWith: 'git/blobs/') ifTrue: [^self getBlob: (rest copyFrom: 11 to: rest size)]].
	method = 'POST' ifTrue: [
		rest = 'git/blobs' ifTrue: [^self postBlob: aRequest json].
		rest = 'git/trees' ifTrue: [^self postTree: aRequest json].
		rest = 'git/commits' ifTrue: [^self postCommit: aRequest json].
		rest = 'git/refs' ifTrue: [^self postRef: aRequest json].
		rest = 'pulls' ifTrue: [^self postPull: aRequest json]].
	^self status: 404 message: 'Not Found'
!
getRef: aBranch
	| sha |
	sha := refs at: aBranch ifAbsent: [^self status: 404 message: 'Not Found'].
	^self status: 200 json: (Dictionary new
		at: 'ref' put: 'refs/heads/', aBranch;
		at: 'object' put: (Dictionary new at: 'sha' put: sha; at: 'type' put: 'commit'; yourself);
		yourself)
!
getCommit: aSha
	| c |
	c := commits at: aSha ifAbsent: [^self status: 404 message: 'Not Found'].
	^self status: 200 json: (Dictionary new
		at: 'sha' put: aSha;
		at: 'tree' put: (Dictionary new at: 'sha' put: c first; yourself);
		at: 'parents' put: (c second collect: [:p | Dictionary new at: 'sha' put: p; yourself]);
		at: 'message' put: c last;
		yourself)
!
getTree: aSha
	| tree entries dirs |
	tree := trees at: aSha ifAbsent: [^self status: 404 message: 'Not Found'].
	entries := OrderedCollection new.
	dirs := Set new.
	tree keysAndValuesDo: [:path :e |
		entries add: (Dictionary new at: 'path' put: path; at: 'mode' put: e first; at: 'type' put: 'blob'; at: 'sha' put: e last; at: 'size' put: (blobs at: e last) size; yourself).
		1 to: path size do: [:i | (path at: i) = $/ ifTrue: [dirs add: (path copyFrom: 1 to: i - 1)]]].
	dirs do: [:d | entries add: (Dictionary new at: 'path' put: d; at: 'mode' put: '040000'; at: 'type' put: 'tree'; at: 'sha' put: self newSha; yourself)].
	^self status: 200 json: (Dictionary new at: 'sha' put: aSha; at: 'tree' put: entries asArray; at: 'truncated' put: false; yourself)
!
getBlob: aSha
	| bytes b64 lines |
	bytes := blobs at: aSha ifAbsent: [^self status: 404 message: 'Not Found'].
	b64 := Base64 encode: bytes.
	lines := WriteStream on: (String new: b64 size + (b64 size // 60) + 1).
	1 to: b64 size by: 60 do: [:i | lines nextPutAll: (b64 copyFrom: i to: (i + 59 min: b64 size)); nextPut: Character lf].
	^self status: 200 json: (Dictionary new
		at: 'sha' put: aSha;
		at: 'size' put: bytes size;
		at: 'encoding' put: 'base64';
		at: 'content' put: lines contents;
		yourself)
!
postBlob: json
	| bytes |
	bytes := (json at: 'encoding') = 'base64'
		ifTrue: [Base64 decode: (json at: 'content')]
		ifFalse: [(json at: 'content') utf8Encoded].
	^self status: 201 json: (Dictionary new at: 'sha' put: (self addBlob: bytes); yourself)
!
postTree: json
	| tree |
	tree := (json at: 'base_tree' ifAbsent: [nil]) isNil
		ifTrue: [Dictionary new]
		ifFalse: [(trees at: (json at: 'base_tree') ifAbsent: [^self status: 422 message: 'base_tree not found']) copy].
	(json at: 'tree') do: [:e |
		(e at: 'sha') isNil
			ifTrue: [(tree includesKey: (e at: 'path')) ifFalse: [^self status: 422 message: 'GitRPC::BadObjectState'].
				tree removeKey: (e at: 'path')]
			ifFalse: [
				(blobs includesKey: (e at: 'sha')) ifFalse: [^self status: 422 message: 'tree.sha ', (e at: 'sha'), ' is not a valid blob'].
				tree at: (e at: 'path') put: (Array with: (e at: 'mode') with: (e at: 'sha'))]].
	^self status: 201 json: (Dictionary new at: 'sha' put: (self addTree: tree); yourself)
!
postCommit: json
	| sha |
	(trees includesKey: (json at: 'tree')) ifFalse: [^self status: 422 message: 'Tree SHA does not exist'].
	((json at: 'parents') allSatisfy: [:p | commits includesKey: p]) ifFalse: [^self status: 422 message: 'Parent SHA does not exist or is not a commit object'].
	sha := self addCommit: (json at: 'tree') parents: (json at: 'parents') asArray message: (json at: 'message').
	^self status: 201 json: (Dictionary new
		at: 'sha' put: sha;
		at: 'tree' put: (Dictionary new at: 'sha' put: (json at: 'tree'); yourself);
		yourself)
!
postRef: json
	| ref name |
	ref := json at: 'ref'.
	(ref beginsWith: 'refs/heads/') ifFalse: [^self status: 422 message: 'Reference name is not valid'].
	name := ref copyFrom: 12 to: ref size.
	(refs includesKey: name) ifTrue: [^self status: 422 message: 'Reference already exists'].
	(commits includesKey: (json at: 'sha')) ifFalse: [^self status: 422 message: 'Object does not exist'].
	refs at: name put: (json at: 'sha').
	^self status: 201 json: (Dictionary new
		at: 'ref' put: ref;
		at: 'object' put: (Dictionary new at: 'sha' put: (json at: 'sha'); at: 'type' put: 'commit'; yourself);
		yourself)
!
postPull: json
	| pull |
	(refs includesKey: (json at: 'head')) ifFalse: [^self status: 422 message: 'Validation Failed'].
	(refs includesKey: (json at: 'base')) ifFalse: [^self status: 422 message: 'Validation Failed'].
	pull := json copy.
	pull at: 'number' put: pulls size + 1.
	pull at: 'html_url' put: 'https://github.test/', repository, '/pull/', (pulls size + 1) printString.
	pulls add: pull.
	^self status: 201 json: pull
!
status: anInteger json: anObject
	^HTTPTestServer response: anInteger headers: 'Content-Type: application/json', String crlf body: (JSON render: anObject)
!
status: anInteger message: aString
	^self status: anInteger json: (Dictionary new at: 'message' put: aString; at: 'documentation_url' put: 'https://docs.github.com/rest'; yourself)
! !

!GitHubTestServer class methodsFor: 'instance creation'!
token: aString files: aDictionary
	^self new setToken: aString files: aDictionary
! !
