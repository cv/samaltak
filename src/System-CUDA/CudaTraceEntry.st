Object subclass: #CudaTraceEntry
	instanceVariableNames: 'name detail startMicros stopMicros startEvent stopEvent deviceMs'
	classVariableNames: ''
	package: 'System-CUDA'!

CudaTraceEntry comment: 'I am one operation CudaTrace recorded: its name (the library function, e.g. cublasSgemm), a description (shapes, sizes), when it ran and how long it took the host (to queue it, for work on the device), and the device''s time between two CUDA events around it, read once the device has passed them (resolve; nil before, or for work done on the host).'!

!CudaTraceEntry methodsFor: 'accessing'!
name: aString detail: detailString
	name := aString.
	detail := detailString
!
startAt: micros
	startMicros := micros
!
stopAt: micros
	stopMicros := micros
!
start: aStartEvent stop: aStopEvent
	aStopEvent isNil ifTrue: [^aStartEvent release].
	startEvent := aStartEvent.
	stopEvent := aStopEvent
!
name
	^name
!
detail
	^detail
!
startMicros
	^startMicros
!
hostMicros
	^stopMicros - startMicros
!
deviceMilliseconds
	"The device's milliseconds for my work, nil while not done (or not measured)."
	^deviceMs
!
isPending
	^stopEvent notNil
!
resolve
	"Read the device's time if it has passed my events; release them."
	stopEvent isNil ifTrue: [^self].
	[(startEvent isAlive and: [stopEvent isAlive]) ifFalse: [^self release].
	stopEvent isDone ifFalse: [^self].
	deviceMs := stopEvent millisecondsSince: startEvent]
		on: CudaError do: [:e | nil].
	self release
!
release
	startEvent isNil ifFalse: [startEvent release].
	stopEvent isNil ifFalse: [stopEvent release].
	startEvent := stopEvent := nil
!
milliseconds
	"The device's time where measured, else the host's."
	^deviceMs ifNil: [self hostMicros / 1000.0]
! !

!CudaTraceEntry methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: name; space; nextPutAll: detail; nextPutAll: ': '.
	deviceMs isNil
		ifTrue: [aStream nextPutAll: (CudaComparison milliseconds: self hostMicros / 1000.0); nextPutAll: (self isPending ifTrue: [' host, device pending'] ifFalse: [' host'])]
		ifFalse: [aStream nextPutAll: (CudaComparison milliseconds: deviceMs); nextPutAll: ' device, '; nextPutAll: (CudaComparison milliseconds: self hostMicros / 1000.0); nextPutAll: ' host']
! !
