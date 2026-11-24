VMCoreModule subclass: #PrimitiveTable
	instanceVariableNames: 'byNumber names flags tryGuards initialized'
	classVariableNames: 'MAX_PRIM PRIM_LEAF PRIM_TRYABLE'
	package: 'VM-Core'!

PrimitiveTable comment: 'The primitives by number: the translator (or the simulation) builds the table of every <vmPrimitive:name:> method (number, flags, name, function); I index it. Leaf primitives never allocate, switch processes or inspect Contexts, so the interpreter calls them without writing back its registers; tryable ones may run for the debugger (tryPrimitive).'!

!PrimitiveTable class methodsFor: 'declaring'!
declarations
	^#((byNumber 'prim_fn[MAX_PRIM]') (names 'const char *[MAX_PRIM]') (flags 'int32_t[MAX_PRIM]') (tryGuards 'prim_try_guard[MAX_PRIM]') (initialized bool))
!
typedefs
	^#((prim_try_guard 'bool (*)(oop)'))
!
initialize
	MAX_PRIM := 1024.
	PRIM_LEAF := 1.
	PRIM_TRYABLE := 2
! !

!PrimitiveTable methodsFor: 'table'!
initTable
	<function>
	| t e |
	initialized ifTrue: [^self].
	initialized := true.
	t := self primitiveTable.
	0 to: self primitiveCount - 1 do: [:i |
		e := t + i.
		(e number <= 0 or: [e number >= MAX_PRIM or: [(byNumber at: e number) notNull]]) ifTrue: [
			self fatal: 'bad or duplicate primitive number %d (%s)' with: e number with: e name].
		byNumber at: e number put: e function.
		names at: e number put: e name.
		flags at: e number put: e flags]
!
installTraceFunction: fn for: n
	"Install an opt-in instrumentation wrapper before the interpreter fills any method caches. Keep the primitive's number, name and flags."
	<function>
	<var: #fn type: 'prim_fn'>
	self initTable.
	byNumber at: n put: fn
!
lookup: n
	<function>
	self initTable.
	^(n > 0 and: [n < MAX_PRIM]) ifTrue: [byNumber at: n] ifFalse: [self null]
!
flagsOf: n
	self initTable.
	^(n > 0 and: [n < MAX_PRIM]) ifTrue: [flags at: n] ifFalse: [0]
!
isLeaf: n
	<function>
	^((self flagsOf: n) bitAnd: PRIM_LEAF) ~= 0
!
installTryGuard: guard for: n
	"A receiver-dependent veto, used only by the debugger's primitive probe."
	<function>
	<var: #guard type: 'prim_try_guard'>
	tryGuards at: n put: guard
!
isTryable: n receiver: owner
	<function>
	<var: #owner type: 'oop'>
	| guard |
	((self flagsOf: n) bitAnd: PRIM_TRYABLE) = 0 ifTrue: [^false].
	guard := tryGuards at: n.
	^guard isNull or: [guard call: owner]
!
namesArray
	"Array: element n is the name of primitive n (nil for gaps)."
	<function>
	| t max a root s e |
	t := self primitiveTable.
	max := 0.
	0 to: self primitiveCount - 1 do: [:i | (t + i) number > max ifTrue: [max := (t + i) number]].
	a := memory allocObj: memory clsArray format: F_VAR slots: max asUInt32.
	root := self local: 'oop'.
	root value: a.
	memory pushRoot: root.
	0 to: self primitiveCount - 1 do: [:i |
		e := t + i.
		s := memory stringFromUtf8: e name size: (libc strlen: e name).
		self storeRef: root value at: e number - 1 put: s].
	memory popRoot.
	^root value
! !

VMStruct subclass: #PrimitiveEntry
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

PrimitiveEntry comment: 'A row of the primitive table the translator writes: number, flags (1 leaf, 2 tryable), name, function.'!

!PrimitiveEntry class methodsFor: 'declaring'!
fields
	^#((number int32_t) (flags int32_t) (name 'const char *') (function prim_fn))
! !
