VMModule subclass: #Arm64Module
	instanceVariableNames: ''
	classVariableNames: 'X0 X1 X2 X3 X4 X5 X6 X7 X8 X9 X10 X11 X12 X13 X14 X15 X16 X17 X18 X19 X20 X21 X22 X23 X24 X25 X26 X27 X28 X29 X30 XZR SP W0 W1 W2 W3 W4 W5 W6 W7 W8 W9 W10 W11 W12 W13 W14 W15 W16 W17 W18 W19 W20 W21 W22 W23 W24 W25 W26 W27 W28 W29 W30 WZR WSP D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 D10 D11 D12 D13 D14 D15 D16 D17 D18 D19 D20 D21 D22 D23 D24 D25 D26 D27 D28 D29 D30 D31 COND_EQ COND_NE COND_HS COND_LO COND_MI COND_PL COND_VS COND_VC COND_HI COND_LS COND_GE COND_LT COND_GT COND_LE COND_AL COND_NV COND_CS COND_CC REG_W REG_SP REG_D SHIFT_LSL SHIFT_LSR SHIFT_ASR SHIFT_ROR EXT_UXTB EXT_UXTH EXT_UXTW EXT_UXTX EXT_SXTB EXT_SXTH EXT_SXTW EXT_SXTX EXT_LSL BARRIER_OSHLD BARRIER_OSHST BARRIER_OSH BARRIER_NSHLD BARRIER_NSHST BARRIER_NSH BARRIER_ISHLD BARRIER_ISHST BARRIER_ISH BARRIER_LD BARRIER_ST BARRIER_SY ASM_OK ASM_ERR_FULL ASM_ERR_IMMEDIATE ASM_ERR_RANGE ASM_ERR_LABEL ASM_ERR_OPERAND ASM_ERR_FLAGS ASM_EF_NONE ASM_EF_LOAD ASM_EF_STORE ASM_EF_MOVE ASM_EF_WRITE ASM_EF_FORGET'
	package: 'VM-Jit'!

Arm64Module comment: 'I am the abstract class of the modules that generate arm64 code: my class variables name the registers, condition codes, shifts, extends and barriers the assembler (Arm64Assembler) takes.

A register is a number: X0-X30 0-30, XZR 31, SP 63 (31 + REG_SP), W0-W30 and WZR the same + REG_W, WSP 127, D0-D31 128-159 (REG_D). An instruction takes its width (sf) from its destination register (W or X) and FP registers by their REG_D bit, so one selector covers the 32-bit, 64-bit and FP forms (ldr: W0, X0 or D0).'!

!Arm64Module class methodsFor: 'declaring'!
isAbstractModule
	^self == Arm64Module
!
initialize
	REG_W := 64.
	REG_SP := 32.
	REG_D := 128.
	0 to: 30 do: [:i |
		self classVarNamed: 'X' , i printString put: i.
		self classVarNamed: 'W' , i printString put: i + REG_W].
	0 to: 31 do: [:i | self classVarNamed: 'D' , i printString put: i + REG_D].
	XZR := 31.
	SP := 31 + REG_SP.
	WZR := 31 + REG_W.
	WSP := 31 + REG_SP + REG_W.
	#(#COND_EQ #COND_NE #COND_HS #COND_LO #COND_MI #COND_PL #COND_VS #COND_VC #COND_HI #COND_LS #COND_GE #COND_LT #COND_GT #COND_LE #COND_AL #COND_NV)
		doWithIndex: [:name :i | self classVarNamed: name put: i - 1].
	COND_CS := COND_HS.
	COND_CC := COND_LO.
	SHIFT_LSL := 0.
	SHIFT_LSR := 1.
	SHIFT_ASR := 2.
	SHIFT_ROR := 3.
	#(#EXT_UXTB #EXT_UXTH #EXT_UXTW #EXT_UXTX #EXT_SXTB #EXT_SXTH #EXT_SXTW #EXT_SXTX)
		doWithIndex: [:name :i | self classVarNamed: name put: i - 1].
	"in a register offset, lsl is uxtx"
	EXT_LSL := EXT_UXTX.
	BARRIER_OSHLD := 1.
	BARRIER_OSHST := 2.
	BARRIER_OSH := 3.
	BARRIER_NSHLD := 5.
	BARRIER_NSHST := 6.
	BARRIER_NSH := 7.
	BARRIER_ISHLD := 9.
	BARRIER_ISHST := 10.
	BARRIER_ISH := 11.
	BARRIER_LD := 13.
	BARRIER_ST := 14.
	BARRIER_SY := 15.
	"Arm64Assembler's error codes (the first error sticks)"
	ASM_OK := 0.
	ASM_ERR_FULL := 1.
	ASM_ERR_IMMEDIATE := 2.
	ASM_ERR_RANGE := 3.
	ASM_ERR_LABEL := 4.
	ASM_ERR_OPERAND := 5.
	"Amd64Assembler: an instruction read flags that the x86 code of an instruction since the one that set them destroyed"
	ASM_ERR_FLAGS := 6.
	"what an x86 instruction does to what registers hold (Amd64Assembler>>effectAt:)"
	ASM_EF_NONE := 0.
	ASM_EF_LOAD := 1.
	ASM_EF_STORE := 2.
	ASM_EF_MOVE := 3.
	ASM_EF_WRITE := 4.
	ASM_EF_FORGET := 5
! !
