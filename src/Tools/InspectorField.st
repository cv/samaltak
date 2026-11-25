Object subclass: #InspectorField
	instanceVariableNames: 'name kind key'
	classVariableNames: ''
	package: 'Tools'!

InspectorField comment: 'I am one row of an Inspector: self, class, a named instance variable (#ivar, key = its index), an indexed slot (#index, key = the index), a dictionary key (#key) or a value the object computes for its inspectors (#computed, key = a block of the object: inspectorExtraFields, e.g. a CudaArray''s values copied from the device). I fetch my value from the inspected object every time, so the inspector shows the object as it is now.'!

!InspectorField methodsFor: 'accessing'!
setName: aString kind: aSymbol key: anObject
	name := aString.
	kind := aSymbol.
	key := anObject
!
name
	^name
!
kind
	^kind
!
key
	^key
!
isInstVar
	^kind == #ivar
!
isPseudo
	^kind == #self or: [kind == #class]
!
valueIn: anObject
	kind == #self ifTrue: [^anObject].
	kind == #class ifTrue: [^anObject class].
	kind == #ivar ifTrue: [^anObject instVarAt: key].
	kind == #index ifTrue: [^(anObject isKindOf: OrderedCollection) ifTrue: [anObject at: key] ifFalse: [anObject basicAt: key]].
	kind == #key ifTrue: [^anObject at: key ifAbsent: [nil]].
	kind == #computed ifTrue: [^key value: anObject].
	^nil
!
printOn: aStream
	aStream nextPutAll: 'a Field('; nextPutAll: name; nextPut: $)
! !

!InspectorField class methodsFor: 'instance creation'!
name: aString kind: aSymbol key: anObject
	^self new setName: aString kind: aSymbol key: anObject
!
fieldsOf: anObject
	"self, class, then named instance variables, then indexed slots or dictionary keys (at most 500)."
	| fields cls n |
	fields := OrderedCollection new.
	fields add: (self name: 'self' kind: #self key: nil).
	fields add: (self name: 'class' kind: #class key: nil).
	cls := anObject class.
	(anObject isKindOf: Dictionary) ifTrue: [
		((anObject keys asSortedCollection: [:a :b | a printString <= b printString]) asArray first: (anObject size min: 500))
			do: [:k | fields add: (self name: k printString kind: #key key: k)].
		^fields asArray].
	cls allInstVarNames doWithIndex: [:ivar :i | fields add: (self name: ivar kind: #ivar key: i)].
	(anObject respondsTo: #inspectorExtraFields) ifTrue: [
		anObject inspectorExtraFields do: [:each | fields add: (self name: each key kind: #computed key: each value)]].
	(anObject isKindOf: OrderedCollection) ifTrue: [
		1 to: (anObject size min: 500) do: [:i | fields add: (self name: i printString kind: #index key: i)].
		^fields asArray].
	(cls isVariable and: [cls isImmediateClass not]) ifTrue: [
		n := anObject basicSize min: 500.
		1 to: n do: [:i | fields add: (self name: i printString kind: #index key: i)]].
	^fields asArray
! !
