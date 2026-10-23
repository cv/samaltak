Widget subclass: #ProfilerHeader
	instanceVariableNames: 'title crumbs note rightText legend otherLabel rightWidget onCrumb crumbRects'
	classVariableNames: ''
	package: 'Tools'!

ProfilerHeader comment: 'I am a pane header of the Profiler window (like PaneHeader: tracked capitals, a rule below) that can also show a breadcrumb trail (clickable; onCrumb: receives the index), an italic note after it, the frame timeline legend, and right-aligned muted text or a widget (rightWidget:).'!

!ProfilerHeader methodsFor: 'initialization'!
initialize
	super initialize.
	crumbs := #().
	self fixed: (self theme metric: #paneHeaderHeight)
! !

!ProfilerHeader methodsFor: 'accessing'!
title
	^title ifNil: ['']
!
title: aString
	title := aString.
	self invalidate
!
crumbs
	^crumbs
!
crumbs: anArrayOfStrings
	crumbs = anArrayOfStrings ifTrue: [^self].
	crumbs := anArrayOfStrings.
	self invalidate
!
note: aString
	note = aString ifTrue: [^self].
	note := aString.
	self invalidate
!
rightText
	^rightText isBlock ifTrue: [rightText value asString] ifFalse: [rightText ifNil: ['']]
!
rightText: aStringOrBlock
	rightText = aStringOrBlock ifTrue: [^self].
	rightText := aStringOrBlock.
	self invalidate
!
legend: aBoolean
	legend := aBoolean.
	self invalidate
!
otherLabel: aString
	"The legend's name for the grey segments (system, or others when one Process is selected)."
	otherLabel = aString ifTrue: [^self].
	otherLabel := aString.
	self invalidate
!
rightWidget: aWidget
	rightWidget isNil ifFalse: [self removeChild: rightWidget].
	rightWidget := aWidget.
	aWidget isNil ifFalse: [self addChild: aWidget]
!
onCrumb: aBlock
	onCrumb := aBlock
! !

!ProfilerHeader methodsFor: 'layout'!
layout
	| w |
	rightWidget isNil ifTrue: [^self].
	w := rightWidget preferredExtent x.
	rightWidget bounds: ((self width - (self theme metric: #paneHeaderPaddingX) - w) @ 2 extent: w @ (self height - 4))
! !

!ProfilerHeader methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| pad x limit right rw small italic muted ink sep |
	rightText isBlock ifTrue: [aCanvas noteVolatile].
	pad := self theme metric: #paneHeaderPaddingX.
	ink := self theme ink.
	muted := self theme muted.
	small := self theme font: #small.
	italic := self theme font: #smallItalic.
	aCanvas fillRect: (0 @ 0 corner: self width @ (self height - 1)) color: self theme paper.
	aCanvas fillRect: (0 @ (self height - 1) corner: self width @ self height) color: self theme rule.
	limit := self width - pad.
	rightWidget isNil
		ifTrue: [
			right := self rightText.
			right isEmpty ifFalse: [
				rw := italic widthOf: right.
				aCanvas drawString: right in: ((limit - rw) @ 0 corner: limit @ (self height - 1)) font: italic color: muted align: #left.
				limit := limit - rw - 10]]
		ifFalse: [limit := rightWidget bounds left - 10].
	x := pad.
	aCanvas drawString: self title in: (x @ 0 corner: limit @ (self height - 1)) font: (self theme font: #header) color: ink align: #left.
	x := x + ((self theme font: #header) widthOf: self title) + 10.
	crumbRects := OrderedCollection new.
	sep := '›'.
	aCanvas clip: (0 @ 0 corner: (limit max: 0) @ self height) during: [
		crumbs doWithIndex: [:c :i | | f w |
			i > 1 ifTrue: [
				aCanvas drawString: sep in: (x @ 0 corner: (x + 10) @ (self height - 1)) font: small color: muted align: #center.
				x := x + 10].
			f := i = crumbs size ifTrue: [small] ifFalse: [italic].
			w := f widthOf: c.
			aCanvas drawString: c in: (x @ 0 corner: (x + w) @ (self height - 1)) font: f color: ink align: #left.
			crumbRects add: (x @ 0 corner: (x + w) @ self height).
			x := x + w + 2].
		note isNil ifFalse: [
			x := x + 8.
			aCanvas drawString: note in: (x @ 0 corner: limit @ (self height - 1)) font: italic color: muted align: #left].
		legend == true ifTrue: [self drawLegendAt: x on: aCanvas]]
!
drawLegendAt: startX on: aCanvas
	| x font ink y item |
	x := startX.
	font := self theme font: #smallItalic.
	ink := self theme ink.
	y := (self height - 9) / 2.
	item := [:label :swatchWidth :drawBlock |
		drawBlock value: (x @ y extent: swatchWidth @ 9).
		x := x + swatchWidth + 4.
		aCanvas drawString: label in: (x @ 0 corner: (x + (font widthOf: label)) @ (self height - 1)) font: font color: ink align: #left.
		x := x + (font widthOf: label) + 10].
	item value: 'Processes' value: 18 value: [:r |
		aCanvas fillRect: (r origin extent: 6 @ 9) color: (ProfilerTimeline processShade: 1).
		aCanvas fillRect: ((r left + 6) @ r top extent: 6 @ 9) color: (ProfilerTimeline processShade: 2).
		aCanvas fillRect: ((r left + 12) @ r top extent: 6 @ 9) color: (ProfilerTimeline processShade: 3)].
	item value: (otherLabel ifNil: ['system']) value: 9 value: [:r | aCanvas fillRect: r color: ProfilerTimeline otherColor].
	item value: 'draw' value: 9 value: [:r | aCanvas fillRect: r color: ProfilerTimeline drawColor].
	item value: 'raster' value: 9 value: [:r | aCanvas fillRect: r color: ProfilerTimeline rasterColor].
	item value: 'GPU' value: 9 value: [:r |
		aCanvas fillRect: r color: self theme paper.
		aCanvas pattern: #diagonalStripes in: r color: ink.
		aCanvas strokeRect: r color: ink width: 1].
	item value: 'GC' value: 3 value: [:r | aCanvas fillRect: r color: ink].
	item value: '16.7 ms' value: 14 value: [:r |
		0 to: 12 by: 4 do: [:dx | aCanvas fillRect: ((r left + dx) @ (r top + 4) extent: 2 @ 1.5) color: ink]]
! !

!ProfilerHeader methodsFor: 'events'!
mouseDown: anEvent
	| p |
	anEvent button = 1 ifFalse: [^false].
	(onCrumb isNil or: [crumbRects isNil]) ifTrue: [^false].
	p := self localEventPosition: anEvent.
	crumbRects doWithIndex: [:r :i | (r containsPoint: p) ifTrue: [onCrumb value: i. ^true]].
	^false
!
cursorAt: aPoint
	crumbRects isNil ifFalse: [
		crumbRects doWithIndex: [:r :i | ((r containsPoint: aPoint) and: [i < crumbs size]) ifTrue: [^#hand]]].
	^#arrow
! !

!ProfilerHeader methodsFor: 'remote control'!
remoteRole
	^#header
!
remoteLabel
	^self title
!
remoteName
	^name ifNil: ['header-', self title]
!
remoteState
	| r |
	r := self rightText.
	^(r isEmpty or: [rightWidget notNil]) ifTrue: [#()] ifFalse: [Array with: 'right=', (self remoteQuote: r)]
!
remoteChildren
	| parts |
	parts := OrderedCollection new.
	crumbs doWithIndex: [:c :i |
		parts add: (WidgetPart of: self role: #crumb label: c
			state: (i = crumbs size ifTrue: [#(#current)] ifFalse: [#()])
			rect: (crumbRects isNil ifTrue: [nil] ifFalse: [crumbRects at: i ifAbsent: [nil]]))].
	rightWidget isNil ifFalse: [parts add: rightWidget].
	^parts asArray
! !
