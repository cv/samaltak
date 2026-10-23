Object subclass: #ProfileFrame
	instanceVariableNames: 'method startpc label'
	classVariableNames: ''
	package: 'System-Profiling'!

ProfileFrame comment: 'I identify the code of one sampled stack frame: a CompiledMethod, or a block in it (startpc is the block''s first bytecode, nil for the method itself). The Profiler interns me (see ProfileFrameTable), so equal frames are identical. My label reads like MessageTally''s: MandelbrotView>>renderRow: or [] in MandelbrotView>>render.'!

!ProfileFrame methodsFor: 'accessing'!
method
	"Answer the CompiledMethod (for a block: its home method)."
	^method
!
startpc
	^startpc
!
methodClass
	^method methodClass
!
selector
	^method selector
!
label
	^label ifNil: [label := self computeLabel]
!
name
	^self label
! !

!ProfileFrame methodsFor: 'testing'!
isBlock
	^startpc notNil
! !

!ProfileFrame methodsFor: 'printing'!
computeLabel
	| base |
	base := method isNil ifTrue: ['?'] ifFalse: [method printString].
	^startpc isNil ifTrue: [base] ifFalse: ['[] in ', base]
!
printOn: aStream
	aStream nextPutAll: self label
! !

!ProfileFrame methodsFor: 'private'!
setMethod: aCompiledMethod startpc: anIntegerOrNil
	method := aCompiledMethod.
	startpc := anIntegerOrNil
! !

!ProfileFrame class methodsFor: 'instance creation'!
method: aCompiledMethod startpc: anIntegerOrNil
	^self new setMethod: aCompiledMethod startpc: anIntegerOrNil
! !
