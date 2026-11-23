VMCoreModule subclass: #FFIWrapperHelpers
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

FFIWrapperHelpers comment: 'Typed operations called at fixed sites in emitted FFI wrappers. Argument helpers never allocate or safepoint. Boxing may allocate only after the native target returns and borrowed pointers are no longer needed.'!

!FFIWrapperHelpers methodsFor: 'compile-time addresses'!
wrappedArgumentHelper: tag
	<function>
	<var: #tag type: 'int32_t'>
	<returns: 'uint64_t'>
	^tag caseOf: {
		[1] -> [self cCoerce: (self functionPointer: #ffiUnboxI32:into:) to: 'uint64_t'].
		[2] -> [self cCoerce: (self functionPointer: #ffiUnboxU32:into:) to: 'uint64_t'].
		[3] -> [self cCoerce: (self functionPointer: #ffiUnboxI64:into:) to: 'uint64_t'].
		[4] -> [self cCoerce: (self functionPointer: #ffiUnboxU64:into:) to: 'uint64_t'].
		[5] -> [self cCoerce: (self functionPointer: #ffiBorrowSlice:into:length:) to: 'uint64_t'].
		[6] -> [self cCoerce: (self functionPointer: #ffiUnboxF64:into:) to: 'uint64_t'].
		[8] -> [self cCoerce: (self functionPointer: #ffiBorrowSlice:into:length:) to: 'uint64_t'].
		[9] -> [self cCoerce: (self functionPointer: #ffiBorrowWritableSlice:into:length:) to: 'uint64_t'].
		[10] -> [self cCoerce: (self functionPointer: #ffiBorrowInteger:into:signedCount:) to: 'uint64_t']}
		otherwise: [0 asUInt64]
!
wrappedResultHelper: tag
	<function>
	<var: #tag type: 'int32_t'>
	<returns: 'uint64_t'>
	"Select stress entry points when emitting the wrapper, not on every call."
	(libc getenv: 'SAMALTAK_FFI_BOX_FULL_GC') notNull ifTrue: [
		tag = 3 ifTrue: [^self cCoerce: (self functionPointer: #ffiBoxI64WithGC:) to: 'uint64_t'].
		tag = 4 ifTrue: [^self cCoerce: (self functionPointer: #ffiBoxU64WithGC:) to: 'uint64_t'].
		tag = 6 ifTrue: [^self cCoerce: (self functionPointer: #ffiBoxF64WithGC:) to: 'uint64_t'].
		tag = 11 ifTrue: [^self cCoerce: (self functionPointer: #ffiBoxOwnedIntegerWithGC:) to: 'uint64_t']].
	^tag caseOf: {
		[3] -> [self cCoerce: (self functionPointer: #ffiBoxI64:) to: 'uint64_t'].
		[4] -> [self cCoerce: (self functionPointer: #ffiBoxU64:) to: 'uint64_t'].
		[6] -> [self cCoerce: (self functionPointer: #ffiBoxF64:) to: 'uint64_t'].
		[7] -> [self cCoerce: (self functionPointer: #ffiBoxVoid) to: 'uint64_t'].
		[11] -> [self cCoerce: (self functionPointer: #ffiBoxOwnedInteger:) to: 'uint64_t']}
		otherwise: [0 asUInt64]
! !

!FFIWrapperHelpers methodsFor: 'arguments'!
ffiUnboxI32: o into: out
	<function>
	<var: #o type: 'oop'>
	<var: #out type: 'int32_t *'>
	<returns: 'bool'>
	| wide |
	wide := self local: 'int64_t'.
	(o = 0 or: [(memory int64Of: o into: wide) not]) ifTrue: [^false].
	(wide value < -16r80000000 or: [wide value > 16r7FFFFFFF]) ifTrue: [^false].
	out value: wide value asInt32.
	^true
!
ffiUnboxU32: o into: out
	<function>
	<var: #o type: 'oop'>
	<var: #out type: 'uint32_t *'>
	<returns: 'bool'>
	| wide |
	wide := self local: 'uint64_t'.
	(o = 0 or: [(memory u64Of: o into: wide) not]) ifTrue: [^false].
	wide value > 16rFFFFFFFF ifTrue: [^false].
	out value: wide value asUInt32.
	^true
!
ffiUnboxI64: o into: out
	<function>
	<var: #o type: 'oop'>
	<var: #out type: 'int64_t *'>
	<returns: 'bool'>
	^o ~= 0 and: [memory int64Of: o into: out]
!
ffiUnboxU64: o into: out
	<function>
	<var: #o type: 'oop'>
	<var: #out type: 'uint64_t *'>
	<returns: 'bool'>
	^o ~= 0 and: [memory u64Of: o into: out]
!
ffiUnboxF64: o into: out
	<function>
	<var: #o type: 'oop'>
	<var: #out type: 'double *'>
	<returns: 'bool'>
	(o = 0 or: [(memory isFloat: o) not]) ifTrue: [^false].
	out value: (memory floatVal: o).
	^true
!
ffiBorrowSlice: slice into: out length: length
	<function>
	<var: #slice type: 'oop'>
	<var: #out type: 'uint64_t *'>
	<var: #length type: 'uint64_t *'>
	<returns: 'bool'>
	^self checkedSlice: slice into: out length: length writable: false
!
ffiBorrowWritableSlice: slice into: out length: length
	<function>
	<var: #slice type: 'oop'>
	<var: #out type: 'uint64_t *'>
	<var: #length type: 'uint64_t *'>
	<returns: 'bool'>
	^self checkedSlice: slice into: out length: length writable: true
!
checkedSlice: slice into: out length: length writable: writable
	| bytes offsetOop lengthOop start len size fmt |
	(slice = 0 or: [(self isPtr: slice) not]) ifTrue: [^false].
	((self rawClass: slice) = memory clsArray and: [(self formatOf: slice) = F_VAR and: [(self numSlots: slice) = 3]]) ifFalse: [^false].
	bytes := self loadRef: slice at: 0.
	(bytes = 0 or: [(self isPtr: bytes) not or: [(self rawClass: bytes) ~= memory clsBytearray]]) ifTrue: [^false].
	(writable and: [self isImmutable: bytes]) ifTrue: [^false].
	fmt := self formatOf: bytes.
	(fmt < F_BYTES or: [fmt >= (F_BYTES + 8)]) ifTrue: [^false].
	offsetOop := self loadRef: slice at: 1.
	lengthOop := self loadRef: slice at: 2.
	((self isInt: offsetOop) and: [self isInt: lengthOop]) ifFalse: [^false].
	start := self intVal: offsetOop.
	len := self intVal: lengthOop.
	(start < 1 or: [len < 0]) ifTrue: [^false].
	start := start - 1.
	size := 8 * (self numSlots: bytes) asUInt64.
	(size < (fmt - F_BYTES) asUInt64) ifTrue: [^false].
	size := size - (fmt - F_BYTES) asUInt64.
	(start asUInt64 > size or: [len asUInt64 > (size - start asUInt64)]) ifTrue: [^false].
	out value: (self cCoerce: (self bytesOf: bytes) + start to: 'uint64_t').
	length value: len asUInt64.
	^true
! !

!FFIWrapperHelpers methodsFor: 'results'!
ffiBoxI64: value
	<function>
	<var: #value type: 'int64_t'>
	<returns: 'oop'>
	jit syncPendingBoundFrame.
	value = -16r8000000000000000 ifTrue: [^memory largeIntFrom: 16r8000000000000000 asUInt64 negative: true].
	^memory int64Oop: value
!
ffiBoxU64: value
	<function>
	<var: #value type: 'uint64_t'>
	<returns: 'oop'>
	jit syncPendingBoundFrame.
	^memory largeIntFrom: value negative: false
!
ffiBoxF64: value
	<function>
	<var: #value type: 'double'>
	<returns: 'oop'>
	jit syncPendingBoundFrame.
	^memory floatOop: value
!
ffiBoxVoid
	<function>
	<returns: 'oop'>
	^memory nilOop
! !

!FFIWrapperHelpers methodsFor: 'GC stress'!
ffiBoxI64WithGC: value
	<function>
	<var: #value type: 'int64_t'>
	<returns: 'oop'>
	jit syncPendingBoundFrame.
	gc fullGC.
	^self ffiBoxI64: value
!
ffiBoxU64WithGC: value
	<function>
	<var: #value type: 'uint64_t'>
	<returns: 'oop'>
	jit syncPendingBoundFrame.
	gc fullGC.
	^self ffiBoxU64: value
!
ffiBoxF64WithGC: value
	<function>
	<var: #value type: 'double'>
	<returns: 'oop'>
	jit syncPendingBoundFrame.
	gc fullGC.
	^self ffiBoxF64: value
! !
