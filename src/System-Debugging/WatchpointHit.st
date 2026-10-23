Halt subclass: #WatchpointHit
	instanceVariableNames: 'watchpoint modification'
	classVariableNames: ''
	package: 'System-Debugging'!

WatchpointHit comment: 'I am signaled when a store into a watched field was attempted (the object is read-only while watched, so the store failed with modification, a ModificationForbidden). I am a Halt, not an Error, so error handlers of the program do not see watchpoints. Proceeding performs the store.'!

!WatchpointHit methodsFor: 'accessing'!
watchpoint
	^watchpoint
!
watchpoint: aWatchpoint
	watchpoint := aWatchpoint
!
modification
	"The ModificationForbidden of the store."
	^modification
!
modification: aModificationForbidden
	modification := aModificationForbidden
!
description
	^watchpoint isNil ifTrue: ['Watchpoint'] ifFalse: [watchpoint label]
! !
