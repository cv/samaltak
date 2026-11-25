Object subclass: #VirtualMachine
	instanceVariableNames: ''
	classVariableNames: 'ExternalObjectsLock'
	package: 'System-Support'!

VirtualMachine comment: 'I am the facade for the VM''s system primitives (Smalltalk vm): command-line arguments, image path, statistics, garbage collection, standard output and the primitive table. Tools use me instead of calling primitives directly.'!

!VirtualMachine methodsFor: 'recording clock'!
isOnWorkClock
	^self workClockNextFrame notNil
!
workClockStart: fps semaphore: anIndex
	"The clock of the image (Time, Delay) becomes the work clock, running; if fps > 0, external semaphore anIndex is signaled when each frame of fps per second is due, the first one now. Answer when that first frame was (µs). See the comment of the VM's Scheduler."
	<primitive: 'workClockStart'>
	^self primitiveFailed
!
workClockStop
	<primitive: 'workClockStop'>
	^self primitiveFailed
!
workClockRunning: aBoolean
	"Does the clock run (a driver command is in flight) or stand still?"
	<primitive: 'workClockRunning'>
	^self primitiveFailed
!
workClockPaced: aBoolean
	"Whether an external program runs: then the clock keeps moving, at least at the pace of real time."
	<primitive: 'workClockPaced'>
	^self primitiveFailed
!
workClockQuerying: aBoolean
	"A query is being served while the clock stands still: a Process below the control server's priority may run if the query waits for it (it may hold a lock)."
	<primitive: 'workClockQuerying'>
	^self primitiveFailed
!
workClockHold
	"A frame of the compositor begins: its work does not move the clock."
	<primitive: 'workClockHold'>
	^self primitiveFailed
!
workClockRelease
	"The frame ended: answer its work (µs at the clock's rate)."
	<primitive: 'workClockRelease'>
	^self primitiveFailed
!
workClockSkipRealTime
	"Paced: the real time gone by and not yet counted (a recorded frame's wait for the GPU and for the reader) is not counted."
	<primitive: 'workClockSkipRealTime'>
	^self primitiveFailed
!
workClockHeldMicros
	"During a frame: the clock plus the frame's work so far (the times the frame reports); else the clock."
	<primitive: 'workClockHeldMicros'>
	^self primitiveFailed
!
workClockCharge: microseconds
	"Move the clock on by microseconds: a frame took longer than a display refresh."
	<primitive: 'workClockCharge'>
	^self primitiveFailed
!
workClockNextFrame
	"When the next frame is due (µs of the clock), nil while the work clock is off."
	<primitive: 'workClockNextFrame'>
	^self primitiveFailed
! !

!VirtualMachine methodsFor: 'accessing'!
arguments
	"Answer the command-line arguments after the image path."
	<primitive: 'vmArguments'>
	^#()
!
imagePath
	<primitive: 'imagePath'>
	^''
!
banner
	"What the VM calls itself (VMMain>>banner); nil if it does not say."
	<primitive: 'vmBanner'>
	^nil
!
primitiveNames
	"Answer an Array whose element n is the name of primitive n (nil for gaps)."
	<primitive: 'primitiveNames'>
	^#()
!
primitiveNumberFor: aString
	^self primitiveNames indexOf: aString
