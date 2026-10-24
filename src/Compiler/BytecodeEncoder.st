Object subclass: #BytecodeEncoder
	instanceVariableNames: 'bytes count literals depth maxDepth sourceMap pushes barrier'
	classVariableNames: ''
	package: 'Compiler'!

BytecodeEncoder comment: 'I emit the bytecodes of docs/implementation.md, choosing the short forms when possible. I collect literals, track the operand stack depth (depth, maxDepth of the frame being generated) and record the sourceMap (pc start stop triples).

Superinstructions: "push temp; push temp | literal | small integer; send a binary special selector" becomes one instruction (16r97-16r99; for + - < > <= >= 16r9A-16r9F, 16rF0-16rFB) when nothing can jump between its parts. pushes remembers the last two pushes ({start. end. kind. operand}); barrier is the last pc something may jump to or record (jump targets and every pc asked for), so a fusion needs barrier <= the first push.'!

!BytecodeEncoder class methodsFor: 'instance creation'!
new
	^self basicNew initialize
! !

!BytecodeEncoder methodsFor: 'initialization'!
initialize
	bytes := ByteArray new: 64.
	count := 0.
	literals := OrderedCollection new.
	depth := 0.
	maxDepth := 0.
	sourceMap := OrderedCollection new.
	pushes := OrderedCollection new.
	barrier := 0
! !

!BytecodeEncoder methodsFor: 'accessing'!
pc
	"Answer the 0-based pc of the next instruction (a jump target or scope boundary: no superinstruction spans it)."
	barrier := count.
	^count
!
bytecodes
	| result |
	result := ByteArray new: count.
	1 to: count do: [:i | result at: i put: (bytes at: i)].
	^result
!
literals
	^literals asArray
!
sourceMap
	^sourceMap asArray
!
sourceMapSize
	^sourceMap size
!
depth
	^depth
!
depth: anInteger
	depth := anInteger
!
maxDepth
	^maxDepth
!
maxDepth: anInteger
	maxDepth := anInteger
! !

!BytecodeEncoder methodsFor: 'stack'!
push
	depth := depth + 1.
	depth > maxDepth ifTrue: [maxDepth := depth]
!
pop: anInteger
	depth := depth - anInteger
! !

!BytecodeEncoder methodsFor: 'private'!
emit: aByte
	| new |
	count >= bytes size ifTrue: [
		new := ByteArray new: bytes size * 2.
		1 to: count do: [:i | new at: i put: (bytes at: i)].
		bytes := new].
	count := count + 1.
	bytes at: count put: aByte
!
emit: opcode operand: operand
	operand > 255 ifTrue: [^self compileError: 'Operand too large'].
	self emit: opcode.
	self emit: operand
!
emit: opcode operand: first operand: second
	(first > 255 or: [second > 255]) ifTrue: [^self compileError: 'Operand too large'].
	self emit: opcode.
	self emit: first.
	self emit: second
!
emitInt16: anInteger
	| v |
	(anInteger < -32768 or: [anInteger > 32767]) ifTrue: [^self compileError: 'Method too large'].
	v := anInteger < 0 ifTrue: [anInteger + 65536] ifFalse: [anInteger].
	self emit: v \\ 256.
	self emit: v // 256
!
byteAt: aPc put: aByte
	bytes at: aPc + 1 put: aByte
!
compileError: aString
	^SyntaxError signal: aString at: 1 in: nil
! !

!BytecodeEncoder methodsFor: 'literals'!
literalIndexOf: anObject
	1 to: literals size do: [:i |
		(self literal: (literals at: i) matches: anObject) ifTrue: [^i - 1]].
	literals size >= 256 ifTrue: [^self compileError: 'Too many literals'].
	literals add: anObject.
	^literals size - 1
!
literal: a matches: b
	"Literals are shared when they are identical, or equal strings, arrays, byte arrays or large integers of the same class. Associations (variables) and floats are only shared when identical."
	a == b ifTrue: [^true].
	a class == b class ifFalse: [^false].
	a isString ifTrue: [^a isSymbol not and: [a = b]].
	a class == Array ifTrue: [
		a size = b size ifFalse: [^false].
		1 to: a size do: [:i | (self literal: (a at: i) matches: (b at: i)) ifFalse: [^false]].
		^true].
	a class == ByteArray ifTrue: [^a = b].
	a isInteger ifTrue: [^a = b].
	^false
!
freeze: anObject
	"Make a literal constant immutable (arrays deeply). Symbols and immediates are left alone."
	(anObject isNil or: [anObject == true or: [anObject == false or: [anObject isSymbol or: [anObject class isImmediateClass]]]])
		ifTrue: [^anObject].
	anObject class == Array ifTrue: [anObject do: [:each | self freeze: each]].
	anObject beReadOnlyObject.
	^anObject
