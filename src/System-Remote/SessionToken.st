Object subclass: #SessionToken
	instanceVariableNames: 'value made'
	classVariableNames: 'Current Announcement Password PasswordMade PasswordAnnouncement'
	package: 'System-Remote'!

SessionToken comment: 'I am the session''s secret for the network services (docs/remote.md): the control service (ControlServer) and the remote display take the same token, so an operator learns one and either service works without the other. SessionToken current is configured or made once a session: from --control-token-file path (its contents, blanks aside), else $SAMALTAK_CONTROL_TOKEN, else --control-token (samaltak.args on UEFI), else 128 bits from SecureRandom as 32 hexadecimal digits, which announceIfMade shows once (on the console, and as a toast when a World opens: takeAnnouncement). authorizes: compares in constant time, blanks and dashes aside (a token typed in groups is the same token). A token I was given is never printed.

The display password is a separate secret for VNC authentication (RFB security type 2), which carries at most 8 characters and is weak: whoever sees one exchange can find it offline. So it is never derived from the token: it comes from --display-password-file path, else is made per session (8 characters from SecureRandom) and shown beside the token (announceDisplayPassword: "display: password ..." on the console, a toast).

A session ends with the VM: an image resumed from a snapshot makes or reads them again.'!

!SessionToken methodsFor: 'initialization'!
setValue: aString made: aBoolean
	value := self class normalized: aString.
	made := aBoolean
! !

!SessionToken methodsFor: 'accessing'!
value
	"The token, blanks and dashes removed. Never written to a log."
	^value
!
isTooShort
	"Too short to keep out anyone who guesses: a service does not listen with it."
	^value size < self class minimumSize
!
isMade
	"Whether I was made here (and may be shown) rather than given."
	^made
!
grouped
	^self class grouped: value
!
authorizes: aString
	"Whether aString is my token (blanks and dashes aside), compared in constant time: the work is the same whatever aString holds, so its timing tells nothing about how much of it was right."
	| given diff |
	(value isNil or: [value isEmpty or: [aString isString not]]) ifTrue: [^false].
	given := self class normalized: aString.
	diff := given size bitXor: value size.
	1 to: value size do: [:i | | c |
		c := given isEmpty ifTrue: [0] ifFalse: [(given at: i - 1 \\ given size + 1) value].
		diff := diff bitOr: ((value at: i) value bitXor: c)].
	^diff = 0
!
announceIfMade
	"A token I made: show it once (announce:); a given one never."
	made ifFalse: [^self].
	made := false.
	self class announce: value
! !

!SessionToken methodsFor: 'printing'!
printOn: aStream
	"Never the token."
	aStream nextPutAll: 'a SessionToken'
! !

!SessionToken class methodsFor: 'class initialization'!
initialize
	"First, so that the services starting up after a resume see a new session."
	Smalltalk addFirstToStartUpList: self
! !

!SessionToken class methodsFor: 'system startup'!
startUp: resuming
	"An image resumed from a snapshot is a new session: its secrets are read or made again (the secrets in the snapshot are not reused). After taking a snapshot the image goes on with them."
	resuming ifTrue: [self forget]
!
forget
	Current := Announcement := Password := PasswordAnnouncement := nil.
	PasswordMade := false
! !

!SessionToken class methodsFor: 'instance creation'!
value: aString
	"A token of aString (blanks and dashes aside), given."
	^self new setValue: aString made: false
!
new: aString made: aBoolean
	^self new setValue: aString made: aBoolean
! !

!SessionToken class methodsFor: 'the session'!
current
	"The session's token: the configured one, else one made now (announceIfMade shows it once). An error if its file cannot be read. A service refuses one shorter than minimumSize (isTooShort)."
	| configured |
	Current isNil ifTrue: [
		configured := self configuredValue.
		Current := configured isNil
			ifTrue: [self new: self newValue made: true]
			ifFalse: [self value: configured]].
	^Current
!
current: aSessionTokenOrNil
	"Set the session's token (tests); nil: configure or make it again at the next use."
	Current := aSessionTokenOrNil
!
configuredValue
	"The token from --control-token-file path (its contents, blanks aside), else $SAMALTAK_CONTROL_TOKEN, else --control-token (on UEFI only: elsewhere ps shows a command line to everyone); nil: none."
	| file value |
	file := Smalltalk argumentAfter: '--control-token-file'.
	file isNil ifFalse: [
		value := [File readText: file] on: Error do: [:e | self error: 'cannot read the token file ', file].
		^self normalized: value].
	value := Smalltalk vm getenv: 'SAMALTAK_CONTROL_TOKEN'.
	(value notNil and: [value notEmpty]) ifTrue: [^value].
	value := Smalltalk argumentAfter: '--control-token'.
	(value notNil and: [Machine hasFirmware not]) ifTrue: [
		Smalltalk vm stderrWrite: 'control: warning: --control-token is on the command line, which ps shows to everyone here: use --control-token-file', (String with: Character lf)].
	^value
