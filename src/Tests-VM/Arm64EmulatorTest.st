TestCase subclass: #Arm64EmulatorTest
	instanceVariableNames: 'memory emu code'
	classVariableNames: ''
	package: 'Tests-VM'!

Arm64EmulatorTest comment: 'Arm64Emulator runs code from the system assembler (cc -c, objdump -d). The expected values were taken from running the same instructions and programs on an arm64 CPU.'!

!Arm64EmulatorTest methodsFor: 'running'!
setUp
	memory := SimulatedMemory new.
	emu := Arm64Emulator memory: memory.
	code := memory allocate: 65536
! !

!Arm64EmulatorTest methodsFor: 'helpers'!
load: words at: anAddress
	words doWithIndex: [:w :i | memory uint32At: anAddress + (i - 1 * 4) put: w].
	^anAddress
!
call: words type: aString arguments: anArray
	^emu call: (self load: words at: code) type: (CTypeRegistry default parse: aString) arguments: anArray
!
exec: word
	memory uint32At: code put: word.
	emu pc: code.
	emu step
!
register: aSymbol
	| n |
	aSymbol = #nzcv ifTrue: [^emu nzcv].
	n := (aSymbol copyFrom: 2 to: aSymbol size) asNumber.
	^aSymbol first = $x ifTrue: [emu x: n] ifFalse: [emu dBits: n]
!
register: aSymbol put: anInteger
	| n |
	aSymbol = #nzcv ifTrue: [^emu nzcv: anInteger].
	n := (aSymbol copyFrom: 2 to: aSymbol size) asNumber.
	aSymbol first = $x ifTrue: [emu x: n put: anInteger] ifFalse: [emu dBits: n put: anInteger]
!
check: rows
	"Each row: assembly, word, registers and values before, registers and values after. Flags not listed after must be unchanged."
	rows do: [:row |
		| before after flags |
		before := row at: 3.
		after := row at: 4.
		emu nzcv: 2r0101.
		1 to: before size by: 2 do: [:i | self register: (before at: i) put: (before at: i + 1)].
		flags := emu nzcv.
		self exec: (row at: 2).
		(after includes: #nzcv) ifFalse: [self assert: emu nzcv equals: flags].
		1 to: after size by: 2 do: [:i |
			| actual |
			actual := self register: (after at: i).
			self
				assert: actual = (after at: i + 1)
				description: [(row at: 1) , ' with ' , before printString , ': ' , (after at: i) , ' = 16r' , (actual printStringBase: 16)]]]
!
callback: a with: b
	<c: 'int64_t cb(int64_t a, double b)'>
	^a * 10 + b truncated
!
fibViaEmulator: n
	<c: 'int64_t fibViaEmulator(int64_t n)'>
	^emu call: code + 4096 type: (CTypeRegistry default parse: 'int64_t (int64_t)') arguments: {n}
!
variadic: n
	<c: 'int64_t variadic(int64_t n, ...)'>
	^n
! !

!Arm64EmulatorTest methodsFor: 'tests-instructions'!
testAddSub
	self check: #(
		('adds x2, x0, x1' 16rAB010002 (x0 16r7FFFFFFFFFFFFFFF x1 1) (x2 16r8000000000000000 nzcv 9))
		('adds x2, x0, x1' 16rAB010002 (x0 16rFFFFFFFFFFFFFFFF x1 1) (x2 0 nzcv 6))
		('adds x2, x0, x1' 16rAB010002 (x0 16r8000000000000000 x1 16r8000000000000000) (x2 0 nzcv 7))
		('adds x2, x0, x1' 16rAB010002 (x0 1 x1 2) (x2 3 nzcv 0))
		('adds x2, x0, x1' 16rAB010002 (x0 2 x1 2) (x2 4 nzcv 0))
		('adds x2, x0, x1' 16rAB010002 (x0 16r7FFFFFFF x1 1) (x2 16r80000000 nzcv 0))
		('adds x2, x0, x1' 16rAB010002 (x0 16rFFFFFFFF x1 1) (x2 16r100000000 nzcv 0))
		('adds w2, w0, w1' 16r2B010002 (x0 16r7FFFFFFFFFFFFFFF x1 1) (x2 0 nzcv 6))
		('adds w2, w0, w1' 16r2B010002 (x0 16rFFFFFFFFFFFFFFFF x1 1) (x2 0 nzcv 6))
		('adds w2, w0, w1' 16r2B010002 (x0 16r8000000000000000 x1 16r8000000000000000) (x2 0 nzcv 4))
		('adds w2, w0, w1' 16r2B010002 (x0 1 x1 2) (x2 3 nzcv 0))
		('adds w2, w0, w1' 16r2B010002 (x0 2 x1 2) (x2 4 nzcv 0))
		('adds w2, w0, w1' 16r2B010002 (x0 16r7FFFFFFF x1 1) (x2 16r80000000 nzcv 9))
		('adds w2, w0, w1' 16r2B010002 (x0 16rFFFFFFFF x1 1) (x2 0 nzcv 6))
		('subs x2, x0, x1' 16rEB010002 (x0 16r7FFFFFFFFFFFFFFF x1 1) (x2 16r7FFFFFFFFFFFFFFE nzcv 2))
		('subs x2, x0, x1' 16rEB010002 (x0 16rFFFFFFFFFFFFFFFF x1 1) (x2 16rFFFFFFFFFFFFFFFE nzcv 16rA))
		('subs x2, x0, x1' 16rEB010002 (x0 16r8000000000000000 x1 16r8000000000000000) (x2 0 nzcv 6))
		('subs x2, x0, x1' 16rEB010002 (x0 1 x1 2) (x2 16rFFFFFFFFFFFFFFFF nzcv 8))
		('subs x2, x0, x1' 16rEB010002 (x0 2 x1 2) (x2 0 nzcv 6))
		('subs x2, x0, x1' 16rEB010002 (x0 16r7FFFFFFF x1 1) (x2 16r7FFFFFFE nzcv 2))
		('subs x2, x0, x1' 16rEB010002 (x0 16rFFFFFFFF x1 1) (x2 16rFFFFFFFE nzcv 2))
		('subs w2, w0, w1' 16r6B010002 (x0 16r7FFFFFFFFFFFFFFF x1 1) (x2 16rFFFFFFFE nzcv 16rA))
		('subs w2, w0, w1' 16r6B010002 (x0 16rFFFFFFFFFFFFFFFF x1 1) (x2 16rFFFFFFFE nzcv 16rA))
		('subs w2, w0, w1' 16r6B010002 (x0 16r8000000000000000 x1 16r8000000000000000) (x2 0 nzcv 6))
		('subs w2, w0, w1' 16r6B010002 (x0 1 x1 2) (x2 16rFFFFFFFF nzcv 8))
		('subs w2, w0, w1' 16r6B010002 (x0 2 x1 2) (x2 0 nzcv 6))
		('subs w2, w0, w1' 16r6B010002 (x0 16r7FFFFFFF x1 1) (x2 16r7FFFFFFE nzcv 2))
		('subs w2, w0, w1' 16r6B010002 (x0 16rFFFFFFFF x1 1) (x2 16rFFFFFFFE nzcv 16rA))
		('cmn x0, x1' 16rAB01001F (x0 16r7FFFFFFFFFFFFFFF x1 1) (nzcv 9))
		('cmn x0, x1' 16rAB01001F (x0 16rFFFFFFFFFFFFFFFF x1 1) (nzcv 6))
		('cmn x0, x1' 16rAB01001F (x0 16r8000000000000000 x1 16r8000000000000000) (nzcv 7))
		('cmn x0, x1' 16rAB01001F (x0 1 x1 2) (nzcv 0))
		('cmn x0, x1' 16rAB01001F (x0 2 x1 2) (nzcv 0))
		('cmn x0, x1' 16rAB01001F (x0 16r7FFFFFFF x1 1) (nzcv 0))
		('cmn x0, x1' 16rAB01001F (x0 16rFFFFFFFF x1 1) (nzcv 0))
		('cmp w0, w1' 16r6B01001F (x0 16r7FFFFFFFFFFFFFFF x1 1) (nzcv 16rA))
		('cmp w0, w1' 16r6B01001F (x0 16rFFFFFFFFFFFFFFFF x1 1) (nzcv 16rA))
		('cmp w0, w1' 16r6B01001F (x0 16r8000000000000000 x1 16r8000000000000000) (nzcv 6))
		('cmp w0, w1' 16r6B01001F (x0 1 x1 2) (nzcv 8))
		('cmp w0, w1' 16r6B01001F (x0 2 x1 2) (nzcv 6))
		('cmp w0, w1' 16r6B01001F (x0 16r7FFFFFFF x1 1) (nzcv 2))
		('cmp w0, w1' 16r6B01001F (x0 16rFFFFFFFF x1 1) (nzcv 16rA))
		('adds x2, x0, #4095' 16rB13FFC02 (x0 16r123456789ABCDEF0) (x2 16r123456789ABCEEEF nzcv 0))
		('adds x2, x0, #4095' 16rB13FFC02 (x0 16r8000000000000000) (x2 16r8000000000000FFF nzcv 8))
		('subs x2, x0, #1, lsl #12' 16rF1400402 (x0 16r123456789ABCDEF0) (x2 16r123456789ABCCEF0 nzcv 2))
		('subs x2, x0, #1, lsl #12' 16rF1400402 (x0 16r8000000000000000) (x2 16r7FFFFFFFFFFFF000 nzcv 3))
		('subs w2, w0, #1' 16r71000402 (x0 16r123456789ABCDEF0) (x2 16r9ABCDEEF nzcv 16rA))
		('subs w2, w0, #1' 16r71000402 (x0 16r8000000000000000) (x2 16rFFFFFFFF nzcv 8))
		('adds w2, w0, #0xfff, lsl #12' 16r317FFC02 (x0 16r123456789ABCDEF0) (x2 16r9BBCCEF0 nzcv 8))
		('adds w2, w0, #0xfff, lsl #12' 16r317FFC02 (x0 16r8000000000000000) (x2 16rFFF000 nzcv 0))
		('add x2, x0, x1, lsl #3' 16r8B010C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r91A2B3C4D5E6F70))
		('add x2, x0, x1, lsl #3' 16r8B010C02 (x0 16r8000000000000000 x1 1) (x2 16r8000000000000008))
		('sub x2, x0, x1, asr #5' 16rCB811402 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r123D70A3D70A3D60))
		('sub x2, x0, x1, asr #5' 16rCB811402 (x0 16r8000000000000000 x1 1) (x2 16r8000000000000000))
		('adds w2, w0, w1, lsr #7' 16r2B411C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r9BA98754 nzcv 8))
		('adds w2, w0, w1, lsr #7' 16r2B411C02 (x0 16r8000000000000000 x1 1) (x2 0 nzcv 4))
		('subs x2, x0, x1, lsl #63' 16rEB01FC02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r123456789ABCDEF0 nzcv 2))
		('subs x2, x0, x1, lsl #63' 16rEB01FC02 (x0 16r8000000000000000 x1 1) (x2 0 nzcv 6))
		('add x2, x0, w1, sxtw #2' 16r8B21C802 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r1234567A740DA730))
		('add x2, x0, w1, sxtw #2' 16r8B21C802 (x0 16r8000000000000000 x1 1) (x2 16r8000000000000004))
		('add x2, x0, w1, uxtb' 16r8B210002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r123456789ABCDF00))
		('add x2, x0, w1, uxtb' 16r8B210002 (x0 16r8000000000000000 x1 1) (x2 16r8000000000000001))
		('sub x2, x0, w1, sxth #1' 16rCB21A402 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r123456789ABC7AD0))
		('sub x2, x0, w1, sxth #1' 16rCB21A402 (x0 16r8000000000000000 x1 1) (x2 16r7FFFFFFFFFFFFFFE))
		('adds w2, w0, w1, uxth #4' 16r2B213002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r9ABFFFF0 nzcv 8))
		('adds w2, w0, w1, uxth #4' 16r2B213002 (x0 16r8000000000000000 x1 1) (x2 16r10 nzcv 0))
		('subs x2, x0, x1, sxtx' 16rEB21E002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r13579BE02468ACE0 nzcv 0))
		('subs x2, x0, x1, sxtx' 16rEB21E002 (x0 16r8000000000000000 x1 1) (x2 16r7FFFFFFFFFFFFFFF nzcv 3))
		('subs x2, x0, w1, uxtw #3' 16rEB214C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r12345674E81B4E70 nzcv 2))
		('subs x2, x0, w1, uxtw #3' 16rEB214C02 (x0 16r8000000000000000 x1 1) (x2 16r7FFFFFFFFFFFFFF8 nzcv 3))
		('negs x2, x0' 16rEB0003E2 (x0 16r123456789ABCDEF0) (x2 16rEDCBA98765432110 nzcv 8))
		('negs x2, x0' 16rEB0003E2 (x0 16r8000000000000000) (x2 16r8000000000000000 nzcv 9))
		('negs w2, w0' 16r6B0003E2 (x0 16r123456789ABCDEF0) (x2 16r65432110 nzcv 0))
		('negs w2, w0' 16r6B0003E2 (x0 16r8000000000000000) (x2 0 nzcv 6)))
