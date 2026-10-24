Object subclass: #Arm64CodeAnnotations
	instanceVariableNames: 'comments bytecodes symbols'
	classVariableNames: ''
	package: 'VM-Jit'!

Arm64CodeAnnotations comment: 'What a JIT compiler records about the code it emits, for Arm64Disassembler''s annotated listing: comments and the bytecodes at byte offsets from the start of the code, names of addresses (runtime entry points).'!

!Arm64CodeAnnotations methodsFor: 'initialization'!
initialize
	comments := Dictionary new.
	bytecodes := Dictionary new.
	symbols := Dictionary new
! !

!Arm64CodeAnnotations methodsFor: 'adding'!
addComment: aString at: offset
	(comments at: offset ifAbsentPut: [OrderedCollection new]) add: aString
!
addBytecode: pc text: aString source: aStringOrNil at: offset
	"the code of the bytecode at pc starts at offset"
	(bytecodes at: offset ifAbsentPut: [OrderedCollection new]) add: {pc. aString. aStringOrNil}
!
addSymbol: aString at: anAddress
	symbols at: anAddress put: aString
! !

!Arm64CodeAnnotations methodsFor: 'accessing'!
commentsAt: offset
	^comments at: offset ifAbsent: [#()]
!
bytecodesAt: offset
	"{pc. text. source or nil} of each bytecode whose code starts at offset"
	^bytecodes at: offset ifAbsent: [#()]
!
symbolAt: anAddress
	^symbols at: anAddress ifAbsent: [nil]
!
comments
	^comments
!
bytecodes
	^bytecodes
!
symbols
	^symbols
! !
