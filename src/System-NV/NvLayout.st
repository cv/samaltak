Object subclass: #NvLayout
	instanceVariableNames: 'name size align fields'
	classVariableNames: ''
	package: 'System-NV'!

NvLayout comment: 'I am the memory layout of a C struct, computed from its declaration the way the C compiler (gcc and clang on arm64 and x86-64) lays it out: each member at the next offset aligned to its alignment (1 in a packed struct), the size rounded up to the largest alignment. fields maps every member''s name, nested ones as ''outer.inner'' (members of anonymous unions and structs by their own names), to {offset. size}. NvGsp declares the GSP structures this way; NvGspLayoutTest checks every offset and size against what the compiler says from NVIDIA''s headers (NvGspLayouts).

A declaration is an Array of {name. type}; a type is #u8 #u16 #u32 #u64 #bool (1 byte) #enum (4) #handle (4), {#array. type. count} (count 0: a flexible array member), {#struct. declaration} or {#packed. declaration}, {#union. member. member...} (each member a {name. type}, all at offset 0), or {#aligned. n. type} (NV_DECLARE_ALIGNED). A nil name makes an anonymous member.

	(NvLayout named: ''pair'' declaration: #((''a'' #u8) (''b'' #u32))) offsetOf: ''b''	"4"'!

!NvLayout class methodsFor: 'instance creation'!
named: aString declaration: anArray
	^self named: aString declaration: anArray packed: false
!
named: aString declaration: anArray packed: aBoolean
	^self new setName: aString; layOut: anArray packed: aBoolean; yourself
! !

!NvLayout methodsFor: 'initialization'!
setName: aString
	name := aString
!
layOut: declaration packed: packed
	"Compute my fields, size and alignment."
	| offset |
	fields := Dictionary new.
	offset := 0.
	align := 1.
	declaration do: [:member | | info a |
		info := self infoOf: member last packed: packed.
		a := packed ifTrue: [1] ifFalse: [info at: 2].
		offset := self align: offset to: a.
		self add: member first offset: offset info: info.
		offset := offset + info first.
		align := align max: a].
	size := self align: offset to: align
! !

!NvLayout methodsFor: 'accessing'!
name
	^name
!
size
	^size
!
align
	^align
!
fields
	"name -> {offset. size}"
	^fields
!
offsetOf: aName
	^(self fieldAt: aName) first
!
sizeOf: aName
	^(self fieldAt: aName) last
!
fieldAt: aName
	^fields at: aName ifAbsent: [self error: name, ' has no field ', aName printString]
!
includes: aName
	^fields includesKey: aName
! !

!NvLayout methodsFor: 'private'!
align: offset to: n
	^offset + n - 1 // n * n
!
add: aName offset: offset info: info
	"info: {size. align. inner fields (name -> {offset. size}) or nil}"
	aName isNil ifFalse: [fields at: aName put: (Array with: offset with: info first)].
	(info at: 3) ifNotNil: [:inner |
		inner keysAndValuesDo: [:k :v |
			fields at: (aName isNil ifTrue: [k] ifFalse: [aName, '.', k]) put: (Array with: offset + v first with: v last)]]
!
infoOf: type packed: packed
	"{size. alignment. inner fields or nil}"
	| inner |
	type isSymbol ifTrue: [| n |
		n := #(#u8 1 #bool 1 #u16 2 #u32 4 #enum 4 #handle 4 #u64 8) at: (#(#u8 #bool #u16 #u32 #enum #handle #u64) indexOf: type) * 2 ifAbsent: [self error: 'unknown type ', type].
		^Array with: n with: n with: nil].
	type first = #array ifTrue: [| element |
		element := self infoOf: (type at: 2) packed: packed.
		^Array with: element first * (type at: 3) with: (element at: 2) with: nil].
	(type first = #struct or: [type first = #packed]) ifTrue: [
		inner := NvLayout new setName: name; layOut: (type at: 2) packed: (packed or: [type first = #packed]); yourself.
		^Array with: inner size with: inner align with: inner fields].
	type first = #union ifTrue: [| big a f |
		big := 0.
		a := 1.
		f := Dictionary new.
		type allButFirst do: [:member | | info |
			info := self infoOf: member last packed: packed.
			big := big max: info first.
			a := a max: (info at: 2).
			member first isNil ifFalse: [f at: member first put: (Array with: 0 with: info first)].
			(info at: 3) ifNotNil: [:d | d keysAndValuesDo: [:k :v | f at: (member first isNil ifTrue: [k] ifFalse: [member first, '.', k]) put: v]]].
		^Array with: (self align: big to: a) with: a with: f].
	type first = #aligned ifTrue: [| info |
		info := self infoOf: (type at: 3) packed: packed.
		^Array with: info first with: (type at: 2) with: (info at: 3)].
	^self error: 'unknown type ', type printString
! !
