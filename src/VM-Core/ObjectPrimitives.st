VMPrimitiveModule subclass: #ObjectPrimitives
	instanceVariableNames: 'instancesClass instancesResult instancesCount search png deflate coder packer zrle'
	classVariableNames: ''
	package: 'VM-Core'!

ObjectPrimitives comment: 'Object, string and byte-access primitives. Indices are 1-based over indexable fields; byte offsets 1-based, little-endian unless BigEndian.'!

!ObjectPrimitives class methodsFor: 'declaring'!
declarations
	^#((instancesClass oop) (instancesResult oop) (instancesCount size_t) (search ByteSearch) (png PngFilter) (deflate DeflateMatcher) (coder DeflateCoder) (packer PixelPacker) (zrle ZrleCoder))
! !

!ObjectPrimitives methodsFor: 'object'!
primClass
	<vmPrimitive: 78 name: 'class'>
	<leaf>
	self answer: (memory classOf: (self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver]))
!
primIdentical
	<vmPrimitive: 79 name: 'identical'>
	<leaf>
	self answerBool: self receiver = self arg0
!
primIdentityHash
	<vmPrimitive: 77 name: 'identityHash'>
	<leaf>
	| r |
	r := self receiver.
	(self isPtr: r) ifTrue: [^self answer: (self intOop: (self hashOf: r))].
	(self isInt: r) ifTrue: [^self answer: r].
	(self isChar: r) ifTrue: [^self answer: (self intOop: (self charVal: r))].
	self answer: (self intOop: ((r >> 3) bitAnd: 16r3FFFFFFF))
!
primBasicNew
	<vmPrimitive: 70 name: 'basicNew'>
	| err o |
	err := self local: 'int'.
	o := memory instantiate: self receiver size: 0 error: err.
	err value ~= 0 ifTrue: [^err value > 0 ifTrue: [self failCode: err value] ifFalse: [self fail]].
	self answer: o
!
primBasicNewSize
	"A size no object can have (a LargePositiveInteger too) fails with PRIM_ERR_NO_MEMORY."
	<vmPrimitive: 71 name: 'basicNew:'>
	| n u err o |
	n := self arg0.
	u := self local: 'uint64_t'.
	(memory u64Of: n into: u) ifFalse: [
		((self isPtr: n) and: [(self rawClass: n) = (memory special: SO_LARGEPOS)]) ifFalse: [^self fail].
		u value: 16rFFFFFFFFFFFFFFFF].
	err := self local: 'int'.
	o := memory instantiate: self receiver size: u value error: err.
	err value ~= 0 ifTrue: [^err value > 0 ifTrue: [self failCode: err value] ifFalse: [self fail]].
	self answer: o
!
primBasicSize
	<vmPrimitive: 72 name: 'basicSize'>
	<leaf>
	self answer: (self intOop: (memory indexableSize: self receiver) asInt64)
!
primAt
	<vmPrimitive: 73 name: 'at'>
	| r k f v |
	r := self receiver.
	(self isPtr: r) ifFalse: [^self fail].
	k := self indexOf: self arg0 limit: (memory indexableSize: r).
	k < 0 ifTrue: [^self fail].
	"a married Context's slots are its frame's"
	(interpreter isMarried: r) ifTrue: [
		v := interpreter contextSlot: k asInt64 of: r.
		v ~= 0 ifTrue: [^self answer: v].
		r := self receiver].
	f := self formatOf: r.
	(self fmtHasPointers: f) ifTrue: [^self answer: (self loadRef: r at: (memory fixedFields: r) + k asUInt32)].
	f = F_W64 ifTrue: [
		v := (self slotsOf: r) at: k.
		^self answer: (v <= VM_INT_MAX asUInt64 ifTrue: [self intOop: v asInt64] ifFalse: [memory largeIntFrom: v negative: false])].
	(f = 10 or: [f = 11]) ifTrue: [^self answer: (self intOop: ((self words32Of: r) at: k))].
	f >= F_BYTES ifTrue: [^self answer: (self intOop: ((self bytesOf: r) at: k))].
	self fail
!
primAtPut
	<vmPrimitive: 74 name: 'atPut'>
	| r k v f u |
	r := self receiver.
	(self argCount < 2 or: [(self isPtr: r) not or: [self isImmutable: r]]) ifTrue: [^self fail].
	k := self indexOf: (self arg: 0) limit: (memory indexableSize: r).
	k < 0 ifTrue: [^self fail].
	v := self arg: 1.
	(interpreter isMarried: r) ifTrue: [
		(interpreter context: r slot: k asInt64 put: v) ifTrue: [^self answer: v].
		r := self receiver.
		v := self arg: 1].
	f := self formatOf: r.
	(self fmtHasPointers: f)
		ifTrue: [self storeRef: r at: (memory fixedFields: r) + k asUInt32 put: v]
		ifFalse: [
			f = F_W64
				ifTrue: [
					u := self local: 'uint64_t'.
					(memory u64Of: v into: u) ifFalse: [^self fail].
					(self slotsOf: r) at: k put: u value]
				ifFalse: [
					(f = 10 or: [f = 11])
						ifTrue: [
							((self isInt: v) and: [(self intVal: v) >= 0 and: [(self intVal: v) <= 16rFFFFFFFF]]) ifFalse: [^self fail].
							(self words32Of: r) at: k put: (self intVal: v) asUInt32]
						ifFalse: [
							f >= F_BYTES ifFalse: [^self fail].
							((self isInt: v) and: [(self intVal: v) >= 0 and: [(self intVal: v) <= 255]]) ifFalse: [^self fail].
							(self bytesOf: r) at: k put: (self intVal: v) asUInt8]]].
	self answer: v
