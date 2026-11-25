Widget subclass: #CuOptRouteMap
	instanceVariableNames: 'tool dragging dragMoved stale'
	classVariableNames: ''
	package: 'Tools-CUDA'!

CuOptRouteMap comment: 'I am the cuOpt window''s map: its CuOptRouting drawn in the unit square, the depot a black square, the stops small numbered squares, each vehicle''s route a line in its color (from the depot round its stops and back). A click on the map adds a stop, a drag moves a stop or the depot, a shift-click (or a right click) on a stop removes it; when one lets go the window solves again. While a stop moves the old routes stay, grey.'!

!CuOptRouteMap methodsFor: 'accessing'!
tool: aCuOptWindow
	tool := aCuOptWindow
!
routing
	^tool routing
!
markStale
	stale := true.
	self invalidate
!
markFresh
	stale := false.
	self invalidate
! !

!CuOptRouteMap methodsFor: 'geometry'!
plot
	"The square the unit square is drawn in, centered, with a margin."
	| side |
	side := (self width min: self height) - 36 max: 10.
	^((self width - side) / 2) rounded @ ((self height - side) / 2) rounded extent: side @ side
!
pointOf: aUnitPoint
	| r |
	r := self plot.
	^r origin + (aUnitPoint * r extent)
!
unitOf: aLocalPoint
	| r p |
	r := self plot.
	p := aLocalPoint - r origin / r extent.
	^((p x max: 0) min: 1) @ ((p y max: 0) min: 1)
!
nodeAt: aLocalPoint
	"0 for the depot, i for the i-th stop, nil for none (within 8 points)."
	| best bestD |
	best := nil.
	bestD := 8.
	0 to: self routing stops size do: [:i | | d |
		d := (self pointOf: (self routing nodeAt: i)) dist: aLocalPoint.
		d <= bestD ifTrue: [best := i. bestD := d]].
	^best
!
colorOfRoute: k
	^self theme color: (#(#ink #ultramarine #l2 #l3 #ink3 #l1) at: k - 1 \\ 6 + 1)
! !

!CuOptRouteMap methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| t r routing small |
	t := self theme.
	routing := self routing.
	aCanvas fillRect: self localBounds color: t paper.
	r := self plot.
	0 to: 10 do: [:i | | x y |
		x := r left + (r width * i / 10).
		y := r top + (r height * i / 10).
		aCanvas fillRect: (x @ r top extent: 1 @ r height) color: (t color: #hair).
		aCanvas fillRect: (r left @ y extent: r width @ 1) color: (t color: #hair)].
	aCanvas strokeRect: r color: (t color: #ink4) width: 1.
	routing routes isNil ifFalse: [
		routing routes doWithIndex: [:route :k | | color prev |
			color := stale == true ifTrue: [t color: #ink4] ifFalse: [self colorOfRoute: k].
			prev := self pointOf: routing depot.
			(route copyWith: 0) do: [:i | | p |
				p := self pointOf: (routing nodeAt: i).
				aCanvas line: prev to: p color: color width: 2.
				prev := p]]].
	small := t font: #small.
	routing stops doWithIndex: [:s :i | | p box k |
		p := self pointOf: s.
		box := (p - (5 @ 5)) extent: 10 @ 10.
		k := self routeIndexOf: i.
		aCanvas fillRect: box color: t paper.
		(k notNil and: [stale ~~ true]) ifTrue: [aCanvas fillRect: (box insetBy: 2) color: (self colorOfRoute: k)].
		aCanvas strokeRect: box color: t ink width: 1.
		aCanvas drawString: i printString at: p + (7 @ -16) font: small color: t ink].
	self drawDepotOn: aCanvas
!
drawDepotOn: aCanvas
	| p box t |
	t := self theme.
	p := self pointOf: self routing depot.
	box := (p - (8 @ 8)) extent: 16 @ 16.
	aCanvas fillRect: (box translateBy: 2 @ 2) color: t ink.
	aCanvas fillRect: box color: t ink.
	aCanvas fillRect: (box insetBy: 4) color: t paper.
	aCanvas drawString: 'depot' at: p + (11 @ -18) font: (t font: #smallItalic) color: t ink
!
routeIndexOf: stopIndex
	self routing routes isNil ifTrue: [^nil].
	self routing routes doWithIndex: [:route :k | (route includes: stopIndex) ifTrue: [^k]].
	^nil
! !

!CuOptRouteMap methodsFor: 'events'!
mouseDown: anEvent
	| p node |
	p := self localEventPosition: anEvent.
	node := self nodeAt: p.
	(node notNil and: [node > 0 and: [anEvent button = 2 or: [anEvent modifiers shift]]]) ifTrue: [
		tool removeStop: node.
		^true].
	anEvent button = 1 ifFalse: [^false].
	node isNil
		ifTrue: [
			(self plot containsPoint: p) ifFalse: [^true].
			tool addStop: (self unitOf: p).
			dragging := nil]
		ifFalse: [dragging := node. dragMoved := false].
	^true
!
mouseMove: anEvent
	dragging isNil ifTrue: [^false].
	dragMoved := true.
	dragging = 0
		ifTrue: [self routing depot: (self unitOf: (self localEventPosition: anEvent))]
		ifFalse: [self routing stopAt: dragging put: (self unitOf: (self localEventPosition: anEvent))].
	stale := true.
	tool routingMoved.
	^true
!
mouseUp: anEvent
	| moved |
	dragging isNil ifTrue: [^true].
	moved := dragMoved.
	dragging := nil.
	moved == true ifTrue: [tool solveRouting].
	^true
!
cursorAt: aPoint
	^(self nodeAt: aPoint) isNil ifTrue: [#crosshair] ifFalse: [#hand]
! !

!CuOptRouteMap methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteLabel
	^'routes'
!
remoteState
	| s |
	s := OrderedCollection new.
	s add: 'stops=' , self routing stops size printString.
	s add: 'vehicles=' , self routing vehicles printString.
	self routing routes isNil ifFalse: [
		s add: 'routes=' , self routing routes size printString.
		s add: 'distance=' , (self routing totalDistance printShowingDecimalPlaces: 3)].
	stale == true ifTrue: [s add: #stale].
	^s asArray
!
remotePointAt: aString
	"The point of a node: 'depot', or a stop's number."
	| i |
	aString = 'depot' ifTrue: [^self localToScreen: (self pointOf: self routing depot)].
	i := [aString asNumber] on: Error do: [:e | e return: nil].
	(i isInteger and: [i between: 1 and: self routing stops size]) ifFalse: [^nil].
	^self localToScreen: (self pointOf: (self routing stops at: i))
! !