!
testLogical
	self check: #(
		('and x2, x0, x1' 16r8A010002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r1214121812141210))
		('and x2, x0, x1' 16r8A010002 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 16r8000000000000000))
		('orr x2, x0, x1, lsl #4' 16rAA011002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16rFFFFFFFFFFFFFFF0))
		('orr x2, x0, x1, lsl #4' 16rAA011002 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 16rFFFFFFFFFFFFFFFF))
		('eor x2, x0, x1, ror #13' 16rCAC13402 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r82B3A09D4E7F6C51))
		('eor x2, x0, x1, ror #13' 16rCAC13402 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 16rFFFBFFFFFFFFFFFF))
		('bic x2, x0, x1' 16r8A210002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r20446088A8CCE0))
		('bic x2, x0, x1' 16r8A210002 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 16r7FFFFFFFFFFFFFFF))
		('orn x2, x0, x1, lsr #8' 16rAA612002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16rFF35777DFFBDFFFD))
		('orn x2, x0, x1, lsr #8' 16rAA612002 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 16rFFFFFFFFFFFFFFFF))
		('eon w2, w0, w1, ror #31' 16r4AE17C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r89EB452F))
		('eon w2, w0, w1, ror #31' 16r4AE17C02 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 0))
		('and x2, x0, #0xff00ff00ff00ff00' 16r92089C02 (x0 16r123456789ABCDEF0) (x2 16r120056009A00DE00))
		('and x2, x0, #0xff00ff00ff00ff00' 16r92089C02 (x0 16rFFFFFFFFFFFFFFFF) (x2 16rFF00FF00FF00FF00))
		('orr x2, x0, #0x5555555555555555' 16rB200F002 (x0 16r123456789ABCDEF0) (x2 16r5775577DDFFDDFF5))
		('orr x2, x0, #0x5555555555555555' 16rB200F002 (x0 16rFFFFFFFFFFFFFFFF) (x2 16rFFFFFFFFFFFFFFFF))
		('eor w2, w0, #0xf0f0f0f0' 16r5204CC02 (x0 16r123456789ABCDEF0) (x2 16r6A4C2E00))
		('eor w2, w0, #0xf0f0f0f0' 16r5204CC02 (x0 16rFFFFFFFFFFFFFFFF) (x2 16rF0F0F0F))
		('ands x2, x0, x1' 16rEA010002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r1214121812141210 nzcv 0))
		('ands x2, x0, x1' 16rEA010002 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 16r8000000000000000 nzcv 8))
		('ands x2, x0, x1' 16rEA010002 (x0 0 x1 16r7FFFFFFFFFFFFFFF) (x2 0 nzcv 4))
		('ands w2, w0, w1, asr #3' 16r6A810C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16rA888640 nzcv 0))
		('ands w2, w0, w1, asr #3' 16r6A810C02 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 0 nzcv 4))
		('ands w2, w0, w1, asr #3' 16r6A810C02 (x0 0 x1 16r7FFFFFFFFFFFFFFF) (x2 0 nzcv 4))
		('bics w2, w0, w1' 16r6A210002 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r88A8CCE0 nzcv 8))
		('bics w2, w0, w1' 16r6A210002 (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (x2 16rFFFFFFFF nzcv 8))
		('bics w2, w0, w1' 16r6A210002 (x0 0 x1 16r7FFFFFFFFFFFFFFF) (x2 0 nzcv 4))
		('tst x0, x1' 16rEA01001F (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (nzcv 0))
		('tst x0, x1' 16rEA01001F (x0 16rFFFFFFFFFFFFFFFF x1 16r8000000000000000) (nzcv 8))
		('tst x0, x1' 16rEA01001F (x0 0 x1 16r7FFFFFFFFFFFFFFF) (nzcv 4))
		('ands w2, w0, #0x80000001' 16r72010402 (x0 16r123456789ABCDEF0) (x2 16r80000000 nzcv 8))
		('ands w2, w0, #0x80000001' 16r72010402 (x0 16rFFFFFFFFFFFFFFFF) (x2 16r80000001 nzcv 8))
		('ands w2, w0, #0x80000001' 16r72010402 (x0 0) (x2 0 nzcv 4))
		('ands x2, x0, #0x8000000000000000' 16rF2410002 (x0 16r123456789ABCDEF0) (x2 0 nzcv 4))
		('ands x2, x0, #0x8000000000000000' 16rF2410002 (x0 16rFFFFFFFFFFFFFFFF) (x2 16r8000000000000000 nzcv 8))
		('ands x2, x0, #0x8000000000000000' 16rF2410002 (x0 0) (x2 0 nzcv 4)))
!
testMoveWide
	self check: #(
		('movz x2, #0x1234, lsl #48' 16rD2E24682 () (x2 16r1234000000000000))
		('movn x2, #0x1234, lsl #16' 16r92A24682 () (x2 16rFFFFFFFFEDCBFFFF))
		('movn w2, #0x1234, lsl #16' 16r12A24682 () (x2 16rEDCBFFFF))
		('movk x0, #0xbeef, lsl #32' 16rF2D7DDE0 (x0 16r123456789ABCDEF0) (x0 16r1234BEEF9ABCDEF0))
		('movk w0, #0xbeef, lsl #16' 16r72B7DDE0 (x0 16r123456789ABCDEF0) (x0 16rBEEFDEF0)))
