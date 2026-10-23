TestCase subclass: #CompilerFixpointTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Compiler'!

CompilerFixpointTest comment: 'After stage 2 every method in the image was compiled by the Smalltalk compiler. Recompiling each one again must give identical bytecodes, literals (by value), numTemps and frameSize.'!

!CompilerFixpointTest methodsFor: 'accessing'!
timeLimitMilliseconds
	"Recompiling the image takes about 14 s under SAMALTAK_VERIFY_GC with a 1 MB eden, more on a loaded machine."
	^120000
! !

!CompilerFixpointTest methodsFor: 'helpers'!
literal: a matches: b
	a == b ifTrue: [^true].
	a class == b class ifFalse: [^false].
	a class == Array ifTrue: [
		a size = b size ifFalse: [^false].
		1 to: a size do: [:i | (self literal: (a at: i) matches: (b at: i)) ifFalse: [^false]].
		^true].
	(a isKindOf: LookupKey) ifTrue: [^false].
	^a = b
!
method: old matches: new
	old bytecodes = new bytecodes ifFalse: [^false].
	old numTemps = new numTemps ifFalse: [^false].
	old frameSize = new frameSize ifFalse: [^false].
	old numArgs = new numArgs ifFalse: [^false].
	old primitive = new primitive ifFalse: [^false].
	^self literal: old literals asArray matches: new literals asArray
! !

!CompilerFixpointTest methodsFor: 'tests'!
testEveryStopIsMapped
	"After stage 2, every send, store, return and closure push in the image has a sourceMap entry."
	| unmapped |
	Compiler hasRecompiledAll ifFalse: [^self].
	unmapped := OrderedCollection new.
	Smalltalk allBehaviorsDo: [:behavior |
		behavior methodsDo: [:method |
			(method source notNil and: [(CompilerTest unmappedStopsIn: method) notEmpty])
				ifTrue: [unmapped add: method printString]]].
	self assert: unmapped isEmpty description: 'unmapped stops in: ' , (unmapped asArray first: (unmapped size min: 20)) printString
!
testFixpoint
	| mismatches count |
	Compiler hasRecompiledAll ifFalse: [^self].
	mismatches := OrderedCollection new.
	count := 0.
	Smalltalk allBehaviorsDo: [:behavior |
		behavior methodsDo: [:method |
			| new |
			method source isNil ifFalse: [
				count := count + 1.
				new := Compiler compileMethod: method source in: behavior classified: method category.
				(self method: method matches: new) ifFalse: [mismatches add: method printString]]]].
	self assert: count > 1000.
	self assert: mismatches isEmpty description: 'not a fixpoint: ' , mismatches asArray printString
! !