!
primInstVarAt
	<vmPrimitive: 75 name: 'instVarAt'>
	| r k v |
	r := self receiver.
	((self isPtr: r) and: [self fmtHasPointers: (self formatOf: r)]) ifFalse: [^self fail].
	k := self indexOf: self arg0 limit: (self numSlots: r).
	k < 0 ifTrue: [^self fail].
	"a married Context's sender, pc, stackp and slots are its frame's"
	((interpreter isMarried: r) and: [k <= CTX_STACKP or: [k >= CTX_FIXED]]) ifTrue: [
		v := k <= CTX_STACKP
			ifTrue: [interpreter contextField: k asInt64 of: r]
			ifFalse: [interpreter contextSlot: k asInt64 - CTX_FIXED of: r].
		v ~= 0 ifTrue: [^self answer: v].
		r := self receiver].
	self answer: (self loadRef: r at: k)
!
primInstVarAtPut
	<vmPrimitive: 76 name: 'instVarAtPut'>
	| r k v |
	r := self receiver.
	(self argCount < 2 or: [(self isPtr: r) not or: [(self isImmutable: r) or: [(self fmtHasPointers: (self formatOf: r)) not]]]) ifTrue: [^self fail].
	k := self indexOf: (self arg: 0) limit: (self numSlots: r).
	k < 0 ifTrue: [^self fail].
	v := self arg: 1.
	"a married Context: a slot goes to its frame; a fixed field may change how it continues, its frames are flushed first"
	(interpreter isMarried: r) ifTrue: [
		k >= CTX_FIXED
			ifTrue: [(interpreter context: r slot: k asInt64 - CTX_FIXED put: v) ifTrue: [^self answer: v]]
			ifFalse: [interpreter materializeAll].
		r := self receiver.
		v := self arg: 1].
	self storeRef: r at: k put: v.
	self answer: v
!
primShallowCopy
	<vmPrimitive: 80 name: 'shallowCopy'>
	| r c |
	r := self receiver.
	(self isPtr: r) ifFalse: [^self answer: r].
	"a married Context's state is its frame's: Context>>shallowCopy copies what Smalltalk reads"
	(interpreter isMarried: r) ifTrue: [^self fail].
	c := memory allocObjTry: (self rawClass: r) format: (self formatOf: r) slots: (self numSlots: r) asUInt64.
	c = 0 ifTrue: [^self failCode: PRIM_ERR_NO_MEMORY].
	r := self receiver.
	libc memcpy: (self slotsOf: c) from: (self slotsOf: r) size: (self numSlots: r) asUInt64 * 8.
	(self fmtHasPointers: (self formatOf: r)) ifTrue: [gc rememberIfOld: c].
	self answer: c
!
primIsImmutable
	<vmPrimitive: 83 name: 'isImmutable'>
	| r |
	r := self receiver.
	self answerBool: ((self isPtr: r) not or: [self isImmutable: r])
!
primSetImmutable
	<vmPrimitive: 84 name: 'setImmutable:'>
	| r v old |
	r := self receiver.
	v := self arg0.
	(v ~= memory trueOop and: [v ~= memory falseOop]) ifTrue: [^self fail].
	(self isPtr: r) ifFalse: [
		v = memory trueOop ifTrue: [^self answer: memory trueOop].
		^self fail].
	old := self isImmutable: r.
	v = memory trueOop
		ifTrue: [self header: r put: ((self header: r) bitOr: H_IMMUTABLE)]
		ifFalse: [
			old ifTrue: [gc invalidateNativeWeakOwners].
			self header: r put: ((self header: r) bitClear: H_IMMUTABLE)].
	self answerBool: old
!
primChangeClassTo
	<vmPrimitive: 85 name: 'changeClassTo:'>
	| r c spec isize f nf |
	r := self receiver.
	c := self arg0.
	((self isPtr: r) and: [(self isPtr: c) and: [(self numSlots: c) > BEH_FORMAT and: [self isInt: (self loadRef: c at: BEH_FORMAT)]]]) ifFalse: [^self fail].
	(interpreter isMarried: r) ifTrue: [
		interpreter materializeAll.
		r := self receiver.
		c := self arg0].
	spec := (self intVal: (self loadRef: c at: BEH_FORMAT)) >> CLS_SPEC_SHIFT.
	isize := (self intVal: (self loadRef: c at: BEH_FORMAT)) bitAnd: CLS_INSTSIZE_MASK.
	f := self formatOf: r.
	nf := f.
	spec <= 1
		ifTrue: [
			(f > 1 or: [(self numSlots: r) asInt64 ~= isize]) ifTrue: [^self fail].
			nf := isize ~= 0 ifTrue: [1] ifFalse: [0]]
		ifFalse: [
			spec <= 4
				ifTrue: [
					(f < 2 or: [f > 4 or: [(memory fixedFields: r) asInt64 ~= isize]]) ifTrue: [^self fail].
					nf := (spec = 2 and: [isize ~= 0]) ifTrue: [3] ifFalse: [spec asInt32]]
				ifFalse: [
					spec = 9
						ifTrue: [f ~= 9 ifTrue: [^self fail]]
						ifFalse: [
							spec = 10
								ifTrue: [(f ~= 10 and: [f ~= 11]) ifTrue: [^self fail]]
								ifFalse: [
									spec = 16 ifFalse: [^self fail].
									f < 16 ifTrue: [^self fail]]]]].
	self header: r put: (((self header: r) bitClear: 16r1F asUInt64 << H_FMT_SHIFT) bitOr: nf asUInt64 << H_FMT_SHIFT).
	self rawClass: r put: c.
	(self isYoung: c) ifTrue: [gc rememberIfOld: r].
	jit classChanged.
	self answer: r