! !

!BytecodeEncoder methodsFor: 'source map'!
noteStart: start stop: stop
	"Map the instruction about to be emitted to the source interval."
	start isNil ifTrue: [^self].
	sourceMap add: count; add: start; add: stop
!
noteNode: aNode
	self noteStart: aNode start stop: aNode stop
! !

!BytecodeEncoder methodsFor: 'pushing'!
pushTemp: index
	| start |
	start := count.
	index < 16 ifTrue: [self emit: index] ifFalse: [self emit: 16r80 operand: index].
	self notePush: #temp operand: index from: start.
	self push
!
pushInstVar: index
	index < 16 ifTrue: [self emit: 16r10 + index] ifFalse: [self emit: 16r81 operand: index].
	self push
!
pushOuterTemp: index depth: d
	self emit: 16r8A operand: d operand: index.
	self push
!
pushLiteral: anObject
	"Push a constant."
	| index start |
	anObject isNil ifTrue: [^self pushNil].
	anObject == true ifTrue: [self emit: 16r71. ^self push].
	anObject == false ifTrue: [self emit: 16r72. ^self push].
	start := count.
	anObject class == SmallInteger ifTrue: [
		anObject = 0
			ifTrue: [self emit: 16r74]
			ifFalse: [
				anObject = 1
					ifTrue: [self emit: 16r75]
					ifFalse: [
						(anObject >= -32768 and: [anObject <= 32767]) ifTrue: [
							self emit: 16r93.
							self emitInt16: anObject]]].
		count > start ifTrue: [
			(anObject between: -128 and: 127) ifTrue: [self notePush: #int operand: anObject from: start].
			^self push]].
	index := self literalIndexOf: (self freeze: anObject).
	index < 32 ifTrue: [self emit: 16r20 + index] ifFalse: [self emit: 16r82 operand: index].
	self notePush: #lit operand: index from: start.
	self push
!
pushLiteralVariable: anAssociation
	| index |
	index := self literalIndexOf: anAssociation.
	index < 32 ifTrue: [self emit: 16r40 + index] ifFalse: [self emit: 16r83 operand: index].
	self push
!
pushSelf
	self emit: 16r70.
	self push
!
pushNil
	self emit: 16r73.
	self push
!
pushThisContext
	self emit: 16r76.
	self push
!
dup
	self emit: 16r77.
	self push
!
pop
	self emit: 16r78.
	self pop: 1
! !

!BytecodeEncoder methodsFor: 'storing'!
storeTemp: index
	self emit: 16r84 operand: index
!
popStoreTemp: index
	index < 8 ifTrue: [self emit: 16r60 + index] ifFalse: [self emit: 16r87 operand: index].
	self pop: 1
!
storeInstVar: index
	self emit: 16r85 operand: index
!
storeLiteralVariable: anAssociation
	self emit: 16r86 operand: (self literalIndexOf: anAssociation)
!
popStoreLiteralVariable: anAssociation
	self emit: 16r89 operand: (self literalIndexOf: anAssociation).
	self pop: 1
!
storeOuterTemp: index depth: d
	self emit: 16r8B operand: d operand: index
!
popStoreOuterTemp: index depth: d
	self emit: 16r8C operand: d operand: index.
	self pop: 1
! !

!BytecodeEncoder methodsFor: 'returning'!
returnTop
	self emit: 16r79.
	self pop: 1
!
returnSelf
	self emit: 16r7A
!
blockReturnTop
	self emit: 16r7B.
	self pop: 1
!
nonLocalReturnTop
	self emit: 16r7C.
	self pop: 1
! !

!BytecodeEncoder methodsFor: 'sending'!
send: selector numArgs: n super: isSuper
	| special index |
	(isSuper not and: [n = 1 and: [self fuseSend: (Compiler specialSelectorIndexOf: selector)]]) ifTrue: [^self pop: 1].
	isSuper
		ifTrue: [self emit: 16r8E operand: (self literalIndexOf: selector) operand: n]
		ifFalse: [
			special := Compiler specialSelectorIndexOf: selector.
			special > 0
				ifTrue: [self emit: 16rA0 + special - 1]
				ifFalse: [
					index := self literalIndexOf: selector.
					(index < 16 and: [n <= 2])
						ifTrue: [self emit: 16rC0 + (n * 16) + index]
						ifFalse: [self emit: 16r8D operand: index operand: n]]].
	self pop: n
!
makeArray: n
	self emit: 16r94 operand: n.
	self pop: n.
	self push
! !

!BytecodeEncoder methodsFor: 'superinstructions'!
notePush: kind operand: anInteger from: start
	"Remember a push that the next send may fuse."
	pushes addLast: (Array with: start with: count with: kind with: anInteger).
	pushes size > 2 ifTrue: [pushes removeFirst]
!
fuseSend: special
	"If the last two instructions are a push temp and a push temp, literal or small integer that only this send consumes, replace all three by one superinstruction (16r97 temp temp op, 16r98 temp literal op, 16r99 temp int8 op, op = the special send bytecode; for + - < > <= >= the selector is in the opcode: 16r9A-16r9F temp temp, 16rF0-16rF5 temp literal, 16rF6-16rFB temp int8). Answer whether done."
	| first second operand interval |
	(special between: 1 and: 17) ifFalse: [^false].
	special = 12 ifTrue: [^false].
	pushes size < 2 ifTrue: [^false].
	first := pushes first.
	second := pushes last.
	((second at: 2) = count and: [(first at: 2) = (second at: 1) and: [(first at: 3) == #temp and: [barrier <= (first at: 1)]]])
		ifFalse: [^false].
	(first at: 4) > 255 ifTrue: [^false].
	operand := second at: 4.
	(second at: 3) == #int ifTrue: [operand < 0 ifTrue: [operand := operand + 256]].
	operand > 255 ifTrue: [^false].
	interval := (sourceMap size >= 3 and: [(sourceMap at: sourceMap size - 2) = count])
		ifTrue: [Array with: (sourceMap at: sourceMap size - 1) with: sourceMap last].
	[sourceMap size >= 3 and: [(sourceMap at: sourceMap size - 2) >= (first at: 1)]] whileTrue: [
		sourceMap removeLast; removeLast; removeLast].
	count := first at: 1.
	interval isNil ifFalse: [sourceMap add: count; add: interval first; add: interval last].
	special <= 6
		ifTrue: [
			self emit: ((second at: 3) == #temp ifTrue: [16r9A] ifFalse: [(second at: 3) == #lit ifTrue: [16rF0] ifFalse: [16rF6]]) + special - 1.
			self emit: (first at: 4).
			self emit: operand]
		ifFalse: [
			self emit: ((second at: 3) == #temp ifTrue: [16r97] ifFalse: [(second at: 3) == #lit ifTrue: [16r98] ifFalse: [16r99]]).
			self emit: (first at: 4).
			self emit: operand.
			self emit: 16rA0 + special - 1].
	pushes := OrderedCollection new.
	^true
! !

!BytecodeEncoder methodsFor: 'jumps'!
jump
	"Emit a forward jump; answer the position to patch."
	self emit: 16r90.
	self emit: 0.
	self emit: 0.
	^count - 2
!
jumpTrue
	self pop: 1.
	self emit: 16r91.
	self emit: 0.
	self emit: 0.
	^count - 2
!
jumpFalse
	self pop: 1.
	self emit: 16r92.
	self emit: 0.
	self emit: 0.
	^count - 2
!
patchJump: position
	"Make the jump whose operand is at position go to the current pc."
	| offset v |
	barrier := count.
	offset := count - (position + 2).
	offset > 32767 ifTrue: [^self compileError: 'Method too large'].
	v := offset.
	self byteAt: position put: v \\ 256.
	self byteAt: position + 1 put: v // 256
!
jumpBackTo: aPc
	self emit: 16r90.
	self emitInt16: aPc - (count + 2)
!
jumpBackTo: aPc if: aBoolean
	"Pop; jump back to aPc if it was aBoolean."
	self pop: 1.
	self emit: (aBoolean ifTrue: [16r91] ifFalse: [16r92]).
	self emitInt16: aPc - (count + 2)
! !

!BytecodeEncoder methodsFor: 'closures'!
pushClosureNumArgs: n
	"Emit a closure header with placeholders; answer the position to patch with patchClosure:numTemps:frameSize:."
	self emit: 16r8F operand: n.
	self emit: 0.
	self emit: 0.
	self emit: 0.
	self emit: 0.
	^count - 4
!
patchClosure: position numTemps: t frameSize: f
	| size |
	(t > 255 or: [f > 255]) ifTrue: [^self compileError: 'Block too large'].
	size := count - (position + 4).
	size > 65535 ifTrue: [^self compileError: 'Block too large'].
	self byteAt: position put: t.
	self byteAt: position + 1 put: f.
	self byteAt: position + 2 put: size // 256.
	self byteAt: position + 3 put: size \\ 256
! !
