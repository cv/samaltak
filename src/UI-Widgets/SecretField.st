Widget subclass: #SecretField
	instanceVariableNames: 'secret placeholder onAccept'
	classVariableNames: ''
	package: 'UI-Widgets'!

SecretField comment: 'I am a one-line field for a secret (an API key, a token): what is typed or pasted (⌘V, or paste from a button) shows as bullets, and nothing reads it back but secret: no copy or cut, no undo, no remote text, no printString with it. Return evaluates onAccept:. The owner takes the secret (secret), hands it on, then release (the receiver keeps it now) or clear (overwrite its characters and drop it). Every edit overwrites the String it replaces, and before every snapshot and quit every SecretField is cleared (I am on the shutdown list), so a half-typed key is in no image file. Pasting a secret empties the clipboard, so the World does not keep it either.

	field := SecretField new placeholder: ''paste the key''; onAccept: [:f | ...]; yourself.
	field paste.
	field hasSecret.
	account apiKey: field secret. field release'!

!SecretField methodsFor: 'accessing'!
secret
	"What was typed or pasted, or nil."
	^secret
!
hasSecret
	^secret notNil
!
placeholder
	^placeholder ifNil: ['']
!
placeholder: aString
	placeholder := aString.
	self invalidate
!
onAccept: aBlock
	"aBlock cull: me when Return is pressed."
	onAccept := aBlock
! !

!SecretField methodsFor: 'editing'!
replaceSecretWith: aStringOrNil
	"Make aStringOrNil (nil or empty: none) the secret, overwriting the one before."
	| old |
	old := secret.
	secret := (aStringOrNil isNil or: [aStringOrNil isEmpty]) ifTrue: [nil] ifFalse: [aStringOrNil].
	old == secret ifFalse: [self class wipe: old].
	self invalidate
!
append: aString
	| s |
	s := aString select: [:c | c value >= 32 and: [c value ~= 127 and: [c value < 128 or: [c value > 159]]]].
	s isEmpty ifTrue: [^self].
	secret isNil
		ifTrue: [self replaceSecretWith: s]
		ifFalse: [self replaceSecretWith: secret, s. self class wipe: s]
!
deleteLast
	secret isNil ifTrue: [^self].
	self replaceSecretWith: secret allButLast
!
paste
	"Append the clipboard's text (trimmed: a copied key often ends in a newline) and empty the clipboard."
	| s |
	self isEnabled ifFalse: [^self].
	s := self clipboardText.
	(s isString and: [s trimBoth notEmpty]) ifFalse: [^self].
	self append: s trimBoth.
	self clipboardText: ''
!
clear
	"Overwrite the secret and drop it."
	self replaceSecretWith: nil
!
release
	"Drop the secret without overwriting it: whoever took it (secret) keeps it now."
	secret := nil.
	self invalidate
! !

!SecretField methodsFor: 'events'!
wantsKeyboardFocus
	^self isEnabled
!
cursorAt: aPoint
	^#ibeam
!
mouseDown: anEvent
	^anEvent button = 1
!
textInput: anEvent
	self isEnabled ifTrue: [self append: anEvent string].
	^true
!
keyDown: anEvent
	| key cmd |
	key := anEvent key.
	cmd := anEvent modifiers commandKey.
	key isCharacter ifTrue: [
		cmd ifFalse: [^false].
		key asLowercase = $v ifTrue: [self paste. ^true].
		"Never copied or cut; ⌘A selects nothing to show."
		('cxaz' includes: key asLowercase) ifTrue: [^true].
		^false].
	key == #backspace ifTrue: [cmd ifTrue: [self clear] ifFalse: [self deleteLast]. ^true].
	key == #delete ifTrue: [self clear. ^true].
	(key == #return or: [key == #enter]) ifTrue: [
		onAccept isNil ifTrue: [^false].
		onAccept cull: self.
		^true].
	^false
!
focusGained
	self invalidate
!
focusLost
	self invalidate
! !

!SecretField methodsFor: 'drawing'!
bullets
	"A bullet per character, as many as fit."
	| font n |
	secret isNil ifTrue: [^''].
	font := self fontFor: #ui.
	n := secret size min: ((self width - 24) // ((font widthOf: (String with: self class bullet)) max: 1) max: 1).
	^String new: n withAll: self class bullet
!
drawSelfOn: aCanvas
	| r font text x |
	r := self localBounds.
	font := self fontFor: #ui.
	aCanvas fillRect: r color: self theme paper.
	aCanvas strokeRect: r color: (self isEnabled ifTrue: [self theme ink] ifFalse: [self theme color: #ink4]) width: 1.
	r := r insetBy: 8 @ 0.
	secret isNil
		ifTrue: [
			self isFocused ifFalse: [aCanvas drawString: self placeholder in: r font: (self fontFor: #uiItalic) color: (self theme color: #ink3) align: #left].
			x := r left]
		ifFalse: [
			text := self bullets.
			aCanvas drawString: text in: r font: font color: self theme ink align: #left.
			x := r left + (font widthOf: text)].
	self isFocused ifTrue: [
		aCanvas fillRect: (x @ (self height - font lineHeight // 2) extent: (self theme metric: #caretWidth) @ font lineHeight) color: self theme ink]
!
preferredExtent
	^200 @ ((self fontFor: #ui) lineHeight + 10) ceiling
! !

!SecretField methodsFor: 'remote control'!
remoteRole
	^#secret
!
remoteLabel
	"The placeholder, never the secret."
	^self placeholder
!
remoteState
	| s |
	s := OrderedCollection new.
	s add: (secret isNil ifTrue: [#empty] ifFalse: [#filled]).
	self isFocused ifTrue: [s add: #focused].
	self isEnabled ifFalse: [s add: #disabled].
	^s asArray
! !

!SecretField methodsFor: 'printing'!
printOn: aStream
	"Never the secret."
	aStream nextPutAll: 'a SecretField ('; nextPutAll: (secret isNil ifTrue: ['empty'] ifFalse: ['filled']); nextPut: $)
! !

!SecretField class methodsFor: 'secrets'!
bullet
	^Character value: 16r2022
!
wipe: aStringOrNil
	"Overwrite aStringOrNil's characters (a literal or read-only String stays as it is)."
	aStringOrNil isString ifFalse: [^self].
	[1 to: aStringOrNil size do: [:i | aStringOrNil at: i put: $*]] on: Error do: [:e | e return: nil]
! !

!SecretField class methodsFor: 'class initialization'!
initialize
	Smalltalk addToShutDownList: self
! !

!SecretField class methodsFor: 'system startup'!
shutDown: quitting
	"Before a snapshot or quit: no field keeps its secret."
	self allInstancesDo: [:each | each clear]
! !