!
countInstance: o data: d
	<function>
	((self rawClass: o) = instancesClass and: [o ~= instancesResult]) ifTrue: [
		(instancesResult ~= 0 and: [instancesCount >= (self numSlots: instancesResult)]) ifTrue: [^self].
		instancesResult ~= 0 ifTrue: [self storeRef: instancesResult at: instancesCount put: o].
		instancesCount := instancesCount + 1]
!
primAllInstances
	<vmPrimitive: 86 name: 'allInstances'>
	| a |
	gc fullGC.
	instancesClass := self receiver.
	instancesResult := 0.
	instancesCount := 0.
	gc walkOldSpace: (self functionPointer: #countInstance:data:) data: self null.
	a := memory allocOld: memory clsArray format: F_VAR slots: instancesCount asUInt32.
	instancesClass := self receiver.
	instancesResult := a.
	instancesCount := 0.
	gc walkOldSpace: (self functionPointer: #countInstance:data:) data: self null.
	instancesResult := 0.
	self answer: a
!
primBecomeForward
	<vmPrimitive: 88 name: 'becomeForward'>
	((self isPtr: self receiver) and: [(self isPtr: self arg0) and: [self receiver ~= memory nilOop]]) ifFalse: [^self fail].
	interpreter flushIfMarried: self receiver.
	gc fullGC.
	gc becomeForward: self receiver to: self arg0.
	self answer: self receiver
!
primSpecialObjectsArray
	<vmPrimitive: 89 name: 'specialObjectsArray'>
	self answer: memory specialsOop
! !

!ObjectPrimitives methodsFor: 'strings'!
isStringLike: o
	| f |
	(self isPtr: o) ifFalse: [^false].
	f := self formatOf: o.
	^f >= F_BYTES or: [f = 10 or: [f = 11]]
!
primStringAt
	<vmPrimitive: 100 name: 'stringAt'>
	<leaf>
	| r k |
	r := self receiver.
	(self isStringLike: r) ifFalse: [^self fail].
	k := self indexOf: self arg0 limit: (memory stringSize: r).
	k < 0 ifTrue: [^self fail].
	self answer: (self charOop: (memory stringCharAt: r index: k asUInt64))
!
primStringAtPut
	<vmPrimitive: 101 name: 'stringAtPut'>
	<leaf>
	| r k c |
	r := self receiver.
	(self argCount < 2 or: [(self isStringLike: r) not or: [self isImmutable: r]]) ifTrue: [^self fail].
	k := self indexOf: (self arg: 0) limit: (memory stringSize: r).
	k < 0 ifTrue: [^self fail].
	c := self arg: 1.
	(self isChar: c) ifFalse: [^self fail].
	(self formatOf: r) >= F_BYTES
		ifTrue: [
			(self charVal: c) > 255 ifTrue: [^self fail].
			(self bytesOf: r) at: k put: (self charVal: c) asUInt8]
		ifFalse: [(self words32Of: r) at: k put: (self charVal: c)].
	self answer: c
!
primStringHash
	<vmPrimitive: 102 name: 'stringHash'>
	<leaf>
	| s |
	s := self argCount > 0 ifTrue: [self arg: 0] ifFalse: [self receiver].
	(self isStringLike: s) ifFalse: [^self fail].
	self answer: (self intOop: (memory stringHash: s))
!
primStringCompare
	<vmPrimitive: 103 name: 'stringCompare'>
	<leaf>
	| a b na nb n x y k wa wb |
	a := self receiver.
	b := self arg0.
	((self isStringLike: a) and: [self isStringLike: b]) ifFalse: [^self fail].
	na := memory stringSize: a.
	nb := memory stringSize: b.
	n := na < nb ifTrue: [na] ifFalse: [nb].
	((self formatOf: a) >= F_BYTES and: [(self formatOf: b) >= F_BYTES])
		ifTrue: [
			k := search mismatchOf: (self bytesOf: a) with: (self bytesOf: b) from: 0 size: n asInt64.
			k < n asInt64 ifTrue: [^self answer: (self intOop: (((self bytesOf: a) at: k) < ((self bytesOf: b) at: k) ifTrue: [-1] ifFalse: [1]))]]
		ifFalse: [
			((self formatOf: a) < F_BYTES and: [(self formatOf: b) < F_BYTES])
				ifTrue: [
					wa := self words32Of: a.
					wb := self words32Of: b.
					0 to: n asInt64 - 1 do: [:i |
						(wa at: i) ~= (wb at: i) ifTrue: [^self answer: (self intOop: ((wa at: i) < (wb at: i) ifTrue: [-1] ifFalse: [1]))]]]
				ifFalse: [
					0 to: n asInt64 - 1 do: [:i |
						x := memory stringCharAt: a index: i asUInt64.
						y := memory stringCharAt: b index: i asUInt64.
						x ~= y ifTrue: [^self answer: (self intOop: (x < y ifTrue: [-1] ifFalse: [1]))]]]].
	self answer: (self intOop: (na < nb ifTrue: [-1] ifFalse: [na > nb ifTrue: [1] ifFalse: [0]]))
!
isByteString: o
	"A ByteString or ByteSymbol."
	^(self isPtr: o) and: [(self rawClass: o) = memory clsBytestring or: [(self rawClass: o) = (memory special: SO_BYTESYMBOL)]]
!

primStringCaseInsensitiveCompare
	"stringCompare of the characters' asLowercase, for ByteStrings and ByteSymbols (String>>caseInsensitiveCompare: loops for wide ones)."
	<vmPrimitive: 116 name: 'stringCaseInsensitiveCompare'>
	<leaf>
	| a b na nb pa pb x y n i |
	a := self receiver.
	b := self arg0.
	((self isByteString: a) and: [self isByteString: b]) ifFalse: [^self fail].
	na := memory byteSize: a.
	nb := memory byteSize: b.
	pa := self bytesOf: a.
	pb := self bytesOf: b.
	n := (na < nb ifTrue: [na] ifFalse: [nb]) asInt64.
	i := search mismatchOf: pa with: pb from: 0 size: n.
	[i < n] whileTrue: [
		x := search lowercase: (pa at: i) asInt32.
		y := search lowercase: (pb at: i) asInt32.
		x ~= y ifTrue: [^self answer: (self intOop: (x < y ifTrue: [-1] ifFalse: [1]))].
		i := search mismatchOf: pa with: pb from: i + 1 size: n].
	self answer: (self intOop: (na < nb ifTrue: [-1] ifFalse: [na > nb ifTrue: [1] ifFalse: [0]]))
!

convertCase: upper
	"asUppercase (upper) or asLowercase of a ByteString or ByteSymbol: a new ByteString. Fails for others and for ÿ going up."
	<function>
	| r n s |
	r := self receiver.
	(self isByteString: r) ifFalse: [^self fail].
	n := memory byteSize: r.
	s := memory allocBytes: memory clsBytestring count: n.
	r := self receiver.
	(search convertCase: (self bytesOf: r) into: (self bytesOf: s) size: n asInt64 upper: upper) ifFalse: [^self fail].
	self answer: s
!
primStringAsUppercase
	<vmPrimitive: 92 name: 'stringAsUppercase'>
	self convertCase: true
!
primStringAsLowercase
	<vmPrimitive: 93 name: 'stringAsLowercase'>
	self convertCase: false
!
primStringIndexOf
	"indexOf: aCharacter startingAt: start: the index of its first occurrence at or after start, 0 if none. Fails for a start below 1 or anything but a Character."
	<vmPrimitive: 117 name: 'stringIndexOf'>
	<leaf>
	| r c s v w |
	r := self receiver.
	c := self arg: 0.
	s := self arg: 1.
	(self argCount = 2 and: [(self isStringLike: r) and: [(self isChar: c) and: [(self isInt: s) and: [(self intVal: s) >= 1]]]]) ifFalse: [^self fail].
	v := self charVal: c.
	(self formatOf: r) >= F_BYTES
		ifTrue: [
			v < 256 ifTrue: [
				^self answer: (self intOop: (search indexOfByte: v asUInt8 in: (self bytesOf: r) size: (memory byteSize: r) asInt64 from: (self intVal: s) - 1) + 1)]]
		ifFalse: [
			w := self words32Of: r.
			(self intVal: s) - 1 to: (memory word32Size: r) asInt64 - 1 do: [:i |
				(w at: i) = v ifTrue: [^self answer: (self intOop: i + 1)]]].
	self answer: (self intOop: 0)
!
primStringIndexOfSubstring
	"indexOfSubCollection: aString startingAt: start: where aString next begins at or after start, 0 if it does not (start if it is empty). Fails for a start below 1 or anything but a String."
	<vmPrimitive: 118 name: 'stringIndexOfSubstring'>
	<leaf>
	| r p s n m k w v |
	r := self receiver.
	p := self arg: 0.
	s := self arg: 1.
	(self argCount = 2 and: [(self isStringLike: r) and: [(memory isKindOfString: p) and: [(self isInt: s) and: [(self intVal: s) >= 1]]]]) ifFalse: [^self fail].
	n := (memory stringSize: r) asInt64.
	m := (memory stringSize: p) asInt64.
	m = 0 ifTrue: [^self answer: s].
	((self formatOf: r) >= F_BYTES and: [(self formatOf: p) >= F_BYTES]) ifTrue: [
		^self answer: (self intOop: (search indexOfBytes: (self bytesOf: p) size: m in: (self bytesOf: r) size: n from: (self intVal: s) - 1) + 1)].
	((self formatOf: r) < F_BYTES and: [(self formatOf: p) < F_BYTES]) ifTrue: [
		w := self words32Of: r.
		v := self words32Of: p.
		(self intVal: s) - 1 to: n - m do: [:i |
			((w at: i) = (v at: 0) and: [(libc memcmp: w + i with: v size: m asUInt64 * 4) = 0]) ifTrue: [^self answer: (self intOop: i + 1)]].
		^self answer: (self intOop: 0)].
	(self intVal: s) - 1 to: n - m do: [:i |
		k := 0.
		[k < m and: [(memory stringCharAt: r index: (i + k) asUInt64) = (memory stringCharAt: p index: k asUInt64)]] whileTrue: [k := k + 1].
		k = m ifTrue: [^self answer: (self intOop: i + 1)]].
	self answer: (self intOop: 0)
!
elementKindOf: o
	| f |
	f := self formatOf: o.
	(self fmtHasPointers: f) ifTrue: [^1].
	f = F_W64 ifTrue: [^2].
	(f = 10 or: [f = 11]) ifTrue: [^3].
	f >= F_BYTES ifTrue: [^4].
	^0
!
primReplaceFromTo
	<vmPrimitive: 104 name: 'replaceFromToWithStartingAt'>
	<leaf>
	| r src so eo ro kind start stop rstart n fr fs |
	self argCount < 4 ifTrue: [^self fail].
	r := self receiver.
	src := self arg: 2.
	so := self arg: 0.
	eo := self arg: 1.
	ro := self arg: 3.
	((self isPtr: r) and: [(self isPtr: src) and: [(self isImmutable: r) not and: [(self isInt: so) and: [(self isInt: eo) and: [self isInt: ro]]]]]) ifFalse: [^self fail].
	kind := self elementKindOf: r.
	(kind = 0 or: [kind ~= (self elementKindOf: src)]) ifTrue: [^self fail].
	"a married Context's slots are in its frame: the fallback reads them"
	(kind = 1 and: [(interpreter isMarried: src) or: [interpreter isMarried: r]]) ifTrue: [^self fail].
	start := self intVal: so.
	stop := self intVal: eo.
	rstart := self intVal: ro.
	n := stop - start + 1.
	(n = 0 and: [start >= 1]) ifTrue: [^self answer: r].
	(start < 1 or: [n < 0 or: [stop > (memory indexableSize: r) asInt64 or: [rstart < 1 or: [rstart + n - 1 > (memory indexableSize: src) asInt64]]]]) ifTrue: [^self fail].
	kind = 1 ifTrue: [
		fr := memory fixedFields: r.
		fs := memory fixedFields: src.
		libc memmove: (self slotsOf: r) + fr + start - 1 from: (self slotsOf: src) + fs + rstart - 1 size: n asUInt64 * 8.
		gc rememberIfOld: r].
	kind = 2 ifTrue: [libc memmove: (self slotsOf: r) + start - 1 from: (self slotsOf: src) + rstart - 1 size: n asUInt64 * 8].
	kind = 3 ifTrue: [libc memmove: (self words32Of: r) + start - 1 from: (self words32Of: src) + rstart - 1 size: n asUInt64 * 4].
	kind = 4 ifTrue: [libc memmove: (self bytesOf: r) + start - 1 from: (self bytesOf: src) + rstart - 1 size: n asUInt64].
	self answer: r
! !

!ObjectPrimitives methodsFor: 'bytes'!
rawByteSize: o
	| f |
	f := self formatOf: o.
	f >= F_BYTES ifTrue: [^memory byteSize: o].
	(f = 10 or: [f = 11]) ifTrue: [^(memory word32Size: o) * 4].
	f = F_W64 ifTrue: [^(self numSlots: o) asUInt64 * 8].
	^0 asUInt64
!
byteAt: width put: isPut
	"The address of width bytes of the receiver at the 1-based offset argument, or 0."
	| r n i |
	r := self receiver.
	((self isPtr: r) not or: [isPut and: [self isImmutable: r]]) ifTrue: [^0 asUInt64].
	n := self rawByteSize: r.
	i := self arg0.
	((self isInt: i) and: [(self intVal: i) >= 1 and: [((self intVal: i) - 1) asUInt64 + width <= n]]) ifFalse: [^0 asUInt64].
	^r + 16 + ((self intVal: i) - 1) asUInt64
!
storedFloat: v
	"The Float or SmallInteger v as a double; the caller checked it."
	^(self isInt: v) ifTrue: [(self intVal: v) asFloat] ifFalse: [memory floatVal: v]
!
primBytesUint16At
	<vmPrimitive: 105 name: 'bytesUint16At'>
	<leaf>
	| p |
	p := self byteAt: 2 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: (self uint16At: p))
!
primBytesUint32At
	<vmPrimitive: 106 name: 'bytesUint32At'>
	<leaf>
	| p |
	p := self byteAt: 4 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: (self uint32At: p))
