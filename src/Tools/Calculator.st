ToolPane subclass: #Calculator
	instanceVariableNames: 'engine display'
	classVariableNames: ''
	package: 'Tools'!

Calculator comment: 'I am a calculator styled after the HP 12C: a grey-green readout on a light bezel over a graphite keyboard in columns, memory and functions lettered gold, = the tall gold key between them and the number pad; my CalculatorEngine does the arithmetic (algebraic, not RPN). Keys are typed too: digits . , + - * / = % (@ is sqrt, r 1/x), Return is =, Escape C, Delete CE; ⌘C copies the display, ⌘V types the clipboard.

	Calculator open   "also from the World menu"'!

!Calculator methodsFor: 'building'!
actionFor: aString
	"The block a key's label stands for."
	aString size = 1 ifTrue: [
		aString first isDigit ifTrue: [^[:e | e digit: aString first]].
		aString = '.' ifTrue: [^[:e | e point]].
		aString = '=' ifTrue: [^[:e | e equals]].
		aString = '%' ifTrue: [^[:e | e percent]].
		aString = 'C' ifTrue: [^[:e | e clear]].
		^[:e | e operate: aString asSymbol]].
	^(Dictionary new
		at: 'MC' put: [:e | e memoryClear];
		at: 'MR' put: [:e | e memoryRecall];
		at: 'MS' put: [:e | e memoryStore];
		at: 'M+' put: [:e | e memoryAdd];
		at: 'sqrt' put: [:e | e squareRoot];
		at: '1/x' put: [:e | e reciprocal];
		at: '+/-' put: [:e | e negate];
		at: 'CE' put: [:e | e clearEntry];
		at: 'Backspace' put: [:e | e backspace];
		yourself) at: aString
!
build
	"After the HP 12C: the readout on a light bezel over a graphite keyboard in columns, memory and functions in gold, = tall as ENTER between them and the number pad."
	display := CalculatorDisplay new.
	display name: 'display'; fixed: 76.
	self add: display.
	self add: ((Row with: (self keyColumns collect: [:labels |
			labels isEmpty
				ifTrue: [Widget new fixed: 6; yourself]
				ifFalse: [(Column with: (labels collect: [:each |
						(self key: each do: (self actionFor: each)) fixed: (each = '=' ifTrue: [66] ifFalse: [30]); yourself]) asArray)
					spacing: 6; yourself]]) asArray)
		spacing: 6; padding: (14 @ 12 corner: 14 @ 14); yourself).
	self spacing: 0
!
key: aString do: aBlock
	"A key named by its label; a click runs aBlock on my engine."
	^(CalculatorKey label: (self labelFor: aString) action: [self press: aBlock])
		name: aString;
		kind: (self kindFor: aString);
		yourself
!
keyColumns
	"Memory, functions, the clearing keys over =, a gap, then the number pad column by column."
	^#(#('MC' 'MR' 'MS' 'M+')
		#('sqrt' '%' '1/x' '+/-')
		#('C' 'CE' '=')
		#()
		#('7' '4' '1' '0')
		#('8' '5' '2' '.')
		#('9' '6' '3' 'Backspace')
		#('/' '*' '-' '+'))
!
kindFor: aString
	"Memory and functions are gold-lettered, = is the gold key, the rest plain."
	aString = '=' ifTrue: [^#accent].
	(#('MC' 'MR' 'MS' 'M+' 'sqrt' '%' '1/x' '+/-') includes: aString) ifTrue: [^#gold].
	^#plain
!
labelFor: aString
	"The glyph a key shows for its name."
	^(Dictionary new
		at: '/' put: (String with: (Character value: 16rF7));
		at: '*' put: (String with: (Character value: 16rD7));
		at: '-' put: (String with: (Character value: 16r2212));
		at: 'sqrt' put: (String with: (Character value: 16r221A)), 'x';
		at: '+/-' put: (String with: (Character value: 16rB1));
		at: 'Backspace' put: (String with: (Character value: 16r2190));
		yourself) at: aString ifAbsent: [aString]
! !

!Calculator methodsFor: 'accessing'!
displayText
	^display text
!
engine
	^engine
! !

!Calculator methodsFor: 'initialize-release'!
initialize
	super initialize.
	engine := CalculatorEngine new.
	self build.
	self refresh
! !

!Calculator methodsFor: 'events'!
keyDown: anEvent
	"Return is =, Escape C, Delete CE, Backspace Backspace; ⌘C copies the display, ⌘V types the clipboard."
	| key |
	key := anEvent key.
	anEvent modifiers commandKey ifTrue: [
		key = $c ifTrue: [self clipboardText: engine display. ^true].
		key = $v ifTrue: [self typeAll: (self clipboardText ifNil: ['']). ^true]].
	key == #return ifTrue: [^self pressKey: '='].
	key == #enter ifTrue: [^self pressKey: '='].
	key == #escape ifTrue: [^self pressKey: 'C'].
	key == #delete ifTrue: [^self pressKey: 'CE'].
	key == #backspace ifTrue: [^self pressKey: 'Backspace'].
	^super keyDown: anEvent
!
labelForCharacter: aCharacter
	"The key a typed character presses, as in Windows: @ is sqrt, r 1/x, a comma the point."
	(aCharacter isDigit or: ['./*-+=%' includes: aCharacter]) ifTrue: [^String with: aCharacter].
	aCharacter = $, ifTrue: [^'.'].
	aCharacter = $@ ifTrue: [^'sqrt'].
	(aCharacter = $r or: [aCharacter = $R]) ifTrue: [^'1/x'].
	^nil
!
textInput: anEvent
	self typeAll: anEvent string.
	^true
!
typeAll: aString
	aString do: [:c | (self labelForCharacter: c) ifNotNil: [:label | self pressKey: label]]
!
wantsKeyboardFocus
	^true
! !

!Calculator methodsFor: 'opening'!
minimumWindowExtent
	^380 @ 276
! !

!Calculator methodsFor: 'actions'!
press: aBlock
	aBlock value: engine.
	self refresh
!
pressKey: aString
	"Press the key labelled aString as a click would, flashing it."
	| button |
	button := self widgetNamed: aString.
	button isNil ifTrue: [^false].
	button flash.
	button click.
	^true
!
refresh
	display text: engine display.
	display annunciator: (engine hasMemory ifTrue: ['M'] ifFalse: [''])
! !

!Calculator class methodsFor: 'class initialization'!
initialize
	ToolsMenu register: 'Calculator' description: 'after the HP 12C' order: 57 action: [:point | self openAt: point].
	Tools registerOpener: #calculator with: [:argOrNil | self open]
! !

!Calculator class methodsFor: 'opening'!
open
	^self openAt: nil
! !

!Calculator methodsFor: 'drawing'!
drawSelfOn: aCanvas
	aCanvas fillRect: self localBounds color: self class bedColor.
	super drawSelfOn: aCanvas
! !

!Calculator class methodsFor: 'drawing'!
bedColor
	"The keyboard's graphite faceplate."
	^Color hex: 16r2B2B2B
! !

!Calculator class methodsFor: 'instance creation'!
openAt: aPointOrNil
	| calculator window |
	calculator := self new.
	window := calculator openIn: (Tools placeAt: aPointOrNil extent: 430 @ 276) title: 'Calculator'.
	window do: [calculator focus].
	^window
! !