!
testBitfield
	"Shifts by immediate, extends, bitfield moves, extr."
	self check: #(
		('ubfx x2, x0, #8, #16' 16rD3485C02 (x0 16r123456789ABCDEF0) (x2 16rBCDE))
		('ubfx x2, x0, #8, #16' 16rD3485C02 (x0 16rFEDCBA9876543210) (x2 16r5432))
		('sbfx x2, x0, #60, #4' 16r937CFC02 (x0 16r123456789ABCDEF0) (x2 1))
		('sbfx x2, x0, #60, #4' 16r937CFC02 (x0 16rFEDCBA9876543210) (x2 16rFFFFFFFFFFFFFFFF))
		('sbfx w2, w0, #3, #7' 16r13032402 (x0 16r123456789ABCDEF0) (x2 16rFFFFFFDE))
		('sbfx w2, w0, #3, #7' 16r13032402 (x0 16rFEDCBA9876543210) (x2 16rFFFFFFC2))
		('ubfiz x2, x0, #5, #10' 16rD37B2402 (x0 16r123456789ABCDEF0) (x2 16r5E00))
		('ubfiz x2, x0, #5, #10' 16rD37B2402 (x0 16rFEDCBA9876543210) (x2 16r4200))
		('sbfiz x2, x0, #50, #10' 16r934E2402 (x0 16r123456789ABCDEF0) (x2 16rFBC0000000000000))
		('sbfiz x2, x0, #50, #10' 16r934E2402 (x0 16rFEDCBA9876543210) (x2 16rF840000000000000))
		('sbfiz w2, w0, #4, #8' 16r131C1C02 (x0 16r123456789ABCDEF0) (x2 16rFFFFFF00))
		('sbfiz w2, w0, #4, #8' 16r131C1C02 (x0 16rFEDCBA9876543210) (x2 16r100))
		('bfi x0, x1, #8, #12' 16rB3782C20 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x0 16r123456789AB210F0))
		('bfi x0, x1, #8, #12' 16rB3782C20 (x0 16rFEDCBA9876543210 x1 16r123456789ABCDEF0) (x0 16rFEDCBA98765EF010))
		('bfxil x0, x1, #4, #8' 16rB3442C20 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x0 16r123456789ABCDE21))
		('bfxil x0, x1, #4, #8' 16rB3442C20 (x0 16rFEDCBA9876543210 x1 16r123456789ABCDEF0) (x0 16rFEDCBA98765432EF))
		('bfi w0, w1, #28, #4' 16r33040C20 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x0 16rABCDEF0))
		('bfi w0, w1, #28, #4' 16r33040C20 (x0 16rFEDCBA9876543210 x1 16r123456789ABCDEF0) (x0 16r6543210))
		('bfxil w0, w1, #20, #12' 16r33147C20 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x0 16r9ABCD765))
		('bfxil w0, w1, #20, #12' 16r33147C20 (x0 16rFEDCBA9876543210 x1 16r123456789ABCDEF0) (x0 16r765439AB))
		('lsl x2, x0, #17' 16rD36FB802 (x0 16r123456789ABCDEF0) (x2 16rACF13579BDE00000))
		('lsl x2, x0, #17' 16rD36FB802 (x0 16rFEDCBA9876543210) (x2 16r7530ECA864200000))
		('lsr x2, x0, #17' 16rD351FC02 (x0 16r123456789ABCDEF0) (x2 16r91A2B3C4D5E))
		('lsr x2, x0, #17' 16rD351FC02 (x0 16rFEDCBA9876543210) (x2 16r7F6E5D4C3B2A))
		('asr x2, x0, #17' 16r9351FC02 (x0 16r123456789ABCDEF0) (x2 16r91A2B3C4D5E))
		('asr x2, x0, #17' 16r9351FC02 (x0 16rFEDCBA9876543210) (x2 16rFFFFFF6E5D4C3B2A))
		('lsl w2, w0, #5' 16r531B6802 (x0 16r123456789ABCDEF0) (x2 16r579BDE00))
		('lsl w2, w0, #5' 16r531B6802 (x0 16rFEDCBA9876543210) (x2 16rCA864200))
		('lsr w2, w0, #5' 16r53057C02 (x0 16r123456789ABCDEF0) (x2 16r4D5E6F7))
		('lsr w2, w0, #5' 16r53057C02 (x0 16rFEDCBA9876543210) (x2 16r3B2A190))
		('asr w2, w0, #5' 16r13057C02 (x0 16r123456789ABCDEF0) (x2 16rFCD5E6F7))
		('asr w2, w0, #5' 16r13057C02 (x0 16rFEDCBA9876543210) (x2 16r3B2A190))
		('sxtb x2, w0' 16r93401C02 (x0 16r123456789ABCDEF0) (x2 16rFFFFFFFFFFFFFFF0))
		('sxtb x2, w0' 16r93401C02 (x0 16rFEDCBA9876543210) (x2 16r10))
		('sxth x2, w0' 16r93403C02 (x0 16r123456789ABCDEF0) (x2 16rFFFFFFFFFFFFDEF0))
		('sxth x2, w0' 16r93403C02 (x0 16rFEDCBA9876543210) (x2 16r3210))
		('sxtw x2, w0' 16r93407C02 (x0 16r123456789ABCDEF0) (x2 16rFFFFFFFF9ABCDEF0))
		('sxtw x2, w0' 16r93407C02 (x0 16rFEDCBA9876543210) (x2 16r76543210))
		('sxtb w2, w0' 16r13001C02 (x0 16r123456789ABCDEF0) (x2 16rFFFFFFF0))
		('sxtb w2, w0' 16r13001C02 (x0 16rFEDCBA9876543210) (x2 16r10))
		('uxtb w2, w0' 16r53001C02 (x0 16r123456789ABCDEF0) (x2 16rF0))
		('uxtb w2, w0' 16r53001C02 (x0 16rFEDCBA9876543210) (x2 16r10))
		('uxth w2, w0' 16r53003C02 (x0 16r123456789ABCDEF0) (x2 16rDEF0))
		('uxth w2, w0' 16r53003C02 (x0 16rFEDCBA9876543210) (x2 16r3210))
		('extr x2, x0, x1, #13' 16r93C13402 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16rF787F6E5D4C3B2A1))
		('extr x2, x0, x1, #13' 16r93C13402 (x0 16rFEDCBA9876543210 x1 16r123456789ABCDEF0) (x2 16r908091A2B3C4D5E6))
		('extr w2, w0, w1, #7' 16r13811C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16rE0ECA864))
		('extr w2, w0, w1, #7' 16r13811C02 (x0 16rFEDCBA9876543210 x1 16r123456789ABCDEF0) (x2 16r213579BD))
		('ror x2, x0, #5' 16r93C01402 (x0 16r123456789ABCDEF0) (x2 16r8091A2B3C4D5E6F7))
		('ror x2, x0, #5' 16r93C01402 (x0 16rFEDCBA9876543210) (x2 16r87F6E5D4C3B2A190))
		('ror w2, w0, #31' 16r13807C02 (x0 16r123456789ABCDEF0) (x2 16r3579BDE1))
		('ror w2, w0, #31' 16r13807C02 (x0 16rFEDCBA9876543210) (x2 16rECA86420)))
!
testVariableShifts
	self check: #(
		('lsl x2, x0, x1' 16r9AC12002 (x0 16r123456789ABCDEF0 x1 16r3F) (x2 0))
		('lsl x2, x0, x1' 16r9AC12002 (x0 16rFEDCBA9876543210 x1 16r40) (x2 16rFEDCBA9876543210))
		('lsl x2, x0, x1' 16r9AC12002 (x0 16rFEDCBA9876543210 x1 16r80) (x2 16rFEDCBA9876543210))
		('lsr x2, x0, x1' 16r9AC12402 (x0 16r123456789ABCDEF0 x1 16r3F) (x2 0))
		('lsr x2, x0, x1' 16r9AC12402 (x0 16rFEDCBA9876543210 x1 16r40) (x2 16rFEDCBA9876543210))
		('lsr x2, x0, x1' 16r9AC12402 (x0 16rFEDCBA9876543210 x1 16r80) (x2 16rFEDCBA9876543210))
		('asr x2, x0, x1' 16r9AC12802 (x0 16r123456789ABCDEF0 x1 16r3F) (x2 0))
		('asr x2, x0, x1' 16r9AC12802 (x0 16rFEDCBA9876543210 x1 16r40) (x2 16rFEDCBA9876543210))
		('asr x2, x0, x1' 16r9AC12802 (x0 16rFEDCBA9876543210 x1 16r80) (x2 16rFEDCBA9876543210))
		('ror x2, x0, x1' 16r9AC12C02 (x0 16r123456789ABCDEF0 x1 16r3F) (x2 16r2468ACF13579BDE0))
		('ror x2, x0, x1' 16r9AC12C02 (x0 16rFEDCBA9876543210 x1 16r40) (x2 16rFEDCBA9876543210))
		('ror x2, x0, x1' 16r9AC12C02 (x0 16rFEDCBA9876543210 x1 16r80) (x2 16rFEDCBA9876543210))
		('lsl w2, w0, w1' 16r1AC12002 (x0 16r123456789ABCDEF0 x1 16r3F) (x2 0))
		('lsl w2, w0, w1' 16r1AC12002 (x0 16rFEDCBA9876543210 x1 16r40) (x2 16r76543210))
		('lsl w2, w0, w1' 16r1AC12002 (x0 16rFEDCBA9876543210 x1 16r80) (x2 16r76543210))
		('lsr w2, w0, w1' 16r1AC12402 (x0 16r123456789ABCDEF0 x1 16r3F) (x2 1))
		('lsr w2, w0, w1' 16r1AC12402 (x0 16rFEDCBA9876543210 x1 16r40) (x2 16r76543210))
		('lsr w2, w0, w1' 16r1AC12402 (x0 16rFEDCBA9876543210 x1 16r80) (x2 16r76543210))
		('asr w2, w0, w1' 16r1AC12802 (x0 16r123456789ABCDEF0 x1 16r3F) (x2 16rFFFFFFFF))
		('asr w2, w0, w1' 16r1AC12802 (x0 16rFEDCBA9876543210 x1 16r40) (x2 16r76543210))
		('asr w2, w0, w1' 16r1AC12802 (x0 16rFEDCBA9876543210 x1 16r80) (x2 16r76543210))
		('ror w2, w0, w1' 16r1AC12C02 (x0 16r123456789ABCDEF0 x1 16r3F) (x2 16r3579BDE1))
		('ror w2, w0, w1' 16r1AC12C02 (x0 16rFEDCBA9876543210 x1 16r40) (x2 16r76543210))
		('ror w2, w0, w1' 16r1AC12C02 (x0 16rFEDCBA9876543210 x1 16r80) (x2 16r76543210)))
