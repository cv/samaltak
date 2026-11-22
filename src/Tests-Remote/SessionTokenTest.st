TestCase subclass: #SessionTokenTest
	instanceVariableNames: 'saved'
	classVariableNames: ''
	package: 'Tests-Remote'!

SessionTokenTest comment: 'The session''s secrets (SessionToken): the token, compared in constant time with blanks and dashes aside, made once a session and shown once; the display password for VNC authentication, at most 8 characters, made apart from the token and shown once; both forgotten when an image resumes from a snapshot. The session''s secrets of the image running the tests are saved and put back.'!

!SessionTokenTest methodsFor: 'running'!
setUp
	saved := #(#Current #Announcement #Password #PasswordMade #PasswordAnnouncement) collect: [:k | k -> (SessionToken classPool at: k)].
	SessionToken forget
!
tearDown
	saved do: [:each | SessionToken classPool at: each key put: each value]
! !

!SessionTokenTest methodsFor: 'tests'!
testAuthorizes
	| t s |
	t := SessionToken newValue.
	self assert: t size equals: 32.
	self assert: (t allSatisfy: [:c | '0123456789abcdef' includes: c]).
	s := SessionToken value: (SessionToken grouped: t).
	self assert: s value equals: t.
	self deny: s isMade.
	self deny: s isTooShort.
	self assert: (s authorizes: t).
	self assert: (s authorizes: (SessionToken grouped: t)).
	self assert: (s authorizes: ' ', t, (String with: Character lf)).
	self deny: (s authorizes: t asUppercase).
	self deny: (s authorizes: (t first: 16)).
	self deny: (s authorizes: t, t).
	self deny: (s authorizes: '').
	self deny: (s authorizes: nil).
	self assert: (SessionToken value: 'abc-def') isTooShort.
	self deny: (s printString includesSubstring: t)
!
testCurrentIsMadeOnceAndShownOnce
	| t |
	SessionToken configuredValue isNil ifFalse: [^self].
	t := SessionToken current.
	self assert: SessionToken current == t.
	self assert: t isMade.
	self assert: t value size equals: 32.
	self assert: SessionToken takeAnnouncement isNil.
	t announceIfMade.
	self assert: SessionToken takeAnnouncement equals: t grouped.
	self assert: SessionToken takeAnnouncement isNil.
	t announceIfMade.
	self assert: SessionToken takeAnnouncement isNil description: 'shown once'
!
testGivenTokenIsNeverShown
	| t |
	t := SessionToken value: SessionToken newValue.
	SessionToken current: t.
	self assert: SessionToken current == t.
	t announceIfMade.
	self assert: SessionToken takeAnnouncement isNil
!
testDisplayPassword
	| p token |
	(Smalltalk argumentAfter: '--display-password-file') isNil ifFalse: [^self].
	SessionToken current: (token := SessionToken value: SessionToken newValue).
	p := SessionToken displayPassword.
	self assert: p size equals: 8.
	self assert: (p allSatisfy: [:c | SessionToken displayPasswordAlphabet includes: c]).
	self assert: SessionToken displayPassword == p.
	self deny: (token value includesSubstring: p).
	SessionToken announceDisplayPassword.
	self assert: SessionToken takeDisplayPasswordAnnouncement equals: p.
	self assert: SessionToken takeDisplayPasswordAnnouncement isNil.
	SessionToken announceDisplayPassword.
	self assert: SessionToken takeDisplayPasswordAnnouncement isNil description: 'shown once'.
	self assert: SessionToken current == token description: 'the token is not touched'
!
testDisplayPasswordsDiffer
	| seen |
	seen := Set new.
	1 to: 20 do: [:i | seen add: SessionToken newDisplayPassword].
	self assert: seen size equals: 20
!
testGivenDisplayPasswordIsNeverShown
	SessionToken displayPassword: 'secret12'.
	self assert: SessionToken displayPassword equals: 'secret12'.
	SessionToken announceDisplayPassword.
	self assert: SessionToken takeDisplayPasswordAnnouncement isNil
!
testResumingForgetsTheSession
	| t |
	SessionToken current: (t := SessionToken value: SessionToken newValue).
	SessionToken displayPassword: 'abcdefgh'.
	SessionToken startUp: false.
	self assert: SessionToken current == t description: 'after a snapshot the image goes on with its secrets'.
	SessionToken startUp: true.
	self deny: SessionToken current == t.
	self deny: SessionToken displayPassword = 'abcdefgh'
!
testControlServerSharesTheLogic
	self assert: (ControlServer normalizedToken: 'ab-cd ef') equals: 'abcdef'.
	self assert: (ControlServer grouped: '12345678') equals: '1234-5678'.
	self assert: ControlServer minimumTokenSize equals: SessionToken minimumSize
! !
