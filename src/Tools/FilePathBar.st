Widget subclass: #FilePathBar
	instanceVariableNames: 'segments summary onClick hover shown'
	classVariableNames: ''
	package: 'Tools'!

FilePathBar comment: 'I am the File Browser''s path: its folder as segments separated by slashes, each a link to that folder (underlined under the pointer), the last one bold; on the right, in muted italics, what the folder holds. When the segments do not fit, the first ones give way to an ellipsis, a link to the last of them. segments: takes {label. path} pairs; onClick: [:path | …]. Remote: each segment is a button named after its label (@wN.path.vm).'!

!FilePathBar methodsFor: 'accessing'!
segments: anArray
	segments := anArray.
	hover := nil.
	shown := nil.
	self invalidate
!
summary: aString
	summary := aString.
	shown := nil.
	self invalidate
!
onClick: aBlock
	onClick := aBlock
!
labels
	^self shownSegments collect: [:each | each first]
! !

!FilePathBar methodsFor: 'layout'!
separatorWidth
	^(self theme font: #ui) widthOf: ' / '
!
summaryWidth
	^summary isNil ifTrue: [0] ifFalse: [((self theme font: #smallItalic) widthOf: summary) + 16]
!
shownSegments
	"{label. path. rect} of the segments shown: as many of the last ones as fit, after an ellipsis if not all do."
	| pad avail dropped list x result |
	(shown notNil and: [shown first = self width]) ifTrue: [^shown last].
	segments isNil ifTrue: [^#()].
	pad := self theme metric: #paneHeaderPaddingX.
	avail := self width - (2 * pad) - self summaryWidth.
	dropped := 0.
	[dropped < (segments size - 1) and: [(self widthOf: (self segmentsDropping: dropped)) > avail]] whileTrue: [dropped := dropped + 1].
	list := self segmentsDropping: dropped.
	x := pad.
	result := list collect: [:each | | w r |
		w := (self fontFor: each in: list) widthOf: each first.
		r := x @ 0 corner: (x + w) @ (self height - 1).
		x := x + w + (self gapAfter: each).
		Array with: each first with: (each at: 2) with: r].
	shown := Array with: self width with: result.
	^result
!
segmentsDropping: n
	"The segments without the first n, an ellipsis (a link to the last of them) in their place."
	n = 0 ifTrue: [^segments].
	^(Array with: (Array with: '…' with: ((segments at: n) at: 2))), (segments copyFrom: n + 1 to: segments size)
!
gapAfter: aSegment
	^aSegment first = '/' ifTrue: [4] ifFalse: [self separatorWidth]
!
widthOf: aList
	| w |
	w := 0.
	aList do: [:each | w := w + ((self fontFor: each in: aList) widthOf: each first)].
	aList allButLast do: [:each | w := w + (self gapAfter: each)].
	^w
!
fontFor: aSegment in: aList
	^self theme font: (aSegment == aList last ifTrue: [#uiBold] ifFalse: [#ui])
!
segmentIndexAt: aPoint
	| list |
	list := self shownSegments.
	list doWithIndex: [:each :i | ((each at: 3) containsPoint: aPoint) ifTrue: [^i]].
	^0
! !

!FilePathBar methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| list ui sep |
	aCanvas fillRect: self localBounds color: self theme paper.
	aCanvas fillRect: (0 @ (self height - 1) corner: self width @ self height) color: self theme rule.
	list := self shownSegments.
	ui := self theme font: #ui.
	sep := self separatorWidth.
	list doWithIndex: [:each :i | | r font top |
		r := each at: 3.
		font := self fontFor: each in: list.
		aCanvas drawString: each first in: r font: font color: self theme ink align: #left.
		i = hover ifTrue: [
			top := r top + (r height - font lineHeight / 2) + font baselineOffset + 2.
			aCanvas fillRect: (r left @ top corner: r right @ (top + 1)) color: self theme ink].
		(i < list size and: [each first ~= '/']) ifTrue: [
			aCanvas drawString: ' / ' in: (r right @ r top corner: (r right + sep) @ r bottom) font: ui color: (self theme color: #ink4) align: #left]].
	summary isNil ifFalse: [
		aCanvas drawString: summary in: (0 @ 0 corner: (self width - (self theme metric: #paneHeaderPaddingX)) @ (self height - 1))
			font: (self theme font: #smallItalic) color: self theme muted align: #right]
! !

!FilePathBar methodsFor: 'events'!
mouseDown: anEvent
	| i |
	anEvent button = 1 ifFalse: [^false].
	i := self segmentIndexAt: (self localEventPosition: anEvent).
	(i > 0 and: [onClick notNil]) ifTrue: [onClick value: ((self shownSegments at: i) at: 2)].
	^true
!
mouseMove: anEvent
	| i |
	i := self segmentIndexAt: (self localEventPosition: anEvent).
	i = 0 ifTrue: [i := nil].
	i = hover ifFalse: [hover := i. self invalidate].
	^true
!
mouseLeave: anEvent
	hover isNil ifFalse: [hover := nil. self invalidate].
	^false
!
cursorAt: aPoint
	^(self segmentIndexAt: aPoint) > 0 ifTrue: [#hand] ifFalse: [#arrow]
! !

!FilePathBar methodsFor: 'remote control'!
remoteRole
	^#path
!
remoteLabel
	| labels |
	labels := self labels.
	^String new: 80 streamContents: [:s |
		labels doWithIndex: [:each :i |
			s nextPutAll: each.
			(i < labels size and: [each ~= '/']) ifTrue: [s nextPutAll: ' / ']]]
!
remoteState
	^summary isNil ifTrue: [#()] ifFalse: [Array with: 'summary=', (self remoteQuote: summary)]
!
remoteChildren
	| list |
	list := self shownSegments.
	^(1 to: list size) collect: [:i | | part |
		part := WidgetPart of: self role: #button label: (list at: i) first.
		(list at: i) first = '…' ifTrue: [part name: 'more'].
		i = list size ifTrue: [part state: #(#current)].
		part rect: ((list at: i) at: 3).
		part]
! !
