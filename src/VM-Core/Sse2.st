CLibrary subclass: #Sse2
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Sse2 comment: 'The SSE2 intrinsics of the VM (every x86-64 CPU has SSE2): 16 bytes at a time. A __m128i is a ByteArray of 16 in the simulation.'!

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
