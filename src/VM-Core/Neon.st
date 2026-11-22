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
	^#((uint8x16_t opaque) (uint8x8_t opaque) (uint16x8_t opaque) (uint32x4_t opaque))
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
