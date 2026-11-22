CLibrary subclass: #Neon
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Neon comment: 'The Advanced SIMD (NEON) intrinsics of the VM on arm64 (every arm64 CPU has them; SVE2 is 128 bits too on the CPUs this runs on, so NEON is the vector width): 16 bytes at a time, for the arm64 arch modules (NeonPixelRows, NeonByteBlocks). In the simulation a vector is a ByteArray of its bytes, lanes little-endian (uint8x16_t, uint16x8_t and uint32x4_t 16 bytes, uint8x8_t 8). A shift count (rsra:with:shift:, rshrn:shift:, rshrnHigh:with:shift:) must be a literal: it is an immediate of the instruction.'!

!Neon class methodsFor: 'declaring'!
headers
	^#('<arm_neon.h>')
!
typedefs
	^#((uint8x16_t opaque) (uint8x8_t opaque) (uint16x8_t opaque) (uint32x4_t opaque) (uint64x1_t opaque))
! !

!Neon class methodsFor: 'simulation'!
halves: aByteArray
	"The 16-bit lanes of aByteArray."
	^(1 to: aByteArray size // 2) collect: [:i | (aByteArray at: 2 * i - 1) + ((aByteArray at: 2 * i) bitShift: 8)]
!
bytesOfHalves: anArray
	| b |
	b := ByteArray new: anArray size * 2.
	anArray doWithIndex: [:h :i |
		b at: 2 * i - 1 put: (h bitAnd: 255).
		b at: 2 * i put: ((h bitShift: -8) bitAnd: 255)].
	^b
!
rounding: x shift: n
	"x >> n, rounded: (x + 2^(n-1)) >> n."
	^(x + (1 bitShift: n - 1)) bitShift: n negated
! !

!Neon methodsFor: 'lanes'!
dupU8: aByte
	"Each byte aByte."
	<c: 'uint8x16_t vdupq_n_u8(uint8_t v)'>
	^ByteArray new: 16 withAll: (aByte bitAnd: 255)
!
dupU32: aWord
	"Each 32-bit lane aWord."
	<c: 'uint32x4_t vdupq_n_u32(uint32_t v)'>
	| b |
	b := ByteArray new: 16.
	1 to: 16 do: [:i | b at: i put: ((aWord bitShift: (i - 1 \\ 4) * -8) bitAnd: 255)].
	^b
!
u8FromU32: v
	"The same bits as bytes."
	<c: 'uint8x16_t vreinterpretq_u8_u32(uint32x4_t v)'>
	^v
!
create: bits
	"The 8 bytes of a 64-bit word, the least significant first."
	<c: 'uint8x8_t vcreate_u8(uint64_t bits)'>
	^((0 to: 7) collect: [:i | (bits bitShift: i * -8) bitAnd: 255]) asByteArray
!
combine: low with: high
	"low's 8 bytes, then high's."
	<c: 'uint8x16_t vcombine_u8(uint8x8_t low, uint8x8_t high)'>
	^low , high
!
low: v
	"The first 8 bytes."
	<c: 'uint8x8_t vget_low_u8(uint8x16_t v)'>
	^v copyFrom: 1 to: 8
! !

!Neon methodsFor: 'memory'!
load: p
	"The 16 bytes at p, aligned or not."
	<c: 'uint8x16_t vld1q_u8(const uint8_t *p)'>
	^self memory bytesAt: (self memory addressOf: p) count: 16
!
store: p value: v
	"v's 16 bytes at p, aligned or not."
	<c: 'void vst1q_u8(uint8_t *p, uint8x16_t v)'>
	self memory bytesAt: (self memory addressOf: p) put: v.
	^nil
!
storeU32: p value: v
	"v's four 32-bit lanes at p."
	<c: 'void vst1q_u32(uint32_t *p, uint32x4_t v)'>
	self memory bytesAt: (self memory addressOf: p) put: v.
	^nil
! !

!Neon methodsFor: 'arithmetic'!
mull: a with: b
	"The products of the 8 bytes of a and b, 16 bits each."
	<c: 'uint16x8_t vmull_u8(uint8x8_t a, uint8x8_t b)'>
	^Neon bytesOfHalves: ((1 to: 8) collect: [:i | (a at: i) * (b at: i)])
!
mullHigh: a with: b
	"The products of the last 8 bytes of a and b, 16 bits each."
	<c: 'uint16x8_t vmull_high_u8(uint8x16_t a, uint8x16_t b)'>
	^Neon bytesOfHalves: ((9 to: 16) collect: [:i | (a at: i) * (b at: i)])
!
rsra: a with: b shift: n
	"Each 16-bit lane of a plus b's shifted right by n, rounded (modulo 2^16)."
	<c: 'uint16x8_t vrsraq_n_u16(uint16x8_t a, uint16x8_t b, const int n)'>
	| x y |
	x := Neon halves: a.
	y := Neon halves: b.
	^Neon bytesOfHalves: ((1 to: 8) collect: [:i | (x at: i) + (Neon rounding: (y at: i) shift: n) bitAnd: 16rFFFF])
!
rshrn: a shift: n
	"Each 16-bit lane of a shifted right by n, rounded, as a byte (its low 8 bits)."
	<c: 'uint8x8_t vrshrn_n_u16(uint16x8_t a, const int n)'>
	^((Neon halves: a) collect: [:h | (Neon rounding: h shift: n) bitAnd: 255]) asByteArray
!
rshrnHigh: low with: a shift: n
	"low's 8 bytes, then rshrn: a shift: n."
	<c: 'uint8x16_t vrshrn_high_n_u16(uint8x8_t low, uint16x8_t a, const int n)'>
	^low , (self rshrn: a shift: n)
!
qadd: a with: b
	"The sums of the bytes, saturated at 255."
	<c: 'uint8x16_t vqaddq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) + (b at: i) min: 255]) asByteArray
!
not: a
	"Each byte 255 minus a's."
	<c: 'uint8x16_t vmvnq_u8(uint8x16_t a)'>
	^(a asArray collect: [:x | 255 - x]) asByteArray
! !

!Neon methodsFor: 'permuting'!
tbl: t index: idx
	"Byte i is t's byte idx[i], 0 if idx[i] > 15."
	<c: 'uint8x16_t vqtbl1q_u8(uint8x16_t t, uint8x16_t idx)'>
	^(idx asArray collect: [:k | k < 16 ifTrue: [t at: k + 1] ifFalse: [0]]) asByteArray
! !

!Neon methodsFor: 'bytes'!
eq: a with: b
	"Each byte 255 where a's equals b's, else 0."
	<c: 'uint8x16_t vceqq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) = (b at: i) ifTrue: [255] ifFalse: [0]]) asByteArray
!
lt: a with: b
	"Each byte 255 where a's is below b's (unsigned), else 0."
	<c: 'uint8x16_t vcltq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) < (b at: i) ifTrue: [255] ifFalse: [0]]) asByteArray
!
and: a with: b
	<c: 'uint8x16_t vandq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) bitAnd: (b at: i)]) asByteArray
!
or: a with: b
	<c: 'uint8x16_t vorrq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) bitOr: (b at: i)]) asByteArray
!
bic: a with: b
	"a's bits that are not b's."
	<c: 'uint8x16_t vbicq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) bitClear: (b at: i)]) asByteArray
!
add: a with: b
	"The sums of the bytes, modulo 256."
	<c: 'uint8x16_t vaddq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) + (b at: i) bitAnd: 255]) asByteArray
!
sub: a with: b
	"The differences of the bytes, modulo 256."
	<c: 'uint8x16_t vsubq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) - (b at: i) bitAnd: 255]) asByteArray
!
max: a
	"The largest byte."
	<c: 'uint8_t vmaxvq_u8(uint8x16_t a)'>
	^a inject: 0 into: [:m :x | m max: x]
!
u16FromU8: v
	"The same bits as 16-bit lanes."
	<c: 'uint16x8_t vreinterpretq_u16_u8(uint8x16_t v)'>
	^v
!
shrn: a shift: n
	"Each 16-bit lane of a shifted right by n, as a byte (its low 8 bits). With n = 4, of bytes that are 0 or 255: 4 bits a byte."
	<c: 'uint8x8_t vshrn_n_u16(uint16x8_t a, const int n)'>
	^((Neon halves: a) collect: [:h | (h bitShift: n negated) bitAnd: 255]) asByteArray
!
u64FromU8x8: v
	"The same bits as one 64-bit lane."
	<c: 'uint64x1_t vreinterpret_u64_u8(uint8x8_t v)'>
	^v
!
lane: v at: k
	"Lane k of a vector of one 64-bit lane (k = 0)."
	<c: 'uint64_t vget_lane_u64(uint64x1_t v, const int k)'>
	^(1 to: 8) inject: 0 into: [:w :i | w + ((v at: i) bitShift: (i - 1) * 8)]
! !

!Neon class methodsFor: 'simulation'!
words: aByteArray
	"The 32-bit lanes of aByteArray."
	^(1 to: aByteArray size // 4) collect: [:i | (1 to: 4) inject: 0 into: [:w :k | w + ((aByteArray at: 4 * i - 4 + k) bitShift: (k - 1) * 8)]]
!
bytesOfWords: anArray
	| b |
	b := ByteArray new: anArray size * 4.
	anArray doWithIndex: [:w :i | 1 to: 4 do: [:k | b at: 4 * i - 4 + k put: ((w bitShift: (k - 1) * -8) bitAnd: 255)]].
	^b
! !

!Neon methodsFor: 'lanes'!
dupU16: aHalf
	"Each 16-bit lane aHalf."
	<c: 'uint16x8_t vdupq_n_u16(uint16_t v)'>
	^Neon bytesOfHalves: (Array new: 8 withAll: (aHalf bitAnd: 16rFFFF))
! !

!Neon methodsFor: 'filtering'!
hadd: a with: b
	"(a + b) >> 1 of each pair of bytes, without overflow."
	<c: 'uint8x16_t vhaddq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) + (b at: i) bitShift: -1]) asByteArray
!
abd: a with: b
	"|a - b| of each pair of bytes."
	<c: 'uint8x16_t vabdq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | ((a at: i) - (b at: i)) abs]) asByteArray
!
min: a with: b
	"The smaller of each pair of bytes."
	<c: 'uint8x16_t vminq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) min: (b at: i)]) asByteArray
!
le: a with: b
	"Each byte 255 where a's is at most b's (unsigned), else 0."
	<c: 'uint8x16_t vcleq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) <= (b at: i) ifTrue: [255] ifFalse: [0]]) asByteArray
!
ge: a with: b
	"Each byte 255 where a's is at least b's (unsigned), else 0."
	<c: 'uint8x16_t vcgeq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) >= (b at: i) ifTrue: [255] ifFalse: [0]]) asByteArray
!
xor: a with: b
	<c: 'uint8x16_t veorq_u8(uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | (a at: i) bitXor: (b at: i)]) asByteArray
!
bsl: mask with: a with: b
	"a's bits where mask has ones, b's where it has zeros."
	<c: 'uint8x16_t vbslq_u8(uint8x16_t mask, uint8x16_t a, uint8x16_t b)'>
	^((1 to: 16) collect: [:i | ((mask at: i) bitAnd: (a at: i)) bitOr: ((mask at: i) bitInvert bitAnd: (b at: i))]) asByteArray
!
padal: a with: b
	"Each 16-bit lane of a plus the two bytes of b in it (modulo 2^16)."
	<c: 'uint16x8_t vpadalq_u8(uint16x8_t a, uint8x16_t b)'>
	^Neon bytesOfHalves: ((Neon halves: a) collectWithIndex: [:h :i | h + (b at: 2 * i - 1) + (b at: 2 * i) bitAnd: 16rFFFF])
!
padalU16: a with: b
	"Each 32-bit lane of a plus the two 16-bit lanes of b in it (modulo 2^32)."
	<c: 'uint32x4_t vpadalq_u16(uint32x4_t a, uint16x8_t b)'>
	| h |
	h := Neon halves: b.
	^Neon bytesOfWords: ((Neon words: a) collectWithIndex: [:w :i | w + (h at: 2 * i - 1) + (h at: 2 * i) bitAnd: 16rFFFFFFFF])
!
addvU32: a
	"The sum of the 32-bit lanes (modulo 2^32)."
	<c: 'uint32_t vaddvq_u32(uint32x4_t a)'>
	^(Neon words: a) inject: 0 into: [:s :w | s + w bitAnd: 16rFFFFFFFF]
! !
