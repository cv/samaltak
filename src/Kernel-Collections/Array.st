ArrayedCollection variableSubclass: #Array
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

Array comment: 'I am a fixed-size sequence of arbitrary objects. Literal arrays #(1 #two $3) and brace arrays {a. b} create me.'!

!Array methodsFor: 'testing'!
isArray
	^true
!
isLiteral
	"Answer whether every element has a literal form, so that I print as #(...)."
	^self allSatisfy: [:each | each isLiteral]
!
refersToLiteral: anObject
	^self anySatisfy: [:each |
		each == anObject
			or: [(each class == anObject class and: [each = anObject])
			or: [each class == Array and: [each refersToLiteral: anObject]]]]
! !

!Array methodsFor: 'printing'!
printOn: aStream
	"#(1 2 3), and with other elements their printStrings: #((3/4) 3@4 'text')."
	self printAsLiteralOn: aStream
!
printAsLiteralOn: aStream
	aStream nextPutAll: '#('.
	self do: [:each | aStream print: each] separatedBy: [aStream space].
	aStream nextPut: $)
!
storeOn: aStream
	self isLiteral ifTrue: [^self printAsLiteralOn: aStream].
	aStream nextPut: ${.
	self do: [:each | aStream store: each] separatedBy: [aStream nextPutAll: '. '].
	aStream nextPut: $}
! !

!Array methodsFor: 'converting'!
asArray
	^self class == Array ifTrue: [self] ifFalse: [super asArray]
! !

!Array methodsFor: 'copying'!
copyWith: anObject
	| result |
	result := Array new: self size + 1.
	result replaceFrom: 1 to: self size with: self startingAt: 1.
	result at: self size + 1 put: anObject.
	^result
! !
