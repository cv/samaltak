Object subclass: #WeakRegistry
	instanceVariableNames: 'keys executors size lock'
	classVariableNames: 'Default FinalizationProcess FinalizationSemaphore Registries SnapshotTaken'
	package: 'System-Support'!

WeakRegistry comment: 'I map objects to executors without keeping the objects alive. Once the garbage collector has cleared an object from my weak keys, the finalization process (priority 50) sends #finalize to its executor, or #value if it is a Block. An executor must not reference its object, or the object never dies; it keeps a copy of what it releases (a handle). "WeakRegistry default" serves GPU resources, FileStreams and sockets.

Executors of an image resumed from a snapshot are dropped unrun: they name handles of the VM process that saved it. I am first in the startup list, so objects registered by other startUp: methods survive that.'!

!WeakRegistry methodsFor: 'initialization'!
initialize
	keys := WeakArray new: 16.
	executors := Array new: 16.
	size := 0.
	lock := Semaphore forMutualExclusion
! !

!WeakRegistry methodsFor: 'registering'!
add: anObject executor: anExecutor
	"Finalize anExecutor once anObject has been collected; answer anObject."
	anObject isNil ifTrue: [^self error: 'cannot register nil'].
	lock critical: [
		size = keys size ifTrue: [self compact].
		size = keys size ifTrue: [self grow].
		size := size + 1.
		keys at: size put: anObject.
		executors at: size put: anExecutor].
	^anObject
!
remove: anObject
	"Forget anObject's executor without running it; answer the executor, or nil if anObject is not registered."
	^lock critical: [
		| index executor |
		index := self indexOf: anObject.
		index = 0 ifFalse: [
			executor := executors at: index.
			keys at: index put: nil.
			executors at: index put: nil].
		executor]
!
includes: anObject
	^lock critical: [(self indexOf: anObject) > 0]
!
size
	"Answer the number of executors not yet run: live objects plus collected ones awaiting finalization."
	^lock critical: [(1 to: size) count: [:i | (executors at: i) notNil]]
!
removeAll
	"Drop every executor unrun."
	lock critical: [self initialize]
! !

!WeakRegistry methodsFor: 'finalization'!
finalizeValues
	"Run the executors of collected objects (outside my lock, so they may register and remove)."
	| ready |
	ready := lock critical: [
		| list |
		list := OrderedCollection new.
		1 to: size do: [:i |
			((keys at: i) isNil and: [(executors at: i) notNil]) ifTrue: [
				list add: (executors at: i).
				executors at: i put: nil]].
		list].
	ready do: [:each | self runExecutor: each]
!
runExecutor: anExecutor
	[anExecutor isBlock ifTrue: [anExecutor value] ifFalse: [anExecutor finalize]]
		on: Error do: [:e |
			Transcript show: 'finalization: ', e messageText; cr.
			e return: nil]
! !

!WeakRegistry methodsFor: 'private'!
indexOf: anObject
	1 to: size do: [:i | ((keys at: i) == anObject and: [(executors at: i) notNil]) ifTrue: [^i]].
	^0
!
compact
	"Drop the slots of removed and finalized entries."
	| j |
	j := 0.
	1 to: size do: [:i |
		(executors at: i) isNil ifFalse: [
			j := j + 1.
			keys at: j put: (keys at: i).
			executors at: j put: (executors at: i)]].
	j + 1 to: size do: [:i |
		keys at: i put: nil.
		executors at: i put: nil].
	size := j
!
grow
	| newKeys newExecutors |
	newKeys := WeakArray new: keys size * 2.
	newExecutors := Array new: keys size * 2.
	newKeys replaceFrom: 1 to: size with: keys startingAt: 1.
	newExecutors replaceFrom: 1 to: size with: executors startingAt: 1.
	keys := newKeys.
	executors := newExecutors
! !

!WeakRegistry class methodsFor: 'instance creation'!
default
	"The registry for external resources (GPU objects, files, sockets)."
	Default isNil ifTrue: [Default := self new].
	^Default
!
new
	"A new registry; it is finalized as long as it is itself alive."
	| registry |
	registry := super new.
	self addRegistry: registry.
	^registry
! !

!WeakRegistry class methodsFor: 'finalization'!
finalizeAll
	self registriesDo: [:each | each finalizeValues]
!
finalizationProcess
	^FinalizationProcess
!
startFinalizationProcess
	"Start the priority-50 process that runs executors whenever the garbage collector cleared weak references (once)."
	(FinalizationProcess notNil and: [FinalizationProcess isTerminated not]) ifTrue: [^FinalizationProcess].
	FinalizationSemaphore := Semaphore new.
	Smalltalk vm finalizationSemaphore: FinalizationSemaphore.
	FinalizationProcess := [[FinalizationSemaphore wait. self finalizeAll] repeat] newProcess.
	FinalizationProcess priority: 50; name: 'finalization'.
	^FinalizationProcess resume
!
shutDown: quitting
	quitting ifFalse: [SnapshotTaken := true]
!
startUp: resuming
	"In an image resumed from a snapshot, the handles of the VM process that saved it are gone: drop their executors unrun."
	(resuming and: [SnapshotTaken == true]) ifTrue: [self registriesDo: [:each | each removeAll]].
	SnapshotTaken := false.
	FinalizationSemaphore isNil ifFalse: [Smalltalk vm finalizationSemaphore: FinalizationSemaphore]
! !

!WeakRegistry class methodsFor: 'private'!
addRegistry: aRegistry
	| index |
	Registries isNil ifTrue: [Registries := WeakArray new: 4].
	index := Registries indexOf: nil.
	index = 0 ifTrue: [
		Registries := (WeakArray new: Registries size * 2)
			replaceFrom: 1 to: Registries size with: Registries startingAt: 1;
			yourself.
		index := Registries indexOf: nil].
	Registries at: index put: aRegistry
!
registriesDo: aBlock
	Registries isNil ifTrue: [^self].
	Registries do: [:each | each isNil ifFalse: [aBlock value: each]]
! !
