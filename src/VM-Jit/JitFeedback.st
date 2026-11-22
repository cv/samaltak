VMCoreModule subclass: #JitFeedback
	instanceVariableNames: 'fbSites fbCount fbYoung fbFloats'
	classVariableNames: 'FB_CLASSES FB_FLOAT_BITS FB_INTS FB_DEOPT_ARITH FB_DEOPT_BOUNDS FB_DEOPT_CLASS FB_DEOPT_HOISTED FB_DEOPT_OTHER FB_FLOAT FB_MAX FB_MEGA FB_NONINT FB_OVERFLOW'
	package: 'VM-Jit'!

JitFeedback comment: 'Type feedback for the optimizing tier, independent of the compiler that collects it: one FeedbackSite per (method, bytecode pc), in an open-addressed table keyed by the method''s identity hash and the pc. A site holds up to FB_CLASSES receiver classes with counts (FB_MEGA once more were seen) and profile bits: FB_FLOAT (an arithmetic or comparison saw a Float operand), FB_NONINT (one that was neither SmallInteger nor Float), FB_OVERFLOW (SmallInteger arithmetic overflowed), FB_DEOPT_* (optimized code deoptimized here: a class guard, an arithmetic guard, a bounds check, anything else, a guard moved before a loop: it stays in the loop from then on).

Lower tiers report into it (docs/jit.md, Optimizing tier): noteSend:pc:class: when a send site sees a class (baseline code on a miss of its inline cache), noteFlags:pc:flags: for profile bits; machine code sets FB_FLOAT without a call, in a byte of fbFloats (floatBitAddressFor:pc:, shared by hash). The optimizer reads sites with siteAt:pc: and flagsAt:pc:. Methods and classes are GC roots (all of them for full GCs and become, for scavenges only while one is young). A full table is cleared.'!

!JitFeedback class methodsFor: 'declaring'!
declarations
	^#((fbSites 'FeedbackSite[FB_MAX]') (fbCount int64_t) (fbYoung bool) (fbFloats 'uint8_t[FB_FLOAT_BITS]'))
!
initialize
	FB_MAX := 65536.
	"a byte per instruction, shared by hash: one another method's Float arithmetic sets makes a SmallInteger instruction look like it saw Floats (it is sent then), so many more bytes than sites"
	FB_FLOAT_BITS := 1048576.
	FB_CLASSES := 4.
	FB_MEGA := 1.
	FB_FLOAT := 2.
	FB_NONINT := 4.
	FB_OVERFLOW := 8.
	FB_DEOPT_CLASS := 16.
	FB_DEOPT_ARITH := 32.
	FB_DEOPT_BOUNDS := 64.
	FB_DEOPT_OTHER := 128.
	FB_INTS := 256.
	FB_DEOPT_HOISTED := 512
! !

!JitFeedback methodsFor: 'constants'!
classSlots
	^FB_CLASSES
!
mega
	^FB_MEGA
!
sawFloat
	^FB_FLOAT
!
sawInts
	"Two SmallIntegers where optimized code speculated on a Float."
	^FB_INTS
!
sawNonInt
	^FB_NONINT
!
overflowed
	^FB_OVERFLOW
!
deoptClass
	^FB_DEOPT_CLASS
!
deoptArith
	^FB_DEOPT_ARITH
!
deoptBounds
	^FB_DEOPT_BOUNDS
!
deoptOther
	^FB_DEOPT_OTHER
!
deoptHoisted
	^FB_DEOPT_HOISTED
! !

!JitFeedback methodsFor: 'sites'!
siteAt: m pc: pc
	"m's site at pc, null if there is none."
	<function>
	<var: #pc type: 'int64_t'>
	| i s |
	i := ((self hashOf: m) asUInt64 * 31 + pc asUInt64) bitAnd: FB_MAX - 1.
	[(s := fbSites + i) method ~= 0] whileTrue: [
		(s method = m and: [s pc = pc asInt32]) ifTrue: [^s].
		i := (i + 1) bitAnd: FB_MAX - 1].
	^self null
!
siteFor: m pc: pc
	"m's site at pc, made if there is none."
	<function>
	| i s |
	i := ((self hashOf: m) asUInt64 * 31 + pc asUInt64) bitAnd: FB_MAX - 1.
	[(s := fbSites + i) method ~= 0] whileTrue: [
		(s method = m and: [s pc = pc asInt32]) ifTrue: [^s].
		i := (i + 1) bitAnd: FB_MAX - 1].
	fbCount >= ((FB_MAX quo: 4) * 3) ifTrue: [
		self clear.
		^self siteFor: m pc: pc].
	libc memset: s value: 0 size: (self sizeof: 'FeedbackSite').
	s method: m.
	s pc: pc asInt32.
	fbCount := fbCount + 1.
	(self isYoung: m) ifTrue: [fbYoung := true].
	^s