!
primBytesInt16At
	<vmPrimitive: 107 name: 'bytesInt16At'>
	<leaf>
	| p |
	p := self byteAt: 2 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: (self int16At: p))
!
primBytesFloat32At
	<vmPrimitive: 108 name: 'bytesFloat32At'>
	| p |
	p := self byteAt: 4 put: false.
	p = 0 ifTrue: [^self fail].
	self answerFloat: (self float32At: p)
!
primBytesFloat32AtPut
	<vmPrimitive: 109 name: 'bytesFloat32AtPut'>
	<leaf>
	| p v |
	p := self byteAt: 4 put: true.
	(p = 0 or: [self argCount < 2]) ifTrue: [^self fail].
	v := self arg: 1.
	((memory isFloat: v) or: [self isInt: v]) ifFalse: [^self fail].
	self float32At: p put: (self storedFloat: v).
	self answer: v
!
primBytesUint32AtPut
	<vmPrimitive: 110 name: 'bytesUint32AtPut'>
	<leaf>
	| p v |
	p := self byteAt: 4 put: true.
	(p = 0 or: [self argCount < 2]) ifTrue: [^self fail].
	v := self arg: 1.
	((self isInt: v) and: [(self intVal: v) >= 0 and: [(self intVal: v) <= 16rFFFFFFFF]]) ifFalse: [^self fail].
	self uint32At: p put: (self intVal: v) asUInt32.
	self answer: v
