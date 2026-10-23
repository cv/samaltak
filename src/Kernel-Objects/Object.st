ProtoObject subclass: #Object
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Objects'!

Object comment: 'I am the root of almost every class. I define the protocol all ordinary objects share: comparing, copying, printing, error handling, reflection, indexed access and immutability.'!

!Object methodsFor: 'comparing'!
= anObject
	"Answer whether the receiver and anObject represent the same value. Subclasses that override me must also override hash."
	^self == anObject
!
~= anObject
	^(self = anObject) == false
!
hash
	"Answer a SmallInteger such that equal objects have equal hashes."
	^self identityHash
! !

!Object methodsFor: 'accessing'!
at: index
	"Answer the indexable field at index (1-based)."
	<primitive: 'at'>
	^self errorSubscriptBounds: index
!
at: index put: value
	"Store value into the indexable field at index (1-based). Answer value."
	<primitive: 'atPut'>
	^self checkedAt: index put: value retrying: #at:put:
!
basicAt: index
	<primitive: 'at'>
	^self errorSubscriptBounds: index
!
basicAt: index put: value
	<primitive: 'atPut'>
	^self checkedAt: index put: value retrying: #basicAt:put:
!
basicSize
	"Answer the number of indexable fields."
	<primitive: 'basicSize'>
	^0
!
size
	"Answer the number of indexable fields."
	<primitive: 'basicSize'>
	^0
!
yourself
	^self
!
value
	"Objects evaluate to themselves, so they can be used where a block is expected."
	^self
! !

!Object methodsFor: 'converting'!
-> anObject
	"Answer an Association with the receiver as key."
	^Association key: self value: anObject
!
asString
	^self printString
!
asOrderedCollection
	^OrderedCollection with: self
! !

!Object methodsFor: 'copying'!
copy
	"Answer a copy of the receiver; subclasses customize postCopy."
	^self shallowCopy postCopy
!
postCopy
	"Fix up a fresh shallow copy. Subclasses copy the parts they must not share."
!
shallowCopy
	"Answer a copy sharing the receiver's fields."
	<primitive: 'shallowCopy' error: ec>
	ec = VMConstants primErrNoMemory ifTrue: [^OutOfMemory signalForClass: self class size: self basicSize].
	self primitiveFailed
!
deepCopy
	"Answer a copy whose fields are copies of the receiver's fields."
	| copy n |
	copy := self shallowCopy.
	n := self class instSize.
	1 to: n do: [:i | copy instVarAt: i put: (self instVarAt: i) copy].
	self class isVariable ifTrue: [
		(self class isPointers) ifTrue: [
			1 to: self basicSize do: [:i | copy basicAt: i put: (self basicAt: i) copy]]].
	^copy
! !

!Object methodsFor: 'printing'!
printOn: aStream
	"Append a developer-readable description of the receiver to aStream."
	| title |
	title := self class name.
	aStream
		nextPutAll: (title first isVowel ifTrue: ['an '] ifFalse: ['a ']);
		nextPutAll: title
!
printString
	"Answer a String describing the receiver for a developer."
	^String new: 16 streamContents: [:stream | self printOn: stream]
!
printString: base
	^self printString
!
printStringLimitedTo: limit
	| s |
	s := self printString.
	^s size > limit
		ifTrue: [(s copyFrom: 1 to: limit), '...']
		ifFalse: [s]
!
displayOn: aStream
	"Append an end-user description of the receiver; defaults to printOn:."
	self printOn: aStream
!
displayString
	"Answer a String describing the receiver for an end user (no quotes around strings)."
	^String new: 16 streamContents: [:stream | self displayOn: stream]
!
displayNl
	"Show the receiver on the Transcript, followed by a newline."
	Transcript show: self displayString; cr
!
printNl
	"Show the receiver's printString on the Transcript, followed by a newline."
	Transcript show: self printString; cr