!
noteSend: m pc: pc class: cls
	"The send at m's pc saw a receiver of class cls."
	<export>
	| s |
	s := self siteFor: m pc: pc.
	0 to: FB_CLASSES - 1 do: [:k |
		(s classes at: k) = cls ifTrue: [
			(s counts at: k) < 16rFFFFFFF ifTrue: [s counts at: k put: (s counts at: k) + 1].
			^self].
		(s classes at: k) = 0 ifTrue: [
			s classes at: k put: cls.
			s counts at: k put: 1.
			(self isYoung: cls) ifTrue: [fbYoung := true].
			^self]].
	s flags: (s flags bitOr: FB_MEGA)
!
floatBitAddressFor: m pc: pc
	"A byte machine code sets to 1 when the arithmetic at m's pc sees a Float (no call, no site: flagsAt:pc: answers it as FB_FLOAT; bytes are shared by hash)."
	^self cCoerce: fbFloats + (((self hashOf: m) asUInt64 * 31 + pc asUInt64) bitAnd: FB_FLOAT_BITS - 1) to: 'uint64_t'
!
noteFlags: m pc: pc flags: f
	"Profile bits for the instruction at m's pc."
	<var: #pc type: 'int64_t'>
	<export>
	| s |
	s := self siteFor: m pc: pc.
	s flags: (s flags bitOr: f)
!
flagsOf: v
	"The profile bits of v as an operand of arithmetic: FB_FLOAT, FB_NONINT, 0 for a SmallInteger."
	((v bitAnd: 7) = 4 or: [(self isPtr: v) and: [(self rawClass: v) = memory clsBoxedfloat]]) ifTrue: [^FB_FLOAT].
	(self isInt: v) ifFalse: [^FB_NONINT].
	^0
!
flagsAt: m pc: pc
	<function>
	<var: #pc type: 'int64_t'>
	| s f |
	s := self siteAt: m pc: pc.
	f := s isNull ifTrue: [0 asUInt32] ifFalse: [s flags].
	"the byte is m's only while m has the code that sets it (compiling that code clears it)"
	((self uint8At: (self floatBitAddressFor: m pc: pc)) ~= 0 and: [jit hasCode: (jit lookup: m)]) ifTrue: [f := f bitOr: FB_FLOAT].
	^f
!
clear
	<function>
	libc memset: fbSites value: 0 size: (self sizeof: 'FeedbackSite') * FB_MAX.
	fbCount := 0.
	fbYoung := false
!
release
	"All code was dropped (JitRuntime>>releaseMemory): forget the feedback and give back its pages (a hash table: even a few sites touch all of them)."
	<function>
	self clear.
	gc releasePages: fbSites size: (self sizeof: 'FeedbackSite') * FB_MAX.
	gc releasePages: fbFloats size: FB_FLOAT_BITS
! !

!JitFeedback methodsFor: 'garbage collection'!
youngRoots: fn
	"Scavenges: the sites' methods and classes while one of them may be young."
	<function>
	fbYoung ifFalse: [^self].
	self allRoots: fn.
	fbYoung := false.
	0 to: FB_MAX - 1 do: [:i |
		(fbSites + i) method ~= 0 ifTrue: [
			(self isYoung: (fbSites + i) method) ifTrue: [fbYoung := true].
			0 to: FB_CLASSES - 1 do: [:k | (self isYoung: ((fbSites + i) classes at: k)) ifTrue: [fbYoung := true]]]]
!
allRoots: fn
	<function>
	| s |
	fbCount = 0 ifTrue: [^self].
	0 to: FB_MAX - 1 do: [:i |
		s := fbSites + i.
		s method ~= 0 ifTrue: [
			fn call: (s fieldAddress: #method).
			0 to: FB_CLASSES - 1 do: [:k | (s classes at: k) ~= 0 ifTrue: [fn call: s classes + k]]]]
! !

VMStruct subclass: #FeedbackSite
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

FeedbackSite comment: 'What the lower tiers saw at one bytecode of one method (JitFeedback): the receiver classes of a send with how often each was reported, and profile bits. method 0: the entry is free.'!

!FeedbackSite class methodsFor: 'declaring'!
fields
	^#((method oop) (pc int32_t) (flags uint32_t) (classes 'oop[4]') (counts 'uint32_t[4]') (stamp uint32_t) (pad uint32_t))
! !
