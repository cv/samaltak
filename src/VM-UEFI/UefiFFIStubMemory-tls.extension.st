!UefiFFIStubMemory methodsFor: 'static tls wrappers'!
staticTlsEntry: name signature: signature
	"The TLS engine's core_tls_* exports (FFIPrimitives-tls), else the cryptography's, or 0."
	<function>
	<var: #name type: 'const char *'>
	<var: #signature type: 'uint32_t'>
	<returns: 'uint64_t'>
	(signature = 16r83 and: [(libc strcmp: name with: 'core_tls_seed') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsSeed:) to: 'uint64_t'].
	(signature = 16r33 and: [(libc strcmp: name with: 'core_tls_set_time') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsSetTime:) to: 'uint64_t'].
	(signature = 16r3 and: [(libc strcmp: name with: 'core_tls_store_new') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsStoreNew:) to: 'uint64_t'].
	(signature = 16r383 and: [(libc strcmp: name with: 'core_tls_store_add') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsStoreAdd:) to: 'uint64_t'].
	(signature = 16r33 and: [(libc strcmp: name with: 'core_tls_store_free') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsStoreFree:) to: 'uint64_t'].
	(signature = 16r383 and: [(libc strcmp: name with: 'core_tls_new') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsOpen:) to: 'uint64_t'].
	(signature = 16r3893 and: [(libc strcmp: name with: 'core_tls_handshake') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsHandshake:) to: 'uint64_t'].
	(signature = 16r3983 and: [(libc strcmp: name with: 'core_tls_read') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsRead:) to: 'uint64_t'].
	(signature = 16r3893 and: [(libc strcmp: name with: 'core_tls_write') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsWrite:) to: 'uint64_t'].
	(signature = 16r393 and: [(libc strcmp: name with: 'core_tls_take') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsTake:) to: 'uint64_t'].
	(signature = 16r393 and: [(libc strcmp: name with: 'core_tls_close') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsClose:) to: 'uint64_t'].
	(signature = 16r3393 and: [(libc strcmp: name with: 'core_tls_info') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsInfo:) to: 'uint64_t'].
	(signature = 16r33 and: [(libc strcmp: name with: 'core_tls_free') = 0]) ifTrue: [^self cCoerce: (self functionPointer: #staticTlsRelease:) to: 'uint64_t'].
	^self staticCryptoEntry: name signature: signature
!
staticTlsSeed: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| bytes bytesLen |
	bytes := self local: 'uint64_t'.
	bytesLen := self local: 'uint64_t'.
	(wrappers ffiBorrowSlice: (args at: 0) into: bytes length: bytesLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsSeed: (self cCoerce: bytes value to: 'const uint8_t *') length: bytesLen value)
!
staticTlsSetTime: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| seconds |
	seconds := self local: 'int64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: seconds) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsSetTime: seconds value)
!
staticTlsStoreNew: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	^wrappers ffiBoxI64: (core nativeTlsStoreNew)
!
staticTlsStoreAdd: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| storeId der derLen |
	storeId := self local: 'int64_t'.
	der := self local: 'uint64_t'.
	derLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: storeId) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 1) into: der length: derLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsStoreAdd: storeId value der: (self cCoerce: der value to: 'const uint8_t *') length: derLen value)
!
staticTlsStoreFree: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| storeId |
	storeId := self local: 'int64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: storeId) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsStoreFree: storeId value)
!
staticTlsOpen: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| storeId host hostLen |
	storeId := self local: 'int64_t'.
	host := self local: 'uint64_t'.
	hostLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: storeId) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 1) into: host length: hostLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsOpen: storeId value host: (self cCoerce: host value to: 'const uint8_t *') length: hostLen value)
!
staticTlsHandshake: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| h in inLen out outLen |
	h := self local: 'int64_t'.
	in := self local: 'uint64_t'.
	inLen := self local: 'uint64_t'.
	out := self local: 'uint64_t'.
	outLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: h) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 1) into: in length: inLen) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 2) into: out length: outLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsHandshake: h value in: (self cCoerce: in value to: 'const uint8_t *') length: inLen value out: (self cCoerce: out value to: 'uint8_t *') length: outLen value)
!
staticTlsRead: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| h plain plainLen in inLen |
	h := self local: 'int64_t'.
	plain := self local: 'uint64_t'.
	plainLen := self local: 'uint64_t'.
	in := self local: 'uint64_t'.
	inLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: h) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 1) into: plain length: plainLen) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 2) into: in length: inLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsRead: h value into: (self cCoerce: plain value to: 'uint8_t *') length: plainLen value in: (self cCoerce: in value to: 'const uint8_t *') length: inLen value)
!
staticTlsWrite: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| h plain plainLen out outLen |
	h := self local: 'int64_t'.
	plain := self local: 'uint64_t'.
	plainLen := self local: 'uint64_t'.
	out := self local: 'uint64_t'.
	outLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: h) ifFalse: [^0].
	(wrappers ffiBorrowSlice: (args at: 1) into: plain length: plainLen) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 2) into: out length: outLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsWrite: h value bytes: (self cCoerce: plain value to: 'const uint8_t *') length: plainLen value out: (self cCoerce: out value to: 'uint8_t *') length: outLen value)
!
staticTlsTake: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| h out outLen |
	h := self local: 'int64_t'.
	out := self local: 'uint64_t'.
	outLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: h) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 1) into: out length: outLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsTake: h value out: (self cCoerce: out value to: 'uint8_t *') length: outLen value)
!
staticTlsClose: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| h out outLen |
	h := self local: 'int64_t'.
	out := self local: 'uint64_t'.
	outLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: h) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 1) into: out length: outLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsClose: h value out: (self cCoerce: out value to: 'uint8_t *') length: outLen value)
!
staticTlsInfo: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| h what out outLen |
	h := self local: 'int64_t'.
	what := self local: 'int64_t'.
	out := self local: 'uint64_t'.
	outLen := self local: 'uint64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: h) ifFalse: [^0].
	(wrappers ffiUnboxI64: (args at: 1) into: what) ifFalse: [^0].
	(wrappers ffiBorrowWritableSlice: (args at: 2) into: out length: outLen) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsInfo: h value what: what value into: (self cCoerce: out value to: 'uint8_t *') length: outLen value)
!
staticTlsRelease: args
	<function>
	<var: #args type: 'const oop *'>
	<returns: 'oop'>
	| h |
	h := self local: 'int64_t'.
	(wrappers ffiUnboxI64: (args at: 0) into: h) ifFalse: [^0].
	^wrappers ffiBoxI64: (core nativeTlsRelease: h value)
! !