!
storeOn: aStream
	"Append Smalltalk source that evaluates to an equal object."
	aStream nextPut: $(; nextPutAll: self class name; nextPutAll: ' basicNew'.
	1 to: self class instSize do: [:i |
		aStream nextPutAll: ' instVarAt: '; print: i; nextPutAll: ' put: '.
		(self instVarAt: i) storeOn: aStream.
		aStream nextPut: $;].
	aStream nextPutAll: ' yourself)'
!
storeString
	^String new: 16 streamContents: [:stream | self storeOn: stream]
! !

!Object methodsFor: 'error handling'!
error: aString
	"Signal an Error with aString as message text."
	^Error new signal: aString
!
halt
	"Stop here: signal Halt, which opens a debugger (or prints the stack when headless)."
	^Halt new signal
!
halt: aString
	^Halt new signal: aString
!
shouldBeImplemented
	"Placeholder for code that still has to be written."
	^NotYetImplemented new
		selector: thisContext sender selector;
		signal
!
shouldNotImplement
	^self error: 'This message is not appropriate for this object'
!
subclassResponsibility
	"An abstract method was not overridden."
	^SubclassResponsibility new
		selector: thisContext sender selector;
		signal: 'My subclass should have overridden ', thisContext sender selector printString
!
notYetImplemented
	^self shouldBeImplemented
!
deprecated: aString
	^Warning signal: aString
!
assert: aBlockOrBoolean
	"Fail with an AssertionFailure unless the argument is (or evaluates to) true."
	aBlockOrBoolean value ifFalse: [^AssertionFailure signal: 'Assertion failed']
!
assert: aBlockOrBoolean description: aString
	aBlockOrBoolean value ifFalse: [^AssertionFailure signal: aString value]
!
errorSubscriptBounds: index
	^SubscriptOutOfBounds signalFor: index lowerBound: 1 upperBound: self basicSize in: self
!
errorNonIntegerIndex
	^self error: 'Only integers can be used as indices'
!
errorNotIndexable
	^self error: 'Instances of ', self class name, ' are not indexable'
!
errorImproperStore
	^self error: 'Improper store into indexable object'
!
errorKeyNotFound: aKey
	^KeyNotFound signalFor: aKey in: self
!
errorEmptyCollection
	^CollectionIsEmpty signalOn: self
!
errorNotFound: anObject
	^NotFound signalFor: anObject
!
checkedAt: index put: value retrying: aSelector
	"An at:put:-style primitive failed: explain why."
	self isReadOnlyObject ifTrue: [
		^self modificationForbiddenFor: aSelector index: index value: value].
	index isInteger ifFalse: [^self errorNonIntegerIndex].
	self class isVariable ifFalse: [^self errorNotIndexable].
	(index between: 1 and: self basicSize) ifFalse: [^self errorSubscriptBounds: index].
	^self errorImproperStore
!
modificationForbiddenFor: aSelector index: index value: value
	^(ModificationForbidden new)
		object: self;
		fieldIndex: index;
		newValue: value;
		retrySelector: aSelector;
		signal
!
modificationForbiddenFor: aSelector value: value
	^(ModificationForbidden new)
		object: self;
		newValue: value;
		retrySelector: aSelector;
		signal
! !

!Object methodsFor: 'system primitives'!
attemptToAssign: value withIndex: index
	"The VM sends me when a method tries to store into an instance variable of the receiver while it is read-only."
	^(ModificationForbidden new)
		object: self;
		fieldIndex: index;
		newValue: value;
		retrySelector: #instVarAt:put:;
		signal
!
mustBeBoolean
	"The VM sends me when a conditional jump finds a non-Boolean. Answer the Boolean to use instead."
	^(NonBooleanReceiver new)
		object: self;
		signal: 'proceed for truth.'
!
changeClassTo: aClass
	"Make the receiver an instance of aClass, which must have the same shape."
	<primitive: 'changeClassTo:'>
	self primitiveFailed
! !

!Object methodsFor: 'class membership'!
class
	"Answer the receiver's class."
	<primitive: 'class'>
	self primitiveFailed
!
species
	"Answer the class to use for copies that hold the same kind of elements."
	^self class
!
isKindOf: aClass
	"Answer whether the receiver is an instance of aClass or of one of its subclasses."
	| c |
	c := self class.
	[c == nil] whileFalse: [
		c == aClass ifTrue: [^true].
		c := c superclass].
	^false
!
isMemberOf: aClass
	^self class == aClass
!
respondsTo: aSymbol
	"Answer whether the receiver's class or a superclass implements aSymbol."
	^self class canUnderstand: aSymbol
! !

!Object methodsFor: 'introspection'!
instVarAt: index
	"Answer the receiver's named or indexed field at index (named fields first)."
	<primitive: 'instVarAt'>
	^self errorSubscriptBounds: index
!
instVarAt: index put: value
	<primitive: 'instVarAtPut'>
	self isReadOnlyObject ifTrue: [
		^self modificationForbiddenFor: #instVarAt:put: index: index value: value].
	^self errorSubscriptBounds: index
!
instVarNamed: aString
	^self instVarAt: (self class allInstVarNames indexOf: aString asString)
!
instVarNamed: aString put: value
	^self instVarAt: (self class allInstVarNames indexOf: aString asString) put: value
!
inspect
	"Tools override me to open an Inspector; headless I print the fields."
	Transcript show: self printString; cr.
	self class allInstVarNames doWithIndex: [:name :i |
		Transcript tab; show: name; show: ': '; show: (self instVarAt: i) printString; cr]
! !

!Object methodsFor: 'message performing'!
perform: aSymbol
	<primitive: 'perform'>
	^self perform: aSymbol withArguments: #()
!
perform: aSymbol with: arg1
	<primitive: 'perform'>
	^self perform: aSymbol withArguments: {arg1}
!
perform: aSymbol with: arg1 with: arg2
	<primitive: 'perform'>
	^self perform: aSymbol withArguments: {arg1. arg2}
!
perform: aSymbol with: arg1 with: arg2 with: arg3
	<primitive: 'perform'>
	^self perform: aSymbol withArguments: {arg1. arg2. arg3}
!
perform: aSymbol with: arg1 with: arg2 with: arg3 with: arg4
	<primitive: 'perform'>
	^self perform: aSymbol withArguments: {arg1. arg2. arg3. arg4}
!
perform: aSymbol withArguments: anArray
	<primitive: 'performWithArguments'>
	aSymbol isSymbol ifFalse: [^self error: 'perform: needs a Symbol'].
	aSymbol numArgs = anArray size ifFalse: [^self error: 'Wrong number of arguments'].
	^self primitiveFailed
!
perform: aSymbol withEnoughArguments: anArray
	"Like perform:withArguments: but drop or pad (with nil) the arguments to fit aSymbol."
	| args n |
	n := aSymbol numArgs.
	args := Array new: n.
	1 to: (n min: anArray size) do: [:i | args at: i put: (anArray at: i)].
	^self perform: aSymbol withArguments: args
! !

!Object methodsFor: 'testing'!
isArray
	^false
!
isBehavior
	^false
!
isBlock
	^false
!
isBoolean
	^false
!
isCharacter
	^false
!
isClass
	^false
!
isCollection
	^false
!
isContext
	^false
!
isDictionary
	^false
!
isFloat
	^false
!
isFraction
	^false
!
isInteger
	^false
!
isInterval
	^false
!
isLiteral
	"Answer whether the receiver has a literal text form the compiler accepts."
	^false
!
isNumber
	^false
!
isPoint
	^false
!
isRectangle
	^false
!
isSequenceable
	^false
!
isStream
	^false
!
isString
	^false
!
isSymbol
	^false
!
isCompiledMethod
	^false
!
isEmptyOrNil
	^false
!
isText
	^false
! !

!Object methodsFor: 'immutability'!
isReadOnlyObject
	"Answer whether stores into the receiver are forbidden."
	<primitive: 'isImmutable'>
	^false
!
beReadOnlyObject
	"Forbid stores into the receiver. Answer whether it was read-only before."
	^self setIsReadOnlyObject: true
!
beWritableObject
	"Allow stores into the receiver again. Answer whether it was read-only before."
	^self setIsReadOnlyObject: false
!
setIsReadOnlyObject: aBoolean
	<primitive: 'setImmutable:'>
	self primitiveFailed
! !

