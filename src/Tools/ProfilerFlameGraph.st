Widget subclass: #ProfilerFlameGraph
	instanceVariableNames: 'profiler unit root zoomKeys zoomNode entries maxSelf animFrom animT animation offset hover hoverPoint lastLayoutWidth emptyText glideT glide labels shades ink paper ancestorColor halftoneColor sliver lineHeights'
	classVariableNames: ''
	package: 'Tools'!

ProfilerFlameGraph comment: 'I draw a call tree (ProfileNode) as an icicle graph, top-down: the root on top, each node as wide as its share of its parent, 19-point rows, ultramarine shaded by self time (the hotter, the darker), labels clipped with an ellipsis. A click zooms into a node (its ancestors stay on top as full-width italic rows; a click on one of them zooms back out), animated in about 180 ms by interpolating the horizontal mapping; a double click opens the method in a System Browser. Hovering inverts a node and shows a tooltip (name, weight, share, self). unit is #samples (CPU) or #bytes (allocations). My zoom is a path of node keys, so it survives the live refreshes.

Live refreshes give me the same (live) tree again: I lay it out anew (siblings in their stable order, frames from 2 points wide, and once shown down to 1.5), and when frames at least 20 points wide moved by more than 8 points, or new ones at least 30 points wide appeared, they glide from where they were (and new ones fade in) in 120 ms; smaller changes just snap, so a steady profile costs one redraw per refresh.'!

!ProfilerFlameGraph methodsFor: 'initialization'!
initialize
	super initialize.
	zoomKeys := #().
	entries := #().
	offset := 0.
	animT := 1.
	glideT := 1
! !

!ProfilerFlameGraph methodsFor: 'accessing'!
profiler: aProfilerView
	profiler := aProfilerView
