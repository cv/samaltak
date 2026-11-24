Widget subclass: #ToggleGroup
	instanceVariableNames: 'options selection onChange fade previous framed'
	classVariableNames: ''
	package: 'UI-Widgets'!

ToggleGroup comment: 'I am a segmented control (the browser''s instance / ? / class switch): equal segments with 1-point frames sharing borders; the selected one is inverted and bold. A change cross-fades the old and new segment.

	ToggleGroup options: #(''instance'' ''?'' ''class'') selected: 1

options are Strings, or Associations key -> label. onChange: receives the selected key (or label). framed: true adds the .seg bar look: a rule on top and 3 points of padding.'!

!ToggleGroup methodsFor: 'accessing'!
options
	^options ifNil: [#()]
!
options: aCollection
	options := aCollection asArray.
	(selection isNil or: [selection > options size]) ifTrue: [selection := options isEmpty ifTrue: [0] ifFalse: [1]].
	self invalidate
!
labelAt: index
	| o |
	o := self options at: index.
	^o isString ifTrue: [o] ifFalse: [o value asString]
!
keyAt: index
	| o |
	o := self options at: index.
	^o isString ifTrue: [o] ifFalse: [o key]
!
selectionIndex
	^selection ifNil: [0]
!
selection
	^self selectionIndex = 0 ifTrue: [nil] ifFalse: [self keyAt: self selectionIndex]
!
selectionIndex: anInteger
	"Select without notifying."
	| old |
	old := self selectionIndex.
	old = anInteger ifTrue: [^self].
	selection := anInteger.
	previous := old.
	fade := 0.
	self tweenFrom: 0 to: 1 duration: (self theme metric: #fadeMs) do: [:t | fade := t. self invalidate].
	self invalidate
!
selection: aKeyOrLabel
	1 to: self options size do: [:i |
		((self keyAt: i) = aKeyOrLabel or: [(self labelAt: i) = aKeyOrLabel]) ifTrue: [^self selectionIndex: i]]
!
onChange: aBlock
	onChange := aBlock
!
framed
	^framed == true
!
framed: aBoolean
	framed := aBoolean.
	self invalidate
!
choose: index
	"Select as if clicked and notify."
	(index between: 1 and: self options size) ifFalse: [^self].
	index = self selectionIndex ifTrue: [^self].
	self selectionIndex: index.
	onChange isNil ifFalse: [onChange cull: self selection cull: self]
! !

!ToggleGroup methodsFor: 'geometry'!
segmentArea
	| r p |
	r := self localBounds.
	self framed ifTrue: [
		p := self theme metric: #segmentBarPadding.
		r := (r left + p) @ (r top + 1 + p) corner: (r right - p) @ (r bottom - p)].
	^r
!
segmentRects
	"Answer the rectangles of the segments (sharing their 1-point borders)."
	| area n w rects |
	area := self segmentArea.
	n := self options size.
	n = 0 ifTrue: [^#()].
	w := area width / n.
	rects := Array new: n.
	1 to: n do: [:i |
		rects at: i put: ((area left + ((i - 1) * w)) rounded @ area top corner: (i = n ifTrue: [area right] ifFalse: [(area left + (i * w)) rounded + 1]) @ area bottom)].
	^rects
!
segmentAt: aPoint
	self segmentRects doWithIndex: [:r :i | (r containsPoint: aPoint) ifTrue: [^i]].
	^0
!
preferredExtent
	| w |
	w := 0.
	1 to: self options size do: [:i | w := w + ((self theme font: #button) widthOf: (self labelAt: i)) + 20].
	^w ceiling @ ((self theme metric: #segmentHeight) + (self framed ifTrue: [7] ifFalse: [0]))
! !

!ToggleGroup methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| rects ink paper on |
	self theme isBevelled ifTrue: [^self drawTabsOn: aCanvas].
	ink := self theme ink.
	paper := self theme paper.
	on := ink.
	aCanvas fillRect: self localBounds color: paper.
	self framed ifTrue: [aCanvas fillRect: (0 @ 0 extent: self width @ 1) color: self theme rule].
	rects := self segmentRects.
	rects doWithIndex: [:r :i |
		| amount |
		amount := self onAmountAt: i.
		amount > 0 ifTrue: [aCanvas fillRect: r color: (on alpha: amount)].
		aCanvas strokeRect: r color: ink width: 1.
		aCanvas drawString: (self labelAt: i) in: r
			font: (self theme font: (amount > 0.5 ifTrue: [#buttonBold] ifFalse: [#button]))
			color: (ink mixed: amount with: paper) align: #center]
!
onAmountAt: index
	"How inverted segment index is (cross-fade between the previous and the new selection)."
	| f |
	f := fade ifNil: [1].
	index = self selectionIndex ifTrue: [^f].
	index = previous ifTrue: [^1 - f].
	^0
!
drawTabsOn: aCanvas
	"Haiku's tab view: the segments are tabs, the chosen one raised and lighter, the others darker."
	| t edge |
	t := self theme.
	edge := t color: #bevelDark.
	aCanvas fillRect: self localBounds color: t panel.
	self segmentRects doWithIndex: [:r :i |
		| amount top bottom |
		amount := self onAmountAt: i.
		top := (t panel mixed: 0.15 with: edge) mixed: amount with: (t color: #buttonTop).
		bottom := (t panel mixed: 0.1 with: edge) mixed: amount with: t panel.
		t shade: (r insetBy: 1) from: top to: bottom on: aCanvas.
		aCanvas strokeRect: r color: edge width: 1.
		aCanvas fillRect: ((r left + 1) @ (r top + 1) extent: (r width - 2) @ 1) color: ((t color: #bevelLight) alpha: amount * 0.8 + 0.2).
		aCanvas drawString: (self labelAt: i) in: r
			font: (t font: (amount > 0.5 ifTrue: [#buttonBold] ifFalse: [#button]))
			color: t ink align: #center]
! !

!ToggleGroup methodsFor: 'events'!
mouseDown: anEvent
	| i |
	anEvent button = 1 ifFalse: [^false].
	i := self segmentAt: (self localEventPosition: anEvent).
	i = 0 ifFalse: [self choose: i].
	^true
! !

!ToggleGroup methodsFor: 'remote control'!
segmentRole
	^#button
!
remoteRole
	^#group
!
remoteState
	| s |
	s := OrderedCollection new.
	self selection isNil ifFalse: [s add: 'sel=', (self remoteQuote: (self labelAt: self selectionIndex))].
	^s asArray
!
remoteChildren
	| rects |
	rects := self segmentRects.
	^(1 to: self options size) collect: [:i |
		WidgetPart of: self role: self segmentRole label: (self labelAt: i)
			state: (i = self selectionIndex ifTrue: [self selectedStateWords] ifFalse: [#()])
			rect: (rects at: i)]
!
selectedStateWords
	^#(#on)
! !

!ToggleGroup class methodsFor: 'instance creation'!
options: aCollection
	^self new options: aCollection; yourself
!
options: aCollection selected: anInteger
	^self new options: aCollection; selectionIndex: anInteger; yourself
! !
