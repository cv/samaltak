"What the Benchmarks Game's Pharo programs need of Pharo besides the class library: Stdio's standard streams (StdioStream, which the programs extend), Zinc's stream wrappers (here the stream they wrap), ScaledDecimal printing, Character>>asciiValue, String>>findString: and the global newline revcomp-pharo-1 reads (undeclared in Pharo)."!

FileStream subclass: #StdioStream
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BenchmarksGame-Pharo'!

Object subclass: #Stdio
	instanceVariableNames: ''
	classVariableNames: 'Out In'
	package: 'BenchmarksGame-Pharo'!

Object subclass: #ZnBufferedWriteStream
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BenchmarksGame-Pharo'!

Object subclass: #ZnBufferedReadStream
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BenchmarksGame-Pharo'!

Object subclass: #ZnCharacterWriteStream
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BenchmarksGame-Pharo'!

Object subclass: #ZnCharacterReadStream
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BenchmarksGame-Pharo'!

!Stdio class methodsFor: 'accessing'!
stdout
	"Appending: a shell's redirection opens it write-only."
	^Out ifNil: [Out := StdioStream appendingFileNamed: '/dev/stdout']
!
stdin
	"Bytes, as Pharo's (ZnCharacterReadStream reads Characters)."
	^In ifNil: [In := (StdioStream readOnlyFileNamed: '/dev/stdin') binary; yourself]
! !

!ZnBufferedWriteStream class methodsFor: 'instance creation'!
on: aStream
	^aStream
! !

!ZnBufferedReadStream class methodsFor: 'instance creation'!
on: aStream
	^aStream
! !

!ZnCharacterWriteStream class methodsFor: 'instance creation'!
on: aStream
	^aStream
! !

!ZnCharacterReadStream class methodsFor: 'instance creation'!
on: aStream
	^aStream ascii; yourself
! !

Object subclass: #ScaledDecimal
	instanceVariableNames: 'number scale'
	classVariableNames: ''
	package: 'BenchmarksGame-Pharo'!

!ScaledDecimal methodsFor: 'printing'!
setNumber: aNumber scale: anInteger
	number := aNumber.
	scale := anInteger
!
printOn: aStream
	"As Pharo prints one: the digits, then s and the scale."
	aStream print: number showingDecimalPlaces: scale; nextPut: $s; print: scale
! !

!Number methodsFor: '*BenchmarksGame-Pharo'!
asScaledDecimal: scale
	^ScaledDecimal new setNumber: self scale: scale
! !
Smalltalk at: #newline put: nil!

!Character methodsFor: '*BenchmarksGame-Pharo'!
asciiValue
	^self value
! !

!String methodsFor: '*BenchmarksGame-Pharo'!
findString: aString
	^self indexOfSubCollection: aString startingAt: 1
! !
