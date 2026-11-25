TestCase subclass: #GitHubClientTest
	instanceVariableNames: 'server account client'
	classVariableNames: ''
	package: 'Tests-Net'!

GitHubClientTest comment: 'I test GitHubAccount and GitHubClient against a fake GitHub (GitHubTestServer): the headers and JSON of requests and answers, GitHubError carrying the API''s message, refusing refs outside the branch prefix before anything is sent, and that the token is never printed (GitHubAccountTest tests the account).'!

!GitHubClientTest methodsFor: 'running'!
setUp
	server := GitHubTestServer token: self token files: (Dictionary new at: 'README.md' put: 'hi'; yourself).
	account := GitHubAccount new.
	account configure: (Dictionary new
		at: 'repository' put: 'test/repo';
		at: 'apiUrl' put: server url;
		at: 'token' put: self token;
		yourself).
	client := GitHubClient on: account
!
tearDown
	client close.
	server stop.
	account clear
!
token
	^'ghp_ClientTestToken0123456789' copy
! !

!GitHubClientTest methodsFor: 'tests'!
testGetSendsTheHeadersAndAnswersJSON
	| ref request |
	ref := client get: (client repositoryPath: 'git/ref/heads/main').
	self assert: ((ref at: 'object') at: 'sha') equals: (server refs at: 'main').
	request := server requests last.
	self assert: request method equals: 'GET'.
	self assert: request path equals: '/repos/test/repo/git/ref/heads/main'.
	self assert: (request headerAt: 'authorization') equals: 'Bearer ', self token.
	self assert: (request headerAt: 'accept') equals: 'application/vnd.github+json'.
	self assert: (request headerAt: 'x-github-api-version') equals: '2022-11-28'.
	self assert: (request headerAt: 'user-agent') equals: 'Samaltak'
!
testPostSendsJSON
	| answer request |
	answer := client post: (client repositoryPath: 'git/blobs') json: (Dictionary new at: 'content' put: 'aGk='; at: 'encoding' put: 'base64'; yourself).
	request := server requests last.
	self assert: (request headerAt: 'content-type') equals: 'application/json'.
	self assert: (request json at: 'content') equals: 'aGk='.
	self assert: (answer at: 'sha') size equals: 40
!
testErrorCarriesTheAPIMessage
	| error |
	error := [client get: (client repositoryPath: 'git/ref/heads/nope'). nil] on: GitHubError do: [:e | e return: e].
	self assert: error notNil.
	self assert: error status equals: 404.
	self assert: error apiMessage equals: 'Not Found'.
	self assert: error request equals: 'GET /repos/test/repo/git/ref/heads/nope'.
	self assert: error messageText equals: 'GitHub 404: Not Found (GET /repos/test/repo/git/ref/heads/nope)'.
	server fail: 'POST git/refs' status: 422 message: 'Reference already exists'.
	error := [client post: (client repositoryPath: 'git/refs') json: (Dictionary new at: 'ref' put: 'refs/heads/agent/x'; at: 'sha' put: (server refs at: 'main'); yourself). nil]
		on: GitHubError do: [:e | e return: e].
	self assert: error status equals: 422.
	self assert: error apiMessage equals: 'Reference already exists'.
	self deny: (server refs includesKey: 'agent/x')
!
testErrorMessageListsTheAPIErrors
	| response |
	response := HTTPResponse new setStatus: 422 headers: Dictionary new.
	response body: '{"message": "Validation Failed", "errors": [{"resource": "PullRequest", "code": "custom", "message": "No commits between main and agent/x"}, {"code": "missing_field", "field": "head"}]}' utf8Encoded.
	self assert: (GitHubClient messageOf: response) equals: 'Validation Failed (No commits between main and agent/x; missing_field head)'.
	response body: 'upstream timeout' utf8Encoded.
	self assert: (GitHubClient messageOf: response) equals: 'upstream timeout'.
	response body: ByteArray new.
	self assert: (GitHubClient messageOf: response) equals: 'HTTP 422'
!
testNoConnectionIsAGitHubError
	| other error |
	other := GitHubAccount new.
	other configure: (Dictionary new at: 'repository' put: 'test/repo'; at: 'apiUrl' put: 'http://127.0.0.1:1'; yourself).
	error := [(GitHubClient on: other) get: '/repos/test/repo'. nil] on: GitHubError do: [:e | e return: e].
	self assert: error notNil.
	self assert: error status isNil
!
testRefusesRefsOutsideTheBranchPrefix
	| before error |
	before := server requests size.
	#('refs/heads/main' 'refs/heads/feature' 'refs/tags/v1' 'refs/heads/agent/' 'refs/heads/agent/../main' 'main') do: [:ref |
		self should: [client post: (client repositoryPath: 'git/refs') json: (Dictionary new at: 'ref' put: ref; at: 'sha' put: (server refs at: 'main'); yourself)] raise: GitHubError].
	self should: [client post: (client repositoryPath: 'git/refs') json: (Dictionary new at: 'sha' put: 'x'; yourself)] raise: GitHubError.
	self should: [client patch: (client repositoryPath: 'git/refs/heads/main') json: (Dictionary new at: 'sha' put: 'x'; at: 'force' put: true; yourself)] raise: GitHubError.
	self should: [client delete: (client repositoryPath: 'git/refs/heads/main')] raise: GitHubError.
	self should: [client put: (client repositoryPath: 'contents/README.md') json: (Dictionary new at: 'message' put: 'x'; at: 'content' put: ''; yourself)] raise: GitHubError.
	self should: [client put: (client repositoryPath: 'contents/README.md') json: (Dictionary new at: 'message' put: 'x'; at: 'content' put: ''; at: 'branch' put: 'main'; yourself)] raise: GitHubError.
	self should: [client post: (client repositoryPath: 'merges') json: (Dictionary new at: 'base' put: 'main'; at: 'head' put: 'agent/x'; yourself)] raise: GitHubError.
	self should: [client put: (client repositoryPath: 'pulls/1/merge') json: Dictionary new] raise: GitHubError.
	error := [client delete: (client repositoryPath: 'git/refs/heads/main'). nil] on: GitHubError do: [:e | e return: e].
	self assert: error status isNil.
	self assert: (error messageText includesSubstring: 'refused').
	self assert: server requests size equals: before.
	"a branch under the prefix goes through"
	client post: (client repositoryPath: 'git/refs') json: (Dictionary new at: 'ref' put: 'refs/heads/agent/x'; at: 'sha' put: (server refs at: 'main'); yourself).
	self assert: (server refs at: 'agent/x') equals: (server refs at: 'main')
!
testTokenIsNeverPrinted
	| bad badClient error texts |
	bad := GitHubAccount new.
	bad configure: (Dictionary new at: 'repository' put: 'test/repo'; at: 'apiUrl' put: server url; at: 'token' put: 'ghp_WrongToken987' copy; yourself).
	badClient := GitHubClient on: bad.
	error := [badClient get: '/repos/test/repo/git/ref/heads/main'. nil] on: GitHubError do: [:e | e return: e].
	badClient close.
	self assert: error status equals: 401.
	self assert: error apiMessage equals: 'Bad credentials'.
	texts := {account printString. client printString. bad printString. badClient printString. error messageText. error description. error printString. JSON render: account configuration. JSON render: bad configuration}.
	texts do: [:each |
		self deny: (each includesSubstring: self token).
		self deny: (each includesSubstring: 'ghp_WrongToken987').
		self deny: (each includesSubstring: 'Bearer')]
! !
