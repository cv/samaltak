Object subclass: #GitHubAccount
	instanceVariableNames: 'repository baseBranch branchPrefix apiURL token'
	classVariableNames: 'Default'
	package: 'System-Net'!

GitHubAccount comment: 'I am the GitHub repository the image sends its source changes to (SourceFiler''s GitHub store, docs/github.md) and the token it uses: the repository (''owner/name''), the base branch pull requests go into (''main''), the prefix of the branches the image may create and update (''agent/''; never the base branch or any other ref), the REST API''s URL (''https://api.github.com'') and the token.

The token lives in memory only: I never print it, and it is overwritten and dropped before every snapshot and quit (I am on the shutdown list), so no image file contains it; the rest of my configuration is saved with the image. The World''s Accounts window (AccountsPanel, Tools-Agent) sets it and my settings, or the host sends it over the control connection with samaltak-ctl github-config --from-gh (or --token-command ''cmd''), which is the github-config command I register with RemoteControl:

	{"cmd": "github-config", "repository": "cv/samaltak", "baseBranch": "main", "branchPrefix": "agent/", "token": "..."}
	{"cmd": "github-config"}   "the configuration"
	{"cmd": "github-config", "clear": true}   "forget it all"
each answering the configuration (repository, baseBranch, branchPrefix, apiUrl, hasToken; never the token). A missing setting keeps its value; apiUrl may be set too (tests: a local server).

	account := GitHubAccount default.
	account isConfigured.   "a repository and a token: changes can become commits and pull requests"
	account token.   "the token; an Error saying how to set it when there is none"
	account ownsBranch: ''agent/20261122-101500''   "true: a branch I may create or update"
	account configure: aDictionary.   "the command''s settings (JSON names)"
	account clear   "forget the token and the configuration"

I live in System-Net (layer 0) beside HTTPClient, so the agent, the SourceFiler and the control command all reach me. Bad settings signal Error with a message saying which.'!

!GitHubAccount methodsFor: 'initialization'!
initialize
	baseBranch := 'main'.
	branchPrefix := 'agent/'.
	apiURL := 'https://api.github.com'
! !

!GitHubAccount methodsFor: 'accessing'!
repository
	"'owner/name', or nil."
	^repository
!
baseBranch
	^baseBranch
!
branchPrefix
	^branchPrefix
!
apiURL
	^apiURL
!
token
	"The token. An Error saying how to set it when there is none."
	token isNil ifTrue: [^Error signal: 'No GitHub token: paste it in Accounts (World menu), or on the host run samaltak-ctl github-config --from-gh'].
	^token
!
hasToken
	^token notNil
!
isConfigured
	"A repository and a token: source changes can go to GitHub."
	^repository notNil and: [token notNil]
!
ownsBranch: aBranchName
	"Whether aBranchName is one I may create or update: under my prefix, and not the base branch."
	^aBranchName isString
		and: [(aBranchName beginsWith: branchPrefix)
		and: [aBranchName size > branchPrefix size
		and: [aBranchName ~= baseBranch]]]
!
configuration
	"My settings, without the token."
	^Dictionary new
		at: 'repository' put: repository;
		at: 'baseBranch' put: baseBranch;
		at: 'branchPrefix' put: branchPrefix;
		at: 'apiUrl' put: apiURL;
		at: 'hasToken' put: token notNil;
		yourself
! !

!GitHubAccount methodsFor: 'configuring'!
repository: aRepository baseBranch: aBranchName branchPrefix: aPrefix apiURL: aURLString
	(self class isRepositoryName: aRepository) ifFalse: [^Error signal: 'The repository must be owner/name'].
	(self class isBranchName: aBranchName) ifFalse: [^Error signal: 'Bad base branch name'].
	(self class isBranchName: (aPrefix isString ifTrue: [aPrefix, 'x'] ifFalse: [nil]))
		ifFalse: [^Error signal: 'Bad branch prefix (e.g. agent/)'].
	(aBranchName beginsWith: aPrefix) ifTrue: [^Error signal: 'The base branch must not start with the branch prefix'].
	(aURLString isString and: [(aURLString beginsWith: 'https://') or: [aURLString beginsWith: 'http://']])
		ifFalse: [^Error signal: 'The API URL must be an http(s) URL'].
	repository := aRepository.
	baseBranch := aBranchName.
	branchPrefix := aPrefix.
	apiURL := (aURLString endsWith: '/') ifTrue: [aURLString allButLast] ifFalse: [aURLString]
!
token: aString
	"Hold aString as the token (in memory only)."
	(aString isString and: [aString notEmpty]) ifFalse: [^Error signal: 'The GitHub token is empty'].
	(aString anySatisfy: [:each | each isSeparator]) ifTrue: [^Error signal: 'The GitHub token contains white space'].
	self forgetToken.
	token := aString
