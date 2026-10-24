TestCase subclass: #ImageBuilderTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

ImageBuilderTest comment: 'ImageBuilder builds the VM tests'' mini kernel into a working image, the same bytes every time.'!

!ImageBuilderTest methodsFor: 'running'!
timeLimitMilliseconds
	^120000
! !

!ImageBuilderTest methodsFor: 'tests'!
testBuildsAreReproducible
	| a b |
	a := self scratchDirectory , '/a.image'.
	b := self scratchDirectory , '/b.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: a.
	ImageBuilder buildFrom: 'vm/tests/mini' to: b.
	self assert: (File readBytes: a) = (File readBytes: b)
!
testMiniImageRuns
	| image run |
	image := self scratchDirectory , '/mini.image'.
	ImageBuilder buildFrom: 'vm/tests/mini' to: image.
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. image. '--headless'. 'Arith'}).
	self assert: run output equals: (File readText: 'vm/tests/expected/Arith.txt')
!
testUnknownSuperclassIsReported
	| dir error |
	dir := self scratchDirectory.
	Directory create: dir , '/P'.
	File writeText: 'P 0' to: dir , '/packages.txt'.
	File writeText: 'Nothing subclass: #Thing
	instanceVariableNames: ''''
	classVariableNames: ''''
	package: ''P''!!' to: dir , '/P/Thing.st'.
	error := [ImageBuilder buildFrom: dir to: dir , '/x.image'. nil] on: ImageBuildError do: [:e | e messageText].
	self assert: (error notNil and: [error includesSubstring: 'P/Thing.st:1: unknown superclass Nothing'])
! !
