ListView subclass: #KeyValueList
	instanceVariableNames: 'keyBlock valueBlock'
	classVariableNames: ''
	package: 'UI-Widgets'!

KeyValueList comment: 'I am a ListView of name / value pairs (inspector and debugger fields): the name in code type, the value''s short print string right-aligned and muted. Items are Associations (name -> value) by default; keyBlock: and valueBlock: adapt other items. Values are printed with printString, cut to 60 characters; a valueBlock may answer a String to show instead.'!

!KeyValueList methodsFor: 'initialization'!
initialize
	super initialize.
	self font: #codeSmall.
	self rightFont: #mono11.
	self labelBlock: [:item | (self keyOf: item) asString].
	self rightBlock: [:item | self valueTextOf: item]
! !

!KeyValueList methodsFor: 'accessing'!
keyBlock: aBlock
	keyBlock := aBlock.
	self invalidate
!
valueBlock: aBlock
	valueBlock := aBlock.
	self invalidate
!
keyOf: anItem
	keyBlock isNil ifFalse: [^keyBlock value: anItem].
	^(anItem respondsTo: #key) ifTrue: [anItem key] ifFalse: [anItem]
!
valueOf: anItem
	valueBlock isNil ifFalse: [^valueBlock value: anItem].
	^(anItem respondsTo: #value) ifTrue: [anItem value] ifFalse: [nil]
!
valueTextOf: anItem
	| v s |
	v := self valueOf: anItem.
	s := v isString ifTrue: [v] ifFalse: [[v printStringLimitedTo: 200] on: Error do: [:e | e return: '<error printing>']].
	s := s copyReplaceAll: (String with: Character lf) with: ' '.
	s size > 60 ifTrue: [s := (s first: (s graphemeClusterStartBefore: 60)), (String with: (Character value: 8230))].
	^s
! !
