ToolsTestCase subclass: #TenureTestTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

TenureTestTest comment: 'I test the Tenure Test window: a Run samples old space under the VM''s TENURE_AGE and draws a lane; two runs fill its two lanes, a third pushes out the oldest.'!

!TenureTestTest methodsFor: 'tests'!
testARunFillsALane
	| window tool run |
	window := TenureTest open.
	tool := window content.
	[window sync: [tool run].
	 self assert: (self waitFor: [window sync: [tool runs first points size > 2]] timeout: 10000).
	 run := tool runs first.
	 self assert: run age equals: Smalltalk vm statistics tenureAge.
	 self assert: run summary notEmpty.
	 window sync: [tool chart invalidate]]
		ensure: [window sync: [tool windowClosed]]
!
testVMReportsItsTenureAge
	self assert: Smalltalk vm statistics tenureAge >= 0
! !