!
primBytesFloat64At
	<vmPrimitive: 111 name: 'bytesFloat64At'>
	| p |
	p := self byteAt: 8 put: false.
	p = 0 ifTrue: [^self fail].
	self answerFloat: (self float64At: p)
!
primBytesFloat64AtPut
	<vmPrimitive: 112 name: 'bytesFloat64AtPut'>
	<leaf>
	| p v |
	p := self byteAt: 8 put: true.
	(p = 0 or: [self argCount < 2]) ifTrue: [^self fail].
	v := self arg: 1.
	((memory isFloat: v) or: [self isInt: v]) ifFalse: [^self fail].
	self float64At: p put: (self storedFloat: v).
	self answer: v
!
primBytesUint16BigEndianAt
	<vmPrimitive: 113 name: 'bytesUint16BigEndianAt'>
	<leaf>
	| p |
	p := self byteAt: 2 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: ((self uint8At: p) asInt64 << 8 bitOr: (self uint8At: p + 1)))
!
primBytesInt16BigEndianAt
	<vmPrimitive: 114 name: 'bytesInt16BigEndianAt'>
	<leaf>
	| p |
	p := self byteAt: 2 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: ((self uint8At: p) asInt64 << 8 bitOr: (self uint8At: p + 1)) asInt16)
