!FFIPrimitives methodsFor: 'bytes exports'!
nativeBytesMismatch: a size: aSize at: start with: b size: bSize at: otherStart count: n
	"ByteArray>>indexOfMismatchAt:with:at:size: (once primitive 119): the first i in 1 .. n where byte start + i - 1 of a and byte otherStart + i - 1 of b differ (ByteSearch, a block at a time), 0 if none does; -1 if a range is outside."
	<function>
	<approvedFFI: 119 symbol: 'core_bytes_mismatch' arguments: #(17 3 17 3 3) result: 3>
	<var: #a type: 'const uint8_t *'>
	<var: #aSize type: 'uint64_t'>
	<var: #start type: 'int64_t'>
	<var: #b type: 'const uint8_t *'>
	<var: #bSize type: 'uint64_t'>
	<var: #otherStart type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	| k |
	((self range: start count: n within: aSize) and: [self range: otherStart count: n within: bSize]) ifFalse: [^-1].
	k := search
		mismatchOf: (self cCoerce: a to: 'uint8_t *') + (start - 1)
		with: (self cCoerce: b to: 'uint8_t *') + (otherStart - 1)
		from: 0
		size: n.
	^k = n ifTrue: [0] ifFalse: [k + 1]
!
nativeBytesLastMismatch: a size: aSize at: start with: b size: bSize at: otherStart count: n
	"ByteArray>>lastIndexOfMismatchAt:with:at:size: (once primitive 122): as nativeBytesMismatch:..., the last such i."
	<function>
	<approvedFFI: 122 symbol: 'core_bytes_last_mismatch' arguments: #(17 3 17 3 3) result: 3>
	<var: #a type: 'const uint8_t *'>
	<var: #aSize type: 'uint64_t'>
	<var: #start type: 'int64_t'>
	<var: #b type: 'const uint8_t *'>
	<var: #bSize type: 'uint64_t'>
	<var: #otherStart type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	((self range: start count: n within: aSize) and: [self range: otherStart count: n within: bSize]) ifFalse: [^-1].
	^(search
		lastMismatchOf: (self cCoerce: a to: 'uint8_t *') + (start - 1)
		with: (self cCoerce: b to: 'uint8_t *') + (otherStart - 1)
		size: n) + 1
!
nativePngFilter: rgba size: rgbaSize width: w height: h channels: n into: raw size: rawSize
	"PNGWriter class>>filtered:width:height:channels: (once primitive 207): raw := the PNG rows of rgba (w * h pixels of 4 bytes, rows top to bottom), each its filter type byte and its pixels packed to n channels (3: alpha dropped, 4), filtered with the filter of the smallest cost (PngFilter, 16 bytes at a time); 0, or -1 unless rgba and raw are distinct, of w * h * 4 and (w * n + 1) * h bytes, 1 <= w, h <= 2^22 and n 3 or 4."
	<function>
	<approvedFFI: 207 symbol: 'core_png_filter' arguments: #(17 3 3 3 18) result: 3>
	<var: #rgba type: 'const uint8_t *'>
	<var: #rgbaSize type: 'uint64_t'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<var: #raw type: 'uint8_t *'>
	<var: #rawSize type: 'uint64_t'>
	<returns: 'int64_t'>
	((w >= 1 and: [w <= 16r400000]) and: [(h >= 1 and: [h <= 16r400000]) and: [n = 3 or: [n = 4]]]) ifFalse: [^-1].
	(rgbaSize = (w * h * 4) asUInt64 and: [rawSize = ((w * n + 1) * h) asUInt64]) ifFalse: [^-1].
	(self cCoerce: rgba to: 'uint64_t') = (self cCoerce: raw to: 'uint64_t') ifTrue: [^-1].
	png filterPng: (self cCoerce: rgba to: 'uint8_t *') width: w height: h channels: n into: raw.
	^0
!
nativeRawBytesReplace: dst size: dstSize from: start to: stop with: src size: srcSize at: s
	"ByteArray>>replaceFrom:to:withRawBytesOf:startingAt: (once primitive 212): dst's bytes start to stop (1-based) := src's memory from its byte s (bytes, or words as the CPU stores them; the two may overlap); 0, or -1 unless both ranges are inside."
	<function>
	<approvedFFI: 212 symbol: 'core_raw_bytes_replace' arguments: #(18 3 3 17 3) result: 3>
	<var: #dst type: 'uint8_t *'>
	<var: #dstSize type: 'uint64_t'>
	<var: #start type: 'int64_t'>
	<var: #stop type: 'int64_t'>
	<var: #src type: 'const uint8_t *'>
	<var: #srcSize type: 'uint64_t'>
	<var: #s type: 'int64_t'>
	<returns: 'int64_t'>
	| n |
	n := stop - start + 1.
	((self range: start count: n within: dstSize) and: [self range: s count: n within: srcSize]) ifFalse: [^-1].
	libc memmove: dst + (start - 1) from: (self cCoerce: src to: 'uint8_t *') + (s - 1) size: n asUInt64.
	^0
!
range: start count: n within: size
	"Whether the n bytes from the 1-based start are inside size bytes."
	<function>
	<var: #start type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<var: #size type: 'uint64_t'>
	<returns: 'bool'>
	^start >= 1 and: [n >= 0 and: [(start - 1) asUInt64 <= size and: [n asUInt64 <= (size - (start - 1) asUInt64)]]]
! !
