"awfy.sh --cpu: the laps of Samaltak in CPU time."!

!AwfyPlatform class methodsFor: 'benchmarking'!
microseconds
	"The CPU time of my thread: what my Process used plus the JIT's compiling, which no Process is charged."
	^Processor activeProcess cpuMicroseconds + Smalltalk vm statistics jitCompileMicroseconds
! !