!
primBytesUint32BigEndianAt
	<vmPrimitive: 115 name: 'bytesUint32BigEndianAt'>
	<leaf>
	| p |
	p := self byteAt: 4 put: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: ((((self uint8At: p) asUInt64 << 24 bitOr: (self uint8At: p + 1) asUInt64 << 16) bitOr: (self uint8At: p + 2) asUInt64 << 8) bitOr: (self uint8At: p + 3)))
! !

!ObjectPrimitives methodsFor: 'images'!
isBytes: o size: n
	"Whether o is a byte object of n bytes."
	| f |
	(self isPtr: o) ifFalse: [^false].
	f := self formatOf: o.
	^f >= F_BYTES and: [f < (F_BYTES + 8) and: [(memory byteSize: o) = n asUInt64]]
!
primPngFilter
	"(rgba, w, h, n, raw): raw := the PNG rows of rgba (w * h pixels, 4 bytes each, rows top to bottom), each its filter type byte and its pixels packed to n channels (3: alpha dropped, 4), filtered with the filter of the smallest cost (PngFilter; PNGWriter class>>filtered:width:height:channels:); answers raw. rgba and raw are distinct byte objects of w * h * 4 and (w * n + 1) * h bytes, raw mutable; 1 <= w, h <= 2^22."
	<vmPrimitive: 207 name: 'pngFilter'>
	<leaf>
	| rgba raw w h n |
	self argCount = 5 ifFalse: [^self fail].
	((self isInt: (self arg: 1)) and: [(self isInt: (self arg: 2)) and: [self isInt: (self arg: 3)]]) ifFalse: [^self fail].
	w := self intVal: (self arg: 1).
	h := self intVal: (self arg: 2).
	n := self intVal: (self arg: 3).
	((w >= 1 and: [w <= 16r400000]) and: [(h >= 1 and: [h <= 16r400000]) and: [n = 3 or: [n = 4]]]) ifFalse: [^self fail].
	rgba := self arg: 0.
	raw := self arg: 4.
	(rgba ~= raw and: [(self isBytes: rgba size: w * h * 4) and: [(self isBytes: raw size: (w * n + 1) * h) and: [(self isImmutable: raw) not]]]) ifFalse: [^self fail].
	png filterPng: (self bytesOf: rgba) width: w height: h channels: n into: (self bytesOf: raw).
	self answer: raw
! !

!ObjectPrimitives methodsFor: 'images'!
primPixelsPack
	"(src, stride, x, y, w, h, swap, dst): dst's first w * h * 3 bytes := the w x h pixels of 4 bytes at x, y of src (rows of stride bytes), each as its bytes 0 1 2 (swap 0) or 2 1 0 (swap 1), alpha dropped: BGRA or RGBA rows as 3-byte pixels (RFB ZRLE's CPIXEL, Tight's TPIXEL, PNG's RGB), row after row (PixelPacker; PixelPack class>>pack:stride:x:y:width:height:swap:into:). Answers dst. src and dst are distinct byte objects, dst mutable and at least w * h * 3 bytes, the rectangle within src: 0 <= x, y; 0 <= w, h <= 2^22; (x + w) * 4 <= stride <= 2^26."
	<vmPrimitive: 213 name: 'pixelsPack'>
	<leaf>
	| src dst stride x y w h swap |
	self argCount = 8 ifFalse: [^self fail].
	((self isInt: (self arg: 1)) and: [(self isInt: (self arg: 2)) and: [(self isInt: (self arg: 3)) and: [(self isInt: (self arg: 4)) and: [(self isInt: (self arg: 5)) and: [self isInt: (self arg: 6)]]]]]) ifFalse: [^self fail].
	stride := self intVal: (self arg: 1).
	x := self intVal: (self arg: 2).
	y := self intVal: (self arg: 3).
	w := self intVal: (self arg: 4).
	h := self intVal: (self arg: 5).
	swap := self intVal: (self arg: 6).
	((x >= 0 and: [y >= 0]) and: [(w >= 0 and: [w <= 16r400000]) and: [(h >= 0 and: [h <= 16r400000]) and: [(swap = 0 or: [swap = 1]) and: [(x + w) * 4 <= stride and: [stride <= 16r4000000]]]]]) ifFalse: [^self fail].
	src := self arg: 0.
	dst := self arg: 7.
	(src ~= dst and: [(self isPtr: src) and: [(self isPtr: dst) and: [(self isImmutable: dst) not]]]) ifFalse: [^self fail].
	((self formatOf: src) >= F_BYTES and: [(self formatOf: src) < (F_BYTES + 8) and: [(self formatOf: dst) >= F_BYTES and: [(self formatOf: dst) < (F_BYTES + 8)]]]) ifFalse: [^self fail].
	(w * h * 3) <= (memory byteSize: dst) asInt64 ifFalse: [^self fail].
	(w > 0 and: [h > 0]) ifFalse: [^self answer: dst].
	((y + h - 1) * stride + ((x + w) * 4)) <= (memory byteSize: src) asInt64 ifFalse: [^self fail].
	packer pack: (self bytesOf: src) + (y * stride) + (x * 4) stride: stride width: w height: h swap: swap into: (self bytesOf: dst).
	self answer: dst
