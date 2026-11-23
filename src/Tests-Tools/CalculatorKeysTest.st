WidgetTestCase subclass: #CalculatorKeysTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

CalculatorKeysTest comment: 'I test that a Calculator window takes the keyboard: typed text and Return, Backspace and Escape.'!

!CalculatorKeysTest methodsFor: 'tests'!
testTypingAndKeys
	| calculator |
	calculator := self open: Calculator new extent: 320 @ 460.
	self type: '7*6'.
	self key: #return.
	self assert: calculator displayText equals: '42'.
	self type: '12'.
	self key: #backspace.
	self assert: calculator displayText equals: '1'.
	self key: #escape.
	self assert: calculator displayText equals: '0'.
	self type: '?'.
	self assert: calculator displayText equals: '0'
! !
