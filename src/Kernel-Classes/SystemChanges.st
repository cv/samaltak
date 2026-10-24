Object subclass: #SystemChanges
	instanceVariableNames: ''
	classVariableNames: 'Subscribers Silent'
	package: 'Kernel-Classes'!

SystemChanges comment: 'I announce changes to the system (class side only): Behavior announces every method it adds, replaces or removes, ClassBuilder every class it defines or redefines. Subscribers react in the Process that made the change, so they must be quick: mark caches stale, ask for redraws.

	SystemChanges subscribe: #theme do: [:change | (change affects: Theme) ifTrue: [...]].
	SystemChanges unsubscribe: #theme.
	SystemChanges silentlyDuring: [...]	"no announcements from this Process"

Subscribers run in the order they subscribed (class-side initialize runs in load order, so lower layers update their caches before higher ones redraw); subscribing again under the same key replaces the block in place. An error in a subscriber goes to the Transcript; the change and the other subscribers are unaffected.'!

!SystemChanges class methodsFor: 'subscribing'!
subscribe: aKey do: aBlock
	"aBlock receives each SystemChange from now on."
	| list i |
	list := Subscribers ifNil: [#()].
	i := list findFirst: [:each | each key = aKey].
	Subscribers := i = 0
		ifTrue: [list copyWith: aKey -> aBlock]
		ifFalse: [list copy at: i put: aKey -> aBlock; yourself]
!
unsubscribe: aKey
	Subscribers isNil ifFalse: [Subscribers := Subscribers reject: [:each | each key = aKey]]
!
subscribers
	"Answer the subscriber keys, in announcement order."
	^Subscribers isNil ifTrue: [#()] ifFalse: [Subscribers collect: [:each | each key]]
! !

!SystemChanges class methodsFor: 'announcing'!
announce: aSystemChange
	| process |
	(Subscribers isNil or: [Subscribers isEmpty]) ifTrue: [^self].
	process := Processor activeProcess.
	(Silent notNil and: [Silent includes: process]) ifTrue: [^self].
	Subscribers do: [:each |
		[each value value: aSystemChange]
			on: Error
			do: [:e |
				(Smalltalk at: #Transcript ifAbsent: [nil]) ifNotNil: [:t |
					t show: 'SystemChanges: error announcing ', aSystemChange printString, ': ', e messageText asString; cr].
				e return: nil]]
!
methodAdded: aMethod in: aBehavior replacing: anOldMethodOrNil
	self announce: (SystemChange
		kind: (anOldMethodOrNil isNil ifTrue: [#methodAdded] ifFalse: [#methodChanged])
		behavior: aBehavior selector: aMethod selector old: anOldMethodOrNil new: aMethod)
!
method: aMethod removedFrom: aBehavior
	self announce: (SystemChange kind: #methodRemoved behavior: aBehavior selector: aMethod selector old: aMethod new: nil)
!
classDefined: aClass
	self announce: (SystemChange kind: #classDefined behavior: aClass selector: nil old: nil new: nil)
!
silentlyDuring: aBlock
	"Evaluate aBlock without announcing the changes the active Process makes."
	| process |
	process := Processor activeProcess.
	Silent isNil ifTrue: [Silent := IdentitySet new].
	(Silent includes: process) ifTrue: [^aBlock value].
	Silent add: process.
	^aBlock ensure: [Silent remove: process ifAbsent: [nil]]
! !
