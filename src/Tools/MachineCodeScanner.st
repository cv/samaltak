Object subclass: #MachineCodeScanner
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

MachineCodeScanner comment: 'I tokenize a machine code listing (CompiledMethod>>machineCode: Arm64Disassembler''s and Amd64Disassembler''s annotated format) for TextHighlighter scanner:, as Scanner does Smalltalk, in the Smalltalk highlighter''s types (Theme syntaxStyleFor:): #pattern the title (line 1); #return a bytecode''s header (pc 5: send: #+), #global the statement after its --; #self offsets and machine words (an instruction''s bytes on x86); #keyword mnemonics, label lines (L12:) and x86 operand sizes (QWORD PTR); #symbol registers (arm64''s and x86''s); #global immediates, displacements, targets (#0x58, #-0x10, 0x58, -0x10, 0x102bf0148, L12, <baseline miss>); #comment from ; to the end of the line. Everything between them, white space included, comes as one #identifier token (a listing of 20,000 lines: 180,000 tokens, 16 ms).

	MachineCodeScanner highlight: ''pc 1: send: #+  -- 3 + 4'' do: [:type :start :stop | Transcript show: type; cr]'!

!MachineCodeScanner class methodsFor: 'highlighting'!
highlight: aString do: aBlock
	"Evaluate aBlock with the type, start and stop of every token of aString, all of it covered, in order. Never fails."
	| n plain emit start stop |
	n := aString size.
	plain := 1.
	emit := [:type :first :last |
		plain < first ifTrue: [aBlock value: #identifier value: plain value: first - 1].
		aBlock value: type value: first value: last.
		plain := last + 1].
	start := 1.
	[start <= n] whileTrue: [
		stop := (aString indexOf: Character lf startingAt: start) - 1.
		stop < 0 ifTrue: [stop := n].
		stop >= start ifTrue: [
			start = 1
				ifTrue: [emit value: #pattern value: start value: stop]
				ifFalse: [self line: aString from: start to: stop emit: emit]].
		start := stop + 2].
	plain <= n ifTrue: [aBlock value: #identifier value: plain value: n]
!
line: s from: a to: z emit: emit
	"A line of the listing (not its title), what its first characters say it is: a bytecode header, a label, an instruction, a comment continuation; anything else stays plain."
	| c i |
	c := s at: a.
	(c == $p and: [self isHeader: s from: a to: z]) ifTrue: [^self header: s from: a to: z emit: emit].
	(c == $L and: [self isLabel: s from: a to: z]) ifTrue: [^emit value: #keyword value: a value: z].
	c == $  ifFalse: [^self].
	i := self skipSpaces: s from: a to: z.
	i > z ifTrue: [^self].
	c := s at: i.
	c == $+ ifTrue: [^self instruction: s from: i to: z emit: emit].
	c == $; ifTrue: [emit value: #comment value: i value: z]
!
isHeader: s from: a to: z
	"'pc 12: ...'"
	^z > (a + 3) and: [(s at: a + 1) == $c and: [(s at: a + 2) == $  and: [(s at: a + 3) isDigit]]]
!
header: s from: a to: z emit: emit
	"'pc 5: send: #+  -- real + aComplex real': the pc and its bytecode, then the statement (the first '  -- ' ends the bytecode)."
	| at |
	at := (s copyFrom: a to: z) indexOfSubCollection: '  -- '.
	at = 0 ifTrue: [^emit value: #return value: a value: z].
	emit value: #return value: a value: a + at - 2.
	emit value: #global value: a + at + 1 value: z
!
isLabel: s from: a to: z
	"'L12:'"
	^(s at: z) == $: and: [z > (a + 1) and: [self allDigits: s from: a + 1 to: z - 1]]
!
instruction: s from: a to: z emit: emit
	"'+0004  54000060  b.ne L1      ; comment', a at the +: the offset and the machine word, the mnemonic, the operands, the comment."
	| i j |
	i := a.
	1 to: 2 do: [:field |
		j := self wordEnd: s from: i to: z.
		emit value: #self value: i value: j.
		i := self skipSpaces: s from: j + 1 to: z.
		i > z ifTrue: [^self]].
	j := self wordEnd: s from: i to: z.
	emit value: #keyword value: i value: j.
	i := j + 1.
	[i <= z] whileTrue: [i := self operand: s at: i to: z emit: emit]
!
operand: s at: i to: z emit: emit
	"Tokenize at i in the operands of an instruction, answering the position after what I consumed."
	| c j |
	c := s at: i.
	c == $; ifTrue: [emit value: #comment value: i value: z. ^z + 1].
	c == $< ifTrue: [
		j := i.
		[j < z and: [(s at: j) ~~ $>]] whileTrue: [j := j + 1].
		emit value: #global value: i value: j.
		^j + 1].
	(c isDigit or: [(c == $# or: [c == $-]) and: [i < z and: [(s at: i + 1) ~~ $ ]]]) ifTrue: [
		"#0x10 #-0x10 (arm64), 0x10 -0x10 (x86); objdump's '# 0x...' after a pc-relative operand is a space and an address"
		j := self wordEnd: s from: i to: z.
		emit value: #global value: i value: j.
		^j + 1].
	c isLetter ifTrue: [
		j := self nameEnd: s from: i to: z.
		(self isRegister: s from: i to: j)
			ifTrue: [emit value: #symbol value: i value: j]
			ifFalse: [
				(c == $L and: [j > i and: [self allDigits: s from: i + 1 to: j]]) ifTrue: [emit value: #global value: i value: j].
				(c isUppercase and: [j + 4 <= z and: [(s copyFrom: j + 1 to: j + 4) = ' PTR']]) ifTrue: [
					"x86 operand sizes: BYTE PTR ... XMMWORD PTR"
					emit value: #keyword value: i value: j + 4.
					^j + 5]].
		^j + 1].
	^i + 1
!
isRegister: s from: i to: j
	"x0-x30, w0-w30, d0-d31, sp, wsp, xzr, wzr (Arm64Disassembler's names); x86's (Amd64Disassembler's: objdump's)."
	| c |
	c := s at: i.
	((c == $x or: [c == $w or: [c == $d]]) and: [j > i and: [self allDigits: s from: i + 1 to: j]]) ifTrue: [^true].
	((j - i between: 1 and: 2) and: [#('sp' 'wsp' 'xzr' 'wzr') includes: (s copyFrom: i to: j)]) ifTrue: [^true].
	^self isX86Register: s from: i to: j
!
isX86Register: s from: i to: j
	"rax-r15, eax-r15d, ax-r15w, al-r15b (ah-bh, spl-dil), xmm0-xmm15, rip, riz (Amd64Disassembler's names: objdump's); not al after ', ', where arm64 has its condition al."
	| c n last |
	c := s at: i.
	n := j - i + 1.
	(c == $x and: [n > 3 and: [(s at: i + 1) == $m and: [(s at: i + 2) == $m and: [self allDigits: s from: i + 3 to: j]]]]) ifTrue: [^true].
	(c == $r and: [n > 1 and: [(s at: i + 1) isDigit]]) ifTrue: [
		last := s at: j.
		last isDigit ifTrue: [^self allDigits: s from: i + 1 to: j].
		^(last == $d or: [last == $w or: [last == $b]]) and: [n > 2 and: [self allDigits: s from: i + 1 to: j - 1]]].
	last := s at: j.
	n = 2 ifTrue: [
		(last == $l or: [last == $h]) ifFalse: [^self isWordRegister: c with: last].
		('abcd' includes: c) ifFalse: [^false].
		^(c == $a and: [last == $l]) not or: [i < 3 or: [((s at: i - 1) == $  and: [(s at: i - 2) == $,]) not]]].
	n = 3 ifFalse: [^false].
	((c == $r or: [c == $e]) and: [self isWordRegister: (s at: i + 1) with: last]) ifTrue: [^true].
	(c == $r and: [(s at: i + 1) == $i]) ifTrue: [^last == $p or: [last == $z]].
	^last == $l and: [(s at: i + 1) ~~ $x and: [self isWordRegister: c with: (s at: i + 1)]]
!
isWordRegister: c with: d
	"Whether cd is ax bx cx dx si di bp or sp (and so rcx, ecx, sil ...)."
	d == $x ifTrue: [^'abcd' includes: c].
	d == $i ifTrue: [^c == $s or: [c == $d]].
	^d == $p and: [c == $b or: [c == $s]]
!
allDigits: s from: a to: b
	a to: b do: [:k | (s at: k) isDigit ifFalse: [^false]].
	^true
!
wordEnd: s from: i to: z
	"The position of the last character of the word at i: letters, digits and . _ - (operands end at spaces, commas and brackets)."
	| j c |
	j := i.
	[j < z and: [(c := s at: j + 1) isLetter or: [c isDigit or: [c == $. or: [c == $_ or: [c == $-]]]]]] whileTrue: [j := j + 1].
	^j
!
nameEnd: s from: i to: z
	"The position of the last character of the name at i: letters, digits and . _ (x86's displacements follow a register with - or +)."
	| j c |
	j := i.
	[j < z and: [(c := s at: j + 1) isLetter or: [c isDigit or: [c == $. or: [c == $_]]]]] whileTrue: [j := j + 1].
	^j
!
skipSpaces: s from: i to: z
	"The first position from i on that is not a space (z + 1 if none)."
	| j |
	j := i.
	[j <= z and: [(s at: j) == $ ]] whileTrue: [j := j + 1].
	^j
! !