!
configure: aDictionary
	"Apply a github-config request's settings (JSON names: repository baseBranch branchPrefix apiUrl token); a missing setting keeps its value. Nothing changes when a setting is bad."
	| newToken |
	newToken := aDictionary at: 'token' ifAbsent: [nil].
	((aDictionary includesKey: 'token') and: [(newToken isString and: [newToken notEmpty and: [(newToken anySatisfy: [:each | each isSeparator]) not]]) not])
		ifTrue: [^Error signal: 'The GitHub token is empty or contains white space'].
	self
		repository: (aDictionary at: 'repository' ifAbsent: [repository])
		baseBranch: (aDictionary at: 'baseBranch' ifAbsent: [baseBranch])
		branchPrefix: (aDictionary at: 'branchPrefix' ifAbsent: [branchPrefix])
		apiURL: (aDictionary at: 'apiUrl' ifAbsent: [apiURL]).
	newToken isNil ifFalse: [self token: newToken]
!
clear
	"Forget the token and the configuration."
	self forgetToken.
	repository := nil.
	self initialize
!
forgetToken
	"Drop the token, overwriting its characters first so no copy that shares it survives."
	| old |
	old := token.
	token := nil.
	old isString ifTrue: [[1 to: old size do: [:i | old at: i put: $*]] on: Error do: [:e | e return: nil]]
! !

!GitHubAccount methodsFor: 'printing'!
printOn: aStream
	"Never the token."
	aStream nextPutAll: 'a GitHubAccount'.
	repository isNil ifTrue: [^aStream nextPutAll: ' (not configured)'].
	aStream nextPutAll: ' ('; nextPutAll: repository; nextPutAll: ', '; nextPutAll: branchPrefix; nextPutAll: '* into '; nextPutAll: baseBranch.
	token isNil ifTrue: [aStream nextPutAll: ', no token'].
	aStream nextPut: $)
! !

!GitHubAccount class methodsFor: 'accessing'!
default
	"The image's account."
	^Default ifNil: [Default := self new]
!
default: anAccountOrNil
	"Make anAccountOrNil the image's account (tests); nil: a new one next time."
	Default := anAccountOrNil
!
reset
	Default isNil ifFalse: [Default forgetToken].
	Default := nil
! !

!GitHubAccount class methodsFor: 'validating'!
isRepositoryName: aString
	"owner/name: two non-empty parts of letters, digits, - _ and ."
	| parts |
	aString isString ifFalse: [^false].
	parts := aString subStrings: '/'.
	(parts size = 2 and: [(aString occurrencesOf: $/) = 1]) ifFalse: [^false].
	^parts allSatisfy: [:part | part notEmpty and: [part ~= '.' and: [part ~= '..' and: [part allSatisfy: [:c | c isLetter or: [c isDigit or: ['-_.' includes: c]]]]]]]
!
isBranchName: aString
	"A conservative git branch name: letters, digits, - _ . /; no empty component, none starting with . or ending with .lock."
	aString isString ifFalse: [^false].
	(aString isEmpty or: [(aString includesSubstring: '..') or: [(aString includesSubstring: '//') or: [(aString beginsWith: '/') or: [(aString endsWith: '/') or: [aString endsWith: '.lock']]]]]) ifTrue: [^false].
	(aString allSatisfy: [:c | c isLetter or: [c isDigit or: ['-_./' includes: c]]]) ifFalse: [^false].
	^(aString subStrings: '/') allSatisfy: [:part | (part beginsWith: '.') not]
! !

!GitHubAccount class methodsFor: 'class initialization'!
initialize
	Smalltalk addToShutDownList: self.
	RemoteControl registerCommand: 'github-config' handler: [:request | self githubConfig: request]
! !

!GitHubAccount class methodsFor: 'system startup'!
shutDown: quitting
	"Before a snapshot or quit: no account keeps its token."
	self allInstancesDo: [:each | each forgetToken]
! !

!GitHubAccount class methodsFor: 'remote control'!
githubConfig: aRemoteRequest
	"The github-config command: configure the default account (see my comment) and answer its configuration."
	| arguments |
	arguments := aRemoteRequest arguments.
	(arguments at: 'clear' ifAbsent: [false]) == true
		ifTrue: [self default clear]
		ifFalse: [
			(arguments keys anySatisfy: [:each | #('repository' 'baseBranch' 'branchPrefix' 'apiUrl' 'token') includes: each])
				ifTrue: [[self default configure: arguments] on: Error do: [:e | RemoteError signal: e messageText]]].
	^self default configuration
! !
