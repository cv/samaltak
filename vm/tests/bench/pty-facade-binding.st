"Benchmark-only descriptor binding for the historical Array/word bridge."

Object subclass: #PTYBenchBinding
	instanceVariableNames: 'id library symbol tags resultTag'
	classVariableNames: 'Bindings'
	package: 'PTYFacadeBench'!

!PTYBenchBinding class methodsFor: 'binding'!
bind: descriptor
	^(self tryBind: descriptor) ifNil: [
		FFIError signal: 'No matching FFI export: ', (descriptor at: 2), ' / ', (descriptor at: 3)]
!
tryBind: descriptor
	"Cold bind for the benchmark's literal call descriptors."
	| library symbol types tags resultTag id |
	library := FFI copyName: (descriptor at: 2).
	symbol := FFI copyName: (descriptor at: 3).
	types := descriptor at: 4.
	tags := ByteArray new: types size.
	1 to: types size do: [:i | tags at: i put: (FFI typeTag: (types at: i))].
	tags beReadOnlyObject.
	resultTag := FFI typeTag: (descriptor at: 5).
	id := self primBind: library symbol: symbol types: tags result: resultTag.
	id isNil ifTrue: [^nil].
	^self new initializeID: id library: library symbol: symbol types: tags result: resultTag
!
primBind: library symbol: symbol types: tags result: resultTag
	<primitive: 'ffiBind'>
	^nil
! !

!PTYBenchBinding methodsFor: 'invoking'!
invoke: arguments
	id isNil ifTrue: [^FFIError signal: 'Uninitialized FFI binding'].
	(arguments class == Array and: [arguments size = tags size]) ifFalse: [
		^FFIError signal: 'Expected an FFI argument Array of size ', tags size printString].
	^self primInvoke: id library: library symbol: symbol types: tags result: resultTag arguments: arguments
!
tryInvoke: arguments
	^self tryPrimInvoke: id library: library symbol: symbol types: tags result: resultTag arguments: arguments
!
tryPrimInvoke: anID library: aLibrary symbol: aSymbol types: argumentTags result: aResultTag arguments: arguments
	<primitive: 'ffiInvoke'>
	^false
!
initializeID: anID library: aLibrary symbol: aSymbol types: argumentTags result: aResultTag
	id := anID.
	library := aLibrary.
	symbol := aSymbol.
	tags := argumentTags.
	resultTag := aResultTag.
	self beReadOnlyObject
!
primInvoke: anID library: aLibrary symbol: aSymbol types: argumentTags result: aResultTag arguments: arguments
	<primitive: 'ffiInvoke'>
	^FFIError signal: 'FFI invocation rejected: ', aLibrary, ' / ', aSymbol
! !
