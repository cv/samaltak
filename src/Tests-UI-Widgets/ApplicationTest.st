TestCase subclass: #ApplicationTest
	instanceVariableNames: 'previous app'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

ApplicationTest comment: 'Tests Application on a hidden host window: the window is the content''s preferred size, shows the content, and the hooks run around opening and closing.'!

!ApplicationTest methodsFor: 'running'!
setUp
	previous := World current
!
tearDown
	(app notNil and: [app world notNil and: [app world isRunning]]) ifTrue: [app world stop].
	World current: previous.
	Profiler resume
!
timeLimitMilliseconds
	^30000
! !

!ApplicationTest methodsFor: 'tests'!
testRunOpensTheContentAtItsPreferredSize
	app := TestApplication new runHidden: true.
	self assert: app world class equals: AppWorld.
	self assert: app world extent equals: 240 @ 90.
	self assert: app window content == app content.
	self assert: app window bounds equals: (0 @ 0 extent: 240 @ 90).
	self assert: app log equals: #(#prepare #started).
	self assert: (app world waitUntilSettled: 5000).
	app stop.
	self assert: (self waitFor: [app log last == #stopped and: [app world isRunning not]])
!
testTitle
	self assert: TestApplication new title equals: 'Test application'.
	self assert: (Application new title) equals: 'Application'
! !
