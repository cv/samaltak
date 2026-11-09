ToolsTestCase subclass: #VMRebuilderTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

VMRebuilderTest comment: 'I test the VM Rebuild tool short of the reboot (tests/tools/reboot_test.sh does that): it translates the image''s VM, edits included, and compiles it into a working binary in the build directory it is given, streaming make''s output into its window.'!

!VMRebuilderTest methodsFor: 'running'!
timeLimitMilliseconds
	^180000
! !

!VMRebuilderTest methodsFor: 'tests'!
testBuildCompilesTheEditedVM
	| tool dir original vm run |
	tool := VMRebuilder openAt: 100 @ 100.
	dir := self scratchDirectory , '/vm'.
	original := VMMain compiledMethodAt: #banner.
	VMMain compile: 'banner <function> ^''Samaltak VM (test)''' classified: 'running'.
	vm := [tool build: dir] ensure: [VMMain addSelector: #banner withMethod: original].
	self assert: vm equals: dir , '/samaltak'.
	tool window sync: [tool update].
	self assert: (tool output includesSubstring: 'link build/samaltak').
	self assert: (tool output includesSubstring: 'built ' , vm).
	run := OSProcess run: (OSProcess commandFor: {vm. Smalltalk vm imagePath. '--headless'. '--eval'. 'Smalltalk vm banner'}).
	self assert: run output equals: '''Samaltak VM (test)''' , (String with: Character lf)
! !
