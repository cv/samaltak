CLibrary subclass: #Builtins
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Builtins comment: 'The C compiler''s builtins the VM calls (GCC and Clang have them, without a header).'!

!Builtins methodsFor: 'bits'!
ctz: x
	"The number of trailing zero bits of x, which is not 0."
	<c: 'int __builtin_ctz(unsigned x)'>
	^x lowBit - 1
!
ctz64: x
	"The number of trailing zero bits of x, which is not 0."
	<c: 'int __builtin_ctzll(unsigned long long x)'>
	^x lowBit - 1
! !

!Builtins methodsFor: 'memory'!
memoryBarrier
	"A full barrier, for the compiler and the CPU (the stores before it are seen before those after it, by other CPUs and by devices)."
	<c: 'void __sync_synchronize(void)'>
	^nil
!
deviceBarrier
	"A barrier for memory a device reads (machineBarrier): on arm64 dmb osh, the outer-shareable domain devices are in (Linux's dma_mb), where __sync_synchronize's dmb ish covers the CPUs only; elsewhere memoryBarrier. Defined in PlatformPrimitives' cPreamble: only that module calls it."
	<c: 'void lt_device_barrier(void)'>
	^nil
! !
