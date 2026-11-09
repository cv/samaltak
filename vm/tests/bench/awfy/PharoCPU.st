"awfy.sh --cpu: the laps of Pharo 12 in CPU time."!

!AwfyPlatform class methodsFor: 'benchmarking'!
microseconds
	"The CPU time of the thread running Smalltalk, garbage collection and Cog's compiling included."
	| timespec |
	timespec := ByteArray new: 16.
	(self clockGettime: self threadCputimeClock into: timespec) = 0 ifFalse: [self error: 'clock_gettime failed'].
	^((timespec unsignedLongLongAt: 1) * 1000000) + ((timespec unsignedLongLongAt: 9) // 1000)
!
threadCputimeClock
	"CLOCK_THREAD_CPUTIME_ID on macOS."
	^16
!
clockGettime: clockId into: aByteArray
	^self ffiCall: #(int clock_gettime(int clockId, void* aByteArray)) library: LibC
! !
