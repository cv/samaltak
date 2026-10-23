Widget subclass: #Container
	instanceVariableNames: 'background'
	classVariableNames: ''
	package: 'UI-Widgets'!

Container comment: 'I am the abstract superclass of the layout widgets (Row, Column, Stack). I can fill my background (background: aColor or a theme color name).'!

!Container methodsFor: 'accessing'!
background
	^background
!
background: aColorOrSymbol
	background := aColorOrSymbol.
	self invalidate
!
backgroundColor
	background isNil ifTrue: [^nil].
	background isSymbol ifTrue: [^self theme color: background].
	^background
! !

!Container methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| c |
	c := self backgroundColor.
	c isNil ifFalse: [aCanvas fillRect: self localBounds color: c]
! !

!Container methodsFor: 'remote control'!
remoteRole
	^#group
!
remoteIsTransparent
	"Layout containers are flattened into their parent in snapshots."
	^true
! !
