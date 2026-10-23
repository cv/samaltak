Object subclass: #TableColumn
	instanceVariableNames: 'title width flex align textBlock drawBlock styleBlock remoteKey'
	classVariableNames: ''
	package: 'UI-Widgets'!

TableColumn comment: 'I am one column of a TableView: a header title, a fixed width or a flexible share, alignment (#left #right #center), and either a textBlock (item -> String) with an optional styleBlock (item -> #bold #italic #muted #accent or an Array of them) or a drawBlock [:canvas :rect :item :inverted | ...]. remoteKey: makes my text a state word of the row in remote-control snapshots (''pri=80''; an empty key adds the bare text).'!

!TableColumn methodsFor: 'accessing'!
title
	^title ifNil: ['']
!
title: aString
	title := aString
!
width
	^width
!
width: points
	width := points.
	flex := nil
!
flex
	^flex
!
flex: weight
	flex := weight.
	width := nil
!
isFlexible
	^flex notNil
!
align
	^align ifNil: [#left]
!
align: aSymbol
	align := aSymbol
!
textBlock
	^textBlock
!
textBlock: aBlock
	textBlock := aBlock
!
drawBlock
	^drawBlock
!
drawBlock: aBlock
	drawBlock := aBlock
!
styleBlock: aBlock
	styleBlock := aBlock
!
remoteKey
	^remoteKey
!
remoteKey: aString
	remoteKey := aString
!
textOf: anItem
	textBlock isNil ifTrue: [^''].
	^(textBlock value: anItem) ifNil: [''] ifNotNil: [:t | t asString]
!
stylesOf: anItem
	| s |
	styleBlock isNil ifTrue: [^#()].
	s := styleBlock value: anItem.
	s isNil ifTrue: [^#()].
	^s isSymbol ifTrue: [Array with: s] ifFalse: [s]
! !

!TableColumn class methodsFor: 'instance creation'!
title: aString width: points text: aBlock
	^self new title: aString; width: points; textBlock: aBlock; yourself
!
title: aString flex: weight text: aBlock
	^self new title: aString; flex: weight; textBlock: aBlock; yourself
!
title: aString width: points draw: aBlock
	^self new title: aString; width: points; drawBlock: aBlock; yourself
! !
