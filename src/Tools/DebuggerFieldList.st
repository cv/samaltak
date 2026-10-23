KeyValueList subclass: #DebuggerFieldList
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

DebuggerFieldList comment: 'I list DebuggerFields: the name in code type (thisContext in italics, outer temporaries muted, a watched field marked with an ultramarine dot), a small italic "arg" after arguments, and the value''s short print string right-aligned and muted.'!

!DebuggerFieldList methodsFor: 'initialization'!
initialize
	super initialize.
	self valueBlock: [:field | field shortText].
	self styleBlock: [:field |
		field kind == #context
			ifTrue: [#italic]
			ifFalse: [field kind == #outer ifTrue: [#(#code #muted)] ifFalse: [#code]]].
	self remoteNameBlock: [:field | field name].
	self remoteStateBlock: [:field | Array with: 'value=', (self remoteQuote: field shortText)]
! !

!DebuggerFieldList methodsFor: 'drawing'!
rightTextOf: anItem
	"The value, cut so that the name (and its tag) stays readable."
	| s f max |
	s := super rightTextOf: anItem.
	s isNil ifTrue: [^nil].
	f := self rightFont.
	max := (self rowsWidth - (2 * self paddingX) - ((self labelFontFor: (self stylesOf: anItem)) widthOf: anItem name) - (anItem kind == #arg ifTrue: [30] ifFalse: [12])) max: 24.
	(f widthOf: s) <= max ifTrue: [^s].
	[s size > 1 and: [(f widthOf: s, '…') > max]] whileTrue: [s := s first: s size - 1].
	^s, '…'
!
labelFontFor: styles
	(styles includes: #italic) ifTrue: [^self theme font: #codeItalic].
	^super labelFontFor: styles
!
drawItem: anItem in: r on: aCanvas inverted: inverted
	| x f tag |
	super drawItem: anItem in: r on: aCanvas inverted: inverted.
	tag := anItem kind == #arg ifTrue: ['arg'] ifFalse: [anItem kind == #return ifTrue: ['returning'] ifFalse: [nil]].
	f := self labelFontFor: (self stylesOf: anItem).
	x := r left + self paddingX + (f widthOf: anItem name) + 5.
	tag isNil ifFalse: [
		aCanvas drawString: tag at: x @ (r top + ((r height - (self theme font: #smallItalic) lineHeight) / 2))
			font: (self theme font: #smallItalic) color: (inverted ifTrue: [self theme color: #inverseMuted] ifFalse: [self theme muted])].
	anItem kind == #watched ifTrue: [
		DebuggerGlyphs disc: (x + 3) @ r center y radius: 3 color: (inverted ifTrue: [self theme paper] ifFalse: [self theme ultramarine]) on: aCanvas]
! !
