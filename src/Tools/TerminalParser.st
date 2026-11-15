Object subclass: #TerminalParser
	instanceVariableNames: 'screen state params count current private intermediate string utf8Need utf8Value'
	classVariableNames: ''
	package: 'Tools'!

TerminalParser comment: 'I turn the bytes a program writes to its terminal into TerminalScreen operations: UTF-8 text (a character split across two reads is kept until its last byte arrives), C0 controls, ESC sequences, CSI sequences (cursor movement, erasing, inserting and deleting, scroll regions, SGR attributes and 16/256/truecolor, modes incl. the alternate screen, application cursor keys and bracketed paste, device reports) and OSC strings (0 and 2 set the title); DCS, SOS, PM and APC strings are skipped. A state machine after Paul Williams'' DEC parser (vt100.net/emu/dec_ansi_parser), with a fast path for runs of printable ASCII.

	parser := TerminalParser on: (TerminalScreen rows: 24 cols: 80).
	parser feed: ''hello'' asByteArray.'!

!TerminalParser methodsFor: 'initialization'!
setScreen: aScreen
	screen := aScreen.
	state := 0.
	params := Array new: 32.
	count := 0.
	utf8Need := 0.
	utf8Value := 0
! !

!TerminalParser methodsFor: 'accessing'!
screen
	^screen
! !

!TerminalParser methodsFor: 'feeding'!
feed: bytes
	self feed: bytes from: 1 to: bytes size
!
feed: bytes from: start to: stop
	"Interpret bytes start..stop (a ByteArray, or a String of byte characters)."
	| i b j |
	bytes isString ifTrue: [^self feed: (bytes asByteArray) from: start to: stop].
	i := start.
	[i <= stop] whileTrue: [
		b := bytes at: i.
		(state = 0 and: [b >= 32 and: [b < 127 and: [utf8Need = 0]]])
			ifTrue: [
				j := i.
				[j < stop and: [(b := bytes at: j + 1) >= 32 and: [b < 127]]] whileTrue: [j := j + 1].
				screen putBytes: bytes from: i to: j.
				i := j]
			ifFalse: [self byte: b].
		i := i + 1]
!
byte: b
	"One byte in any state."
	state = 0 ifTrue: [^self ground: b].
	b = 24 ifTrue: [^state := 0].
	b = 26 ifTrue: [^state := 0].
	b = 27 ifTrue: [
		state = 4 ifTrue: [self finishString].
		^state := 1].
	(state = 4 or: [state = 6]) ifTrue: [^self stringByte: b].
	b < 32 ifTrue: [^self control: b].
	state = 1 ifTrue: [^self escape: b].
	state = 2 ifTrue: [^self escapeIntermediate: b].
	state = 3 ifTrue: [^self csi: b]
! !

!TerminalParser methodsFor: 'ground'!
ground: b
	utf8Need > 0 ifTrue: [
		(b >= 16r80 and: [b < 16rC0]) ifTrue: [
			utf8Value := (utf8Value bitShift: 6) + (b bitAnd: 16r3F).
			utf8Need := utf8Need - 1.
			utf8Need = 0 ifTrue: [self putCodePoint: utf8Value].
			^self].
		utf8Need := 0.
		screen putCharacter: (Character value: 16rFFFD)].
	b < 32 ifTrue: [^self control: b].
	b < 127 ifTrue: [^screen putCharacter: (Character value: b)].
	b = 127 ifTrue: [^self].
	b < 16rC0 ifTrue: [^screen putCharacter: (Character value: 16rFFFD)].
	b < 16rE0 ifTrue: [utf8Need := 1. ^utf8Value := b bitAnd: 16r1F].
	b < 16rF0 ifTrue: [utf8Need := 2. ^utf8Value := b bitAnd: 16r0F].
	b < 16rF8 ifTrue: [utf8Need := 3. ^utf8Value := b bitAnd: 16r07].
	screen putCharacter: (Character value: 16rFFFD)
!
putCodePoint: cp
	(cp > 16r10FFFF or: [cp between: 16rD800 and: 16rDFFF]) ifTrue: [^screen putCharacter: (Character value: 16rFFFD)].
	"C1 controls are ignored; an overlong encoding of ASCII is ill-formed."
	cp < 16rA0 ifTrue: [^cp < 16r80 ifTrue: [screen putCharacter: (Character value: 16rFFFD)]].
	screen putCharacter: (Character value: cp)
