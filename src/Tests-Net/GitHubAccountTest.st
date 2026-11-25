TestCase subclass: #GitHubAccountTest
	instanceVariableNames: 'account previous'
	classVariableNames: ''
	package: 'Tests-Net'!

GitHubAccountTest comment: 'Tests GitHubAccount: the github-config control command (configure, answer without the token, refuse bad settings and leave the account as it was, clear), the branches it owns, that the token is never printed, forgotten at shutdown. The image''s account is swapped for a fresh one during each test and put back after it. That no snapshot holds a token is checked from the host, through samaltak-ctl github-config (tests/tools/github_config_test.sh).'!

!GitHubAccountTest methodsFor: 'running'!
setUp
	previous := GitHubAccount default.
	account := GitHubAccount new.
	GitHubAccount default: account
!
tearDown
	account forgetToken.
	GitHubAccount default: previous
!
githubConfig: aDictionary
	"The github-config command's response, as the control connection would send it."
	^RemoteControl dispatch: (RemoteRequest on: (aDictionary copy at: 'cmd' put: 'github-config'; yourself))
!
settings
	^JSON parse: '{"repository":"octo/demo","baseBranch":"trunk","branchPrefix":"bot/"}'
!
newToken
	"A token made at run time, so that no literal in the image holds it."
	| random |
	random := Random new.
	^String new: 40 streamContents: [:s |
		s nextPutAll: 'ghp_'.
		36 timesRepeat: [s nextPut: ('0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ' at: (random nextInt: 62))]]
! !

!GitHubAccountTest methodsFor: 'tests'!
testDefaults
	self deny: account isConfigured.
	self deny: account hasToken.
	self assert: account baseBranch equals: 'main'.
	self assert: account branchPrefix equals: 'agent/'.
	self assert: account apiURL equals: 'https://api.github.com'.
	self should: [account token] raise: Error.
	self assert: ([account token] on: Error do: [:e | e messageText]) equals: 'No GitHub token: on the host run samaltak-ctl github-config --token-command <program> (docs/github.md)'.
	self assert: account printString equals: 'a GitHubAccount (not configured)'
!
testGithubConfigCommand
	| token response |
	token := self newToken.
	response := self githubConfig: (self settings at: 'token' put: token; yourself).
	self assert: (response at: 'ok').
	self assert: (response at: 'hasToken').
	self assert: (response at: 'repository') equals: 'octo/demo'.
	self assert: (response at: 'baseBranch') equals: 'trunk'.
	self assert: (response at: 'branchPrefix') equals: 'bot/'.
	self assert: (response at: 'apiUrl') equals: 'https://api.github.com'.
	self deny: ((JSON render: response) includesSubstring: token).
	self deny: ((JSON render: response) includesSubstring: 'ghp_').
	self assert: account isConfigured.
	self assert: account token equals: token.
	self deny: (account printString includesSubstring: token).
	self assert: account printString equals: 'a GitHubAccount (octo/demo, bot/* into trunk)'.
	response := self githubConfig: Dictionary new.
	self assert: (response at: 'hasToken').
	self assert: (response at: 'repository') equals: 'octo/demo'.
	response := self githubConfig: (Dictionary new at: 'apiUrl' put: 'http://127.0.0.1:9/'; yourself).
	self assert: (response at: 'apiUrl') equals: 'http://127.0.0.1:9'.
	self assert: account token equals: token.
	response := self githubConfig: (Dictionary new at: 'clear' put: true; yourself).
	self deny: (response at: 'hasToken').
	self assert: (response at: 'repository') isNil.
	self assert: (response at: 'baseBranch') equals: 'main'.
	self deny: account isConfigured.
	self assert: (token allSatisfy: [:each | each = $*])
!
testGithubConfigRefusesBadSettings
	| response |
	response := self githubConfig: (self settings at: 'repository' put: 'just-a-name'; yourself).
	self deny: (response at: 'ok').
	self assert: ((response at: 'error') includesSubstring: 'owner/name').
	response := self githubConfig: (self settings at: 'baseBranch' put: 'bot/main'; yourself).
	self deny: (response at: 'ok').
	self assert: ((response at: 'error') includesSubstring: 'branch prefix').
	response := self githubConfig: (self settings at: 'branchPrefix' put: ''; yourself).
	self deny: (response at: 'ok').
	response := self githubConfig: (self settings at: 'baseBranch' put: 'a..b'; yourself).
	self deny: (response at: 'ok').
	response := self githubConfig: (self settings at: 'apiUrl' put: 'ftp://x'; yourself).
	self deny: (response at: 'ok').
	response := self githubConfig: (self settings at: 'token' put: ''; yourself).
	self deny: (response at: 'ok').
	response := self githubConfig: (self settings at: 'token' put: 'ghp_ab cd'; yourself).
	self deny: (response at: 'ok').
	self assert: account repository isNil.
	self assert: account baseBranch equals: 'main'.
	self deny: account hasToken
!
testOwnsBranch
	account configure: self settings.
	self assert: (account ownsBranch: 'bot/20261122-101500-comment').
	self deny: (account ownsBranch: 'bot/').
	self deny: (account ownsBranch: 'trunk').
	self deny: (account ownsBranch: 'main').
	self deny: (account ownsBranch: 'robot/x').
	self deny: (account ownsBranch: nil)
!
testValidation
	self assert: (GitHubAccount isRepositoryName: 'owner/repo').
	self assert: (GitHubAccount isRepositoryName: 'a-b_c/d.e').
	self deny: (GitHubAccount isRepositoryName: 'owner').
	self deny: (GitHubAccount isRepositoryName: 'owner/re/po').
	self deny: (GitHubAccount isRepositoryName: '/repo').
	self deny: (GitHubAccount isRepositoryName: 'owner/..').
	self deny: (GitHubAccount isRepositoryName: 'owner/re po').
	self assert: (GitHubAccount isBranchName: 'main').
	self assert: (GitHubAccount isBranchName: 'agent/20261122-101500-fix').
	self deny: (GitHubAccount isBranchName: '').
	self deny: (GitHubAccount isBranchName: 'a//b').
	self deny: (GitHubAccount isBranchName: 'a/.b').
	self deny: (GitHubAccount isBranchName: 'x.lock').
	self deny: (GitHubAccount isBranchName: 'a b').
	self deny: (GitHubAccount isBranchName: 'a~1')
!
testShutDownForgetsEveryToken
	| other token |
	"GitHubAccount shutDown: forgets the token of every account, the image's own too: only in the image make test runs."
	(Smalltalk vm arguments includes: '--test') ifFalse: [^self].
	token := self newToken.
	account configure: (self settings at: 'token' put: token; yourself).
	other := GitHubAccount new token: self newToken; yourself.
	GitHubAccount shutDown: false.
	self deny: account isConfigured.
	self deny: account hasToken.
	self assert: account repository equals: 'octo/demo'.
	self deny: other hasToken.
	self assert: (token allSatisfy: [:each | each = $*])
! !
