!FFIPrimitives methodsFor: '*VM-Jit'!
arityMix: h with: v
	"One FNV-1a step over a 64-bit lane, as tests/vm/ffi_arity.st and ffi_arity_fixture.c hash arguments."
	<function>
	<var: #h type: 'uint64_t'>
	<var: #v type: 'uint64_t'>
	<returns: 'uint64_t'>
	^(h bitXor: v) * 16r100000001B3
!
arityMix: h float: f
	<function>
	<var: #h type: 'uint64_t'>
	<var: #f type: 'float'>
	<returns: 'uint64_t'>
	| bits x |
	bits := self local: 'uint32_t'.
	x := self local: 'float'.
	x value: f.
	libc memcpy: bits from: x size: 4.
	^self arityMix: h with: bits value asUInt64
!
arityMix: h bytes: p length: n
	<function>
	<var: #h type: 'uint64_t'>
	<var: #p type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #g type: 'uint64_t'>
	<returns: 'uint64_t'>
	| g |
	g := h.
	0 to: n asInt64 - 1 do: [:i | g := self arityMix: g with: (p at: i) asUInt64].
	^self arityMix: g with: n
!
ffiTestArity7: a b: b c: c d: d e: e f: f g: g
	<function>
	<approvedFFI: 4089 symbol: 'ffi_test_arity7' arguments: #(1 3 2 4 1 3 1) result: 4>
	<approvedFFITest>
	<var: #a type: 'int32_t'>
	<var: #b type: 'int64_t'>
	<var: #c type: 'uint32_t'>
	<var: #d type: 'uint64_t'>
	<var: #e type: 'int32_t'>
	<var: #f type: 'int64_t'>
	<var: #g type: 'int32_t'>
	<var: #h type: 'uint64_t'>
	<returns: 'uint64_t'>
	| h |
	h := self arityMix: 16rCBF29CE484222325 asUInt64 with: a asInt64 asUInt64.
	h := self arityMix: h with: b asUInt64.
	h := self arityMix: h with: c asUInt64.
	h := self arityMix: h with: d.
	h := self arityMix: h with: e asInt64 asUInt64.
	h := self arityMix: h with: f asUInt64.
	^self arityMix: h with: g asInt64 asUInt64
!
ffiTestArity8: a b: b c: c d: d e: e f: f g: g bytes: p length: n
	"Hash, then increment the writable slice's bytes."
	<function>
	<approvedFFI: 4090 symbol: 'ffi_test_arity8' arguments: #(1 3 1 3 1 3 1 9) result: 4>
	<approvedFFITest>
	<var: #a type: 'int32_t'>
	<var: #b type: 'int64_t'>
	<var: #c type: 'int32_t'>
	<var: #d type: 'int64_t'>
	<var: #e type: 'int32_t'>
	<var: #f type: 'int64_t'>
	<var: #g type: 'int32_t'>
	<var: #p type: 'uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #h type: 'uint64_t'>
	<returns: 'uint64_t'>
	| h |
	h := self arityMix: 16rCBF29CE484222325 asUInt64 with: a asInt64 asUInt64.
	h := self arityMix: h with: b asUInt64.
	h := self arityMix: h with: c asInt64 asUInt64.
	h := self arityMix: h with: d asUInt64.
	h := self arityMix: h with: e asInt64 asUInt64.
	h := self arityMix: h with: f asUInt64.
	h := self arityMix: h with: g asInt64 asUInt64.
	h := self arityMix: h bytes: p length: n.
	0 to: n asInt64 - 1 do: [:i | p at: i put: ((p at: i) + 1) asUInt8].
	^h
!
ffiTestArity9: a b: b c: c d: d e: e bytes: p length: n f: f g: g i: i
	<function>
	<approvedFFI: 4091 symbol: 'ffi_test_arity9' arguments: #(1 3 1 3 1 8 6 16 3) result: 16>
	<approvedFFITest>
	<var: #a type: 'int32_t'>
	<var: #b type: 'int64_t'>
	<var: #c type: 'int32_t'>
	<var: #d type: 'int64_t'>
	<var: #e type: 'int32_t'>
	<var: #p type: 'const uint8_t *'>
	<var: #n type: 'uint64_t'>
	<var: #f type: 'double'>
	<var: #g type: 'float'>
	<var: #i type: 'int64_t'>
	<var: #h type: 'uint64_t'>
	<returns: 'float'>
	| h |
	h := self arityMix: 16rCBF29CE484222325 asUInt64 with: a asInt64 asUInt64.
	h := self arityMix: h with: b asUInt64.
	h := self arityMix: h with: c asInt64 asUInt64.
	h := self arityMix: h with: d asUInt64.
	h := self arityMix: h with: e asInt64 asUInt64.
	h := self arityMix: h bytes: p length: n.
	h := self arityMix: h with: (self bitsOfDouble: f).
	h := self arityMix: h float: g.
	h := self arityMix: h with: i asUInt64.
	^self cCoerce: (h bitAnd: 16rFFFFFF) to: 'float'
