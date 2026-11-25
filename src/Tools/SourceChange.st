Object subclass: #SourceChange
	instanceVariableNames: 'kind className isMeta selector old new oldCategory newCategory path decision reason'
	classVariableNames: ''
	package: 'Tools'!

SourceChange comment: 'I am one change a SourceUpdate found between two commits'' sources: a method (kind #method: old and new are its source, nil when it is added or removed, with its categories), a class definition (#definition: old and new are specs, SourceUpdate>>specOf:), a class comment (#comment: the strings) or class-side instance variables (#classSide: Arrays of names). decision says what the update does with me: #apply, #already (the image has the new version), #conflict (the image or its pending source changes differ from both: reason says how), #skip (reason says why).'!

!SourceChange methodsFor: 'initialization'!
setKind: aSymbol className: aString isMeta: aBoolean selector: aSelectorOrNil
	kind := aSymbol.
	className := aString.
	isMeta := aBoolean.
	selector := aSelectorOrNil
! !

!SourceChange methodsFor: 'accessing'!
kind
	^kind
!
className
	^className
!
isMeta
	^isMeta
!
selector
	^selector
!
old
	^old
!
old: anObject
	old := anObject
!
new
	^new
!
new: anObject
	new := anObject
!
oldCategory
	^oldCategory
!
oldCategory: aString
	oldCategory := aString
!
newCategory
	^newCategory
!
newCategory: aString
	newCategory := aString
!
path
	"The repository path it lives in (the new one, else the old one)."
	^path
!
path: aString
	path := aString
!
decision
	^decision
!
decision: aSymbol
	decision := aSymbol
!
reason
	^reason
!
decision: aSymbol reason: aString
	decision := aSymbol.
	reason := aString
! !

!SourceChange methodsFor: 'testing'!
isMethod
	^kind == #method
!
isAdded
	^old isNil
!
isRemoved
	^new isNil
!
applies
	^decision == #apply
! !

!SourceChange methodsFor: 'printing'!
label
	"Foo>>bar, Foo class>>bar, Foo (definition), Foo (comment), Foo class (instance variables)."
	kind == #method ifTrue: [^className, (isMeta ifTrue: [' class'] ifFalse: ['']), '>>', selector].
	kind == #definition ifTrue: [^className, ' (definition)'].
	kind == #comment ifTrue: [^className, ' (comment)'].
	^className, ' class (instance variables)'
!
verb
	old isNil ifTrue: [^'added'].
	new isNil ifTrue: [^'removed'].
	^'changed'
!
printOn: aStream
	aStream nextPutAll: self label; nextPutAll: ' ('; nextPutAll: self verb.
	decision isNil ifFalse: [aStream nextPutAll: ', '; nextPutAll: decision].
	aStream nextPut: $)
! !
