Object subclass: #SharedQueue
	instanceVariableNames: 'items accessProtect readSynch'
	classVariableNames: ''
	package: 'Kernel-Processes'!

SharedQueue comment: 'I am a thread-safe FIFO queue: producers nextPut:, consumers next (which waits for an item). readSynch counts the items.'!

!SharedQueue methodsFor: 'initialization'!
initialize
	items := OrderedCollection new.
	accessProtect := Semaphore forMutualExclusion.
	readSynch := Semaphore new
! !

!SharedQueue methodsFor: 'accessing'!
nextPut: anObject
	"Append anObject and wake up a waiting reader. Answer anObject."
	accessProtect critical: [items addLast: anObject].
	readSynch signal.
	^anObject
!
next
	"Answer the first item, waiting until there is one."
	readSynch wait.
	^accessProtect critical: [items removeFirst]
!
nextOrNil
	"Answer the first item, or nil if the queue is empty (never waits)."
	^accessProtect critical: [
		items isEmpty
			ifTrue: [nil]
			ifFalse: [
				readSynch wait.
				items removeFirst]]
!
peek
	"Answer the first item without removing it, or nil."
	^accessProtect critical: [items isEmpty ifTrue: [nil] ifFalse: [items first]]
!
size
	^accessProtect critical: [items size]
!
isEmpty
	^accessProtect critical: [items isEmpty]
!
flush
	"Remove all items."
	accessProtect critical: [
		items size timesRepeat: [readSynch wait].
		items removeAll]
! !
