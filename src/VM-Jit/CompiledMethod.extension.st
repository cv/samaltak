!CompiledMethod methodsFor: '*VM-Jit'!
machineCode
	"An annotated listing of my machine code from the VM's compiler (the template compiler under --jit none)."
	^self machineCodeFor: nil
!
machineCodeFor: aModeOrNil
	"An annotated listing of my machine code from the compiler called aModeOrNil (#template ...): each bytecode with its source line, then its instructions, commented with what they do."
	| code words notes text |
	code := self jitCode: aModeOrNil.
	code isNil ifTrue: [^self printString , ': not compiled by ' , (aModeOrNil ifNil: ['the JIT']) asString].
	words := (1 to: (code at: 2) size // 4) collect: [:i | (code at: 2) uint32At: i - 1 * 4 + 1].
	notes := self jitAnnotationsFrom: code.
	text := Arm64Disassembler new listingOfWords: words at: (code at: 1) annotations: notes.
	^self printString , '  ' , (code at: 6) , ', ' , (code at: 2) size printString , ' bytes at 16r' , ((code at: 1) printStringBase: 16)
		, (String with: Character lf) , (String with: Character lf) , text
!
jitSendSites
	"What the inline caches of my baseline machine code saw: {pc. state. classes. methods. selector} per send site (state 0 unlinked, 1 monomorphic, 2 polymorphic, 3 megamorphic); nil if I have no baseline code."
	<primitive: 'jitSendSites'>
	^self primitiveFailed
!
jitCode: aModeOrNil
	"{address. code. map. notes. symbols. mode} (JitPrimitives>>primJitCode), nil if the compiler does not compile me."
	<primitive: 'jitCode'>
	^self primitiveFailed
!
jitAnnotationsFrom: code
	"Arm64CodeAnnotations for the primitive's notes: bytecode headers (with their source lines), comments, stub names."
	| notes texts lines map |
	notes := Arm64CodeAnnotations new.
	texts := self jitBytecodeTexts.
	lines := source isNil ifTrue: [#()] ifFalse: [source lines].
	map := code at: 4.
	1 to: map size by: 3 do: [:i | | offset text value |
		offset := map at: i.
		text := map at: i + 1.
		value := map at: i + 2.
		text isNil
			ifTrue: [notes addBytecode: value text: (texts at: value ifAbsent: ['?']) source: (self jitSourceLineAt: value in: lines) at: offset]
			ifFalse: [notes addComment: (text copyReplaceAll: '%d' with: value printString) at: offset]].
	map := code at: 5.
	1 to: map size by: 2 do: [:i | notes addSymbol: (map at: i + 1) at: (map at: i)].
	^notes
!
jitBytecodeTexts
	"pc -> the mnemonic of the instruction at pc."
	| d |
	d := Dictionary new.
	self symbolic lines do: [:line | | pc |
		pc := (line copyUpTo: $<) trimBoth asNumber.
		(pc notNil and: [line includes: $>]) ifTrue: [d at: pc put: (line copyAfter: $>) trimBoth]].
	^d
!
jitSourceLineAt: pc in: lines
	"The source line of the first statement at or after pc, trimmed; nil if unknown."
	| interval position |
	interval := self sourceIntervalAt: pc.
	interval isNil ifTrue: [^nil].
	position := 0.
	lines do: [:line |
		interval first <= (position + line size + 1) ifTrue: [^line trimBoth].
		position := position + line size + 1].
	^nil
! !
