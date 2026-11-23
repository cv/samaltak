ToolPane subclass: #Calculator
	instanceVariableNames: 'display buttons bigFont smallFont accumulator operator entry value fresh lastOperator lastOperand error'
	classVariableNames: ''
	package: 'Tools'!

Calculator comment: 'I am a calculator like the standard one of Windows: a display over a grid of keys. Operators apply left to right as they are pressed (2 + 3 × 4 = 20); = again repeats the last operation; % takes a percentage of the first operand for + and −. I calculate exactly (Fractions) and show 16 significant digits. The keyboard works too: digits . + - * / = %, Return is =, Backspace ⌫, Escape C, Delete CE.

	Calculator open'!

!Calculator methodsFor: 'operations'!
apply: anOperator to: aNumber and: anotherNumber
	"Answer the result, nil for a division by zero."
	anOperator = '+' ifTrue: [^aNumber + anotherNumber].
	anOperator = '−' ifTrue: [^aNumber - anotherNumber].
	anOperator = '×' ifTrue: [^aNumber * anotherNumber].
	anotherNumber = 0 ifTrue: [^nil].
	^aNumber / anotherNumber
!
clear
	accumulator := nil.
	operator := nil.
	lastOperator := nil.
	lastOperand := nil.
	error := false.
	self clearEntry
!
clearEntry
	entry := nil.
	value := 0.
	fresh := false.
	self show
!
equals
	| op operand |
	operator isNil
		ifTrue: [
			lastOperator isNil ifTrue: [^self].
			op := lastOperator.
			operand := lastOperand.
			accumulator := value]
		ifFalse: [
			op := operator.
			operand := value.
			lastOperator := op.
			lastOperand := operand.
			operator := nil].
	self result: (self apply: op to: accumulator and: operand).
	fresh := true
!
fail: aString
	"Show aString until the next C, CE, ⌫ or digit."
	error := true.
	entry := nil.
	accumulator := nil.
	operator := nil.
	self showText: aString
!
negate
	entry isNil ifTrue: [^self unary: value negated].
	entry = '0' ifTrue: [^self].
	entry := entry first = $- ifTrue: [entry allButFirst] ifFalse: ['-', entry].
	self entered
!
operator: aKey
	"Apply the pending operator if a number was entered since, then wait for the next operand."
	(operator notNil and: [fresh not]) ifTrue: [
		(self result: (self apply: operator to: accumulator and: value)) ifFalse: [^self]].
	accumulator := value.
	operator := aKey.
	entry := nil.
	fresh := true
!
percent
	self unary: (((operator = '+' or: [operator = '−']) and: [accumulator notNil])
		ifTrue: [accumulator * value / 100]
		ifFalse: [value / 100])
!
reciprocal
	value = 0 ifTrue: [^self fail: 'Cannot divide by zero'].
	self unary: 1 / value
!
result: aNumberOrNil
	"Show a result; answer false (and show the error) when there is none."
	aNumberOrNil isNil ifTrue: [self fail: 'Cannot divide by zero'. ^false].
	value := aNumberOrNil.
	entry := nil.
	self show.
	^true
!
square
	self unary: value squared
!
squareRoot
	| root |
	value < 0 ifTrue: [^self fail: 'Invalid input'].
	root := value asFloat sqrt asExactFraction.
	root squared = value ifFalse: [
		(value isFraction and: [value numerator sqrtFloor squared = value numerator and: [value denominator sqrtFloor squared = value denominator]])
			ifTrue: [root := value numerator sqrtFloor / value denominator sqrtFloor]].
	self unary: root
!
unary: aNumber
	value := aNumber.
	entry := nil.
	fresh := false.
	self show
! !

!Calculator methodsFor: 'entry'!
backspace
	entry isNil ifTrue: [^self].
	entry := entry allButLast.
	(entry isEmpty or: [entry = '-']) ifTrue: [entry := '0'].
	self entered
!
digit: aString
	(entry isNil or: [entry = '0']) ifTrue: [entry := ''].
	(entry count: [:each | each isDigit]) < 16 ifTrue: [entry := entry, aString].
	self entered
!
entered
	value := self entryValue.
	fresh := false.
	self show
!
entryValue
	"The exact number the entry spells."
	| s sign dot fraction |
	s := entry.
	sign := 1.
	(s notEmpty and: [s first = $-]) ifTrue: [sign := -1. s := s allButFirst].
	dot := s indexOf: $..
	dot = 0 ifTrue: [^sign * (self integerFrom: s)].
	fraction := s allButFirst: dot.
	^sign * ((self integerFrom: (s first: dot - 1)) + ((self integerFrom: fraction) / (10 raisedTo: fraction size)))
!
integerFrom: aString
	^aString isEmpty ifTrue: [0] ifFalse: [aString asInteger]
!
point
	entry isNil ifTrue: [entry := '0'].
	(entry includes: $.) ifFalse: [entry := entry, '.'].
	self entered
! !

