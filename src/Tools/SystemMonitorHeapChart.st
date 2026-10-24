SystemMonitorChart subclass: #SystemMonitorHeapChart
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

SystemMonitorHeapChart comment: 'I am the System Monitor''s heap chart (MB): old space in use (ultramarine edge) with eden''s estimated fill on top, old space''s budget dashed, and a dotted line at each full GC.'!

!SystemMonitorHeapChart methodsFor: 'painting'!
paintColumn: x index: k from: t0 to: t1
	| old eden budget full any h oldRow edenRow budgetRow s0 ink |
	old := 0.
	eden := 0.
	budget := 0.
	full := false.
	any := false.
	self data from: t0 to: t1 do: [:s :o |
		any := true.
		old := old max: s oldUsed.
		eden := s edenFill.
		budget := budget max: s oldBudget.
		(s fullGCs > 0 and: [s time >= t0 and: [s time < t1]]) ifTrue: [full := true]].
	h := form height.
	any ifFalse: [self paintBackground: x to: h index: k. ^tops at: x + 1 put: nil].
	oldRow := self rowOf: old / 1048576.0.
	edenRow := self rowOf: old + eden / 1048576.0.
	budgetRow := self rowOf: budget / 1048576.0.
	self paintBackground: x to: edenRow index: k.
	self fill: x from: edenRow to: oldRow pixel: (colors at: #eden).
	self fill: x from: oldRow to: h pixel: (colors at: #old).
	self paintLine: x top: oldRow pixel: (colors at: #line).
	s0 := scale rounded max: 1.
	ink := colors at: #ink.
	k // s0 \\ 4 < 2 ifTrue: [self fill: x from: budgetRow to: budgetRow + s0 pixel: ink].
	full ifTrue: [0 to: h - 1 by: s0 * 2 do: [:r | self fill: x from: r to: r + s0 pixel: ink]]
!
colors
	| d |
	d := super colors.
	d at: #old put: (self pixel: #l4).
	d at: #eden put: (self pixel: #l5).
	d at: #line put: (self pixel: #ultramarine).
	^d
!
scaleNeedOf: aSample
	^(aSample oldUsed + aSample edenFill max: aSample oldBudget) / 1048576.0
!
minimumScale
	^8
! !

!SystemMonitorHeapChart methodsFor: 'drawing'!
drawLabelsOn: aCanvas
	self drawGridLabelsOn: aCanvas format: [:mb | SystemMonitor megabytes: mb]
! !

!SystemMonitorHeapChart methodsFor: 'hover'!
tipLinesFor: aSample
	^monitor heapTipLinesFor: aSample
! !

!SystemMonitorHeapChart methodsFor: 'remote control'!
remoteLabel
	^'Heap (MB): old space, eden, budget'
!
remoteStateFor: aSample
	^Array
		with: 'old=', (SystemMonitor bytes: aSample oldUsed)
		with: 'budget=', (SystemMonitor bytes: aSample oldBudget)
		with: 'eden=', (SystemMonitor bytes: aSample edenFill)
!
remoteValue: aNumber
	^SystemMonitor megabytes: aNumber
! !
