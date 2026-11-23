Object subclass: #PseudoTerminal
	instanceVariableNames: 'handle pid exitStatus semaphore semaphoreIndex session'
	classVariableNames: 'LastActivity Open Session'
	package: 'System-Files'!

PseudoTerminal comment: 'I am the master side of a pseudo-terminal whose slave side runs a child process (a shell), over the platform''s pty primitives (vm/platform/README.md). Reading and writing never block: readInto: answers nil when nothing is pending, write:from:count: nil when the terminal is full. My semaphore is signaled (once, then re-armed by the next read or blocked write) when output arrives, the child side closes, or a blocked write may continue: drain until nil, then wait.

	pty := PseudoTerminal spawn: #(''/bin/sh'' ''-c'' ''ls'') environment: nil directory: ''/tmp'' rows: 24 columns: 80.
	buffer := ByteArray new: 4096.
	[(n := pty readInto: buffer) = 0] whileFalse: [n isNil ifTrue: [pty semaphore wait] ifFalse: [...]].
	pty waitForExit; close.

The child gets TERM=xterm-256color (environment nil: the VM''s environment), a UTF-8 LC_CTYPE unless its locale is UTF-8 already or LC_ALL is set, and a terminal whose input is UTF-8 (IUTF8). close hangs up the child unless it has ended. A PseudoTerminal garbage collected unclosed is closed by the finalization process (WeakRegistry); one saved in an image is dead when the image starts again.'!

!PseudoTerminal methodsFor: 'initialization'!
setHandle: aHandle pid: anInteger
	handle := aHandle.
	pid := anInteger.
	session := self class session.
	Open isNil ifTrue: [Open := Dictionary new].
	Open at: aHandle put: anInteger.
	semaphore := Semaphore new.
	semaphoreIndex := Smalltalk vm registerExternalSemaphore: semaphore.
	self class primSemaphore: handle read: semaphoreIndex write: semaphoreIndex.
	WeakRegistry default add: self executor: self shallowCopy
! !

!PseudoTerminal methodsFor: 'accessing'!
pid
	^pid
!
semaphore
	"Signaled when output arrives, the child side closes, or a blocked write may continue."
	^semaphore
!
isOpen
	self checkSession.
	^handle notNil
! !

!PseudoTerminal methodsFor: 'reading and writing'!
readInto: aByteArray
	"Read what is pending into aByteArray, from its start. Answer the count, nil if nothing is pending, 0 once the child side is closed (or I am)."
	^self readInto: aByteArray startingAt: 1 count: aByteArray size
!
readInto: aByteArray startingAt: start count: count
	| n |
	self isOpen ifFalse: [^0].
	n := self class primRead: handle into: aByteArray start: start count: count.
	n == false ifTrue: [^0].
	(n notNil and: [n > 0]) ifTrue: [LastActivity := Time utcMicroseconds].
	^n
!
write: bytes from: start count: count
	"Write up to count bytes of bytes (a ByteArray or ByteString) from start. Answer the count written, nil if the terminal is full (my semaphore is signaled when it can take more), 0 once closed."
	| n |
	self isOpen ifFalse: [^0].
	n := self class primWrite: handle from: bytes start: start count: count.
	n == false ifTrue: [^0].
	(n notNil and: [n > 0]) ifTrue: [LastActivity := Time utcMicroseconds].
	^n
!
nextPutAll: aStringOrBytes
	"Write all of it (a String is UTF-8 encoded), waiting while the terminal is full. Answer false if I am closed."
	| bytes start n |
	bytes := aStringOrBytes isString ifTrue: [aStringOrBytes utf8Encoded] ifFalse: [aStringOrBytes].
	start := 1.
	[start <= bytes size] whileTrue: [
		n := self write: bytes from: start count: bytes size - start + 1.
		n isNil
			ifTrue: [semaphore waitTimeoutMSecs: 100]
			ifFalse: [
				n = 0 ifTrue: [^false].
				start := start + n]].
	^true
! !

!PseudoTerminal methodsFor: 'controlling'!
rows: rows columns: columns
	"Set the terminal size; the child gets SIGWINCH."
	self isOpen ifFalse: [^self].
	(self class primResize: handle rows: rows columns: columns) isNil
		ifTrue: [FileError signal: 'ptyResize: ', File lastError path: nil]
!
exitStatus
	"Answer the child's exit status (128 + signal number when killed), or nil while it runs. Never waits."
	| status |
	(exitStatus notNil or: [self isOpen not]) ifTrue: [^exitStatus].
	status := self class primWait: handle blocking: false.
	status == false ifFalse: [exitStatus := status].
	^exitStatus
!
isRunning
	^self isOpen and: [self exitStatus isNil]
!
waitForExit
	"Wait (polling, so only this Process waits) until the child has ended; answer its exit status."
	| ms |
	ms := 1.
	[self isRunning] whileTrue: [
		(Delay forMilliseconds: ms) wait.
		ms := ms * 2 min: 50].
	^exitStatus
