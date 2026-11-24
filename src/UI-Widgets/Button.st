Widget subclass: #Button
	instanceVariableNames: 'label action isDefault isOn pressed hover flashing font'
	classVariableNames: ''
	package: 'UI-Widgets'!

Button comment: 'I am a push button (Blue Book .btn): a 1-point black frame around a label; a second frame line on hover; inverted (white on black) while pressed, while on (toggle buttons in tool bars) and briefly after a click; a default button is bold with an outer ring; a disabled one is grey.

	Button label: ''Proceed'' action: [notifier proceed]

action: receives the button (cull:). click runs it as if clicked (remote control, Return on a default button).'!

!Button methodsFor: 'accessing'!
label
	^label ifNil: ['']
!
label: aString
	label = aString ifTrue: [^self].
	label := aString.
	self invalidate
!
action
	^action
!
action: aBlock
	action := aBlock
!
isDefault
	^isDefault == true
!
beDefault
	self isDefault: true
!
isDefault: aBoolean
	isDefault := aBoolean.
	self invalidate
!
isOn
	^isOn == true
!
on: aBoolean
	isOn := aBoolean.
	self invalidate
!
isPressed
	^pressed == true
!
isInverted
	^self isEnabled and: [self isPressed or: [self isOn or: [flashing == true]]]
!
font
	font isNil ifFalse: [^self fontFor: font].
	^self theme font: (self isDefault ifTrue: [#buttonBold] ifFalse: [#button])
!
font: aFontOrSymbol
	font := aFontOrSymbol
!
preferredExtent
	^((self font widthOf: self label) + (2 * (self theme metric: #buttonPaddingX)) + (self isDefault ifTrue: [6] ifFalse: [0])) ceiling
		@ (self theme metric: #buttonHeight)
! !

!Button methodsFor: 'actions'!
click
	"Flash and run the action."
	self isEnabled ifFalse: [^self].
	self flash.
	action isNil ifFalse: [action cull: self]
!
flash
	flashing := true.
	self invalidate.
	self tweenFrom: 0 to: 1 duration: (self theme metric: #flashMs) do: [:t |
		t >= 1 ifTrue: [flashing := false].
		self invalidate]
! !

!Button methodsFor: 'events'!
mouseDown: anEvent
	self isEnabled ifFalse: [^true].
	anEvent button = 1 ifFalse: [^false].
	pressed := true.
	self invalidate.
	^true
!
mouseMove: anEvent
	| inside |
	inside := self localBounds containsPoint: (self localEventPosition: anEvent).
	inside = (hover == true) ifFalse: [hover := inside. self invalidate].
	^true
!
mouseUp: anEvent
	| was |
	was := self isPressed.
	pressed := false.
	self invalidate.
	(was and: [self localBounds containsPoint: (self localEventPosition: anEvent)]) ifTrue: [self click].
	^true
!
mouseEnter: anEvent
	hover := true.
	self invalidate.
	^true
!
mouseLeave: anEvent
	hover := false.
	self invalidate.
	^true
!
cursorAt: aPoint
	^#arrow
! !

!Button methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| r ink paper frame textColor |
	self theme isBevelled ifTrue: [^self drawBevelledOn: aCanvas].
	r := self localBounds.
	ink := self theme ink.
	paper := self theme paper.
	frame := self isEnabled ifTrue: [ink] ifFalse: [self theme color: #ink4].
	self isDefault ifTrue: [
		aCanvas strokeRect: r color: frame width: 1.5.
		r := r insetBy: 2.5].
	aCanvas fillRect: r color: (self isInverted ifTrue: [ink] ifFalse: [paper]).
	aCanvas strokeRect: r color: frame width: 1.
	(hover == true and: [self isEnabled and: [self isInverted not]]) ifTrue: [
		aCanvas strokeRect: (r insetBy: 1) color: ink width: 1].
	textColor := self isInverted ifTrue: [paper] ifFalse: [frame].
	aCanvas drawString: self label in: r font: self font color: textColor align: #center
!
drawBevelledOn: aCanvas
	"A raised gray button with light top-left and dark bottom-right edges; pressed or on, it is the accent green and sunken."
	| r t light dark face frame textColor |
	t := self theme.
	r := self localBounds.
	light := t color: #bevelLight.
	dark := t color: #bevelDark.
	frame := self isEnabled ifTrue: [t color: #ink3] ifFalse: [t color: #ink4].
	self isDefault ifTrue: [
		aCanvas strokeRect: r color: t ink width: 1.5.
		r := r insetBy: 2.5].
	face := self isInverted
		ifTrue: [t color: #pressed]
		ifFalse: [(hover == true and: [self isEnabled]) ifTrue: [light] ifFalse: [t paper mixed: 0.4 with: light]].
	aCanvas fillRect: r color: face.
	self isInverted
		ifTrue: [light := dark. dark := face]
		ifFalse: [].
	aCanvas fillRect: (r origin + 1 extent: (r width - 2) @ 1) color: light.
	aCanvas fillRect: (r origin + 1 extent: 1 @ (r height - 2)) color: light.
	aCanvas fillRect: ((r left + 1) @ (r bottom - 2) extent: (r width - 2) @ 1) color: dark.
	aCanvas fillRect: ((r right - 2) @ (r top + 1) extent: 1 @ (r height - 2)) color: dark.
	aCanvas strokeRect: r color: frame width: 1.
	textColor := self isEnabled ifTrue: [t ink] ifFalse: [t color: #ink4].
	aCanvas drawString: self label in: r font: self font color: textColor align: #center
! !

!Button methodsFor: 'remote control'!
remoteRole
	^#button
!
remoteLabel
	^self label
!
remoteState
	| s |
	s := OrderedCollection new.
	self isDefault ifTrue: [s add: #default].
	self isOn ifTrue: [s add: #on].
	self isEnabled ifFalse: [s add: #disabled].
	^s asArray
!
remoteAction: aSymbol
	aSymbol == #click ifTrue: [^self inWindowDo: [self click]].
	^nil
! !

!Button class methodsFor: 'instance creation'!
label: aString
	^self new label: aString; yourself
!
label: aString action: aBlock
	^self new label: aString; action: aBlock; yourself
! !