!
getenv: name
	"Answer the value of the environment variable aString, or nil."
	<ffiSite>
	| answer |
	answer := (self ffiSite: #(call 'vm:core' 'core_getenv_text' (cText) ownedText)) tryInvoke1: name.
	answer == false ifTrue: [^nil].
	^answer
!
specialObjectsArray
	<primitive: 'specialObjectsArray'>
	^self primitiveFailed
!
platformHandleCounts
	"Answer a Dictionary of live platform handles by kind (#files #sockets #windows #gpuDevices #shaders #pipelines #textures #samplers #buffers #fences #ptys); empty without the platform layer."
	| counts names result |
	result := Dictionary new.
	counts := self primPlatformHandleCounts.
	counts isNil ifTrue: [^result].
	names := #(#files #sockets #windows #gpuDevices #shaders #pipelines #textures #samplers #buffers #fences #ptys).
	1 to: (names size min: counts size) do: [:i | result at: (names at: i) put: (counts at: i)].
	^result
!
droppedEvents
	"Answer how many platform events were dropped because the event queue was full: the image's where it drives the input devices (InputQueue), else the VM's; 0 without either."
	InputQueue current isNil ifFalse: [^InputQueue droppedEvents].
	^self primDroppedEvents
!
finalizationSemaphore
	"Answer the Semaphore the VM signals after a garbage collection cleared weak references."
	^self specialObjectsArray at: VMConstants soFinalizationSemaphore
!
finalizationSemaphore: aSemaphore
	self specialObjectsArray at: VMConstants soFinalizationSemaphore put: aSemaphore
! !

!VirtualMachine methodsFor: 'external semaphores'!
externalObjects
	"Answer the Array whose Semaphores the VM and the platform signal by 1-based index."
	^self specialObjectsArray at: VMConstants soExternalObjects
!
registerExternalSemaphore: aSemaphore
	"Put aSemaphore into the first free slot of the external objects (growing them when full); answer its index."
	^ExternalObjectsLock critical: [| table index |
		table := self externalObjects.
		index := table identityIndexOf: nil.
		index = 0 ifTrue: [
			index := table size + 1.
			table := table, (Array new: (table size max: 16)).
			self specialObjectsArray at: VMConstants soExternalObjects put: table].
		table at: index put: aSemaphore.
		index]
!
unregisterExternalSemaphore: anIndex
	"Free the slot at anIndex (nil: do nothing)."
	anIndex isNil ifFalse: [self externalObjects at: anIndex put: nil]
! !

!VirtualMachine methodsFor: 'statistics'!
statistics
	"Answer a VMStatistics of the VM's counters now."
	^VMStatistics counters: self primStatistics
!
primStatistics
	"Answer the counters as an Array (see prims.def)."
	<primitive: 'vmStats'>
	^#()
!
threadCpuMicroseconds
	"Answer the CPU time of the VM's thread: every Process's, the garbage collector's and the JIT's."
	<ffiSite>
	| answer |
	answer := (self ffiSite: #(call 'vm:core' 'core_thread_cpu_microseconds' () i64)) tryInvoke0.
	answer == false ifTrue: [^self primitiveFailed].
	answer = -4611686018427387904 ifTrue: [^self primitiveFailed].
	^answer
! !

!VirtualMachine methodsFor: 'jit'!
jitParameters
	"{mode. flags. threshold. osr. cache MB. CPU}: the JIT's settings (--jit, --jit-flags, --jit-threshold, --jit-osr, --jit-cache) and the CPU it emits code for; mode, flags and CPU are Strings ('template', 'arith,fuse,barrier', 'arm64' or 'x86_64')."
	<primitive: 'jitParameters'>
	^self primitiveFailed
!
jitParameters: anArray
	"Set {mode. flags. threshold. osr} (nil keeps one; flags change as with --jit-flags: 'embed,-fuse'); answer the settings before. A new mode or new flags drop all machine code."
	<primitive: 'jitParameters'>
	^self primitiveFailed
!
jitMode
	^self jitParameters first asSymbol
!
jitFlags
	"The names of the JIT's flags that are on."
	^(self jitParameters at: 2) substrings: ','
!
jitArchitecture
	"#arm64 or #x86_64: the CPU the JIT emits code for (and machine code listings decode)."
	^(self jitParameters at: 6) asSymbol
!
jitMode: aSymbol
	"#none or #template; answer the previous mode."
	^(self jitParameters: {aSymbol asString. nil. nil. nil}) first asSymbol
! !

!VirtualMachine methodsFor: 'memory'!
garbageCollect
	"Run a full GC; answer the free old-space bytes."
	<primitive: 'gc'>
	^0
!
scavenge
	"Collect the young generation; answer the free eden bytes."
	<primitive: 'scavenge'>
	^0
!
timeSliceMicroseconds: anInteger
	"Equal-priority Processes take turns every anInteger µs while more than one is ready (0: never); answer whether the VM slices. It arms the slice only while they compete, so a program whose Processes idle or do not compete has no timer for it. A VM without the primitive does not slice (equal-priority Processes take turns when one waits or yields)."
	<primitive: 'timeSlice'>
	^false
!
releaseMemory
	"Give back to the system what I hold only because I was busy before: eden's pages (after a scavenge) and all machine code with its type feedback and the JIT's scratch areas (what runs again is compiled again). For a program that has gone idle: AppWorld calls it when nothing happened for a while."
	<primitive: 'releaseMemory'>
	^self
! !

!VirtualMachine methodsFor: 'method cache'!
flushMethodCache
	<primitive: 'flushMethodCache'>
!
flushCacheForSelector: aSymbol
	<primitive: 'flushCacheForSelector'>
	self flushMethodCache
! !

!VirtualMachine methodsFor: 'output'!
stdoutWrite: text
	"Write aString (UTF-8 encoded) to standard output."
	<ffiSite>
	((self ffiSite: #(call 'vm:core' 'core_stdout_text' (countedText) void)) tryInvoke1: text) == false
		ifTrue: [^self primitiveFailed].
	^self
!
stderrWrite: text
	<ffiSite>
	((self ffiSite: #(call 'vm:core' 'core_stderr_text' (countedText) void)) tryInvoke1: text) == false
		ifTrue: [^self primitiveFailed].
	^self
! !

!VirtualMachine methodsFor: 'profiling'!
samplerInterval: microseconds semaphoreIndex: index
	"Signal the external semaphore at index every microseconds (0 stops)."
	<primitive: 'samplerInterval'>
	^self primitiveFailed
!
allocationSamplingEvery: bytes semaphoreIndex: index
	<primitive: 'allocationSampling'>
	^self primitiveFailed
!
samplerBufferIndex: index depth: maxDepth
	^self samplerBufferIndex: index depth: maxDepth cpu: false
!
samplerBufferIndex: index depth: maxDepth cpu: aBoolean
	"Have the VM record allocation samples (with aBoolean CPU samples too) into the Array at index of the external objects (0: none), at most maxDepth frames each, where the sampled process runs: no switch to the sampling process per sample (Profiler>>drainBuffer). Answer false if the VM cannot."
	<primitive: 'samplerBuffer'>
	^false
!
allocationSampleInfo
	"Answer {class. size} of the last sampled allocation."
	<primitive: 'allocationSampleInfo'>
	^nil
!
allocationSampleTake
	"Answer {class. size} of an allocation sample not taken yet (marking it taken), or nil."
	<primitive: 'allocationSampleTake'>
	^nil
!
samplerTickTake
	"Answer whether a CPU sampler tick was signalled and not taken yet (marking it taken)."
	<primitive: 'samplerTickTake'>
	^false
! !

!VirtualMachine methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'Smalltalk vm'
! !

!VirtualMachine class methodsFor: 'class initialization'!
initialize
	ExternalObjectsLock := Semaphore forMutualExclusion
! !
