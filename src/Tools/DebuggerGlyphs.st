Object subclass: #DebuggerGlyphs
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

DebuggerGlyphs comment: 'I draw the debugging tools'' small vector glyphs with Canvas lines (antialiased): the reason icons of the Debugger and Notifier headers (#break: a dot, #halt: an octagon, #watch: an eye, #error: a warning triangle, #interrupt: pause bars) on a 22-point tile, and the breakpoint marks of the stack and Breakpoints lists (#break #once #log #condition #object #watch, filled or as a grey ring when disabled).'!

!DebuggerGlyphs class methodsFor: 'icons'!
drawIcon: aSymbol in: aRectangle on: aCanvas
	"A reason tile: ultramarine for breakpoints, halts and watchpoints, a black frame for errors and interrupts."
	| theme accent fg c |
	theme := Theme current.
	accent := #(#break #halt #watch) includes: aSymbol.
	accent
		ifTrue: [aCanvas fillRect: aRectangle color: theme ultramarine. fg := theme paper]
		ifFalse: [
			aCanvas fillRect: aRectangle color: theme paper.
			aCanvas strokeRect: aRectangle color: theme ink width: 1.
			fg := theme ink].
	c := aRectangle center.
	aSymbol == #break ifTrue: [^self disc: c radius: 4.2 color: fg on: aCanvas].
	aSymbol == #halt ifTrue: [
		self polygon: (self octagonAt: c radius: 6) color: fg width: 1.4 on: aCanvas.
		^aCanvas fillRect: ((c x - 2.8) @ (c y - 0.75) extent: 5.6 @ 1.5) color: fg].
	aSymbol == #watch ifTrue: [
		self eyeAt: c width: 13 height: 7.6 color: fg on: aCanvas.
		^self disc: c radius: 1.9 color: fg on: aCanvas].
	aSymbol == #interrupt ifTrue: [
		aCanvas fillRect: ((c x - 3.5) @ (c y - 4.5) extent: 2.4 @ 9) color: fg.
		^aCanvas fillRect: ((c x + 1.1) @ (c y - 4.5) extent: 2.4 @ 9) color: fg].
	self polygon: (Array with: c x @ (c y - 6.2) with: (c x + 6.6) @ (c y + 5.2) with: (c x - 6.6) @ (c y + 5.21)) color: fg width: 1.4 on: aCanvas.
	aCanvas fillRect: ((c x - 0.7) @ (c y - 2.4) extent: 1.4 @ 4.4) color: fg.
	aCanvas fillRect: ((c x - 0.7) @ (c y + 2.8) extent: 1.4 @ 1.4) color: fg
! !

!DebuggerGlyphs class methodsFor: 'breakpoint marks'!
drawMark: aSymbol enabled: aBoolean at: aPoint inverted: inverted on: aCanvas
	"A 9-point breakpoint mark centered at aPoint."
	| theme on bg |
	theme := Theme current.
	on := inverted ifTrue: [theme paper] ifFalse: [theme ultramarine].
	bg := inverted ifTrue: [theme ink] ifFalse: [theme paper].
	aBoolean ifFalse: [^self ring: aPoint radius: 4 width: 1 color: (inverted ifTrue: [theme paper] ifFalse: [theme color: #ink4]) on: aCanvas].
	aSymbol == #once ifTrue: [
		self ring: aPoint radius: 4 width: 1.4 color: on on: aCanvas.
		^aCanvas clip: (aPoint x - 5 @ (aPoint y - 5) corner: aPoint x @ (aPoint y + 5)) during: [
			self disc: aPoint radius: 4.4 color: on on: aCanvas]].
	aSymbol == #log ifTrue: [
		^self fillPolygon: (Array with: aPoint x @ (aPoint y - 4.2) with: (aPoint x + 4.2) @ aPoint y with: aPoint x @ (aPoint y + 4.2) with: (aPoint x - 4.2) @ aPoint y)
			color: on on: aCanvas].
	aSymbol == #condition ifTrue: [
		self disc: aPoint radius: 4.4 color: on on: aCanvas.
		^self disc: aPoint radius: 1.6 color: bg on: aCanvas].
	aSymbol == #object ifTrue: [
		self ring: aPoint radius: 4 width: 1.4 color: on on: aCanvas.
		^self disc: aPoint radius: 1.9 color: on on: aCanvas].
	aSymbol == #watch ifTrue: [
		^aCanvas strokeRect: (aPoint - (4 @ 4) extent: 8 @ 8) color: on width: 1.5].
	self disc: aPoint radius: 4.4 color: on on: aCanvas
!
markKindOf: aBreakpointOrWatchpoint
	(aBreakpointOrWatchpoint respondsTo: #isWatchpoint) ifTrue: [
		aBreakpointOrWatchpoint isWatchpoint ifTrue: [^#watch]].
	aBreakpointOrWatchpoint isObjectBreakpoint ifTrue: [^#object].
	^aBreakpointOrWatchpoint mode == #break ifTrue: [#break] ifFalse: [aBreakpointOrWatchpoint mode]
! !

!DebuggerGlyphs class methodsFor: 'shapes'!
disc: aPoint radius: r color: aColor on: aCanvas
	"A filled circle: a ring of segments whose width is the radius."
	self ring: aPoint radius: r / 2 width: r + 0.15 color: aColor on: aCanvas
!
ring: aPoint radius: r width: w color: aColor on: aCanvas
	| n pts |
	n := 20.
	pts := (0 to: n - 1) collect: [:i | | a |
		a := i * 2 * Float pi / n + 0.13.
		(aPoint x + (r * a cos)) @ (aPoint y + (r * a sin))].
	self polygon: pts color: aColor width: w on: aCanvas
!
polygon: points color: aColor width: w on: aCanvas
	1 to: points size do: [:i |
		aCanvas line: (points at: i) to: (points at: i \\ points size + 1) color: aColor width: w]
!
fillPolygon: points color: aColor on: aCanvas
	"A small convex polygon without axis-aligned edges, filled by outlines shrinking towards its center."
	| c steps |
	c := (points inject: 0 @ 0 into: [:sum :p | sum + p]) / points size.
	steps := 4.
	1 to: steps do: [:k | | f |
		f := k / steps.
		self polygon: (points collect: [:p | c + ((p - c) * f)]) color: aColor width: 1.6 on: aCanvas]
!
octagonAt: c radius: r
	^(0 to: 7) collect: [:i | | a |
		a := (i * 2 + 1) * Float pi / 8 + 0.001.
		(c x + (r * a cos)) @ (c y + (r * a sin))]
!
eyeAt: c width: w height: h color: aColor on: aCanvas
	"An almond: two arcs meeting at the corners."
	| n top bottom |
	n := 10.
	top := (0 to: n) collect: [:i | | t |
		t := i / n.
		(c x - (w / 2) + (w * t)) @ (c y - (h / 2 * (t * Float pi) sin))].
	bottom := (0 to: n) collect: [:i | | t |
		t := i / n.
		(c x - (w / 2) + (w * t)) @ (c y + (h / 2 * (t * Float pi) sin))].
	1 to: n do: [:i |
		aCanvas line: (top at: i) to: (top at: i + 1) color: aColor width: 1.4.
		aCanvas line: (bottom at: i) to: (bottom at: i + 1) color: aColor width: 1.4]
! !
