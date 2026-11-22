CLibrary subclass: #Sse2
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Sse2 comment: 'The SSE2 intrinsics of the VM (every x86-64 CPU has SSE2): 16 bytes at a time, for the x86-64 arch modules (Sse2ByteBlocks, Sse2PixelRows). A __m128i is a ByteArray of 16 in the simulation, lanes little-endian. A shift count or a shuffle''s selector must be a literal: it is an immediate of the instruction.'!

!Sse2 class methodsFor: 'declaring'!
headers
	^#('<emmintrin.h>')
!
typedefs
	^#((__m128i opaque))
! !

!Sse2 methodsFor: 'bytes'!
set1: aByte
	"Each byte aByte."
	<c: '__m128i _mm_set1_epi8(char b)'>
	^ByteArray new: 16 withAll: (aByte bitAnd: 255)
!
loadu: p
	"The 16 bytes at p, aligned or not."
	<c: '__m128i _mm_loadu_si128(const __m128i *p)'>
	^self memory bytesAt: (self memory addressOf: p) count: 16
!
cmpeq: a with: b
	"Each byte 255 where a's equals b's, else 0."
	<c: '__m128i _mm_cmpeq_epi8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) = (b at: i) ifTrue: [255] ifFalse: [0]]) asByteArray
!
and: a with: b
	<c: '__m128i _mm_and_si128(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) bitAnd: (b at: i)]) asByteArray
!
movemask: a
	"Bit i set if byte i has its top bit set."
	<c: 'int _mm_movemask_epi8(__m128i a)'>
	| m |
	m := 0.
	16 to: 1 by: -1 do: [:i | m := (m bitShift: 1) bitOr: ((a at: i) bitShift: -7)].
	^m
! !

