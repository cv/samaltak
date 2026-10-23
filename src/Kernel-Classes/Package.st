Object subclass: #Package
	instanceVariableNames: 'name layer comment'
	classVariableNames: ''
	package: 'Kernel-Classes'!

Package comment: 'I describe a package: a named unit of source (one directory in src/) on one layer. Layer n may only use layer n-1 and the Kernel (layer 0). My classes are the classes whose package is my name.'!

!Package methodsFor: 'accessing'!
name
	^name
!
name: aString
	name := aString
!
layer
	^layer
!
layer: anInteger
	layer := anInteger
!
comment
	^comment
!
comment: aString
	comment := aString
!
classes
	"Answer my classes, sorted by name."
	| result |
	result := OrderedCollection new.
	Smalltalk allClassesDo: [:c | c packageName = name ifTrue: [result add: c]].
	^(result asSortedCollection: [:a :b | a name <= b name]) asArray
!
classesInLoadOrder
	"Answer my classes, superclasses before subclasses."
	| remaining result |
	remaining := self classes asOrderedCollection.
	result := OrderedCollection new.
	[remaining isEmpty] whileFalse: [
		| ready |
		ready := remaining select: [:c | (remaining includes: c superclass) not].
		result addAll: ready.
		remaining removeAll: ready].
	^result asArray
!
extensionMethods
	"Answer methods my package adds to classes of other packages (method category '*Name...')."
	| result prefix |
	result := OrderedCollection new.
	prefix := '*', name.
	Smalltalk allMethodsDo: [:m |
		(m category notNil and: [m category beginsWith: prefix]) ifTrue: [result add: m]].
	^result asArray
! !

!Package methodsFor: 'comparing'!
= aPackage
	^self class == aPackage class and: [name = aPackage name]
!
hash
	^name hash
! !

!Package methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Package('; nextPutAll: name; nextPut: $)
! !

!Package class methodsFor: 'instance creation'!
named: aString layer: anInteger
	^self new name: aString; layer: anInteger; yourself
! !
