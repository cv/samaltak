Object subclass: #CLibrary
	instanceVariableNames: 'sim'
	classVariableNames: ''
	package: 'VM-Lowtalk'!

CLibrary comment: 'I am the abstract class of the C libraries the VM calls. A subclass declares functions, variables and macros by pragmas on methods whose bodies simulate them:

	memcpy: dst from: src size: n
		<c: ''void *memcpy(void *dst, const void *src, size_t n)''>
		sim memory copy: n from: (sim memory addressOf: src) to: (sim memory addressOf: dst).
		^dst
	stderr
		<cVariable: ''FILE *stderr''>
		^sim stderrFile
	PROT_READ
		<cMacro: ''int PROT_READ''>
		^1

headers (class side) answers the #include lines, typedefs the library''s types (#((FILE opaque) (pthread_t uintptr_t))).'!

!CLibrary class methodsFor: 'declaring'!
headers
	^#()
!
typedefs
	^#()
! !

!CLibrary methodsFor: 'simulation'!
sim
	^sim
!
setSimulation: aSimulation
	sim := aSimulation
!
memory
	^sim memory
! !