!
primZrleTiles
	"(pixels, w, h, bpp, cp, offset, scratch, out): the ZRLE tiles of a w x h rectangle of pixels (rows w * bpp bytes; ZrleCoder, RfbZrleEncoder>>tiles:width:height:format:) into out from its first byte; answers how many bytes they are. bpp 1, 2 or 4; the CPIXEL cp bytes from offset: the whole pixel (cp = bpp, offset 0) or 3 bytes of 4 from 0 or 1. pixels a byte object of at least w * h * bpp bytes; scratch and out distinct mutable byte objects, scratch of exactly 52224 bytes, out of at least w * h * cp bytes and one a 64x64 tile; 0 <= w, h <= 65535."
	<vmPrimitive: 214 name: 'zrleTiles'>
	<leaf>
	| px w h bpp cp off scratch out tiles |
	self argCount = 8 ifFalse: [^self fail].
	((self isInt: (self arg: 1)) and: [(self isInt: (self arg: 2)) and: [(self isInt: (self arg: 3)) and: [(self isInt: (self arg: 4)) and: [self isInt: (self arg: 5)]]]]) ifFalse: [^self fail].
	w := self intVal: (self arg: 1).
	h := self intVal: (self arg: 2).
	bpp := self intVal: (self arg: 3).
	cp := self intVal: (self arg: 4).
	off := self intVal: (self arg: 5).
	((w >= 0 and: [w <= 65535]) and: [(h >= 0 and: [h <= 65535]) and: [bpp = 1 or: [bpp = 2 or: [bpp = 4]]]]) ifFalse: [^self fail].
	((cp = bpp and: [off = 0]) or: [bpp = 4 and: [cp = 3 and: [off = 0 or: [off = 1]]]]) ifFalse: [^self fail].
	px := self arg: 0.
	scratch := self arg: 6.
	out := self arg: 7.
	((self isPtr: px) and: [(self formatOf: px) >= F_BYTES and: [(self formatOf: px) < (F_BYTES + 8)]]) ifFalse: [^self fail].
	((self isMutableBytes: scratch size: 52224) and: [(self isPtr: out) and: [(self isImmutable: out) not]]) ifFalse: [^self fail].
	((self formatOf: out) >= F_BYTES and: [(self formatOf: out) < (F_BYTES + 8) and: [out ~= px and: [out ~= scratch]]]) ifFalse: [^self fail].
	tiles := (w + 63 quo: 64) * (h + 63 quo: 64).
	(w * h * bpp) <= (memory byteSize: px) asInt64 ifFalse: [^self fail].
	(w * h * cp + tiles) <= (memory byteSize: out) asInt64 ifFalse: [^self fail].
	self answer: (self intOop: (zrle
		tiles: (self bytesOf: px)
		width: w
		height: h
		bpp: bpp
		cpixel: cp
		offset: off
		scratch: (self words32Of: scratch)
		into: (self bytesOf: out)))
!
isMutableBytes: o size: n
	^(self isBytes: o size: n) and: [(self isImmutable: o) not]
