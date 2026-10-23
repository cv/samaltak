Widget subclass: #ToastView
	instanceVariableNames: 'message opacity hideTimer'
	classVariableNames: ''
	package: 'UI-Widgets'!

ToastView comment: 'I show a short message inside a window (Blue Book toast: white italic on black with a hard shadow), fading in and out. The World shows screen-wide toasts itself (World current toast:); I am for messages that belong to one pane. show: aString displays me for 2.2 s.'!

!ToastView methodsFor: 'initialization'!
initialize
	super initialize.
	opacity := 0.
	visible := false
! !

!ToastView methodsFor: 'accessing'!
message
	^message
!
opacity
	^opacity
!
show: aString
	self show: aString for: 2200
!
show: aString for: milliseconds
	message := aString.
	self visible: true.
	hideTimer isNil ifFalse: [hideTimer cancel].
	self tweenFrom: opacity to: 1 duration: (self theme metric: #fadeMs) do: [:v | opacity := v. self invalidate].
	hideTimer := self after: milliseconds do: [self hide].
	self invalidate
!
hide
	hideTimer := nil.
	self tweenFrom: opacity to: 0 duration: (self theme metric: #fadeMs) do: [:v |
		opacity := v.
		v = 0 ifTrue: [self visible: false].
		self invalidate]
!
preferredExtent
	| f |
	f := self theme font: #toast.
	^((f widthOf: (message ifNil: [''])) + (2 * (self theme metric: #toastPaddingX)) + 3) ceiling
		@ (f lineHeight + (2 * (self theme metric: #toastPaddingY)) + 3)
! !

!ToastView methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| box |
	message isNil ifTrue: [^self].
	box := 0 @ 0 corner: (self width - 3) @ (self height - 3).
	aCanvas alpha: opacity during: [
		aCanvas fillRect: (box translateBy: 3 @ 3) color: self theme ink.
		aCanvas fillRect: (box translateBy: 2 @ 2) color: self theme paper.
		aCanvas fillRect: box color: self theme ink.
		aCanvas drawString: message in: box font: (self theme font: #toast) color: self theme paper align: #center]
! !

!ToastView methodsFor: 'remote control'!
remoteRole
	^#toast
!
remoteLabel
	^message
! !
