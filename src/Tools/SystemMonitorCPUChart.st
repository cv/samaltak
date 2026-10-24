SystemMonitorChart subclass: #SystemMonitorCPUChart
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

SystemMonitorCPUChart comment: 'I am the System Monitor''s CPU chart: the share of the VM''s time each Process used, stacked: the named Processes (SystemMonitorData>>named) in ultramarine shades by slot, the others grey, and above them, up to 100%, idle in halftone. The black line is the VM''s total (all but idle).'!

!SystemMonitorCPUChart methodsFor: 'painting'!
rescale: always
	yMax = 100 ifTrue: [^false].
	yMax := 100.
	^true
!
paintKey
	^self data named copy
!
paintColumn: x index: k from: t0 to: t1
	| named shares other weight h y row shades s0 |
	named := self data named.
	shares := Array new: named size withAll: 0.
	other := 0.
	weight := 0.
	self data from: t0 to: t1 do: [:s :o | | f |
		f := o asFloat / (s interval max: 1).
		weight := weight + o.
		s processesDo: [:p :us | | slot |
			slot := named indexOf: p.
			slot > 0
				ifTrue: [shares at: slot put: (shares at: slot) + (us * f)]
				ifFalse: [other := other + (us * f)]].
		other := other + (s unaccounted * f)].
	h := form height.
	weight = 0 ifTrue: [self paintIdle: x to: h index: k. ^tops at: x + 1 put: nil].
	shades := colors at: #shades.
	y := 0.
	row := h.
	1 to: shares size do: [:i | | next |
		y := y + (shares at: i).
		next := self rowOf: y * 100.0 / weight.
		self fill: x from: next to: row pixel: (shades at: i).
		row := next].
	y := y + other.
	self fill: x from: (self rowOf: y * 100.0 / weight) to: row pixel: (colors at: #other).
	row := self rowOf: y * 100.0 / weight.
	self paintIdle: x to: row index: k.
	s0 := scale rounded max: 1.
	row < (h - s0) ifTrue: [self paintLine: x top: row pixel: (colors at: #ink)] ifFalse: [tops at: x + 1 put: nil]
!
paintIdle: x to: r1 index: k
	"Halftone: a 1-point dot in every 2-point cell, rows 0 .. r1 of column x."
	| s0 dot |
	self paintBackground: x to: r1 index: k.
	s0 := scale rounded max: 1.
	k \\ (2 * s0) < s0 ifFalse: [^self].
	dot := colors at: #idle.
	0 to: r1 - 1 by: 2 * s0 do: [:r | self fill: x from: r to: (r + s0 min: r1) pixel: dot]
!
colors
	| d |
	d := super colors.
	d at: #shades put: (#(#l1 #l2 #l3 #l4) collect: [:each | self pixel: each]).
	d at: #other put: (self pixel: #ink4).
	d at: #idle put: (self pixel: #hair).
	^d
! !

!SystemMonitorCPUChart methodsFor: 'drawing'!
drawLabelsOn: aCanvas
	self drawGridLabelsOn: aCanvas format: [:v | v rounded printString, '%']
! !

!SystemMonitorCPUChart methodsFor: 'hover'!
tipLinesFor: aSample
	^monitor cpuTipLinesFor: aSample
! !

!SystemMonitorCPUChart methodsFor: 'remote control'!
remoteLabel
	^'CPU by Process (%)'
!
remoteStateFor: aSample
	^Array
		with: 'vm=', (SystemMonitor percent: aSample vmShare * 100)
		with: 'idle=', (SystemMonitor percent: aSample idle * 100.0 / (aSample interval max: 1))
!
remoteValue: aNumber
	^aNumber printString, '%'
! !
