"AWFY platform layer for Pharo 12."!

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
	Stdio stdout nextPutAll: aString; lf; flush
! !

!AwfyPlatform class methodsFor: 'benchmarking'!
microseconds
	^Time microsecondClockValue
!
counters
	"VM parameter indices and names."
	^#(#(7 #fullGCs) #(8 #fullGCMilliseconds) #(9 #scavenges) #(10 #scavengeMilliseconds) #(34 #bytesAllocated))
!
statistics
	^self counters collect: [:each | Smalltalk vm parameterAt: each first]
!
statisticsSince: anArray
	"Answer ' name=delta' per counter."
	| now out |
	now := self statistics.
	out := WriteStream on: String new.
	self counters doWithIndex: [:each :i |
		out space; nextPutAll: each last; nextPut: $=; print: (now at: i) - (anArray at: i)].
	^out contents
! !
