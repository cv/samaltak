"AWFY platform layer for Samaltak."!

Object subclass: #ScriptConsole
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #AwfyPlatform
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

!ScriptConsole class methodsFor: 'printing'!
println: aString
	Transcript show: aString; cr
! !

!AwfyPlatform class methodsFor: 'benchmarking'!
microseconds
	^Time microsecondClockValue
!
statistics
	^Smalltalk vm statistics
!
statisticsSince: aVMStatistics
	"Answer ' name=delta' for every counter the VM answers."
	| delta names out |
	delta := (self statistics - aVMStatistics) counters.
	names := VMStatistics counterNames.
	out := WriteStream on: String new.
	delta doWithIndex: [:each :i |
		out space; nextPutAll: (i <= names size ifTrue: [names at: i] ifFalse: ['counter', i printString]); nextPut: $=; print: each].
	^out contents
! !

!Integer methodsFor: 'awfy'!
& anInteger
	"Pharo protocol the AWFY sources use."
	^self bitAnd: anInteger
! !

!Number methodsFor: 'awfy'!
% aNumber
	"Pharo protocol the AWFY sources use."
	^self \\ aNumber
! !