!
control: b
	"C0 controls (executed in any state but the strings)."
	b = 7 ifTrue: [^self].
	b = 8 ifTrue: [^screen backspace].
	b = 9 ifTrue: [^screen tab].
	(b = 10 or: [b = 11 or: [b = 12]]) ifTrue: [^screen lineFeed].
	b = 13 ifTrue: [^screen carriageReturn].
	b = 14 ifTrue: [^screen shiftTo: 2].
	b = 15 ifTrue: [^screen shiftTo: 1].
	b = 27 ifTrue: [^state := 1]
! !

!TerminalParser methodsFor: 'escape sequences'!
escape: b
	state := 0.
	b = 91 "[" ifTrue: [
		state := 3.
		count := 0.
		current := nil.
		private := nil.
		intermediate := nil.
		^self].
	b = 93 "]" ifTrue: [state := 4. ^string := WriteStream on: (ByteArray new: 64)].
	(b = 80 "P" or: [b = 88 "X" or: [b = 94 "^" or: [b = 95 "_"]]]) ifTrue: [state := 6. ^string := nil].
	(b >= 32 and: [b <= 47]) ifTrue: [state := 2. ^intermediate := b].
	b = 55 "7" ifTrue: [^screen saveCursor].
	b = 56 "8" ifTrue: [^screen restoreCursor].
	b = 68 "D" ifTrue: [^screen index].
	b = 69 "E" ifTrue: [^screen nextLine].
	b = 77 "M" ifTrue: [^screen reverseIndex].
	b = 72 "H" ifTrue: [^screen setTabStop].
	b = 99 "c" ifTrue: [^screen reset; eraseInDisplay: 2]
