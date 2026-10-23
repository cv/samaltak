Object subclass: #ProfileFrameTable
	instanceVariableNames: 'methods blocks unknown'
	classVariableNames: ''
	package: 'System-Profiling'!

ProfileFrameTable comment: 'I intern ProfileFrames: one per CompiledMethod and one per (method, block startpc), so profile trees can key their children by identity and tools can keep references (zoom paths, selections) across refreshes.'!

!ProfileFrameTable methodsFor: 'accessing'!
frameFor: aCompiledMethod startpc: anIntegerOrNil
	| perMethod |
	anIntegerOrNil isNil ifTrue: [
		^methods at: aCompiledMethod ifAbsent: [
			methods at: aCompiledMethod put: (ProfileFrame method: aCompiledMethod startpc: nil)]].
	perMethod := blocks at: aCompiledMethod ifAbsent: [blocks at: aCompiledMethod put: Dictionary new].
	^perMethod at: anIntegerOrNil ifAbsent: [
		perMethod at: anIntegerOrNil put: (ProfileFrame method: aCompiledMethod startpc: anIntegerOrNil)]
!
unknownFrame
	"A frame the profiler could not identify (its frame table was full)."
	^unknown ifNil: [unknown := ProfileFrame method: nil startpc: nil]
!
size
	^methods size + (blocks inject: 0 into: [:sum :each | sum + each size])
! !

!ProfileFrameTable methodsFor: 'initialization'!
initialize
	methods := IdentityDictionary new.
	blocks := IdentityDictionary new
! !