!Calculator methodsFor: 'initialization'!
build
	| rows |
	bigFont := self displayFont: 30.
	smallFont := self displayFont: 20.
	display := Label text: '0' font: bigFont.
	display name: 'display'; align: #right; padding: 10; fixed: 70.
	buttons := Dictionary new.
	rows := self keyRows collect: [:keys | | row |
		row := Row with: (keys collect: [:each | self buttonFor: each]).
		row spacing: 4; flex: 1.
		row].
	self spacing: 4; padding: 8.
	self addAll: (Array with: display), rows
!
buttonFor: aKey
	| button |
	button := Button label: aKey action: [self press: aKey].
	button name: aKey; font: self buttonFont; flex: 1.
	aKey = '=' ifTrue: [button beDefault].
	buttons at: aKey put: button.
	^button
!
initialize
	super initialize.
	self build.
	self clear
!
keyRows
	^#(#('%' 'CE' 'C' '⌫') #('1/x' 'x²' '√' '÷') #('7' '8' '9' '×') #('4' '5' '6' '−') #('1' '2' '3' '+') #('±' '0' '.' '='))
!
minimumWindowExtent
	^240 @ 340
! !

!Calculator methodsFor: 'drawing'!
buttonFont
	| font |
	font := Font faceNamed: 'IosevkaEtoile-Bold' size: 18.
	font lineHeight: 22.
	^font
!
displayFont: aSize
	| font |
	font := Font faceNamed: 'JetBrainsMono-Regular' size: aSize.
	font lineHeight: 40.
	^font
!
format: aNumber
	"aNumber rounded to 16 significant digits, without trailing zeros; very large or small ones as a Float prints."
	| n digits scaled s |
	aNumber isInteger ifTrue: [
		^aNumber abs < (10 raisedTo: 16) ifTrue: [aNumber printString] ifFalse: [aNumber asFloat printString]].
	n := aNumber abs.
	(n >= (10 raisedTo: 16) or: [n < (1 / (10 raisedTo: 15))]) ifTrue: [^aNumber asFloat printString].
	digits := n < 1 ifTrue: [16] ifFalse: [16 - n truncated printString size].
	scaled := (n * (10 raisedTo: digits)) rounded.
	s := scaled printString.
	s size <= digits ifTrue: [s := (String new: digits + 1 - s size withAll: $0), s].
	s := (s first: s size - digits), '.', (s last: digits).
	[s last = $0] whileTrue: [s := s allButLast].
	s last = $. ifTrue: [s := s allButLast].
	(aNumber negative and: [s ~= '0']) ifTrue: [s := '-', s].
	^s
!
show
	self showText: (entry ifNil: [self format: value])
!
showText: aString
	"Long numbers get the smaller font so that 16 digits fit."
	display font: (aString size > 12 ifTrue: [smallFont] ifFalse: [bigFont]).
	display text: aString
! !

!Calculator methodsFor: 'accessing'!
displayText
	^display text
! !

!Calculator methodsFor: 'keys'!
keyDown: anEvent
	| key |
	anEvent modifiers commandKey ifFalse: [
		key := #(#(#return '=') #(#enter '=') #(#backspace '⌫') #(#escape 'C') #(#delete 'CE'))
			detect: [:pair | pair first == anEvent key] ifFound: [:pair | pair last] ifNone: [nil].
		key isNil ifFalse: [(buttons at: key) click. ^true]].
	^super keyDown: anEvent
!
keyForCharacter: aCharacter
	aCharacter isDigit ifTrue: [^aCharacter asString].
	^#(#($+ '+') #($- '−') #($* '×') #($x '×') #($/ '÷') #($= '=') #($. '.') #($, '.') #($% '%') #($r '1/x') #($q 'x²') #($@ '√'))
		detect: [:pair | pair first = aCharacter]
		ifFound: [:pair | pair last]
		ifNone: [nil]
!
press: aKey
	"Act on aKey, the label of one of my buttons."
	| digit |
	digit := aKey size = 1 and: [aKey first isDigit].
	error ifTrue: [
		(#('C' 'CE' '⌫') includes: aKey) ifTrue: [^self clear].
		(digit or: [aKey = '.']) ifFalse: [^self].
		self clear].
	digit ifTrue: [^self digit: aKey].
	(#('+' '−' '×' '÷') includes: aKey) ifTrue: [^self operator: aKey].
	self perform: (self unaryKeys at: aKey ifAbsent: [^self])
!
textInput: anEvent
	| keys |
	keys := anEvent string asArray collect: [:each | self keyForCharacter: each].
	(keys includes: nil) ifTrue: [^false].
	keys do: [:each | (buttons at: each) click].
	^true
!
unaryKeys
	^Dictionary new
		at: '%' put: #percent; at: 'CE' put: #clearEntry; at: 'C' put: #clear; at: '⌫' put: #backspace;
		at: '1/x' put: #reciprocal; at: 'x²' put: #square; at: '√' put: #squareRoot;
		at: '±' put: #negate; at: '.' put: #point; at: '=' put: #equals;
		yourself
! !

!Calculator class methodsFor: 'initialization'!
initialize
	ToolsMenu register: 'Calculator' description: 'standard · keyboard' order: 49 action: [:point | self openAt: point]
! !

!Calculator class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPoint
	^self new openIn: (Tools placeAt: aPoint extent: 320 @ 460) title: 'Calculator'
! !