!
ffiTestArity14: handle transa: transa transb: transb m: m n: n k: k alpha: alpha length: alphaLength a: a lda: lda b: b ldb: ldb beta: beta length: betaLength c: c ldc: ldc
	"cublasSgemm's shape, with alpha and beta as slices."
	<function>
	<approvedFFI: 4092 symbol: 'ffi_test_arity14' arguments: #(4 1 1 1 1 1 8 4 1 4 1 8 4 1) result: 4>
	<approvedFFITest>
	<var: #handle type: 'uint64_t'>
	<var: #transa type: 'int32_t'>
	<var: #transb type: 'int32_t'>
	<var: #m type: 'int32_t'>
	<var: #n type: 'int32_t'>
	<var: #k type: 'int32_t'>
	<var: #alpha type: 'const uint8_t *'>
	<var: #alphaLength type: 'uint64_t'>
	<var: #a type: 'uint64_t'>
	<var: #lda type: 'int32_t'>
	<var: #b type: 'uint64_t'>
	<var: #ldb type: 'int32_t'>
	<var: #beta type: 'const uint8_t *'>
	<var: #betaLength type: 'uint64_t'>
	<var: #c type: 'uint64_t'>
	<var: #ldc type: 'int32_t'>
	<var: #h type: 'uint64_t'>
	<returns: 'uint64_t'>
	| h |
	h := self arityMix: 16rCBF29CE484222325 asUInt64 with: handle.
	h := self arityMix: h with: transa asInt64 asUInt64.
	h := self arityMix: h with: transb asInt64 asUInt64.
	h := self arityMix: h with: m asInt64 asUInt64.
	h := self arityMix: h with: n asInt64 asUInt64.
	h := self arityMix: h with: k asInt64 asUInt64.
	h := self arityMix: h bytes: alpha length: alphaLength.
	h := self arityMix: h with: a.
	h := self arityMix: h with: lda asInt64 asUInt64.
	h := self arityMix: h with: b.
	h := self arityMix: h with: ldb asInt64 asUInt64.
	h := self arityMix: h bytes: beta length: betaLength.
	h := self arityMix: h with: c.
	^self arityMix: h with: ldc asInt64 asUInt64
!
ffiTestArity16: a b: b c: c d: d e: e f: f g: g i: i j: j k: k l: l m: m n: n o: o p: p q: q
	<function>
	<approvedFFI: 4093 symbol: 'ffi_test_arity16' arguments: #(6 1 16 3 6 2 16 4 6 1 16 3 6 1 16 6) result: 6>
	<approvedFFITest>
	<var: #a type: 'double'>
	<var: #b type: 'int32_t'>
	<var: #c type: 'float'>
	<var: #d type: 'int64_t'>
	<var: #e type: 'double'>
	<var: #f type: 'uint32_t'>
	<var: #g type: 'float'>
	<var: #i type: 'uint64_t'>
	<var: #j type: 'double'>
	<var: #k type: 'int32_t'>
	<var: #l type: 'float'>
	<var: #m type: 'int64_t'>
	<var: #n type: 'double'>
	<var: #o type: 'int32_t'>
	<var: #p type: 'float'>
	<var: #q type: 'double'>
	<var: #h type: 'uint64_t'>
	<returns: 'double'>
	| h |
	h := self arityMix: 16rCBF29CE484222325 asUInt64 with: (self bitsOfDouble: a).
	h := self arityMix: h with: b asInt64 asUInt64.
	h := self arityMix: h float: c.
	h := self arityMix: h with: d asUInt64.
	h := self arityMix: h with: (self bitsOfDouble: e).
	h := self arityMix: h with: f asUInt64.
	h := self arityMix: h float: g.
	h := self arityMix: h with: i.
	h := self arityMix: h with: (self bitsOfDouble: j).
	h := self arityMix: h with: k asInt64 asUInt64.
	h := self arityMix: h float: l.
	h := self arityMix: h with: m asUInt64.
	h := self arityMix: h with: (self bitsOfDouble: n).
	h := self arityMix: h with: o asInt64 asUInt64.
	h := self arityMix: h float: p.
	h := self arityMix: h with: (self bitsOfDouble: q).
	^self cCoerce: h >> 11 to: 'double'
! !
