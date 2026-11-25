ToolsTestCase subclass: #TenureTestTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

TenureTestTest comment: 'I test the Tenure Test window: a Run samples old space under the VM''s TENURE_AGE and draws a lane; two runs fill its two lanes, a third pushes out the oldest.'!

!TenureTestTest methodsFor: 'tests'!
testARunFillsALane
	"The lane is headed with the tenure age at the run's start: the adaptive age may change while it allocates, so it is read just before and after the run starts."
	| window tool run before after |
	window := TenureTest open.
	tool := window content.
	[window sync: [
		before := Smalltalk vm statistics tenureAge.
		tool run.
		after := Smalltalk vm statistics tenureAge].
	 self assert: (self waitFor: [window sync: [tool runs first points size > 2]] timeout: 30000).
	 run := tool runs first.
	 self assert: (run age = before or: [run age = after]) description: [run age printString, ', the VM''s tenure age ', before printString, ' then ', after printString].
	 self assert: run summary notEmpty.
	 window sync: [tool chart invalidate]]
		ensure: [window sync: [tool windowClosed]]
!
testVMReportsItsTenureAge
	self assert: Smalltalk vm statistics tenureAge >= 0
! !
