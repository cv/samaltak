VMModule subclass: #CpuWorkers
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

CpuWorkers comment: 'The other CPUs, for work that splits into independent parts (PlatformRaster''s bands): how many there are, and running a function on parts 0 .. n - 1, on this CPU and theirs, until all are done. The parts run only C of the VM: no heap, no allocation, no firmware or OS calls, no globals but those the parts own (PlatformRaster''s raster state is per CPU: VMModule class>>threadLocalVariables). NoCpuWorkers (every OS but UEFI) has none; UefiCpuWorkers has the application processors UefiMp starts (docs/uefi.md, More than one CPU).'!

!CpuWorkers class methodsFor: 'declaring'!
isAbstractModule
	^self == CpuWorkers
!
isInterface
	^self == CpuWorkers
! !

!CpuWorkers methodsFor: 'parallel'!
parallelWorkers
	"How many CPUs besides this one take parts (0: none)."
	<returns: 'int64_t'>
	self subclassResponsibility
!
parallelRun: fn context: ctx count: n
	"fn(ctx, i) for each 0 <= i < n, in any order and on any of the CPUs (this one too); answer when all have returned."
	<var: #fn type: 'void (*)(void *, int64_t)'>
	<var: #ctx type: 'void *'>
	<var: #n type: 'int64_t'>
	self subclassResponsibility
! !

CpuWorkers subclass: #NoCpuWorkers
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

NoCpuWorkers comment: 'No other CPUs: the parts run here, one after the other.'!

!NoCpuWorkers methodsFor: 'parallel'!
parallelWorkers
	<export>
	<returns: 'int64_t'>
	^0
!
parallelRun: fn context: ctx count: n
	<export>
	<var: #fn type: 'void (*)(void *, int64_t)'>
	<var: #ctx type: 'void *'>
	<var: #n type: 'int64_t'>
	0 to: n - 1 do: [:i | fn call: ctx with: i]
! !
