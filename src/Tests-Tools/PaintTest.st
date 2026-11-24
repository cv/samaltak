TestCase subclass: #PaintTest
	instanceVariableNames: 'canvas'
	classVariableNames: ''
	package: 'Tests-Tools'!

PaintTest comment: 'I test the PaintCanvas''s tools, undo and the picker, and that Paint''s toolbox and palette drive its canvas.'!

!PaintTest methodsFor: 'private'!
drag: aTool from: p0 to: p1
	canvas tool: aTool; beginAt: p0 primary: true; dragTo: p1; endStroke
! !

!PaintTest methodsFor: 'running'!
setUp
	canvas := PaintCanvas new
! !

!PaintTest methodsFor: 'tests'!
testANewPictureIsWhite
	self assert: canvas form extent equals: 480 @ 320.
	self assert: (canvas form at: 0 @ 0) equals: Color white.
	self assert: (canvas form at: 479 @ 319) equals: Color white
!
testFillStopsAtOutlines
	self drag: #ellipse from: 100 @ 100 to: 200 @ 180.
	canvas foreground: Color red.
	canvas tool: #fill; beginAt: 150 @ 140 primary: true.
	self assert: (canvas form at: 150 @ 140) equals: Color red.
	self assert: (canvas form at: 5 @ 5) equals: Color white
!
testFilledRectangleUsesBothColors
	canvas background: Color blue; filled: true.
	self drag: #rectangle from: 10 @ 10 to: 50 @ 50.
	self assert: (canvas form at: 30 @ 30) equals: Color blue.
	self assert: (canvas form at: 10 @ 30) equals: Color black
!
testLineShowsOnlyItsLastPosition
	canvas tool: #line; beginAt: 0 @ 0 primary: true; dragTo: 100 @ 0; dragTo: 0 @ 100; endStroke.
	self assert: (canvas form at: 0 @ 50) equals: Color black.
	self assert: (canvas form at: 50 @ 0) equals: Color white
!
testPencilDrawsALine
	self drag: #pencil from: 10 @ 10 to: 20 @ 20.
	self assert: (canvas form at: 15 @ 15) equals: Color black.
	self assert: (canvas form at: 15 @ 16) equals: Color white
!
testPickerTakesAColor
	| picked |
	canvas foreground: Color green.
	self drag: #brush from: 70 @ 70 to: 70 @ 70.
	canvas foreground: Color black; onPick: [:c :fg | picked := c].
	canvas tool: #picker; beginAt: 70 @ 70 primary: true.
	self assert: canvas foreground equals: Color green.
	self assert: picked equals: Color green
!
testRightButtonUsesTheBackground
	canvas background: Color red.
	canvas tool: #brush; beginAt: 30 @ 30 primary: false; endStroke.
	self assert: (canvas form at: 30 @ 30) equals: Color red
!
testToolboxAndPaletteDriveTheCanvas
	| paint |
	paint := Paint new.
	(paint widgetNamed: 'Rectangle') click.
	self assert: paint canvas tool equals: #rectangle.
	self assert: (paint widgetNamed: 'Rectangle') isOn.
	self deny: (paint widgetNamed: 'Pencil') isOn.
	paint palette foreground: Color red; changedColors.
	self assert: paint canvas foreground equals: Color red
!
testStatusBarNamesTheToolAndThePixel
	| paint status |
	paint := Paint new.
	status := paint widgetNamed: 'status'.
	(paint widgetNamed: 'Fill') click.
	self assert: (status remoteLabel includesSubstring: 'Fill').
	self assert: (status remoteLabel includesSubstring: '480 × 320').
	status position: 12 @ 34.
	self assert: (status remoteLabel includesSubstring: '12, 34')
!
testUndoGoesBackSeveralStrokesAndRedoForward
	self drag: #brush from: 40 @ 40 to: 60 @ 40.
	self drag: #brush from: 40 @ 80 to: 60 @ 80.
	self assert: canvas undo.
	self assert: (canvas form at: 50 @ 80) equals: Color white.
	self assert: (canvas form at: 50 @ 40) equals: Color black.
	self assert: canvas undo.
	self assert: (canvas form at: 50 @ 40) equals: Color white.
	self deny: canvas undo.
	self assert: canvas redo.
	self assert: canvas redo.
	self assert: (canvas form at: 50 @ 80) equals: Color black.
	self deny: canvas redo
!
testANewStrokeForgetsWhatWasUndone
	self drag: #brush from: 40 @ 40 to: 60 @ 40.
	canvas undo.
	self assert: canvas canRedo.
	self drag: #brush from: 40 @ 80 to: 60 @ 80.
	self deny: canvas canRedo.
	self deny: canvas redo
!
testUndoKeepsAtMostTheLimit
	canvas undoLimit + 5 timesRepeat: [self drag: #pencil from: 10 @ 10 to: 20 @ 10].
	self assert: ((1 to: canvas undoLimit + 5) count: [:i | canvas undo]) equals: canvas undoLimit
!
testUndoAndRedoButtonsFollowTheHistory
	| paint |
	paint := Paint new.
	self deny: (paint widgetNamed: 'Undo') isEnabled.
	paint canvas tool: #brush; beginAt: 40 @ 40 primary: true; dragTo: 60 @ 40; endStroke.
	self assert: (paint widgetNamed: 'Undo') isEnabled.
	self deny: (paint widgetNamed: 'Redo') isEnabled.
	(paint widgetNamed: 'Undo') click.
	self deny: (paint widgetNamed: 'Undo') isEnabled.
	self assert: (paint widgetNamed: 'Redo') isEnabled
! !