!
close
	"Release the terminal; the child is hung up (SIGHUP) unless it has ended. Wakes a Process waiting on my semaphore."
	| h |
	self checkSession.
	h := handle.
	h isNil ifTrue: [^self].
	handle := nil.
	Open removeKey: h ifAbsent: [].
	WeakRegistry default remove: self.
	self class primClose: h.
	self releaseSemaphore
!
finalize
	"I am the executor of a collected PseudoTerminal."
	self close
! !

!PseudoTerminal methodsFor: 'private'!
checkSession
	"In an image started again, my handle belonged to the VM that saved it: drop it unused."
	(handle notNil and: [session ~~ self class session]) ifTrue: [
		handle := nil.
		self releaseSemaphore]
!
releaseSemaphore
	| index |
	index := semaphoreIndex.
	semaphoreIndex := nil.
	(index notNil and: [(Smalltalk vm externalObjects at: index ifAbsent: [nil]) == semaphore])
		ifTrue: [Smalltalk vm unregisterExternalSemaphore: index].
	semaphore signal
! !

!PseudoTerminal methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a PseudoTerminal'.
	pid isNil ifFalse: [aStream nextPutAll: ' pid '; print: pid].
	handle isNil ifTrue: [aStream nextPutAll: ' (closed)']
! !

!PseudoTerminal class methodsFor: 'instance creation'!
spawn: argv environment: anArrayOrNil directory: aPathOrNil rows: rows columns: columns
	"Run argv (its first element looked up in PATH) on a new terminal of rows × columns in aPathOrNil (nil: the VM's directory) with anArrayOrNil (''NAME=value'' Strings; nil: the VM's environment)."
	| result |
	result := self primSpawn: argv asArray environment: (anArrayOrNil ifNotNil: [:env | env asArray]) directory: aPathOrNil rows: rows columns: columns.
	result isNil ifTrue: [^FileError signal: 'Cannot start ', argv first printString, ' on a pty: ', File lastError path: argv first].
	^self new setHandle: (result at: 1) pid: (result at: 2)
! !

!PseudoTerminal class methodsFor: 'system startup'!
session
	^Session ifNil: [Session := Object new]
!
startUp: resuming
	"Handles of ptys saved in the image died with the VM that saved it."
	resuming ifTrue: [
		Session := Object new.
		Open := nil]
!
initialize
	Smalltalk addToStartUpList: self
! !

!PseudoTerminal class methodsFor: 'accessing'!
anyBusy
	"Whether a program outside the image is at work on one of my terminals: a foreground job, or a read or write in the last 300 ms of real time (the shell has yet to get to what was typed, or is just done)."
	^(LastActivity notNil and: [Time utcMicroseconds - LastActivity < 300000]) or: [self anyRunsAJob]
!
anyRunsAJob
	"Whether a program runs in the foreground of one of my terminals: more than the shell each was started with, waiting at its prompt."
	Open isNil ifTrue: [^false].
	^Open associations anySatisfy: [:each | | group |
		group := self primForeground: each key.
		group notNil and: [group ~= each value]]
! !

!PseudoTerminal class methodsFor: 'primitives'!
primForeground: aHandle
	"Answer the foreground process group of aHandle's terminal, nil on failure."
	| result |
	result := PlatformFFI call: #(call 'platform' 'pty_foreground' (i64) i32)
		with: {aHandle} ifUnavailable: [^self legacyForeground: aHandle].
	^result < 0 ifTrue: [nil] ifFalse: [result]
!
primSpawn: argv environment: env directory: cwd rows: rows columns: columns
	<primitive: 'ptySpawn'>
	^nil
!
primRead: aHandle into: bytes start: start count: count
	"Answer the byte count, 0 at end, nil if it would block, false on failure."
	<primitive: 'ptyRead'>
	^false
!
primWrite: aHandle from: bytes start: start count: count
	"Answer the byte count written, nil if it would block, false on failure."
	<primitive: 'ptyWrite'>
	^false
!
primResize: aHandle rows: rows columns: columns
	| result |
	result := PlatformFFI call: #(call 'platform' 'pty_resize' (i64 i64 i64) i32)
		with: {aHandle. rows. columns} ifUnavailable: [^self legacyResize: aHandle rows: rows columns: columns].
	^result = 0 ifTrue: [nil] ifFalse: [self]
!
primSemaphore: aHandle read: readIndex write: writeIndex
	<primitive: 'ptySemaphore'>
	^FileError signal: 'ptySemaphore: ', File lastError path: nil
!
primWait: aHandle blocking: aBoolean
	"Answer the exit status, nil while running, false on failure."
	<primitive: 'ptyWait'>
	^false
!
primClose: aHandle
	| result |
	result := PlatformFFI call: #(call 'platform' 'pty_close' (i64) i32)
		with: {aHandle} ifUnavailable: [^self legacyClose: aHandle].
	^result = 0 ifTrue: [nil] ifFalse: [self]
! !

!PseudoTerminal class methodsFor: 'fallback primitives'!
legacyForeground: aHandle
	<primitive: 'ptyForeground'>
	^nil
!
legacyResize: aHandle rows: rows columns: columns
	<primitive: 'ptyResize'>
	^nil
!
legacyClose: aHandle
	<primitive: 'ptyClose'>
	^nil
! !