!
newValue
	"128 bits from SecureRandom (System-Crypto, loaded after me) as 32 hexadecimal digits."
	^((Smalltalk at: #SecureRandom) default nextBytes: 16) hex asLowercase
!
normalized: aString
	"aString without blanks and dashes: a token typed from the screen, in groups, is the same token."
	^aString asString reject: [:c | c isSeparator or: [c = $-]]
!
minimumSize
	^16
!
grouped: aToken
	"aToken in groups of four, for reading off a screen."
	^String new: aToken size * 5 // 4 streamContents: [:s |
		aToken doWithIndex: [:c :i |
			(i > 1 and: [i - 1 \\ 4 = 0]) ifTrue: [s nextPut: $-].
			s nextPut: c]]
!
announce: aToken
	"A token made here: show it once, on the console, on the firmware's screen too where the console is a serial port, and, when a World opens, as a toast (takeAnnouncement)."
	self show: 'control: token ', (self grouped: aToken), ' (made at start, shown once: samaltak-ctl connect --token-file F with it in F)'.
	Announcement := aToken
!
takeAnnouncement
	"The token announce: showed, grouped, once (the World shows it), else nil."
	| t |
	t := Announcement.
	Announcement := nil.
	^t ifNotNil: [:x | self grouped: x]
!
show: aLine
	Smalltalk vm stdoutWrite: aLine, (String with: Character lf)
! !

!SessionToken class methodsFor: 'display password'!
displayPassword
	"The session's password for VNC authentication (at most 8 characters): from --display-password-file path (its first line, blanks aside), else made now from SecureRandom, never from the token (announceDisplayPassword shows a made one). An error if the file cannot be read or its password is empty or longer than 8 characters."
	| file text |
	Password isNil ifFalse: [^Password].
	file := Smalltalk argumentAfter: '--display-password-file'.
	file isNil ifTrue: [
		PasswordMade := true.
		^Password := self newDisplayPassword].
	text := [File readText: file] on: Error do: [:e | ^self error: 'cannot read the display password file ', file].
	text := text lines.
	text := text isEmpty ifTrue: [''] ifFalse: [text first trimBoth].
	(text isEmpty or: [text size > self displayPasswordSize]) ifTrue: [
		^self error: 'the display password must have 1 to ', self displayPasswordSize printString, ' characters (VNC authentication uses no more)'].
	PasswordMade := false.
	^Password := text
!
displayPassword: aStringOrNil
	"Set the session's display password (tests); nil: read or make it again at the next use."
	Password := aStringOrNil.
	PasswordMade := false
!
displayPasswordSize
	"VNC authentication's DES key takes 8 characters."
	^8
!
displayPasswordAlphabet
	"31 characters that read unambiguously off a screen (no 0 o 1 l i): almost 5 bits each, 39 bits a password."
	^'abcdefghjkmnpqrstuvwxyz23456789'
!
newDisplayPassword
	"8 characters from SecureRandom: a byte below 248 (31 * 8) picks one, uniformly; one above is drawn again."
	| alphabet p random |
	alphabet := self displayPasswordAlphabet.
	random := (Smalltalk at: #SecureRandom) default.
	p := WriteStream on: (String new: self displayPasswordSize).
	[p position < self displayPasswordSize] whileTrue: [
		(random nextBytes: 16) do: [:b |
			(b < (alphabet size * 8) and: [p position < self displayPasswordSize]) ifTrue: [p nextPut: (alphabet at: b \\ alphabet size + 1)]]].
	^p contents
!
announceDisplayPassword
	"A display password made here: show it once, on the console beside the token (display: password ...), and when a World opens as a toast (takeDisplayPasswordAnnouncement). One from a file is never printed."
	| p |
	p := self displayPassword.
	PasswordMade == true ifFalse: [^self].
	PasswordMade := false.
	self show: 'display: password ', p, ' (made at start, shown once: for VNC authentication, at most 8 characters, never the token)'.
	PasswordAnnouncement := p
!
takeDisplayPasswordAnnouncement
	"The display password announceDisplayPassword showed, once (the World shows it), else nil."
	| p |
	p := PasswordAnnouncement.
	PasswordAnnouncement := nil.
	^p
! !
