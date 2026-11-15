Object subclass: #AgentTestAccount
	instanceVariableNames: 'signedIn loginCode loginURL approval approved'
	classVariableNames: ''
	package: 'Tests-Tools-Agent'!

AgentTestAccount comment: 'I stand in for an OpenAIAccount in the Agent window''s tests, without a network: signed in or not, and a device login whose finishLogin waits until the test approves it (approve) or the window cancels it (cancelLogin).'!

!AgentTestAccount methodsFor: 'initialization'!
initialize
	signedIn := true
! !

!AgentTestAccount methodsFor: 'accessing'!
isSignedIn
	^signedIn
!
email
	^signedIn ifTrue: ['tester@example.com'] ifFalse: [nil]
!
loginURL
	^loginURL
!
loginCode
	^loginCode
!
signOut
	signedIn := false
! !

!AgentTestAccount methodsFor: 'login'!
startLogin
	loginURL := 'https://auth.openai.com/codex/device'.
	loginCode := 'TEST-1234'.
	approval := Semaphore new
!
finishLogin
	approval wait.
	loginURL := loginCode := nil.
	signedIn := approved.
	^approved
!
approve
	approved := true.
	approval signal
!
cancelLogin
	approved := false.
	approval isNil ifFalse: [approval signal]
!
isLoginPending
	^loginCode notNil
! !