!
escapeIntermediate: b
	(b >= 32 and: [b <= 47]) ifTrue: [^self].
	state := 0.
	(intermediate = 40 "(" or: [intermediate = 41 ")"]) ifTrue: [
		^screen designate: (b = 48 "0" ifTrue: [#lineDrawing] ifFalse: [#ascii]) charset: intermediate - 39].
	(intermediate = 35 "#" and: [b = 56 "8"]) ifTrue: [^screen fillWithE]
! !

!TerminalParser methodsFor: 'control sequences'!
csi: b
	b >= 48 ifTrue: [
		b <= 57 ifTrue: [^current := ((current ifNil: [0]) * 10 + b - 48) min: 99999].
		(b = 59 or: [b = 58]) ifTrue: [^self nextParameter].
		b <= 63 ifTrue: [^private := b].
		state := 0.
		current isNil ifFalse: [self nextParameter].
		^self dispatch: b].
	"32-47: intermediate bytes"
	intermediate := b
!
nextParameter
	count < params size ifTrue: [params at: (count := count + 1) put: current].
	current := nil
!
param: i default: d
	"Parameter i, or d when it is missing or 0."
	| p |
	i > count ifTrue: [^d].
	p := params at: i.
	(p isNil or: [p = 0]) ifTrue: [^d].
	^p
!
dispatch: final
	private isNil ifFalse: [^self dispatchPrivate: final].
	intermediate isNil ifFalse: [^self dispatchIntermediate: final].
	final = 109 "m" ifTrue: [^screen selectGraphicRendition: params count: count].
	final = 72 "H" ifTrue: [^screen moveTo: (self param: 1 default: 1) col: (self param: 2 default: 1)].
	final = 102 "f" ifTrue: [^screen moveTo: (self param: 1 default: 1) col: (self param: 2 default: 1)].
	final = 65 "A" ifTrue: [^screen cursorUp: (self param: 1 default: 1)].
	final = 66 "B" ifTrue: [^screen cursorDown: (self param: 1 default: 1)].
	final = 67 "C" ifTrue: [^screen cursorForward: (self param: 1 default: 1)].
	final = 68 "D" ifTrue: [^screen cursorBackward: (self param: 1 default: 1)].
	final = 69 "E" ifTrue: [^screen cursorDown: (self param: 1 default: 1); carriageReturn].
	final = 70 "F" ifTrue: [^screen cursorUp: (self param: 1 default: 1); carriageReturn].
	final = 71 "G" ifTrue: [^screen moveToCol: (self param: 1 default: 1)].
	final = 96 "`" ifTrue: [^screen moveToCol: (self param: 1 default: 1)].
	final = 97 "a" ifTrue: [^screen cursorForward: (self param: 1 default: 1)].
	final = 100 "d" ifTrue: [^screen moveToRow: (self param: 1 default: 1)].
	final = 101 "e" ifTrue: [^screen cursorDown: (self param: 1 default: 1)].
	final = 74 "J" ifTrue: [^screen eraseInDisplay: (self param: 1 default: 0)].
	final = 75 "K" ifTrue: [^screen eraseInLine: (self param: 1 default: 0)].
	final = 64 "@" ifTrue: [^screen insertChars: (self param: 1 default: 1)].
	final = 80 "P" ifTrue: [^screen deleteChars: (self param: 1 default: 1)].
	final = 88 "X" ifTrue: [^screen eraseChars: (self param: 1 default: 1)].
	final = 76 "L" ifTrue: [^screen insertLines: (self param: 1 default: 1)].
	final = 77 "M" ifTrue: [^screen deleteLines: (self param: 1 default: 1)].
	final = 83 "S" ifTrue: [^screen scrollUp: (self param: 1 default: 1)].
	(final = 84 "T" and: [count <= 1]) ifTrue: [^screen scrollDown: (self param: 1 default: 1)].
	final = 114 "r" ifTrue: [^screen setScrollRegionTop: (self param: 1 default: 1) bottom: (self param: 2 default: 0)].
	final = 73 "I" ifTrue: [^screen tabForward: (self param: 1 default: 1)].
	final = 90 "Z" ifTrue: [^screen tabBackward: (self param: 1 default: 1)].
	final = 103 "g" ifTrue: [^screen clearTabStop: (self param: 1 default: 0)].
	final = 98 "b" ifTrue: [^screen repeatLastCharacter: (self param: 1 default: 1)].
	final = 104 "h" ifTrue: [^self setModes: true private: false].
	final = 108 "l" ifTrue: [^self setModes: false private: false].
	final = 110 "n" ifTrue: [^screen reportStatus: (self param: 1 default: 0)].
	final = 99 "c" ifTrue: [^screen reportAttributes: false].
	final = 115 "s" ifTrue: [^screen saveCursor].
	final = 117 "u" ifTrue: [^screen restoreCursor]
!
dispatchPrivate: final
	private = 63 "?" ifTrue: [
		final = 104 "h" ifTrue: [^self setModes: true private: true].
		final = 108 "l" ifTrue: [^self setModes: false private: true].
		final = 74 "J" ifTrue: [^screen eraseInDisplay: (self param: 1 default: 0)].
		final = 75 "K" ifTrue: [^screen eraseInLine: (self param: 1 default: 0)].
		^self].
	(private = 62 ">" and: [final = 99 "c"]) ifTrue: [^screen reportAttributes: true]
!
dispatchIntermediate: final
	(intermediate = 33 "exclamation mark" and: [final = 112 "p"]) ifTrue: [^self softReset]
!
setModes: aBoolean private: isPrivate
	1 to: count do: [:i | (params at: i) isNil ifFalse: [screen setMode: (params at: i) private: isPrivate to: aBoolean]]
!
softReset
	"DECSTR"
	screen attribute: 0.
	#(4 20) do: [:m | screen setMode: m private: false to: false].
	screen setMode: 1 private: true to: false.
	screen setMode: 6 private: true to: false.
	screen setMode: 7 private: true to: true.
	screen setMode: 25 private: true to: true.
	screen setScrollRegionTop: 1 bottom: 0
! !

!TerminalParser methodsFor: 'strings'!
stringByte: b
	"Inside OSC (state 4) or an ignored string (state 6); BEL ends an OSC."
	state = 4 ifFalse: [^self].
	b = 7 ifTrue: [self finishString. ^state := 0].
	string position < 4096 ifTrue: [string nextPut: b]
!
finishString
	| text i code |
	string isNil ifTrue: [^self].
	text := string contents utf8Decoded.
	string := nil.
	i := text indexOf: $;.
	i = 0 ifTrue: [^self].
	code := Number readFrom: (text first: i - 1) ifFail: [nil].
	(code = 0 or: [code = 2]) ifTrue: [screen title: (text allButFirst: i)]
! !

!TerminalParser class methodsFor: 'instance creation'!
on: aTerminalScreen
	^self new setScreen: aTerminalScreen
! !