!
primZlibMatches
	"(input, start, head, prev, literals, distances, chain[, size]): the LZ77 tokens of a deflate block of the byte object input (its first size bytes, all of them without size) from the 1-based start, as ZLib>>matchesFrom: makes them (DeflateMatcher): head and prev the hash chains, 32768 uint32 each; literals and distances the tokens, 65535 uint16 each (the most a block has); chain the candidates tried a position, 1 to 4096. Answers the position after the tokens times 65536 plus their count. Fails unless input is a byte object, 0 <= size <= its size, 1 <= start <= size + 1, and the four tables distinct mutable byte objects of those sizes."
	<vmPrimitive: 208 name: 'zlibMatches'>
	<leaf>
	| input n start chain head prev lits dists |
	(self argCount = 7 or: [self argCount = 8]) ifFalse: [^self fail].
	input := self arg: 0.
	((self isPtr: input) and: [(self formatOf: input) >= F_BYTES and: [(self formatOf: input) < (F_BYTES + 8)]]) ifFalse: [^self fail].
	n := (memory byteSize: input) asInt64.
	self argCount = 8 ifTrue: [
		(self isInt: (self arg: 7)) ifFalse: [^self fail].
		((self intVal: (self arg: 7)) >= 0 and: [(self intVal: (self arg: 7)) <= n]) ifFalse: [^self fail].
		n := (self intVal: (self arg: 7)) asInt64].
	((self isInt: (self arg: 1)) and: [self isInt: (self arg: 6)]) ifFalse: [^self fail].
	start := self intVal: (self arg: 1).
	chain := self intVal: (self arg: 6).
	((start >= 1 and: [start <= (n + 1)]) and: [chain >= 1 and: [chain <= 4096]]) ifFalse: [^self fail].
	head := self arg: 2.
	prev := self arg: 3.
	lits := self arg: 4.
	dists := self arg: 5.
	((self isMutableBytes: head size: 131072) and: [(self isMutableBytes: prev size: 131072) and: [(self isMutableBytes: lits size: 131070) and: [self isMutableBytes: dists size: 131070]]]) ifFalse: [^self fail].
	(head ~= prev and: [lits ~= dists]) ifFalse: [^self fail].
	self answer: (self intOop: (deflate
		matches: (self bytesOf: input)
		size: n
		from: start
		head: (self words32Of: head)
		prev: (self words32Of: prev)
		literals: (self cCoerce: (self bytesOf: lits) to: 'uint16_t *')
		distances: (self cCoerce: (self bytesOf: dists) to: 'uint16_t *')
		max: 65535
		chain: chain))
! !

!ObjectPrimitives methodsFor: 'images'!
primZlibWriteTokens
	"(literals, distances, count, table, output, size, bits, bitCount): the Huffman coding of count tokens (ZLib>>writeTokens:distances:count:literals:distances:, DeflateCoder) and the end-of-block code into the byte object output after its first size bytes and the bitCount (0 to 7) bits pending; answers the bytes written in all times 8 plus the bits left over, which are in the byte after them. literals and distances 65535 uint16 each, table 316 uint32 (codes and lengths); output must have room for 6 bytes a token and 8 more. Fails on an invalid token (having written some of output)."
	<vmPrimitive: 210 name: 'zlibWriteTokens'>
	<leaf>
	| lits dists count table out size bits bitCount r |
	self argCount = 8 ifFalse: [^self fail].
	((self isInt: (self arg: 2)) and: [(self isInt: (self arg: 5)) and: [(self isInt: (self arg: 6)) and: [self isInt: (self arg: 7)]]]) ifFalse: [^self fail].
	count := self intVal: (self arg: 2).
	size := self intVal: (self arg: 5).
	bits := self intVal: (self arg: 6).
	bitCount := self intVal: (self arg: 7).
	((count >= 0 and: [count <= 65535]) and: [(size >= 0) and: [(bitCount >= 0 and: [bitCount <= 7]) and: [bits >= 0 and: [bits < (1 << bitCount)]]]]) ifFalse: [^self fail].
	lits := self arg: 0.
	dists := self arg: 1.
	table := self arg: 3.
	out := self arg: 4.
	((self isBytes: lits size: 131070) and: [(self isBytes: dists size: 131070) and: [self isBytes: table size: 1264]]) ifFalse: [^self fail].
	((self isPtr: out) and: [(self formatOf: out) >= F_BYTES and: [(self formatOf: out) < (F_BYTES + 8) and: [(self isImmutable: out) not]]]) ifFalse: [^self fail].
	size + (6 * count) + 8 <= (memory byteSize: out) asInt64 ifFalse: [^self fail].
	r := coder
		write: (self cCoerce: (self bytesOf: lits) to: 'uint16_t *')
		distances: (self cCoerce: (self bytesOf: dists) to: 'uint16_t *')
		count: count
		table: (self words32Of: table)
		into: (self bytesOf: out)
		at: size
		bits: bits asUInt64
		count: bitCount.
	r < 0 ifTrue: [^self fail].
	self answer: (self intOop: r)
! !

!ObjectPrimitives methodsFor: 'bytes'!
primRawBytesReplace
	"ByteArray>>replaceFrom:to:withRawBytesOf:startingAt:: the receiver's bytes start to stop (1-based) := the memory of a non-pointer object (bytes, or 32- or 64-bit words as the CPU stores them) from its byte index; answers the receiver. Fails unless the receiver is a mutable byte object and both ranges are inside."
	<vmPrimitive: 212 name: 'rawBytesReplace'>
	<leaf>
	| r src start stop s n |
	self argCount = 4 ifFalse: [^self fail].
	r := self receiver.
	src := self arg: 2.
	((self isPtr: r) and: [(self isPtr: src) and: [(self isInt: (self arg: 0)) and: [(self isInt: (self arg: 1)) and: [self isInt: (self arg: 3)]]]]) ifFalse: [^self fail].
	((self formatOf: r) >= F_BYTES and: [(self formatOf: r) < (F_BYTES + 8) and: [(self isImmutable: r) not]]) ifFalse: [^self fail].
	start := self intVal: (self arg: 0).
	stop := self intVal: (self arg: 1).
	s := self intVal: (self arg: 3).
	n := stop - start + 1.
	(start >= 1 and: [n >= 0 and: [stop <= (memory byteSize: r) asInt64 and: [s >= 1 and: [s + n - 1 <= (self rawByteSize: src) asInt64]]]]) ifFalse: [^self fail].
	libc memmove: (self bytesOf: r) + start - 1 from: (self bytesOf: src) + s - 1 size: n asUInt64.
	self answer: r
! !
