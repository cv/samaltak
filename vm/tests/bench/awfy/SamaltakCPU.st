"awfy.sh --cpu: the laps of Samaltak in CPU time."!

!AwfyPlatform class methodsFor: 'benchmarking'!
microseconds
	"The CPU time of the thread running Smalltalk, garbage collection, the JIT's compiling and other Processes (the profiler's sampling) included, as PharoCPU.st measures Pharo."
	^Smalltalk vm threadCpuMicroseconds
! !