!Sse2 class methodsFor: 'simulation'!
lanes: aByteArray width: n
	"The n-byte lanes of aByteArray, unsigned."
	^(1 to: 16 // n) collect: [:i | | v | v := 0. n to: 1 by: -1 do: [:k | v := (v bitShift: 8) + (aByteArray at: i - 1 * n + k)]. v]
!
bytesOfLanes: anArray width: n
	| b |
	b := ByteArray new: 16.
	anArray doWithIndex: [:v :i | 1 to: n do: [:k | b at: i - 1 * n + k put: ((v bitShift: (k - 1) * -8) bitAnd: 255)]].
	^b
!
lanesOf: a and: b width: n collect: aBlock
	"The lanes aBlock answers for each pair of a's and b's n-byte lanes, modulo 2^(8n)."
	| x y |
	x := self lanes: a width: n.
	y := self lanes: b width: n.
	^self bytesOfLanes: ((1 to: x size) collect: [:i | (aBlock value: (x at: i) value: (y at: i)) bitAnd: (1 bitShift: 8 * n) - 1]) width: n
! !

!Sse2 methodsFor: 'lanes'!
set1U16: aHalf
	"Each 16-bit lane aHalf."
	<c: '__m128i _mm_set1_epi16(short h)'>
	^Sse2 bytesOfLanes: (Array new: 8 withAll: (aHalf bitAnd: 16rFFFF)) width: 2
!
set1U32: aWord
	"Each 32-bit lane aWord."
	<c: '__m128i _mm_set1_epi32(int w)'>
	^Sse2 bytesOfLanes: (Array new: 4 withAll: (aWord bitAnd: 16rFFFFFFFF)) width: 4
!
zero
	<c: '__m128i _mm_setzero_si128(void)'>
	^ByteArray new: 16
!
storeu: p value: v
	"v's 16 bytes at p, aligned or not."
	<c: 'void _mm_storeu_si128(__m128i *p, __m128i v)'>
	self memory bytesAt: (self memory addressOf: p) put: v.
	^nil
! !

!Sse2 methodsFor: 'bits'!
or: a with: b
	<c: '__m128i _mm_or_si128(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) bitOr: (b at: i)]) asByteArray
!
srli32: a count: n
	"Each 32-bit lane shifted right by n, zeros in."
	<c: '__m128i _mm_srli_epi32(__m128i a, int n)'>
	^Sse2 bytesOfLanes: ((Sse2 lanes: a width: 4) collect: [:v | v bitShift: n negated]) width: 4
!
slli32: a count: n
	"Each 32-bit lane shifted left by n."
	<c: '__m128i _mm_slli_epi32(__m128i a, int n)'>
	^Sse2 bytesOfLanes: ((Sse2 lanes: a width: 4) collect: [:v | (v bitShift: n) bitAnd: 16rFFFFFFFF]) width: 4
!
srli64: a count: n
	"Each 64-bit lane shifted right by n, zeros in."
	<c: '__m128i _mm_srli_epi64(__m128i a, int n)'>
	^Sse2 bytesOfLanes: ((Sse2 lanes: a width: 8) collect: [:v | v bitShift: n negated]) width: 8
!
slli64: a count: n
	"Each 64-bit lane shifted left by n."
	<c: '__m128i _mm_slli_epi64(__m128i a, int n)'>
	^Sse2 bytesOfLanes: ((Sse2 lanes: a width: 8) collect: [:v | (v bitShift: n) bitAnd: 16rFFFFFFFFFFFFFFFF]) width: 8
!
srliBytes: a count: n
	"The 16 bytes moved n places down (byte i is a's byte i + n), zeros in; n a literal."
	<c: '__m128i _mm_srli_si128(__m128i a, int n)'>
	^((1 to: 16) collect: [:i | i + n <= 16 ifTrue: [a at: i + n] ifFalse: [0]]) asByteArray
!
slliBytes: a count: n
	"The 16 bytes moved n places up (byte i is a's byte i - n), zeros in; n a literal."
	<c: '__m128i _mm_slli_si128(__m128i a, int n)'>
	^((1 to: 16) collect: [:i | i - n >= 1 ifTrue: [a at: i - n] ifFalse: [0]]) asByteArray
!
srli16: a count: n
	"Each 16-bit lane shifted right by n, zeros in."
	<c: '__m128i _mm_srli_epi16(__m128i a, int n)'>
	^Sse2 bytesOfLanes: ((Sse2 lanes: a width: 2) collect: [:v | v bitShift: n negated]) width: 2
! !

!Sse2 methodsFor: 'arithmetic'!
add16: a with: b
	<c: '__m128i _mm_add_epi16(__m128i a, __m128i b)'>
	^Sse2 lanesOf: a and: b width: 2 collect: [:x :y | x + y]
!
sub16: a with: b
	<c: '__m128i _mm_sub_epi16(__m128i a, __m128i b)'>
	^Sse2 lanesOf: a and: b width: 2 collect: [:x :y | x - y]
!
mullo16: a with: b
	"The low 16 bits of the products of the 16-bit lanes."
	<c: '__m128i _mm_mullo_epi16(__m128i a, __m128i b)'>
	^Sse2 lanesOf: a and: b width: 2 collect: [:x :y | x * y]
!
addsU8: a with: b
	"The sums of the bytes, saturated at 255."
	<c: '__m128i _mm_adds_epu8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) + (b at: i) min: 255]) asByteArray
! !

!Sse2 methodsFor: 'permuting'!
unpackLow8: a with: b
	"The first 8 bytes of a and b, interleaved: a0 b0 a1 b1 ..."
	<c: '__m128i _mm_unpacklo_epi8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | i odd ifTrue: [a at: i + 1 // 2] ifFalse: [b at: i // 2]]) asByteArray
!
unpackHigh8: a with: b
	"The last 8 bytes of a and b, interleaved."
	<c: '__m128i _mm_unpackhi_epi8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | i odd ifTrue: [a at: i + 1 // 2 + 8] ifFalse: [b at: i // 2 + 8]]) asByteArray
!
packus16: a with: b
	"The signed 16-bit lanes of a, then b's, as bytes saturated to 0..255."
	<c: '__m128i _mm_packus_epi16(__m128i a, __m128i b)'>
	^(((Sse2 lanes: a width: 2) , (Sse2 lanes: b width: 2)) collect: [:v | | s | s := v >= 16r8000 ifTrue: [v - 16r10000] ifFalse: [v]. (s max: 0) min: 255]) asByteArray
!
shuffleLow16: a select: imm
	"The first four 16-bit lanes chosen by the 2-bit fields of imm, the last four as they are."
	<c: '__m128i _mm_shufflelo_epi16(__m128i a, int imm)'>
	| x |
	x := Sse2 lanes: a width: 2.
	^Sse2 bytesOfLanes: ((1 to: 8) collect: [:i | i <= 4 ifTrue: [x at: ((imm bitShift: (i - 1) * -2) bitAnd: 3) + 1] ifFalse: [x at: i]]) width: 2
!
shuffleHigh16: a select: imm
	"The last four 16-bit lanes chosen by the 2-bit fields of imm, the first four as they are."
	<c: '__m128i _mm_shufflehi_epi16(__m128i a, int imm)'>
	| x |
	x := Sse2 lanes: a width: 2.
	^Sse2 bytesOfLanes: ((1 to: 8) collect: [:i | i > 4 ifTrue: [x at: ((imm bitShift: (i - 5) * -2) bitAnd: 3) + 5] ifFalse: [x at: i]]) width: 2
! !

!Sse2 methodsFor: 'bytes'!
add8: a with: b
	"The sums of the bytes, modulo 256."
	<c: '__m128i _mm_add_epi8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) + (b at: i) bitAnd: 255]) asByteArray
!
sub8: a with: b
	"The differences of the bytes, modulo 256."
	<c: '__m128i _mm_sub_epi8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) - (b at: i) bitAnd: 255]) asByteArray
!
minU8: a with: b
	"The smaller of each pair of bytes, unsigned."
	<c: '__m128i _mm_min_epu8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) min: (b at: i)]) asByteArray
!
andNot: a with: b
	"b's bits that are not a's."
	<c: '__m128i _mm_andnot_si128(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (b at: i) bitClear: (a at: i)]) asByteArray
! !

!Sse2 methodsFor: 'filtering'!
subsU8: a with: b
	"a - b of each pair of bytes, saturated at 0."
	<c: '__m128i _mm_subs_epu8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) - (b at: i) max: 0]) asByteArray
!
avgU8: a with: b
	"(a + b + 1) >> 1 of each pair of bytes."
	<c: '__m128i _mm_avg_epu8(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) + (b at: i) + 1 bitShift: -1]) asByteArray
!
xor: a with: b
	<c: '__m128i _mm_xor_si128(__m128i a, __m128i b)'>
	^((1 to: 16) collect: [:i | (a at: i) bitXor: (b at: i)]) asByteArray
!
sadU8: a with: b
	"The sums of |a - b| of each 8 bytes, in the two 64-bit lanes."
	<c: '__m128i _mm_sad_epu8(__m128i a, __m128i b)'>
	^Sse2 bytesOfLanes: ((0 to: 1) collect: [:h | (1 to: 8) inject: 0 into: [:s :i | s + ((a at: 8 * h + i) - (b at: 8 * h + i)) abs]]) width: 8
!
add64: a with: b
	<c: '__m128i _mm_add_epi64(__m128i a, __m128i b)'>
	^Sse2 lanesOf: a and: b width: 8 collect: [:x :y | x + y]
!
unpackHigh64: a with: b
	"The last 64-bit lane of a, then b's."
	<c: '__m128i _mm_unpackhi_epi64(__m128i a, __m128i b)'>
	^(a copyFrom: 9 to: 16) , (b copyFrom: 9 to: 16)
!
low64: a
	"The first 64-bit lane, signed."
	<c: 'int64_t _mm_cvtsi128_si64(__m128i a)'>
	| v |
	v := (Sse2 lanes: a width: 8) first.
	^v >= (1 bitShift: 63) ifTrue: [v - (1 bitShift: 64)] ifFalse: [v]
! !