!
testMultiplyDivide
	self check: #(
		('mul x2, x0, x1' 16r9B017C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r236D88FE5618CF00))
		('mul x2, x0, x1' 16r9B017C02 (x0 16rFFFFFFFF80000000 x1 3) (x2 16rFFFFFFFE80000000))
		('mul w2, w0, w1' 16r1B017C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r5618CF00))
		('mul w2, w0, w1' 16r1B017C02 (x0 16rFFFFFFFF80000000 x1 3) (x2 16r80000000))
		('madd x2, x0, x1, x3' 16r9B010C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210 x3 16r7FFFFFFFFFFFFFFF) (x2 16rA36D88FE5618CEFF))
		('madd x2, x0, x1, x3' 16r9B010C02 (x0 16rFFFFFFFF80000000 x1 3 x3 16r40) (x2 16rFFFFFFFE80000040))
		('msub w2, w0, w1, w3' 16r1B018C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210 x3 16r7FFFFFFFFFFFFFFF) (x2 16rA9E730FF))
		('msub w2, w0, w1, w3' 16r1B018C02 (x0 16rFFFFFFFF80000000 x1 3 x3 16r40) (x2 16r80000040))
		('mneg x2, x0, x1' 16r9B01FC02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16rDC927701A9E73100))
		('mneg x2, x0, x1' 16r9B01FC02 (x0 16rFFFFFFFF80000000 x1 3) (x2 16r180000000))
		('smulh x2, x0, x1' 16r9B417C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16rFFEB49923CC09532))
		('smulh x2, x0, x1' 16r9B417C02 (x0 16r8000000000000000 x1 16rFFFFFFFFFFFFFFFF) (x2 0))
		('smulh x2, x0, x1' 16r9B417C02 (x0 16rFFFFFFFFFFFFFFFF x1 16rFFFFFFFFFFFFFFFF) (x2 0))
		('umulh x2, x0, x1' 16r9BC17C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16r121FA00AD77D7422))
		('umulh x2, x0, x1' 16r9BC17C02 (x0 16r8000000000000000 x1 16rFFFFFFFFFFFFFFFF) (x2 16r7FFFFFFFFFFFFFFF))
		('umulh x2, x0, x1' 16r9BC17C02 (x0 16rFFFFFFFFFFFFFFFF x1 16rFFFFFFFFFFFFFFFF) (x2 16rFFFFFFFFFFFFFFFE))
		('sdiv x2, x0, x1' 16r9AC10C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 16rFFFFFFFFFFFFFFF1))
		('sdiv x2, x0, x1' 16r9AC10C02 (x0 16r8000000000000000 x1 16rFFFFFFFFFFFFFFFF) (x2 16r8000000000000000))
		('sdiv x2, x0, x1' 16r9AC10C02 (x0 16r7FFFFFFFFFFFFFFF x1 0) (x2 0))
		('sdiv x2, x0, x1' 16r9AC10C02 (x0 16rFFFFFFFF80000000 x1 3) (x2 16rFFFFFFFFD5555556))
		('sdiv w2, w0, w1' 16r1AC10C02 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 0))
		('sdiv w2, w0, w1' 16r1AC10C02 (x0 16r8000000000000000 x1 16rFFFFFFFFFFFFFFFF) (x2 0))
		('sdiv w2, w0, w1' 16r1AC10C02 (x0 16r7FFFFFFFFFFFFFFF x1 0) (x2 0))
		('sdiv w2, w0, w1' 16r1AC10C02 (x0 16rFFFFFFFF80000000 x1 3) (x2 16rD5555556))
		('udiv x2, x0, x1' 16r9AC10802 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 0))
		('udiv x2, x0, x1' 16r9AC10802 (x0 16r8000000000000000 x1 16rFFFFFFFFFFFFFFFF) (x2 0))
		('udiv x2, x0, x1' 16r9AC10802 (x0 16r7FFFFFFFFFFFFFFF x1 0) (x2 0))
		('udiv x2, x0, x1' 16r9AC10802 (x0 16rFFFFFFFF80000000 x1 3) (x2 16r555555552AAAAAAA))
		('udiv w2, w0, w1' 16r1AC10802 (x0 16r123456789ABCDEF0 x1 16rFEDCBA9876543210) (x2 1))
		('udiv w2, w0, w1' 16r1AC10802 (x0 16r8000000000000000 x1 16rFFFFFFFFFFFFFFFF) (x2 0))
		('udiv w2, w0, w1' 16r1AC10802 (x0 16r7FFFFFFFFFFFFFFF x1 0) (x2 0))
		('udiv w2, w0, w1' 16r1AC10802 (x0 16rFFFFFFFF80000000 x1 3) (x2 16r2AAAAAAA)))
