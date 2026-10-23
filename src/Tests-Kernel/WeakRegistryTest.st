TestCase subclass: #WeakRegistryTest
	instanceVariableNames: 'dir'
	classVariableNames: ''
	package: 'Tests-Kernel'!

WeakRegistryTest comment: 'Tests weak references (WeakArray, cleared by the VM at scavenges and full GCs), WeakRegistry executors run by the finalization process, and FileStreams closed when they are collected unclosed.'!

!WeakRegistryTest methodsFor: 'running'!
setUp
	dir := self scratchDirectory
! !

!WeakRegistryTest methodsFor: 'support'!
openFiles
	^Smalltalk vm platformHandleCounts at: #files ifAbsent: [0]
!
logger: anObject into: aCollection
	"An executor block whose home context does not reference the registered object."
	^[aCollection add: anObject]
! !

!WeakRegistryTest methodsFor: 'tests'!
testWeakArrayFullGC
	| w kept |
	w := WeakArray new: 4.
	kept := 'kept' copy.
	w at: 1 put: kept; at: 2 put: 'garbage' copy; at: 3 put: 42; at: 4 put: #symbol.
	Smalltalk vm garbageCollect.
	self assert: (w at: 1) == kept.
	self assert: (w at: 2) isNil.
	self assert: (w at: 3) equals: 42.
	self assert: (w at: 4) == #symbol
!
testWeakArrayScavenge
	| w kept old |
	old := Array with: 'old'.
	Smalltalk vm garbageCollect.
	w := WeakArray new: 3.
	kept := 'young' copy.
	w at: 1 put: kept; at: 2 put: 'garbage' copy; at: 3 put: old.
	old := nil.
	Smalltalk vm scavenge.
	self assert: (w at: 1) == kept.
	self assert: (w at: 2) isNil.
	self assert: (w at: 3) notNil description: 'a scavenge does not collect old objects'.
	Smalltalk vm garbageCollect.
	self assert: (w at: 3) isNil
!
testOldWeakArrayHoldingYoungObjects
	| w keep |
	w := WeakArray new: 100.
	Smalltalk vm garbageCollect.
	keep := (1 to: 100) collect: [:i | i printString].
	1 to: 100 do: [:i | w at: i put: (keep at: i)].
	1 to: 100 by: 2 do: [:i | keep at: i put: nil].
	Smalltalk vm scavenge; scavenge.
	self assert: (w count: [:e | e isNil]) equals: 50.
	self assert: (w at: 100) equals: '100'
!
testWeakArraySpecies
	self assert: ((WeakArray new: 2) collect: [:x | x]) class == Array.
	self assert: WeakArray isWeak
!
testExecutorRunsWhenCollected
	| registry log obj |
	registry := WeakRegistry new.
	log := OrderedCollection new.
	obj := Object new.
	registry add: obj executor: [log add: #finalized].
	Smalltalk vm garbageCollect.
	self assert: log isEmpty.
	self assert: registry size equals: 1.
	obj := nil.
	Smalltalk vm garbageCollect.
	self assert: (self waitFor: [log notEmpty]).
	self assert: log asArray equals: #(#finalized).
	self assert: registry size equals: 0
!
testRemovedExecutorDoesNotRun
	| registry log obj witness |
	registry := WeakRegistry new.
	log := OrderedCollection new.
	obj := Object new.
	witness := Object new.
	registry add: obj executor: [log add: #finalized].
	registry add: witness executor: [log add: #witness].
	self assert: (registry includes: obj).
	registry remove: obj.
	self deny: (registry includes: obj).
	obj := witness := nil.
	Smalltalk vm garbageCollect.
	"The witness dies in the same collection: once its executor ran, obj's would have."
	self assert: (self waitFor: [log notEmpty]).
	self assert: log asArray equals: #(#witness)
!
testFailingExecutorDoesNotStopOthers
	| registry log a b |
	registry := WeakRegistry new.
	log := OrderedCollection new.
	a := Object new.
	b := Object new.
	registry add: a executor: [1 / 0].
	registry add: b executor: [log add: #b].
	a := b := nil.
	Smalltalk vm garbageCollect.
	self assert: (self waitFor: [log notEmpty]).
	self assert: registry size equals: 0
!
testManyRegistrations
	| registry log objects |
	registry := WeakRegistry new.
	log := OrderedCollection new.
	objects := (1 to: 1000) collect: [:i | Array with: i].
	objects do: [:each | registry add: each executor: (self logger: each first into: log)].
	1 to: 1000 by: 2 do: [:i | objects at: i put: nil].
	Smalltalk vm garbageCollect.
	self assert: (self waitFor: [log size = 500]).
	self assert: (log allSatisfy: [:n | n odd]).
	self assert: registry size equals: 500
!
testFinalizationProcess
	self assert: WeakRegistry finalizationProcess priority equals: 50.
	self deny: WeakRegistry finalizationProcess isTerminated.
	self assert: Smalltalk vm finalizationSemaphore notNil
!
testDroppedFileStreamIsFlushedAndClosed
	| before path stream |
	path := dir / 'dropped.txt'.
	before := self openFiles.
	stream := FileStream newFileNamed: path.
	stream nextPutAll: 'pending'.
	self assert: self openFiles equals: before + 1.
	stream := nil.
	Smalltalk vm garbageCollect.
	self assert: (self waitFor: [self openFiles = before]).
	self assert: (File readText: path) equals: 'pending'
!
testClosedFileStreamIsUnregistered
	| stream path |
	path := dir / 'closed.txt'.
	stream := FileStream newFileNamed: path.
	self assert: (WeakRegistry default includes: stream).
	stream close.
	self deny: (WeakRegistry default includes: stream)
! !
