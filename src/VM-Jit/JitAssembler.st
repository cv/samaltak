Arm64Module subclass: #JitAssembler
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Jit'!

JitAssembler comment: 'I am the assembler the code generators write with (asm in JitCompiler and JitRuntime): an arch interface (VMModule class>>isArchInterface), so the translation for each CPU connects them to my subclass for it, whose inline instruction methods expand into their code: Arm64Assembler on arm64, Amd64Assembler on x86_64. Both take the same messages, arm64''s instructions with arm64''s registers (Arm64Module); Amd64Assembler emits each as x86-64 code.'!

!JitAssembler class methodsFor: 'declaring'!
isAbstractModule
	^self == JitAssembler
!
isArchInterface
	^self == JitAssembler
! !
