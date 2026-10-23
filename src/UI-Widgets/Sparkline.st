Widget subclass: #Sparkline
	instanceVariableNames: 'values maxValue style color highlight reference onClick'
	classVariableNames: ''
	package: 'UI-Widgets'!

Sparkline comment: 'I draw a small chart of numbers: #bars (default; e.g. frame times) or #line, scaled to maxValue (default: the largest value), with an optional dotted reference line (e.g. the 16.7 ms frame budget) and one highlighted bar in ultramarine. onClick: receives the index of the clicked bar.'!

!Sparkline methodsFor: 'accessing'!
values
	^values ifNil: [#()]
!
values: aCollection
	values := aCollection asArray.
	self invalidate
!
maxValue: aNumberOrNil
	maxValue := aNumberOrNil.
	self invalidate
!
style: aSymbol
	style := aSymbol.
	self invalidate
!
color: aColorOrSymbol
	color := aColorOrSymbol.
	self invalidate
!
highlight: anIndexOrNil
	highlight := anIndexOrNil.
	self invalidate
!
reference: aNumberOrNil
	reference := aNumberOrNil.
	self invalidate
!
onClick: aBlock
	onClick := aBlock
!
scaleMax
	| m |
	maxValue isNil ifFalse: [^maxValue].
	m := self values inject: 0 into: [:a :b | a max: b].
	reference isNil ifFalse: [m := m max: reference].
	^m = 0 ifTrue: [1] ifFalse: [m]
!
indexAt: aPoint
	| n |
	n := self values size.
	n = 0 ifTrue: [^0].
	^((aPoint x / (self width / n)) floor + 1 max: 1) min: n
! !

!Sparkline methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| n w h max ink y |
	n := self values size.
	h := self height.
	ink := self colorFor: (color ifNil: [#ink]).
	aCanvas fillRect: (0 @ (h - 1) corner: self width @ h) color: (self theme color: #hair).
	n = 0 ifTrue: [^self].
	max := self scaleMax.
	w := self width / n.
	(style ifNil: [#bars]) == #line
		ifTrue: [
			| prev |
			prev := nil.
			values doWithIndex: [:v :i |
				| p |
				p := ((i - 0.5) * w) @ (h - 1 - ((v min: max) / max * (h - 2))).
				prev isNil ifFalse: [aCanvas line: prev to: p color: ink width: 1].
				prev := p]]
		ifFalse: [
			values doWithIndex: [:v :i |
				| bh x |
				bh := ((v min: max) / max * (h - 1)) max: (v > 0 ifTrue: [1] ifFalse: [0]).
				x := (i - 1) * w.
				aCanvas fillRect: (x @ (h - 1 - bh) corner: (x + (w - (w > 3 ifTrue: [1] ifFalse: [0]) max: 0.5)) @ (h - 1))
					color: (i = highlight ifTrue: [self theme ultramarine] ifFalse: [ink])]].
	reference isNil ifFalse: [
		y := h - 1 - ((reference min: max) / max * (h - 1)).
		0 to: self width - 1 by: 3 do: [:x | aCanvas fillRect: (x @ y extent: 1.5 @ 1) color: self theme ultramarine]]
! !

!Sparkline methodsFor: 'events'!
mouseDown: anEvent
	| i |
	onClick isNil ifTrue: [^false].
	i := self indexAt: (self localEventPosition: anEvent).
	i > 0 ifTrue: [onClick cull: i cull: self].
	^true
! !

!Sparkline methodsFor: 'remote control'!
remoteRole
	^#chart
!
remoteState
	| s |
	s := OrderedCollection new.
	s add: 'n=', self values size printString.
	self values isEmpty ifFalse: [s add: 'max=', ((self values inject: 0 into: [:a :b | a max: b]) printShowingDecimalPlaces: 1)].
	highlight isNil ifFalse: [s add: 'sel=', highlight printString].
	^s asArray
! !
