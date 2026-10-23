Container subclass: #LinearBox
	instanceVariableNames: 'spacing separators'
	classVariableNames: ''
	package: 'UI-Widgets'!

LinearBox comment: 'I lay out my visible children along one axis (Row: horizontally, Column: vertically), filling the other axis. Each child''s sizeSpec decides its length: fixed points, a percentage of the available length, #preferred (its preferredExtent), or a flexible share (flex: weight) of what is left. With separators: true I draw a 1-point rule between children (the Blue Book pane dividers); spacing: adds room between them.'!

!LinearBox methodsFor: 'accessing'!
spacing
	^spacing ifNil: [0]
!
spacing: aNumber
	spacing := aNumber.
	self layout
!
separators
	^separators == true
!
separators: aBoolean
	separators := aBoolean.
	self layout
!
gap
	^self spacing + (self separators ifTrue: [1] ifFalse: [0])
! !

!LinearBox methodsFor: 'axis'!
isHorizontal
	^self subclassResponsibility
!
along: aPoint
	^self isHorizontal ifTrue: [aPoint x] ifFalse: [aPoint y]
!
across: aPoint
	^self isHorizontal ifTrue: [aPoint y] ifFalse: [aPoint x]
!
pointAlong: a across: b
	^self isHorizontal ifTrue: [a @ b] ifFalse: [b @ a]
! !

!LinearBox methodsFor: 'layout'!
lengthsFor: kids available: total
	"Answer the lengths of kids (an Array) sharing total points."
	| lengths fixedSum flexSum remaining |
	lengths := Array new: kids size.
	fixedSum := 0.
	flexSum := 0.
	kids doWithIndex: [:kid :i |
		| spec len |
		spec := kid sizeSpec.
		len := nil.
		spec first == #fixed ifTrue: [len := spec last].
		spec first == #percent ifTrue: [len := (total * spec last / 100) floor].
		spec first == #preferred ifTrue: [len := self along: kid preferredExtent].
		len isNil
			ifTrue: [flexSum := flexSum + spec last]
			ifFalse: [lengths at: i put: len. fixedSum := fixedSum + len]].
	remaining := total - fixedSum max: 0.
	kids doWithIndex: [:kid :i |
		(lengths at: i) isNil ifTrue: [
			lengths at: i put: (flexSum = 0 ifTrue: [0] ifFalse: [remaining * kid sizeSpec last / flexSum])]].
	^lengths
!
layout
	| kids inner total lengths pos cross crossLen exact |
	kids := self visibleChildren asArray.
	kids isEmpty ifTrue: [^self].
	inner := self innerBounds.
	total := (self along: inner extent) - (self gap * (kids size - 1)) max: 0.
	lengths := self lengthsFor: kids available: total.
	pos := self along: inner origin.
	cross := self across: inner origin.
	crossLen := self across: inner extent.
	exact := pos.
	kids doWithIndex: [:kid :i |
		| start stop |
		start := exact rounded.
		exact := exact + (lengths at: i).
		stop := exact rounded max: start.
		kid bounds: ((self pointAlong: start across: cross) corner: (self pointAlong: stop across: cross + crossLen)).
		exact := exact + self gap]
! !

!LinearBox methodsFor: 'drawing'!
drawSelfOn: aCanvas
	super drawSelfOn: aCanvas.
	self separators ifTrue: [self drawSeparatorsOn: aCanvas]
!
drawSeparatorsOn: aCanvas
	| kids color inner |
	kids := self visibleChildren.
	color := self theme rule.
	inner := self innerBounds.
	1 to: kids size - 1 do: [:i |
		| at |
		at := (self along: (kids at: i) bounds corner) + self spacing.
		self isHorizontal
			ifTrue: [aCanvas fillRect: (at @ inner top corner: at + 1 @ inner bottom) color: color]
			ifFalse: [aCanvas fillRect: (inner left @ at corner: inner right @ (at + 1)) color: color]]
! !

!LinearBox class methodsFor: 'instance creation'!
with: aCollection
	^self new addAll: aCollection; yourself
!
withAll: aCollection
	^self with: aCollection
! !