!
testConditionalSelect
	self check: #(
		('csel x2, x0, x1, eq' 16r9A810002 (x0 1 x1 2 nzcv 9) (x2 2))
		('csel x2, x0, x1, eq' 16r9A810002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csel x2, x0, x1, ne' 16r9A811002 (x0 1 x1 2 nzcv 9) (x2 1))
		('csel x2, x0, x1, ne' 16r9A811002 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('csel x2, x0, x1, hs' 16r9A812002 (x0 1 x1 2 nzcv 9) (x2 2))
		('csel x2, x0, x1, hs' 16r9A812002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csel x2, x0, x1, lo' 16r9A813002 (x0 1 x1 2 nzcv 9) (x2 1))
		('csel x2, x0, x1, lo' 16r9A813002 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('csel x2, x0, x1, mi' 16r9A814002 (x0 1 x1 2 nzcv 9) (x2 1))
		('csel x2, x0, x1, mi' 16r9A814002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csel x2, x0, x1, pl' 16r9A815002 (x0 1 x1 2 nzcv 9) (x2 2))
		('csel x2, x0, x1, pl' 16r9A815002 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('csel x2, x0, x1, vs' 16r9A816002 (x0 1 x1 2 nzcv 9) (x2 1))
		('csel x2, x0, x1, vs' 16r9A816002 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('csel x2, x0, x1, vc' 16r9A817002 (x0 1 x1 2 nzcv 9) (x2 2))
		('csel x2, x0, x1, vc' 16r9A817002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csel x2, x0, x1, hi' 16r9A818002 (x0 1 x1 2 nzcv 9) (x2 2))
		('csel x2, x0, x1, hi' 16r9A818002 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('csel x2, x0, x1, ls' 16r9A819002 (x0 1 x1 2 nzcv 9) (x2 1))
		('csel x2, x0, x1, ls' 16r9A819002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csel x2, x0, x1, ge' 16r9A81A002 (x0 1 x1 2 nzcv 9) (x2 1))
		('csel x2, x0, x1, ge' 16r9A81A002 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('csel x2, x0, x1, lt' 16r9A81B002 (x0 1 x1 2 nzcv 9) (x2 2))
		('csel x2, x0, x1, lt' 16r9A81B002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csel x2, x0, x1, gt' 16r9A81C002 (x0 1 x1 2 nzcv 9) (x2 1))
		('csel x2, x0, x1, gt' 16r9A81C002 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('csel x2, x0, x1, le' 16r9A81D002 (x0 1 x1 2 nzcv 9) (x2 2))
		('csel x2, x0, x1, le' 16r9A81D002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csel x2, x0, x1, al' 16r9A81E002 (x0 1 x1 2 nzcv 9) (x2 1))
		('csel x2, x0, x1, al' 16r9A81E002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csinc x2, x0, x1, ne' 16r9A811402 (x0 1 x1 2 nzcv 9) (x2 1))
		('csinc x2, x0, x1, ne' 16r9A811402 (x0 1 x1 3 nzcv 16rA) (x2 1))
		('csinc x2, x0, x1, ne' 16r9A811402 (x0 2 x1 0 nzcv 16rE) (x2 1))
		('csinv w2, w0, w1, lt' 16r5A81B002 (x0 1 x1 2 nzcv 9) (x2 16rFFFFFFFD))
		('csinv w2, w0, w1, lt' 16r5A81B002 (x0 1 x1 3 nzcv 16rA) (x2 1))
		('csinv w2, w0, w1, lt' 16r5A81B002 (x0 2 x1 0 nzcv 16rE) (x2 2))
		('csneg x2, x0, x1, gt' 16rDA81C402 (x0 1 x1 2 nzcv 9) (x2 1))
		('csneg x2, x0, x1, gt' 16rDA81C402 (x0 1 x1 3 nzcv 16rA) (x2 16rFFFFFFFFFFFFFFFD))
		('csneg x2, x0, x1, gt' 16rDA81C402 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('csneg w2, w0, w1, hi' 16r5A818402 (x0 1 x1 2 nzcv 9) (x2 16rFFFFFFFE))
		('csneg w2, w0, w1, hi' 16r5A818402 (x0 1 x1 3 nzcv 16rA) (x2 1))
		('csneg w2, w0, w1, hi' 16r5A818402 (x0 2 x1 0 nzcv 16rE) (x2 0))
		('cset x2, ge' 16r9A9FB7E2 (nzcv 9) (x2 1))
		('cset x2, ge' 16r9A9FB7E2 (nzcv 16rA) (x2 0))
		('cset x2, ge' 16r9A9FB7E2 (nzcv 16rE) (x2 0))
		('csetm w2, ls' 16r5A9F83E2 (nzcv 9) (x2 16rFFFFFFFF))
		('csetm w2, ls' 16r5A9F83E2 (nzcv 16rA) (x2 0))
		('csetm w2, ls' 16r5A9F83E2 (nzcv 16rE) (x2 16rFFFFFFFF)))
!
testCountLeadingZeros
	self check: #(
		('clz x2, x0' 16rDAC01002 (x0 0) (x2 16r40))
		('clz x2, x0' 16rDAC01002 (x0 16rDEADBEEF) (x2 16r20))
		('clz x2, x0' 16rDAC01002 (x0 16rFFFFFFFFFFFFFFFF) (x2 0))
		('clz x2, x0' 16rDAC01002 (x0 1) (x2 16r3F))
		('clz w2, w0' 16r5AC01002 (x0 0) (x2 16r20))
		('clz w2, w0' 16r5AC01002 (x0 16rDEADBEEF) (x2 0))
		('clz w2, w0' 16r5AC01002 (x0 16rFFFFFFFFFFFFFFFF) (x2 0))
		('clz w2, w0' 16r5AC01002 (x0 1) (x2 16r1F)))
!
testFloatArithmetic
	"IEEE: x/0 is +-inf, 0/0 the default NaN, NaN operands propagate (signaling ones first, quieted)."
	self check: #(
		('fadd d2, d0, d1' 16r1E612802 (d0 16r400D99999999999A d1 16rC00D99999999999A) (d2 0))
		('fadd d2, d0, d1' 16r1E612802 (d0 16r3FF0000000000000 d1 0) (d2 16r3FF0000000000000))
		('fadd d2, d0, d1' 16r1E612802 (d0 0 d1 0) (d2 0))
		('fadd d2, d0, d1' 16r1E612802 (d0 16r7FF0000000000000 d1 16rFFF0000000000000) (d2 16r7FF8000000000000))
		('fadd d2, d0, d1' 16r1E612802 (d0 16r7FF4000000000001 d1 16rFFF8000000000123) (d2 16r7FFC000000000001))
		('fadd d2, d0, d1' 16r1E612802 (d0 16r7FE1CCF385EBC8A0 d1 16r7FE1CCF385EBC8A0) (d2 16r7FF0000000000000))
		('fsub d2, d0, d1' 16r1E613802 (d0 16r400D99999999999A d1 16rC00D99999999999A) (d2 16r401D99999999999A))
		('fsub d2, d0, d1' 16r1E613802 (d0 16r3FF0000000000000 d1 0) (d2 16r3FF0000000000000))
		('fsub d2, d0, d1' 16r1E613802 (d0 0 d1 0) (d2 0))
		('fsub d2, d0, d1' 16r1E613802 (d0 16r7FF0000000000000 d1 16rFFF0000000000000) (d2 16r7FF0000000000000))
		('fsub d2, d0, d1' 16r1E613802 (d0 16r7FF4000000000001 d1 16rFFF8000000000123) (d2 16r7FFC000000000001))
		('fsub d2, d0, d1' 16r1E613802 (d0 16r7FE1CCF385EBC8A0 d1 16r7FE1CCF385EBC8A0) (d2 0))
		('fmul d2, d0, d1' 16r1E610802 (d0 16r400D99999999999A d1 16rC00D99999999999A) (d2 16rC02B6147AE147AE2))
		('fmul d2, d0, d1' 16r1E610802 (d0 16r3FF0000000000000 d1 0) (d2 0))
		('fmul d2, d0, d1' 16r1E610802 (d0 0 d1 0) (d2 0))
		('fmul d2, d0, d1' 16r1E610802 (d0 16r7FF0000000000000 d1 16rFFF0000000000000) (d2 16rFFF0000000000000))
		('fmul d2, d0, d1' 16r1E610802 (d0 16r7FF4000000000001 d1 16rFFF8000000000123) (d2 16r7FFC000000000001))
		('fmul d2, d0, d1' 16r1E610802 (d0 16r7FE1CCF385EBC8A0 d1 16r7FE1CCF385EBC8A0) (d2 16r7FF0000000000000))
		('fdiv d2, d0, d1' 16r1E611802 (d0 16r400D99999999999A d1 16rC00D99999999999A) (d2 16rBFF0000000000000))
		('fdiv d2, d0, d1' 16r1E611802 (d0 16r3FF0000000000000 d1 0) (d2 16r7FF0000000000000))
		('fdiv d2, d0, d1' 16r1E611802 (d0 16rBFF0000000000000 d1 16r8000000000000000) (d2 16r7FF0000000000000))
		('fdiv d2, d0, d1' 16r1E611802 (d0 0 d1 0) (d2 16r7FF8000000000000))
		('fdiv d2, d0, d1' 16r1E611802 (d0 16r7FF0000000000000 d1 16rFFF0000000000000) (d2 16r7FF8000000000000))
		('fdiv d2, d0, d1' 16r1E611802 (d0 16r7FF4000000000001 d1 16rFFF8000000000123) (d2 16r7FFC000000000001))
		('fdiv d2, d0, d1' 16r1E611802 (d0 16rFFF8000000000123 d1 16r7FF8000000000000) (d2 16rFFF8000000000123))
		('fdiv d2, d0, d1' 16r1E611802 (d0 16r7FE1CCF385EBC8A0 d1 16r7FE1CCF385EBC8A0) (d2 16r3FF0000000000000))
		('fsqrt d2, d0' 16r1E61C002 (d0 16rBFF0000000000000) (d2 16r7FF8000000000000))
		('fsqrt d2, d0' 16r1E61C002 (d0 16r8000000000000000) (d2 16r8000000000000000))
		('fsqrt d2, d0' 16r1E61C002 (d0 16r7FF4000000000001) (d2 16r7FFC000000000001))
		('fsqrt d2, d0' 16r1E61C002 (d0 16r400D99999999999A) (d2 16r3FFEC6D0353167A9))
		('fsqrt d2, d0' 16r1E61C002 (d0 16r7FF0000000000000) (d2 16r7FF0000000000000))
		('fneg d2, d0' 16r1E614002 (d0 16rBFF0000000000000) (d2 16r3FF0000000000000))
		('fneg d2, d0' 16r1E614002 (d0 16r8000000000000000) (d2 0))
		('fneg d2, d0' 16r1E614002 (d0 16r7FF4000000000001) (d2 16rFFF4000000000001))
		('fneg d2, d0' 16r1E614002 (d0 16r400D99999999999A) (d2 16rC00D99999999999A))
		('fneg d2, d0' 16r1E614002 (d0 16r7FF0000000000000) (d2 16rFFF0000000000000))
		('fabs d2, d0' 16r1E60C002 (d0 16rBFF0000000000000) (d2 16r3FF0000000000000))
		('fabs d2, d0' 16r1E60C002 (d0 16r8000000000000000) (d2 0))
		('fabs d2, d0' 16r1E60C002 (d0 16r7FF4000000000001) (d2 16r7FF4000000000001))
		('fabs d2, d0' 16r1E60C002 (d0 16r400D99999999999A) (d2 16r400D99999999999A))
		('fabs d2, d0' 16r1E60C002 (d0 16r7FF0000000000000) (d2 16r7FF0000000000000)))
!
testFloatCompare
	"Unordered is 2r0011."
	self check: #(
		('fcmp d0, d1' 16r1E612000 (d0 16r3FF0000000000000 d1 16rBFF0000000000000) (nzcv 2))
		('fcmp d0, d1' 16r1E612000 (d0 16rBFF0000000000000 d1 16r3FF0000000000000) (nzcv 8))
		('fcmp d0, d1' 16r1E612000 (d0 0 d1 16r8000000000000000) (nzcv 6))
		('fcmp d0, d1' 16r1E612000 (d0 16r7FF8000000000000 d1 16r3FF0000000000000) (nzcv 3))
		('fcmp d0, d1' 16r1E612000 (d0 16r3FF0000000000000 d1 16r7FF4000000000001) (nzcv 3))
		('fcmp d0, d1' 16r1E612000 (d0 16r7FF0000000000000 d1 16r7FF0000000000000) (nzcv 6))
		('fcmp d0, #0.0' 16r1E602008 (d0 16r3FF0000000000000) (nzcv 2))
		('fcmp d0, #0.0' 16r1E602008 (d0 16rBFF0000000000000) (nzcv 8))
		('fcmp d0, #0.0' 16r1E602008 (d0 0) (nzcv 6))
		('fcmp d0, #0.0' 16r1E602008 (d0 16r7FF8000000000000) (nzcv 3))
		('fcmp d0, #0.0' 16r1E602008 (d0 16r3FF0000000000000) (nzcv 2))
		('fcmp d0, #0.0' 16r1E602008 (d0 16r7FF0000000000000) (nzcv 2))
		('fcmpe d0, d1' 16r1E612010 (d0 16r3FF0000000000000 d1 16rBFF0000000000000) (nzcv 2))
		('fcmpe d0, d1' 16r1E612010 (d0 16rBFF0000000000000 d1 16r3FF0000000000000) (nzcv 8))
		('fcmpe d0, d1' 16r1E612010 (d0 0 d1 16r8000000000000000) (nzcv 6))
		('fcmpe d0, d1' 16r1E612010 (d0 16r7FF8000000000000 d1 16r3FF0000000000000) (nzcv 3))
		('fcmpe d0, d1' 16r1E612010 (d0 16r3FF0000000000000 d1 16r7FF4000000000001) (nzcv 3))
		('fcmpe d0, d1' 16r1E612010 (d0 16r7FF0000000000000 d1 16r7FF0000000000000) (nzcv 6))
		('fcsel d2, d0, d1, gt' 16r1E61CC02 (d0 16r400D99999999999A d1 16rC00D99999999999A nzcv 9) (d2 16r400D99999999999A))
		('fcsel d2, d0, d1, gt' 16r1E61CC02 (d0 16rC00D99999999999A d1 16r400D99999999999A nzcv 16rF) (d2 16r400D99999999999A))
		('fcsel d2, d0, d1, gt' 16r1E61CC02 (d0 16r3FF0000000000000 d1 16rBFF0000000000000 nzcv 1) (d2 16rBFF0000000000000))
		('fcsel d2, d0, d1, vs' 16r1E616C02 (d0 16r400D99999999999A d1 16rC00D99999999999A nzcv 9) (d2 16r400D99999999999A))
		('fcsel d2, d0, d1, vs' 16r1E616C02 (d0 16rC00D99999999999A d1 16r400D99999999999A nzcv 16rF) (d2 16rC00D99999999999A))
		('fcsel d2, d0, d1, vs' 16r1E616C02 (d0 16r3FF0000000000000 d1 16rBFF0000000000000 nzcv 1) (d2 16r3FF0000000000000)))
!
testFloatConversions
	"fcvtz* round toward zero and saturate; NaN converts to 0."
	self check: #(
		('scvtf d2, x0' 16r9E620002 (x0 16rFFFFFFFFFFFFFFFF) (d2 16rBFF0000000000000))
		('scvtf d2, x0' 16r9E620002 (x0 16r8000000000000000) (d2 16rC3E0000000000000))
		('scvtf d2, x0' 16r9E620002 (x0 16r20000000000001) (d2 16r4340000000000000))
		('scvtf d2, x0' 16r9E620002 (x0 16rFFFFFFFF80000000) (d2 16rC1E0000000000000))
		('scvtf d2, w0' 16r1E620002 (x0 16rFFFFFFFFFFFFFFFF) (d2 16rBFF0000000000000))
		('scvtf d2, w0' 16r1E620002 (x0 16r8000000000000000) (d2 0))
		('scvtf d2, w0' 16r1E620002 (x0 16r20000000000001) (d2 16r3FF0000000000000))
		('scvtf d2, w0' 16r1E620002 (x0 16rFFFFFFFF80000000) (d2 16rC1E0000000000000))
		('ucvtf d2, x0' 16r9E630002 (x0 16rFFFFFFFFFFFFFFFF) (d2 16r43F0000000000000))
		('ucvtf d2, x0' 16r9E630002 (x0 16r8000000000000000) (d2 16r43E0000000000000))
		('ucvtf d2, x0' 16r9E630002 (x0 16r20000000000001) (d2 16r4340000000000000))
		('ucvtf d2, x0' 16r9E630002 (x0 16rFFFFFFFF80000000) (d2 16r43EFFFFFFFF00000))
		('ucvtf d2, w0' 16r1E630002 (x0 16rFFFFFFFFFFFFFFFF) (d2 16r41EFFFFFFFE00000))
		('ucvtf d2, w0' 16r1E630002 (x0 16r8000000000000000) (d2 0))
		('ucvtf d2, w0' 16r1E630002 (x0 16r20000000000001) (d2 16r3FF0000000000000))
		('ucvtf d2, w0' 16r1E630002 (x0 16rFFFFFFFF80000000) (d2 16r41E0000000000000))
		('fcvtzs x2, d0' 16r9E780002 (d0 16rC00D99999999999A) (x2 16rFFFFFFFFFFFFFFFD))
		('fcvtzs x2, d0' 16r9E780002 (d0 16r43E0000000000000) (x2 16r7FFFFFFFFFFFFFFF))
		('fcvtzs x2, d0' 16r9E780002 (d0 16rC3E0000000000000) (x2 16r8000000000000000))
		('fcvtzs x2, d0' 16r9E780002 (d0 16r7FF0000000000000) (x2 16r7FFFFFFFFFFFFFFF))
		('fcvtzs x2, d0' 16r9E780002 (d0 16r7FF8000000000000) (x2 0))
		('fcvtzs x2, d0' 16r9E780002 (d0 16rC1E0000000200000) (x2 16rFFFFFFFF7FFFFFFF))
		('fcvtzs x2, d0' 16r9E780002 (d0 16r41EFFFFFFFF00000) (x2 16rFFFFFFFF))
		('fcvtzs w2, d0' 16r1E780002 (d0 16rC00D99999999999A) (x2 16rFFFFFFFD))
		('fcvtzs w2, d0' 16r1E780002 (d0 16r43E0000000000000) (x2 16r7FFFFFFF))
		('fcvtzs w2, d0' 16r1E780002 (d0 16rC3E0000000000000) (x2 16r80000000))
		('fcvtzs w2, d0' 16r1E780002 (d0 16r7FF0000000000000) (x2 16r7FFFFFFF))
		('fcvtzs w2, d0' 16r1E780002 (d0 16r7FF8000000000000) (x2 0))
		('fcvtzs w2, d0' 16r1E780002 (d0 16rC1E0000000200000) (x2 16r80000000))
		('fcvtzs w2, d0' 16r1E780002 (d0 16r41EFFFFFFFF00000) (x2 16r7FFFFFFF))
		('fcvtzu x2, d0' 16r9E790002 (d0 16rC00D99999999999A) (x2 0))
		('fcvtzu x2, d0' 16r9E790002 (d0 16r43E0000000000000) (x2 16r8000000000000000))
		('fcvtzu x2, d0' 16r9E790002 (d0 16rC3E0000000000000) (x2 0))
		('fcvtzu x2, d0' 16r9E790002 (d0 16r7FF0000000000000) (x2 16rFFFFFFFFFFFFFFFF))
		('fcvtzu x2, d0' 16r9E790002 (d0 16r7FF8000000000000) (x2 0))
		('fcvtzu x2, d0' 16r9E790002 (d0 16rC1E0000000200000) (x2 0))
		('fcvtzu x2, d0' 16r9E790002 (d0 16r41EFFFFFFFF00000) (x2 16rFFFFFFFF))
		('fcvtzu w2, d0' 16r1E790002 (d0 16rC00D99999999999A) (x2 0))
		('fcvtzu w2, d0' 16r1E790002 (d0 16r43E0000000000000) (x2 16rFFFFFFFF))
		('fcvtzu w2, d0' 16r1E790002 (d0 16rC3E0000000000000) (x2 0))
		('fcvtzu w2, d0' 16r1E790002 (d0 16r7FF0000000000000) (x2 16rFFFFFFFF))
		('fcvtzu w2, d0' 16r1E790002 (d0 16r7FF8000000000000) (x2 0))
		('fcvtzu w2, d0' 16r1E790002 (d0 16rC1E0000000200000) (x2 0))
		('fcvtzu w2, d0' 16r1E790002 (d0 16r41EFFFFFFFF00000) (x2 16rFFFFFFFF)))
!
testFloatRounding
	self check: #(
		('frintn d2, d0' 16r1E644002 (d0 16r3FE0000000000000) (d2 0))
		('frintn d2, d0' 16r1E644002 (d0 16rBFE0000000000000) (d2 16r8000000000000000))
		('frintn d2, d0' 16r1E644002 (d0 16r4004000000000000) (d2 16r4000000000000000))
		('frintn d2, d0' 16r1E644002 (d0 16rC004000000000000) (d2 16rC000000000000000))
		('frintn d2, d0' 16r1E644002 (d0 16r3FF8000000000000) (d2 16r4000000000000000))
		('frintn d2, d0' 16r1E644002 (d0 16r400D99999999999A) (d2 16r4010000000000000))
		('frintn d2, d0' 16r1E644002 (d0 16r7FF4000000000001) (d2 16r7FFC000000000001))
		('frintp d2, d0' 16r1E64C002 (d0 16r3FE0000000000000) (d2 16r3FF0000000000000))
		('frintp d2, d0' 16r1E64C002 (d0 16rBFE0000000000000) (d2 16r8000000000000000))
		('frintp d2, d0' 16r1E64C002 (d0 16r4004000000000000) (d2 16r4008000000000000))
		('frintp d2, d0' 16r1E64C002 (d0 16rC004000000000000) (d2 16rC000000000000000))
		('frintp d2, d0' 16r1E64C002 (d0 16r3FF8000000000000) (d2 16r4000000000000000))
		('frintp d2, d0' 16r1E64C002 (d0 16r400D99999999999A) (d2 16r4010000000000000))
		('frintp d2, d0' 16r1E64C002 (d0 16r7FF4000000000001) (d2 16r7FFC000000000001))
		('frintm d2, d0' 16r1E654002 (d0 16r3FE0000000000000) (d2 0))
		('frintm d2, d0' 16r1E654002 (d0 16rBFE0000000000000) (d2 16rBFF0000000000000))
		('frintm d2, d0' 16r1E654002 (d0 16r4004000000000000) (d2 16r4000000000000000))
		('frintm d2, d0' 16r1E654002 (d0 16rC004000000000000) (d2 16rC008000000000000))
		('frintm d2, d0' 16r1E654002 (d0 16r3FF8000000000000) (d2 16r3FF0000000000000))
		('frintm d2, d0' 16r1E654002 (d0 16r400D99999999999A) (d2 16r4008000000000000))
		('frintm d2, d0' 16r1E654002 (d0 16r7FF4000000000001) (d2 16r7FFC000000000001))
		('frintz d2, d0' 16r1E65C002 (d0 16r3FE0000000000000) (d2 0))
		('frintz d2, d0' 16r1E65C002 (d0 16rBFE0000000000000) (d2 16r8000000000000000))
		('frintz d2, d0' 16r1E65C002 (d0 16r4004000000000000) (d2 16r4000000000000000))
		('frintz d2, d0' 16r1E65C002 (d0 16rC004000000000000) (d2 16rC000000000000000))
		('frintz d2, d0' 16r1E65C002 (d0 16r3FF8000000000000) (d2 16r3FF0000000000000))
		('frintz d2, d0' 16r1E65C002 (d0 16r400D99999999999A) (d2 16r4008000000000000))
		('frintz d2, d0' 16r1E65C002 (d0 16r7FF4000000000001) (d2 16r7FFC000000000001)))
!
testFloatMoves
	self check: #(
		('fmov d2, x0' 16r9E670002 (x0 16r123456789ABCDEF0) (d2 16r123456789ABCDEF0))
		('fmov x2, d0' 16r9E660002 (d0 16rFFF8000000000123) (x2 16rFFF8000000000123))
		('fmov d2, d0' 16r1E604002 (d0 16rFFF8000000000123) (d2 16rFFF8000000000123))
		('fmov d2, #1.0' 16r1E6E1002 () (d2 16r3FF0000000000000))
		('fmov d2, #-0.125' 16r1E781002 () (d2 16rBFC0000000000000))
		('fmov d2, #31.0' 16r1E67F002 () (d2 16r403F000000000000))
		('fmov d2, #0.1328125' 16r1E683002 () (d2 16r3FC1000000000000)))
!
testPcRelative
	"At code + 16r7F8:
		adr x0, .+0x1235
		adr x3, .-3
		adr x1, .-1048576
		adrp x2, #0x3000
		adrp x4, #-0x1000
		adrp x5, #0
		adrp x6, #0xfffff000
		adrp x7, #-0x100000000"
	self load: #(16r300091A0 16r30FFFFE3 16r10800001 16rF0000002 16rF0FFFFE4 16r90000005 16rF07FFFE6 16r90800007) at: code + 16r7F8.
	emu pc: code + 16r7F8.
	8 timesRepeat: [emu step].
	self assert: (emu x: 0) equals: code + 16r1A2D.
	self assert: (emu x: 3) equals: code + 16r7F9.
	self assert: (emu x: 1) equals: code + 16r800 - 16r100000.
	self assert: (emu x: 2) equals: code + 16r3000.
	self assert: (emu x: 4) equals: code - 16r1000.
	self assert: (emu x: 5) equals: code.
	self assert: (emu x: 6) equals: code + 16rFFFFF000.
	self assert: (emu x: 7) equals: code - 16r100000000 + 16r10000000000000000
!
testDecodeBitMasks
	| table |
	table := Arm64Reference logicalImmediates64.
	1 to: table size by: 2 do: [:i |
		| e |
		e := table at: i + 1.
		self assert: (emu decodeBitMasks: (e bitShift: -12) immr: ((e bitShift: -6) bitAnd: 63) imms: (e bitAnd: 63) size: 64) equals: (table at: i)].
	table := Arm64Reference logicalImmediates32.
	1 to: table size by: 2 do: [:i |
		| e |
		e := table at: i + 1.
		self assert: (emu decodeBitMasks: (e bitShift: -12) immr: ((e bitShift: -6) bitAnd: 63) imms: (e bitAnd: 63) size: 32) equals: (table at: i)].
	self assert: (emu decodeBitMasks: 0 immr: 0 imms: 2r111111 size: 64) isNil.
	self assert: (emu decodeBitMasks: 1 immr: 0 imms: 2r111111 size: 64) isNil
!
testEveryAssemblerCaseIsSupported
	"Each instruction Arm64AssemblerCases emits decodes; executing it may fault on memory."
	| data |
	data := memory allocate: 1024 * 1024.
	Arm64Reference cases do: [:case |
		(case at: 3) do: [:word |
			0 to: 30 do: [:i | emu x: i put: data + 524288].
			emu sp: data + 524288.
			[self exec: word] on: Error do: [:e |
				self deny: ((e isKindOf: Arm64EmulationError) and: [e messageText beginsWith: 'unsupported']) description: (case at: 1) , ': ' , e messageText]]]
!
testUnsupportedInstruction
	"ldxr x0, [x1]"
	self load: #(16rC85F7C20) at: code + 16r40.
	emu pc: code + 16r40.
	self should: [emu step] raise: Arm64EmulationError withExceptionDo: [:e |
		self assert: e messageText equals: 'unsupported instruction 16rC85F7C20 at 16r' , (code + 16r40 printStringBase: 16)].
	self assert: emu pc equals: code + 16r40
!
testBreakpoint
	"brk #0x3e8"
	self load: #(16rD4207D00) at: code + 16r10.
	emu pc: code + 16r10.
	self should: [emu step] raise: Arm64EmulationError withExceptionDo: [:e |
		self assert: e messageText equals: 'brk #16r3E8 at 16r' , (code + 16r10 printStringBase: 16)]
! !

!Arm64EmulatorTest methodsFor: 'tests-programs'!
testLoop
	self assert: (self call: self sumProgram type: 'int64_t (int64_t)' arguments: #(0)) equals: 0.
	self assert: (self call: self sumProgram type: 'int64_t (int64_t)' arguments: #(100)) equals: 5050
!
testRecursion
	self assert: (self call: self fibProgram type: 'int64_t (int64_t)' arguments: #(12)) equals: 144.
	self assert: emu sp equals: emu stackTop.
	self assert: emu stackTop \\ 16 equals: 0
!
testLoadsAndStores
	| buffer |
	buffer := memory allocate: 1024.
	0 to: 63 do: [:k | memory uint8At: buffer + k put: (k * 37 + 16r85 bitAnd: 255)].
	self call: self memProgram type: 'void (uint8_t *)' arguments: {buffer}.
	#(
		16r85 16rFFFFFFFFFFFFFFAA 16rFFFFFFCF 16r3E19 16rFFFFFFFFFFFF8863 16rFFFFD2AD
		16rB08B6641 16r441FFAD5 16rDBB6916C4722FD 16rF7D2AD88633E19F4 16rFFFFFFFFAD88633E 16r4433221122110011
		16r8877665544332211 16r1100004433221100 16r22110022 16r0 16r13 16rD8B38E69441FFAD5
		16rD5 16rB691000000000000 16r0 16r0 16rF4 16rFFFFFFFFFFFFB691
		16rB08B6641 16rDBB6916C4722FD 16r44332211 16r0 16r44332211 16r0
		16r1CF7D2AD 16rFFFFFFFFB08B6641 16rD8B38E69441FFAD5 16rDBB6916C4722FD 16r1D4 16r2803DEB9946F4A25
		16rDBB6916C4722FD 16rB08B66411CF7D2AD 16r80000001 16r1122334455667788 16r1122334455667788 16rFFFFFFFF80000001
		16rB08B66411CF7D2AD 16r0 16rB08B66411CF7D2AD 16rDBB6916C4722FD 16r260) doWithIndex: [:expected :i |
		self assert: (memory uint64At: buffer + 248 + (i * 8)) = expected description: [(248 + (i * 8)) printString]]
!
testBranches
	"{a. b. bits}: bits 0-13 are the conditions eq ne hs lo mi pl vs vc hi ls ge lt gt le after cmp a, b; 16r10000 a ~= 0, 16r20000 the low word of b is 0, 16r40000 a < 0, 16r80000 bit 3 of b is clear, 16r200000 bl and blr returned, 16r1000000 br did not jump."
	#(
		(0 0 16r2A26A5)
		(1 2 16r292A9A)
		(2 1 16r2915A6)
		(-1 1 16r2D2996)
		(-9223372036854775808 1 16r2D2966)
		(9223372036854775807 -1 16r21165A)
		(8 0 16r2B15A6)
		(-8 3 16r2D2996)) do: [:row |
		self assert: (self call: self branchesProgram type: 'int64_t (int64_t, int64_t)' arguments: {row at: 1. row at: 2}) equals: (row at: 3)]
!
testFloatProgram
	self assert: (self call: self fpprogProgram type: 'double (double, int64_t)' arguments: #(3.0 10)) asIEEEBits equals: 16r3FDEDB4FA273D7D4
!
testArgumentAndResultTypes
	"ret: the result is the first argument, typed by the return type."
	| p |
	self assert: (self call: #(16rD65F03C0) type: 'int32_t (int64_t)' arguments: #(16r100000005)) equals: 5.
	self assert: (self call: #(16rD65F03C0) type: 'int32_t (int64_t)' arguments: #(-1)) equals: -1.
	self assert: (self call: #(16rD65F03C0) type: 'uint64_t (int64_t)' arguments: #(-1)) equals: 16rFFFFFFFFFFFFFFFF.
	self assert: (self call: #(16rD65F03C0) type: 'bool (bool)' arguments: #(true)) equals: true.
	self assert: (self call: #(16rD65F03C0) type: 'bool (bool)' arguments: #(false)) equals: false.
	self assert: (self call: #(16rD65F03C0) type: 'double (double)' arguments: #(2.5)) equals: 2.5.
	self assert: (self call: #(16rD65F03C0) type: 'void (int64_t)' arguments: #(1)) isNil.
	p := self call: #(16rD65F03C0) type: 'uint8_t * (uint8_t *)' arguments: {code + 3}.
	self assert: p address equals: code + 3.
	self assert: p type name equals: 'uint8_t'.
	self should: [self call: #(16rD65F03C0) type: 'int64_t (int64_t, ...)' arguments: #(1)] raise: Arm64EmulationError
!
testCallIntoSmalltalk
	| fp |
	fp := FunctionPointer receiver: self selector: #callback:with:.
	self assert: (self call: self calloutProgram type: 'int64_t (int64_t, double, int64_t (*)(int64_t, double))' arguments: {4. 1.25. fp}) equals: 156.
	self assert: emu sp equals: emu stackTop.
	self assert: (self call: self tailcallProgram type: 'int64_t (int64_t, double, int64_t (*)(int64_t, double))' arguments: {7. 3.9. fp}) equals: 63.
	self should: [self call: self tailcallProgram type: 'int64_t (int64_t, double, int64_t (*)(int64_t))' arguments: {7. 3.9. FunctionPointer receiver: self selector: #variadic:}] raise: Arm64EmulationError
!
testNestedCall
	"nested(10, fibViaEmulator), which calls fib(10) in machine code again: fib(10) + 10."
	self load: self fibProgram at: code + 4096.
	self assert: (self call: self nestedProgram type: 'int64_t (int64_t, int64_t (*)(int64_t))' arguments: {10. FunctionPointer receiver: self selector: #fibViaEmulator:}) equals: 65.
	self assert: emu sp equals: emu stackTop
! !

!Arm64EmulatorTest methodsFor: 'programs'!
sumProgram
	"mov x1, #0
	1: cbz x0, 2f
	add x1, x1, x0
	sub x0, x0, #1
	b 1b
	2: mov x0, x1
	ret"
	^#(
		16rD2800001 16rB4000080 16r8B000021 16rD1000400 16r17FFFFFD 16rAA0103E0 16rD65F03C0)
!
fibProgram
	"0: cmp x0, #2
	b.lt 9f
	stp x29, x30, [sp, #-32]!!
	mov x29, sp
	stp x19, x20, [sp, #16]
	mov x19, x0
	sub x0, x0, #1
	bl 0b
	mov x20, x0
	sub x0, x19, #2
	bl 0b
	add x0, x0, x20
	ldp x19, x20, [sp, #16]
	ldp x29, x30, [sp], #32
	9: ret"
	^#(
		16rF100081F 16r540001AB 16rA9BE7BFD 16r910003FD 16rA90153F3 16rAA0003F3 16rD1000400 16r97FFFFF9
		16rAA0003F4 16rD1000A60 16r97FFFFF6 16r8B140000 16rA94153F3 16rA8C27BFD 16rD65F03C0)
!
memProgram
	"add x17, x0, #256
	ldrb w1, [x0]
	ldrsb x2, [x0, #1]
	ldrsb w3, [x0, #2]
	ldrh w4, [x0, #4]
	ldrsh x5, [x0, #6]
	ldrsh w6, [x0, #8]
	ldr w7, [x0, #12]
	ldrsw x8, [x0, #16]
	ldr x9, [x0, #24]
	ldur x10, [x0, #3]
	ldursw x11, [x0, #5]
	stp x1, x2, [x17, #0]
	stp x3, x4, [x17, #16]
	stp x5, x6, [x17, #32]
	stp x7, x8, [x17, #48]
	stp x9, x10, [x17, #64]
	str x11, [x17, #80]
	movz x12, #0x2211
	movk x12, #0x4433, lsl #16
	movk x12, #0x6655, lsl #32
	movk x12, #0x8877, lsl #48
	strb w12, [x17, #88]
	strh w12, [x17, #90]
	str w12, [x17, #92]
	str x12, [x17, #96]
	stur w12, [x17, #105]
	sturh w12, [x17, #111]
	add x13, x0, #368
	strh w12, [x13, #2]!!
	strb w12, [x13], #6
	sub x13, x13, #300
	ldr x14, [x13, #-60]!!
	ldrb w15, [x13], #3
	sub x13, x13, x0
	stp x13, x14, [x17, #128]
	str x15, [x17, #144]
	mov x1, #3
	ldrb w2, [x0, x1]
	movn w3, #1
	add x4, x0, #32
	ldrsh x5, [x4, w3, sxtw #1]
	ldr w6, [x0, w1, uxtw #2]
	ldr x7, [x0, x1, lsl #3]
	movn x8, #0
	ldrsb w9, [x4, x8]
	add x10, x0, #416
	strh w5, [x10, w3, sxtw]
	str w9, [x10, x1, lsl #2]
	stp x2, x5, [x17, #176]
	stp x6, x7, [x17, #192]
	add x10, x0, #472
	stp w12, w9, [x10, #-8]!!
	ldp w1, w2, [x10], #4
	ldpsw x3, x4, [x0, #8]
	ldp x5, x6, [x0, #16]
	sub x10, x10, x0
	stp x1, x2, [x17, #224]
	stp x3, x4, [x17, #240]
	stp x5, x6, [x17, #256]
	str x10, [x17, #272]
	ldp d0, d1, [x0, #24]
	ldr d2, [x0, #8]
	stp d1, d0, [x17, #280]
	str d2, [x17, #296]
	ldr w1, 3f
	ldr x2, 4f
	ldr d3, 4f
	adr x3, 3f
	ldrsw x4, [x3]
	stp x1, x2, [x17, #304]
	str d3, [x17, #320]
	str x4, [x17, #328]
	add x10, x0, #600
	str d2, [x10, #-8]!!
	ldr d4, [x10], #16
	mov x11, #3
	ldr d5, [x0, x11, lsl #3]
	sub x10, x10, x0
	stp d4, d5, [x17, #352]
	str x10, [x17, #368]
	ret
	3: .word 0x80000001
	.p2align 3
	4: .quad 0x1122334455667788"
	^#(
		16r91040011 16r39400001 16r39800402 16r39C00803 16r79400804 16r79800C05 16r79C01006 16rB9400C07
		16rB9801008 16rF9400C09 16rF840300A 16rB880500B 16rA9000A21 16rA9011223 16rA9021A25 16rA9032227
		16rA9042A29 16rF9002A2B 16rD284422C 16rF2A8866C 16rF2CCCAAC 16rF2F10EEC 16r3901622C 16r7900B62C
		16rB9005E2C 16rF900322C 16rB806922C 16r7806F22C 16r9105C00D 16r78002DAC 16r380065AC 16rD104B1AD
		16rF85C4DAE 16r384035AF 16rCB0001AD 16rA9083A2D 16rF9004A2F 16rD2800061 16r38616802 16r12800023
		16r91008004 16r78A3D885 16rB8615806 16rF8617807 16r92800008 16r38E86889 16r9106800A 16r7823C945
		16rB8217949 16rA90B1622 16rA90C1E26 16r9107600A 16r29BF254C 16r28C08941 16r69411003 16rA9411805
		16rCB00014A 16rA90E0A21 16rA90F1223 16rA9101A25 16rF9008A2A 16r6D418400 16rFD400402 16r6D118221
		16rFD009622 16r18000221 16r58000242 16r5C000223 16r100001C3 16rB9800064 16rA9130A21 16rFD00A223
		16rF900A624 16r9109600A 16rFC1F8D42 16rFC410544 16rD280006B 16rFC6B7805 16rCB00014A 16r6D161624
		16rF900BA2A 16rD65F03C0 16r80000001 16rD503201F 16r55667788 16r11223344)
!
branchesProgram
	"mov x2, #0
	cmp x0, x1
	b.eq 1f
	b 2f
	1: orr x2, x2, #1
	2: b.ne 1f
	b 2f
	1: orr x2, x2, #2
	2: b.hs 1f
	b 2f
	1: orr x2, x2, #4
	2: b.lo 1f
	b 2f
	1: orr x2, x2, #8
	2: b.mi 1f
	b 2f
	1: orr x2, x2, #16
	2: b.pl 1f
	b 2f
	1: orr x2, x2, #32
	2: b.vs 1f
	b 2f
	1: orr x2, x2, #64
	2: b.vc 1f
	b 2f
	1: orr x2, x2, #128
	2: b.hi 1f
	b 2f
	1: orr x2, x2, #256
	2: b.ls 1f
	b 2f
	1: orr x2, x2, #512
	2: b.ge 1f
	b 2f
	1: orr x2, x2, #1024
	2: b.lt 1f
	b 2f
	1: orr x2, x2, #2048
	2: b.gt 1f
	b 2f
	1: orr x2, x2, #4096
	2: b.le 1f
	b 2f
	1: orr x2, x2, #8192
	2: cbz x0, 1f
	orr x2, x2, #0x10000
	1: cbnz w1, 1f
	orr x2, x2, #0x20000
	1: tbz x0, #63, 1f
	orr x2, x2, #0x40000
	1: tbnz w1, #3, 1f
	orr x2, x2, #0x80000
	1: mov x9, x30
	bl 5f
	adr x3, 5f
	blr x3
	adr x3, 6f
	br x3
	orr x2, x2, #0x1000000
	6: mov x30, x9
	mov x0, x2
	ret
	5: add x2, x2, #0x100000
	ret"
	^#(
		16rD2800002 16rEB01001F 16r54000040 16r14000002 16rB2400042 16r54000041 16r14000002 16rB27F0042
		16r54000042 16r14000002 16rB27E0042 16r54000043 16r14000002 16rB27D0042 16r54000044 16r14000002
		16rB27C0042 16r54000045 16r14000002 16rB27B0042 16r54000046 16r14000002 16rB27A0042 16r54000047
		16r14000002 16rB2790042 16r54000048 16r14000002 16rB2780042 16r54000049 16r14000002 16rB2770042
		16r5400004A 16r14000002 16rB2760042 16r5400004B 16r14000002 16rB2750042 16r5400004C 16r14000002
		16rB2740042 16r5400004D 16r14000002 16rB2730042 16rB4000040 16rB2700042 16r35000041 16rB26F0042
		16rB6F80040 16rB26E0042 16r37180041 16rB26D0042 16rAA1E03E9 16r94000009 16r10000103 16rD63F0060
		16r10000063 16rD61F0060 16rB2680042 16rAA0903FE 16rAA0203E0 16rD65F03C0 16r91440042 16rD65F03C0)
!
calloutProgram
	"stp x29, x30, [sp, #-32]!!
	mov x29, sp
	str x19, [sp, #16]
	mov x19, #3
	add x0, x0, #1
	fadd d0, d0, d0
	blr x1
	mul x0, x0, x19
	ldr x19, [sp, #16]
	ldp x29, x30, [sp], #32
	ret"
	^#(
		16rA9BE7BFD 16r910003FD 16rF9000BF3 16rD2800073 16r91000400 16r1E602800 16rD63F0020 16r9B137C00
		16rF9400BF3 16rA8C27BFD 16rD65F03C0)
!
tailcallProgram
	"sub x0, x0, #1
	br x1"
	^#(
		16rD1000400 16rD61F0020)
!
nestedProgram
	"stp x29, x30, [sp, #-32]!!
	mov x29, sp
	str x19, [sp, #16]
	mov x19, x0
	blr x1
	add x0, x0, x19
	ldr x19, [sp, #16]
	ldp x29, x30, [sp], #32
	ret"
	^#(
		16rA9BE7BFD 16r910003FD 16rF9000BF3 16rAA0003F3 16rD63F0020 16r8B130000 16rF9400BF3 16rA8C27BFD
		16rD65F03C0)
!
fpprogProgram
	"fmov d1, xzr
	mov x1, #1
	1: cmp x1, x0
	b.gt 2f
	scvtf d2, x1
	fdiv d3, d0, d2
	fadd d1, d1, d3
	add x1, x1, #1
	b 1b
	2: fabs d1, d1
	fsqrt d0, d1
	fmov d4, #0.5
	fmul d0, d0, d4
	fcvtzs x2, d0
	scvtf d5, x2
	fsub d0, d0, d5
	ret"
	^#(
		16r9E6703E1 16rD2800021 16rEB00003F 16r540000CC 16r9E620022 16r1E621803 16r1E632821 16r91000421
		16r17FFFFFA 16r1E60C021 16r1E61C020 16r1E6C1004 16r1E640800 16r9E780002 16r9E620045 16r1E653800
		16rD65F03C0)
! !
