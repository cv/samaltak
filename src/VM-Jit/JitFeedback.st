VMCoreModule subclass: #JitFeedback
	instanceVariableNames: 'fbSites fbCount fbYoung'
	classVariableNames: 'FB_CLASSES FB_INTS FB_DEOPT_ARITH FB_DEOPT_BOUNDS FB_DEOPT_CLASS FB_DEOPT_OTHER FB_FLOAT FB_MAX FB_MEGA FB_NONINT FB_OVERFLOW'
	package: 'VM-Jit'!

JitFeedback comment: 'Type feedback for the optimizing tier, independent of the compiler that collects it: one FeedbackSite per (method, bytecode pc), in an open-addressed table keyed by the method''s identity hash and the pc. A site holds up to FB_CLASSES receiver classes with counts (FB_MEGA once more were seen) and profile bits: FB_FLOAT (an arithmetic or comparison saw a Float operand), FB_NONINT (one that was neither SmallInteger nor Float), FB_OVERFLOW (SmallInteger arithmetic overflowed), FB_DEOPT_* (optimized code deoptimized here: a class guard, an arithmetic guard, a bounds check, anything else).

Lower tiers report into it (docs/jit.md, Optimizing tier): noteSend:pc:class: when a send site sees a class (the template on a miss of the interpreter''s inline cache, the baseline compiler when one of its inline caches links a class), noteFlags:pc:flags: for profile bits; the optimizer reads sites with siteAt:pc:. Methods and classes are GC roots (all of them for full GCs and become, for scavenges only while one is young). A full table is cleared.'!

!JitFeedback class methodsFor: 'declaring'!
declarations
	^#((fbSites 'FeedbackSite[FB_MAX]') (fbCount int64_t) (fbYoung bool))
!
initialize
	FB_MAX := 16384.
	FB_CLASSES := 4.
	FB_MEGA := 1.
	FB_FLOAT := 2.
	FB_NONINT := 4.
	FB_OVERFLOW := 8.
	FB_DEOPT_CLASS := 16.
	FB_DEOPT_ARITH := 32.
	FB_DEOPT_BOUNDS := 64.
	FB_DEOPT_OTHER := 128.
	FB_INTS := 256
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
! !

!JitFeedback methodsFor: 'sites'!
siteAt: m pc: pc
	"m's site at pc, null if there is none."
	<c: 'FeedbackSite *fb_site_at(oop m, int64_t pc)'>
	| i s |
	i := ((self hashOf: m) asUInt64 * 31 + pc asUInt64) bitAnd: FB_MAX - 1.
	[(s := fbSites + i) method ~= 0] whileTrue: [
		(s method = m and: [s pc = pc asInt32]) ifTrue: [^s].
		i := (i + 1) bitAnd: FB_MAX - 1].
	^self null
!
siteFor: m pc: pc
	"m's site at pc, made if there is none."
	<c: 'FeedbackSite *fb_site_for(oop m, int64_t pc)'>
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
	<c: 'void jit_note_send(oop m, int64_t pc, oop cls)'>
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
noteFlags: m pc: pc flags: f
	"Profile bits for the instruction at m's pc."
	<c: 'void jit_note_flags(oop m, int64_t pc, uint32_t f)'>
	<export>
	| s |
	s := self siteFor: m pc: pc.
	s flags: (s flags bitOr: f)
!
flagsAt: m pc: pc
	<c: 'uint32_t fb_flags_at(oop m, int64_t pc)'>
	| s |
	s := self siteAt: m pc: pc.
	s isNull ifTrue: [^0 asUInt32].
	^s flags
!
clear
	<c: 'void fb_clear(void)'>
	libc memset: fbSites value: 0 size: (self sizeof: 'FeedbackSite') * FB_MAX.
	fbCount := 0.
	fbYoung := false
! !

!JitFeedback methodsFor: 'garbage collection'!
youngRoots: fn
	"Scavenges: the sites' methods and classes while one of them may be young."
	<c: 'void fb_young_roots(void (*fn)(oop *))'>
	fbYoung ifFalse: [^self].
	self allRoots: fn.
	fbYoung := false.
	0 to: FB_MAX - 1 do: [:i |
		(fbSites + i) method ~= 0 ifTrue: [
			(self isYoung: (fbSites + i) method) ifTrue: [fbYoung := true].
			0 to: FB_CLASSES - 1 do: [:k | (self isYoung: ((fbSites + i) classes at: k)) ifTrue: [fbYoung := true]]]]
!
allRoots: fn
	<c: 'void fb_all_roots(void (*fn)(oop *))'>
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
