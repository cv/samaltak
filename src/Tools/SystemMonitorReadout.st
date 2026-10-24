Widget subclass: #SystemMonitorReadout
	instanceVariableNames: 'cells widths'
	classVariableNames: ''
	package: 'Tools'!

SystemMonitorReadout comment: 'I show the System Monitor''s current values in a row of cells: a small label (after a swatch of the chart''s color, if any) above a large value and a muted note. A cell is {key. label. value. note. swatch}; swatch is nil, a theme color name, #halftone, #dashed or #rule. Cells only grow wider, so the row does not jump as values change.'!

!SystemMonitorReadout methodsFor: 'accessing'!
cells
	^cells ifNil: [#()]
!
cells: anArray
	cells = anArray ifTrue: [^self].
	cells := anArray.
	self invalidate
!
cellAt: aKey
	^self cells detect: [:c | c first = aKey] ifNone: [nil]
!
textOf: aCell
	^(aCell at: 2), ' ', (aCell at: 3), ((aCell at: 4) isEmpty ifTrue: [''] ifFalse: [' ', (aCell at: 4)])
! !

!SystemMonitorReadout methodsFor: 'layout'!
layout
	widths := nil
! !

!SystemMonitorReadout methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| theme small value note x labelTop valueTop noteTop |
	theme := self theme.
	small := theme font: #small.
	value := theme font: #readout.
	note := theme font: #smallItalic.
	aCanvas fillRect: self localBounds color: theme paper.
	(widths isNil or: [widths size ~= self cells size]) ifTrue: [widths := Array new: self cells size withAll: 0].
	labelTop := 5.
	valueTop := 21.
	noteTop := valueTop + value baselineOffset - note baselineOffset.
	x := 10.
	self cells doWithIndex: [:cell :i | | sw lx w vw nw label |
		sw := (cell at: 5) isNil ifTrue: [0] ifFalse: [13].
		label := ProfilerFormat fit: (cell at: 2) font: small width: 120.
		vw := value widthOf: (cell at: 3).
		nw := (cell at: 4) isEmpty ifTrue: [0] ifFalse: [(note widthOf: (cell at: 4)) + 5].
		w := (sw + (small widthOf: label)) max: vw + nw.
		widths at: i put: ((widths at: i) max: w).
		w := widths at: i.
		x + w > (self width - 6) ifFalse: [
			sw > 0 ifTrue: [self drawSwatch: (cell at: 5) in: (x @ (labelTop + 4) extent: 9 @ 9) on: aCanvas].
			lx := x + sw.
			aCanvas drawString: label at: lx @ labelTop font: small color: theme muted.
			aCanvas drawString: (cell at: 3) at: x @ valueTop font: value color: theme ink.
			nw > 0 ifTrue: [aCanvas drawString: (cell at: 4) at: (x + vw + 5) @ noteTop font: note color: theme muted]].
		x := x + w + 12]
!
drawSwatch: aSwatch in: r on: aCanvas
	| ink |
	ink := self theme ink.
	aSwatch == #halftone ifTrue: [
		aCanvas fillRect: r color: self theme paper.
		aCanvas pattern: #halftone in: r color: (self theme color: #ink3).
		^aCanvas strokeRect: r color: (self theme color: #ink4) width: 1].
	aSwatch == #dashed ifTrue: [
		^0 to: 8 by: 4 do: [:dx | aCanvas fillRect: ((r left + dx) @ (r top + 4) extent: 2 @ 1.5) color: ink]].
	aSwatch == #rule ifTrue: [^aCanvas fillRect: (r left @ (r top + 3.5) extent: r width @ 2) color: ink].
	aCanvas fillRect: r color: (self theme color: aSwatch)
! !

!SystemMonitorReadout methodsFor: 'remote control'!
remoteRole
	^#readout
!
remoteChildren
	^self cells collect: [:cell |
		(WidgetPart of: self role: #value label: (self textOf: cell) state: #() rect: nil) name: cell first; yourself]
! !