!
unit
	^unit ifNil: [#samples]
!
unit: aSymbol
	unit := aSymbol
!
emptyText: aString
	emptyText := aString
!
root
	^root
!
root: aProfileNode
	"Show aProfileNode's tree, keeping the zoom where the path still exists. The same root again (a live tree, refreshed) glides to its new layout."
	| same |
	same := aProfileNode == root.
	root := aProfileNode.
	self relayoutGliding: same.
	self invalidate
!
zoomNode
	^zoomNode
!
zoomKeys
	^zoomKeys
!
zoomPath
	"Answer the nodes from the root to the zoom node."
	^zoomNode isNil ifTrue: [#()] ifFalse: [self pathOf: zoomNode]
!
entries
	"Answer the laid-out frames: Arrays {node. x. width. depth. isAncestor. shown x. shown width} (x and width as fractions of my width; the shown ones are where a glide starts, nil for a new frame)."
	^entries
!
hoverNode
	^hover isNil ifTrue: [nil] ifFalse: [hover first]
!
rowHeight
	^19
!
topMargin
	^6
!
sideMargin
	^8
! !

!ProfilerFlameGraph methodsFor: 'zooming'!
pathOf: aNode
	"Answer the nodes from my root down to aNode."
	| result node |
	result := OrderedCollection new.
	node := aNode.
	[node notNil] whileTrue: [
		result addFirst: node.
		node := node == root ifTrue: [nil] ifFalse: [node parent]].
	^result asArray
!
zoomTo: aNode
	"Zoom into aNode (a node of my tree), animating from where it is now."
	| old e |
	(aNode isNil or: [aNode == zoomNode]) ifTrue: [^self].
	old := zoomNode.
	e := self entryFor: aNode.
	zoomKeys := (self pathOf: aNode) allButFirst collect: [:n | n key].
	(old notNil and: [((self pathOf: old) includes: aNode)])
		ifTrue: [
			self relayout.
			e := self entryFor: old.
			e isNil ifFalse: [self animateFrom: (Array with: (e at: 2) with: (e at: 2) + (e at: 3) with: #out)]]
		ifFalse: [
			self relayout.
			(e notNil and: [(e at: 5) not]) ifTrue: [self animateFrom: (Array with: (e at: 2) with: (e at: 2) + (e at: 3) with: #in)]].
	offset := offset min: self maxOffset.
	entries do: [:e | e at: 8 put: nil].
	profiler isNil ifFalse: [profiler zoomChanged: self].
	self invalidate
!
zoomToDepth: anInteger
	"Zoom out to the zoom path's node at anInteger (0 = the root)."
	| path |
	path := self zoomPath.
	path isEmpty ifTrue: [^self].
	self zoomTo: (path at: (anInteger + 1 min: path size))
!
resetZoom
	root isNil ifFalse: [self zoomTo: root]
!
resetZoomKeys
	"Forget the zoom without animating (the next root: starts at the top)."
	zoomKeys := #().
	offset := 0
!
animateFrom: anArray
	animation isNil ifFalse: [animation stop].
	glideT := 1.
	animFrom := anArray.
	animT := 0.
	animation := self tweenFrom: 0 to: 1 duration: 180 do: [:t |
		animT := t.
		t >= 1 ifTrue: [animFrom := nil. animation := nil].
		self invalidate]
!
isAnimating
	^animFrom notNil
!
isGliding
	^glideT notNil and: [glideT < 1]
! !

!ProfilerFlameGraph methodsFor: 'layout'!
layout
	self width = lastLayoutWidth ifFalse: [self relayout]
!
plotWidth
	^self width - (2 * self sideMargin) max: 1
!
relayout
	self relayoutGliding: false
!
relayoutGliding: aBoolean
	"Lay my tree out again; with aBoolean (a live refresh) let frames that moved glide from where they are shown now."
	| node list keys old path |
	lastLayoutWidth := self width.
	old := IdentityDictionary new: entries size * 2 + 16.
	entries do: [:e | old at: (e at: 1) put: e].
	root isNil ifTrue: [zoomNode := nil. entries := #(). ^self].
	node := root.
	keys := OrderedCollection new.
	zoomKeys do: [:k | | child |
		child := node childAtKey: k.
		child isNil ifFalse: [node := child. keys add: k]].
	zoomKeys := keys asArray.
	zoomNode := node.
	list := OrderedCollection new.
	path := self pathOf: node.
	path allButLast doWithIndex: [:anc :i | list add: {anc. 0. 1. i - 1. true. 0. 1. nil}].
	maxSelf := 0.
	self lay: node x: 0.0 width: 1.0 depth: path size - 1 into: list shown: old plotWidth: self plotWidth.
	entries := list asArray.
	(aBoolean and: [animFrom isNil])
		ifTrue: [self glideFrom: old]
		ifFalse: [
			glide isNil ifFalse: [glide stop. glide := nil].
			glideT := 1].
	self refreshHover
!
lay: aNode x: x width: w depth: d into: list shown: aDictionary plotWidth: px
	| cx |
	list add: {aNode. x. w. d. false. nil. nil. nil}.
	maxSelf := maxSelf max: aNode selfWeight.
	cx := x.
	aNode weight = 0 ifTrue: [^self].
	aNode stableChildren do: [:k | | kw kpx |
		kw := w * k weight asFloat / aNode weight.
		kpx := kw * px.
		kpx < 1.5 ifTrue: [^self].
		(kpx >= 2 or: [aDictionary includesKey: k]) ifTrue: [
			self lay: k x: cx width: kw depth: d + 1 into: list shown: aDictionary plotWidth: px].
		cx := cx + kw]
!
glideFrom: oldEntries
	"Frames that were shown start where they were shown (6: x, 7: width), new ones (nil) fade in; glide if a wide frame moved visibly or appeared."
	| px visible |
	px := self plotWidth.
	visible := false.
	"Only frames at least 20 points wide decide."
	entries do: [:e | | o ox ow |
		(visible not and: [(e at: 5) not and: [(e at: 3) * px >= 20]]) ifTrue: [
			o := oldEntries at: (e at: 1) ifAbsent: [nil].
			o isNil
				ifTrue: [(e at: 3) * px >= 30 ifTrue: [visible := true]]
				ifFalse: [
					ox := self shownX: o.
					ow := self shownWidth: o.
					(((ox - (e at: 2)) abs * px) > 8 or: [((ow - (e at: 3)) abs * px) > 8])
						ifTrue: [visible := true]]]].
	visible ifFalse: [
		glide isNil ifFalse: [glide stop. glide := nil].
		^glideT := 1].
	entries do: [:e | | o |
		(e at: 5) ifFalse: [
			o := oldEntries at: (e at: 1) ifAbsent: [nil].
			o isNil ifFalse: [e at: 6 put: (self shownX: o); at: 7 put: (self shownWidth: o)]]].
	glide isNil ifFalse: [glide stop].
	glideT := 0.
	glide := self tweenFrom: 0 to: 1 duration: 120 do: [:t |
		glideT := t.
		t >= 1 ifTrue: [glide := nil].
		self invalidate]
!
shownX: anEntry
	"The entry's x as drawn now (fraction of the plot width)."
	(glideT isNil or: [glideT >= 1 or: [(anEntry at: 6) isNil]]) ifTrue: [^anEntry at: 2].
	^(anEntry at: 6) + ((anEntry at: 2) - (anEntry at: 6) * glideT)
!
shownWidth: anEntry
	(glideT isNil or: [glideT >= 1 or: [(anEntry at: 7) isNil]]) ifTrue: [^anEntry at: 3].
	^(anEntry at: 7) + ((anEntry at: 3) - (anEntry at: 7) * glideT)
!
entryFor: aNode
	^entries detect: [:e | e first == aNode] ifNone: [nil]
!
contentHeight
	| d |
	d := 0.
	entries do: [:e | d := d max: (e at: 4)].
	^entries isEmpty ifTrue: [0] ifFalse: [(d + 1) * self rowHeight + self topMargin + 6]
!
maxOffset
	^(self contentHeight - self height) max: 0
!
displayRectOf: anEntry
	"Answer the entry's rectangle in my coordinates, at the current animation step (kept in the entry while nothing animates)."
	| x w a b x0 w0 px t r static |
	static := animFrom isNil and: [glideT isNil or: [glideT >= 1]].
	(static and: [(r := anEntry at: 8) notNil]) ifTrue: [^r].
	x := self shownX: anEntry.
	w := self shownWidth: anEntry.
	(animFrom notNil and: [(anEntry at: 5) not]) ifTrue: [
		a := animFrom first.
		b := animFrom at: 2.
		(animFrom at: 3) == #in
			ifTrue: [x0 := a + (x * (b - a)). w0 := w * (b - a)]
			ifFalse: [x0 := x - a / (b - a). w0 := w / (b - a)].
		t := animT.
		x := x0 + (x - x0 * t).
		w := w0 + (w - w0 * t)].
	px := self plotWidth.
	r := (self sideMargin + (x * px)) @ (self topMargin + ((anEntry at: 4) * self rowHeight) - offset)
		extent: (w * px) @ self rowHeight.
	static ifTrue: [anEntry at: 8 put: r].
	^r
!
entryAt: aPoint
	entries reverseDo: [:e | ((self displayRectOf: e) containsPoint: aPoint) ifTrue: [^e]].
	^nil
! !

!ProfilerFlameGraph methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| font bold advance boldAdvance clip area picked fading px sm tm rh cl cr ct cb |
	paper := self theme paper.
	ink := self theme ink.
	ancestorColor isNil ifTrue: [ancestorColor := Color hex: 16rF2F2F2. halftoneColor := Color black alpha: 0.12].
	aCanvas fillRect: self localBounds color: paper.
	area := self sideMargin @ self topMargin corner: (self width - self sideMargin) @ self height.
	aCanvas fillRect: (area origin extent: area width @ 1) color: ink.
	aCanvas fillRect: (area origin extent: 1 @ area height) color: ink.
	(root isNil or: [root weight = 0]) ifTrue: [
		aCanvas drawString: (emptyText ifNil: ['No samples for this Process in the selected range.'])
			at: (self sideMargin + 6) @ (self topMargin + 6) font: (self theme font: #smallItalic) color: self theme muted.
		^self].
	font := self theme font: #mono11.
	bold := self theme font: #code12Bold.
	advance := font widthOf: 'M'.
	boldAdvance := bold widthOf: 'M'.
	picked := profiler isNil ifTrue: [nil] ifFalse: [profiler picked].
	clip := aCanvas clipRect.
	cl := clip left. cr := clip right. ct := clip top. cb := clip bottom.
	fading := self isGliding.
	px := self plotWidth.
	sm := self sideMargin.
	tm := self topMargin.
	rh := self rowHeight.
	"Entries are drawn from numbers (no Rectangle per entry: a full flame graph has hundreds); a narrow frame with a narrow only child of the same color (a deep stack) becomes one quad."
	sliver := nil.
	aCanvas clip: area during: [
		entries do: [:e | | x w x0 x1 y0 |
			animFrom isNil
				ifTrue: [
					fading
						ifTrue: [x := self shownX: e. w := self shownWidth: e]
						ifFalse: [x := e at: 2. w := e at: 3].
					x0 := sm + (x * px).
					x1 := x0 + (w * px).
					y0 := tm + ((e at: 4) * rh) - offset]
				ifFalse: [ | r |
					r := self displayRectOf: e.
					x0 := r left. x1 := r right. y0 := r top].
			(x1 - x0 > 0.3 and: [x1 > cl and: [x0 < cr and: [y0 + rh > ct and: [y0 < cb]]]]) ifTrue: [
				(fading and: [(e at: 5) not and: [(e at: 6) isNil]])
					ifTrue: [aCanvas alpha: glideT during: [
						self drawEntry: e left: x0 right: x1 top: y0 bottom: y0 + rh font: font advance: advance bold: bold boldAdvance: boldAdvance picked: picked on: aCanvas]]
					ifFalse: [self drawEntry: e left: x0 right: x1 top: y0 bottom: y0 + rh font: font advance: advance bold: bold boldAdvance: boldAdvance picked: picked on: aCanvas]]].
		self flushSliverOn: aCanvas]
!
flushSliverOn: aCanvas
	"Draw the pending narrow frames {left. right. top. bottom. color. depth}."
	sliver isNil ifTrue: [^self].
	aCanvas fillLeft: (sliver at: 1) top: (sliver at: 3) right: (sliver at: 2) bottom: (sliver at: 4) color: (sliver at: 5).
	sliver := nil
!
lineHeightOf: aFont
	"Font>>lineHeight, remembered (it computes with Fractions)."
	(lineHeights isNil or: [lineHeights first ~~ aFont]) ifFalse: [^lineHeights last].
	lineHeights := Array with: aFont with: aFont lineHeight.
	^lineHeights last
!
shadeAt: h
	"The ultramarine shade for h (0..1), from 64 precomputed ones."
	| i |
	shades isNil ifTrue: [
		shades := (0 to: 63) collect: [:k | self theme paper mixed: k / 63.0 with: self theme ultramarine]].
	i := (h * 63) rounded.
	^shades at: ((i max: 0) min: 63) + 1
!
labelOf: aNode width: points font: aFont advance: charWidth
	"aNode's name fitted to points (cached while the number of characters that fit stays the same)."
	| n cached label |
	n := (points / charWidth) floor.
	labels isNil ifTrue: [labels := IdentityDictionary new].
	cached := labels at: aNode ifAbsent: [nil].
	(cached notNil and: [cached first = n]) ifTrue: [^cached last].
	label := ProfilerFormat fit: aNode name advance: charWidth width: points.
	labels size > 4000 ifTrue: [labels := IdentityDictionary new].
	labels at: aNode put: (Array with: n with: label).
	^label
!
drawEntry: e left: x0 right: x1 top: y0 bottom: y1 font: font advance: advance bold: bold boldAdvance: boldAdvance picked: picked on: aCanvas
	| node h bg fg isHover label f adv inner |
	node := e at: 1.
	isHover := hover notNil and: [(hover at: 1) == node].
	(e at: 5)
		ifTrue: [
			bg := ancestorColor.
			fg := ink]
		ifFalse: [
			h := 0.05 + (0.88 * (maxSelf = 0 ifTrue: [0] ifFalse: [(node selfWeight asFloat / maxSelf) sqrt])).
			bg := self shadeAt: h.
			fg := h > 0.52 ifTrue: [paper] ifFalse: [ink]].
	isHover ifTrue: [bg := ink. fg := paper].
	x1 - x0 < 3 ifTrue: [
		(sliver notNil and: [(sliver at: 6) + 1 = (e at: 4) and: [(sliver at: 5) == bg
			and: [((sliver at: 1) - x0) abs < 0.01 and: [((sliver at: 2) - x1) abs < 0.01 and: [((sliver at: 4) - y0) abs < 0.01]]]]])
			ifTrue: [sliver at: 4 put: y1; at: 6 put: (e at: 4)]
			ifFalse: [
				self flushSliverOn: aCanvas.
				sliver := Array new: 6.
				sliver at: 1 put: x0; at: 2 put: x1; at: 3 put: y0; at: 4 put: y1; at: 5 put: bg; at: 6 put: (e at: 4)].
		^self].
	self flushSliverOn: aCanvas.
	"The right and bottom edges in ink, the rest in the shade."
	aCanvas fillLeft: x0 top: y0 right: x1 bottom: y1 color: ink.
	aCanvas fillLeft: x0 top: y0 right: x1 - 1 bottom: y1 - 1 color: bg.
	((e at: 5) and: [isHover not]) ifTrue: [aCanvas pattern: #halftone in: (x0 @ y0 corner: x1 @ y1) color: halftoneColor].
	(picked notNil and: [node key == picked]) ifTrue: [
		inner := x0 @ y0 corner: (x1 - 1) @ (y1 - 1).
		aCanvas strokeRect: inner color: (isHover ifTrue: [paper] ifFalse: [ink]) width: 2.
		isHover ifFalse: [aCanvas strokeRect: (inner insetBy: 2) color: paper width: 1]].
	x1 - x0 < 30 ifTrue: [^self].
	f := node isProcessNode ifTrue: [bold] ifFalse: [font].
	adv := node isProcessNode ifTrue: [boldAdvance] ifFalse: [advance].
	label := self labelOf: node width: x1 - x0 - 11 font: f advance: adv.
	label isEmpty ifTrue: [^self].
	"Vertically centered like drawString:in:font:color:align:, without measuring (the label fits)."
	aCanvas drawString: label at: (x0 + 5) @ (y0 + (y1 - 1 - y0 - (self lineHeightOf: f) / 2)) font: f color: fg
! !

!ProfilerFlameGraph methodsFor: 'events'!
mouseDown: anEvent
	| e |
	anEvent button = 1 ifFalse: [^false].
	e := self entryAt: (self localEventPosition: anEvent).
	e isNil ifTrue: [^true].
	(anEvent clickCount >= 2 or: [anEvent modifiers commandKey])
		ifTrue: [
			profiler isNil ifFalse: [profiler browseNode: e first].
			^true].
	profiler isNil ifFalse: [profiler pickNode: e first].
	self zoomTo: e first.
	^true
!
mouseUp: anEvent
	^true
!
clickItemAt: aPoint
	"The node's path of keys (it survives refreshes)."
	^(self entryAt: aPoint) ifNotNil: [:e | ((self pathOf: e first) collect: [:each | each key]) asArray]
!
mouseMove: anEvent
	self hoverAt: (self localEventPosition: anEvent).
	^true
!
mouseLeave: anEvent
	hoverPoint := nil.
	hover isNil ifFalse: [hover := nil. self invalidate].
	profiler isNil ifFalse: [profiler hideTip].
	^false
!
hoverAt: aPoint
	| e |
	hoverPoint := aPoint.
	e := self entryAt: aPoint.
	(e isNil ifTrue: [hover notNil] ifFalse: [hover isNil or: [hover first ~~ e first]]) ifTrue: [
		hover := e.
		self invalidate].
	profiler isNil ifTrue: [^self].
	e isNil
		ifTrue: [profiler hideTip]
		ifFalse: [profiler showTip: (self tipLinesFor: e first) near: (self pointInWindow: aPoint)]
!
tipLinesFor: aNode
	| rt what |
	rt := root weight.
	what := self unit == #bytes ifTrue: ['bytes'] ifFalse: ['samples'].
	^Array
		with: aNode name
		with: (ProfilerFormat weight: aNode weight unit: self unit), ProfilerFormat dot,
			(ProfilerFormat percentString: aNode weight of: rt), ' of ', what, ' shown'
		with: 'self ', (ProfilerFormat weight: aNode selfWeight unit: self unit), ProfilerFormat dot,
			(ProfilerFormat percentString: aNode selfWeight of: rt)
!
refreshHover
	"After a relayout: the node under the pointer is a new one; find it and update the tooltip."
	(hover isNil or: [hoverPoint isNil]) ifTrue: [^self].
	hover := nil.
	self hoverAt: hoverPoint
!
wheel: anEvent
	offset := ((offset - (anEvent delta y * 40)) max: 0) min: self maxOffset.
	entries do: [:e | e at: 8 put: nil].
	self invalidate.
	^true
!
cursorAt: aPoint
	^(self entryAt: aPoint) isNil ifTrue: [#arrow] ifFalse: [#hand]
!
contextMenuAt: aPoint
	| e node m |
	e := self entryAt: aPoint.
	e isNil ifTrue: [^nil].
	node := e first.
	m := Menu new title: node name; yourself.
	(m add: 'browse method' action: [profiler browseNode: node]) enabled: node isMethodNode.
	m add: 'zoom here' action: [self zoomTo: node].
	m add: 'reset zoom' action: [self resetZoom].
	node isProcessNode ifTrue: [m add: 'only this Process' action: [profiler selectFilter: node process]].
	^m
! !

!ProfilerFlameGraph methodsFor: 'remote control'!
remoteRole
	^#'flame-graph'
!
remoteLabel
	root isNil ifTrue: [^nil].
	^root name, ': ', (ProfilerFormat weight: root weight unit: self unit), '; zoomed to ', (zoomNode ifNil: [root]) name
!
remoteState
	^Array with: 'frames=', entries size printString with: 'depth=', (zoomNode isNil ifTrue: [0] ifFalse: [(self pathOf: zoomNode) size - 1]) printString
!
remoteChildren
	| rt px |
	root isNil ifTrue: [^#()].
	rt := root weight.
	px := self plotWidth.
	^(entries select: [:e | (e at: 3) * px >= 1]) collect: [:e | | node part state r |
		node := e first.
		state := OrderedCollection new.
		(e at: 5) ifTrue: [state add: #ancestor].
		node == zoomNode ifTrue: [state add: #zoomed].
		(profiler notNil and: [profiler picked notNil and: [node key == profiler picked]]) ifTrue: [state add: #picked].
		r := self displayRectOf: e.
		part := WidgetPart of: self role: #'flame-frame'
			label: node name, ' ', (ProfilerFormat percentString: node weight of: rt), ' (', (ProfilerFormat weight: node weight unit: self unit), ')'
			state: state asArray
			rect: ((r intersects: self localBounds) ifTrue: [r intersect: self localBounds] ifFalse: [nil]).
		part name: node name.
		part]
! !
