Widget subclass: #Label
	instanceVariableNames: 'text font color align'
	classVariableNames: ''
	package: 'UI-Widgets'!

Label comment: 'I show one line of text, vertically centered: text:, font: (a Font or a theme font name like #uiItalic), color: (a Color or a theme color name), align: #left #center #right. text: also takes a block, evaluated at every draw.'!

!Label methodsFor: 'accessing'!
text
	^text isBlock ifTrue: [text value asString] ifFalse: [text ifNil: ['']]
!
text: aStringOrBlock
	text = aStringOrBlock ifTrue: [^self].
	text := aStringOrBlock.
	self invalidate
!
font
	^self fontFor: (font ifNil: [#ui])
!
font: aFontOrSymbol
	font := aFontOrSymbol.
	self invalidate
!
color
	^self colorFor: (color ifNil: [#ink])
!
color: aColorOrSymbol
	color := aColorOrSymbol.
	self invalidate
!
align
	^align ifNil: [#left]
!
align: aSymbol
	align := aSymbol.
	self invalidate
!
preferredExtent
	| p |
	p := self padding.
	^((self font widthOf: self text) + p left + p right) ceiling @ (self font lineHeight + p top + p bottom)
! !

!Label methodsFor: 'drawing'!
drawSelfOn: aCanvas
	text isBlock ifTrue: [aCanvas noteVolatile].
	aCanvas drawString: self text in: self innerBounds font: self font color: self color align: self align
! !

!Label methodsFor: 'remote control'!
remoteRole
	^#label
!
remoteLabel
	^self text
! !

!Label class methodsFor: 'instance creation'!
text: aString
	^self new text: aString; yourself
!
text: aString font: aFont
	^self new text: aString; font: aFont; yourself
! !
