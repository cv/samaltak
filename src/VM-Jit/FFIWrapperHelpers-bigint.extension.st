!FFIWrapperHelpers methodsFor: 'integer magnitude arguments'!
ffiBorrowInteger: o into: out signedCount: count
	"Only for vetted, synchronous targets. NULL + decoded immediate, or a read-only
	limb span + signed limb count. Never allocate, copy a magnitude or pass an OOP."
	<function>
	<var: #o type: 'oop'>
	<var: #out type: 'uint64_t *'>
	<var: #count type: 'int64_t *'>
	<returns: 'bool'>
	| c fmt p n negative |
	(self isInt: o) ifTrue: [
		out value: 0.
		count value: (self intVal: o).
		^true].
	(o = 0 or: [(self isPtr: o) not]) ifTrue: [^false].
	fmt := self formatOf: o.
	(fmt < F_BYTES or: [fmt >= (F_BYTES + 8)]) ifTrue: [^false].
	c := self rawClass: o.
	negative := c = (memory special: SO_LARGENEG).
	(negative or: [c = (memory special: SO_LARGEPOS)]) ifFalse: [^false].
	p := self cCoerce: (self bytesOf: o) to: 'const uint64_t *'.
	n := (self numSlots: o) asInt64.
	"Heap byte objects are word-rounded and zero padded. Accept valid old-image
	and explicitly constructed integers with redundant zero magnitude bytes."
	[n > 0 and: [(p at: n - 1) = 0]] whileTrue: [n := n - 1].
	out value: (self cCoerce: p to: 'uint64_t').
	count value: (negative ifTrue: [0 - n] ifFalse: [n]).
	^true
! !
