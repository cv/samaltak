ToolPane subclass: #Calculator
	instanceVariableNames: 'engine display memoryBox'
	classVariableNames: ''
	package: 'Tools'!

Calculator comment: 'I am a calculator after the Windows 95 one (standard view): a display, Backspace CE C beside the memory light, then the memory keys, digits and operators; my CalculatorEngine does the arithmetic. Keys are typed too: digits . , + - * / = % (@ is sqrt, r 1/x), Return is =, Escape C, Delete CE; ⌘C copies the display, ⌘V types the clipboard.

	Calculator open   "also from the World menu"'!

!Calculator methodsFor: 'building'!
actionFor: aString
	"The block a key's label stands for."
	aString size = 1 ifTrue: [
		aString first isDigit ifTrue: [^[:e | e digit: aString first]].
		aString = '.' ifTrue: [^[:e | e point]].
		aString = '=' ifTrue: [^[:e | e equals]].
		aString = '%' ifTrue: [^[:e | e percent]].
		^[:e | e operate: aString asSymbol]].
	^(Dictionary new
		at: 'MC' put: [:e | e memoryClear];
		at: 'MR' put: [:e | e memoryRecall];
		at: 'MS' put: [:e | e memoryStore];
		at: 'M+' put: [:e | e memoryAdd];
		at: 'sqrt' put: [:e | e squareRoot];
		at: '1/x' put: [:e | e reciprocal];
		at: '+/-' put: [:e | e negate];
		yourself) at: aString
!
build
	"The Windows 95 standard view: the display, then Backspace CE C beside the memory light, then four rows of memory keys, digits and operators."
	display := CalculatorDisplay new.
	display name: 'display'; fixed: 34.
	memoryBox := CalculatorDisplay new.
	memoryBox name: 'memory'; align: #center; fixed: 40.
	self addAll: (Array
		with: display
		with: ((Row with: (Array
			with: memoryBox
			with: (Widget new fixed: 8; yourself)
			with: Widget new
			with: ((self key: 'Backspace' do: [:e | e backspace]) fixed: 86; yourself)
			with: ((self key: 'CE' do: [:e | e clearEntry]) fixed: 60; yourself)
			with: ((self key: 'C' do: [:e | e clear]) fixed: 60; yourself))) spacing: 6; fixed: 30; yourself)).
	self keyRows do: [:labels |
		self add: ((Row with: ((labels collect: [:each | self key: each do: (self actionFor: each)]) asArray
				copyReplaceFrom: 2 to: 1 with: (Array with: (Widget new fixed: 8; yourself)))
			) spacing: 6; fixed: 30; yourself)].
	(self widgetNamed: 'MC') fixed: 40.
	(self widgetNamed: 'MR') fixed: 40.
	(self widgetNamed: 'MS') fixed: 40.
	(self widgetNamed: 'M+') fixed: 40.
	self spacing: 8; padding: (10 @ 10 corner: 10 @ 10)
!
key: aString do: aBlock
	"A key named by its label; a click runs aBlock on my engine."
	^(Button label: aString action: [self press: aBlock])
		name: aString;
		yourself
!
keyRows
	^#(#('MC' '7' '8' '9' '/' 'sqrt')
		#('MR' '4' '5' '6' '*' '%')
		#('MS' '1' '2' '3' '-' '1/x')
		#('M+' '0' '+/-' '.' '+' '='))
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
	^300 @ 250
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
	memoryBox text: (engine hasMemory ifTrue: ['M'] ifFalse: [''])
! !

!Calculator class methodsFor: 'class initialization'!
initialize
	ToolsMenu register: 'Calculator' description: 'Windows 95 standard' order: 57 action: [:point | self openAt: point].
	Tools registerOpener: #calculator with: [:argOrNil | self open]
! !

!Calculator class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPointOrNil
	| calculator window |
	calculator := self new.
	window := calculator openIn: (Tools placeAt: aPointOrNil extent: 330 @ 280) title: 'Calculator'.
	window do: [calculator focus].
	^window
! !
