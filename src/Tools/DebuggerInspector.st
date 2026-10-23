Column subclass: #DebuggerInspector
	instanceVariableNames: 'header fields valuePane evaluator evaluateBlock afterEvaluation defaultIndex'
	classVariableNames: ''
	package: 'Tools'!

DebuggerInspector comment: 'I am one of the two inspectors at the bottom of the Debugger (prototype .dbg-ip): a pane header (RECEIVER / CONTEXT with the inspected object at the right), the fields (DebuggerFieldList) beside the selected field''s value, and an evaluator (⌘D do it, ⌘P print it, ⌘I inspect it). evaluateBlock: [:source | value] decides the binding (self, or the frame''s temporaries); afterEvaluation: runs after every evaluation (the Debugger refreshes, since evaluations can change the frame).

Remote names: me (receiver / context), fields, value, evaluator.'!

!DebuggerInspector methodsFor: 'initialization'!
setTitle: aString placeholder: placeholderString
	header := PaneHeader title: aString right: ''.
	fields := DebuggerFieldList new.
	fields name: 'fields'; title: aString, ' fields'.
	fields onSelect: [:field | self showValue].
	valuePane := TextEditor new.
	valuePane name: 'value'; title: aString, ' value'; readOnly: true; highlighting: false; font: #code12; wrap: true.
	evaluator := DebuggerEvaluator new.
	evaluator name: 'evaluator'; title: aString, ' evaluator'; placeholder: placeholderString; font: #code12; fixed: 52.
	evaluator onDoIt: [:text :range | self evaluate: text printing: false inspecting: false].
	evaluator onPrintIt: [:text :range | self evaluate: text printing: true inspecting: false].
	evaluator onInspectIt: [:text :range | self evaluate: text printing: false inspecting: true].
	defaultIndex := 1.
	self addAll: {
		header.
		(Row with: {fields. valuePane}) separators: true; yourself.
		DebuggerRule new.
		evaluator}
! !

!DebuggerInspector methodsFor: 'accessing'!
header
	^header
!
fields
	^fields
!
valuePane
	^valuePane
!
evaluator
	^evaluator
!
evaluateBlock: aBlock
	evaluateBlock := aBlock
!
afterEvaluation: aBlock
	afterEvaluation := aBlock
!
defaultIndex: anInteger
	"The row selected when the previously selected name is gone."
	defaultIndex := anInteger
!
subtitle: aString
	header rightText: aString
!
fieldItems: aCollection
	"Show new DebuggerFields, keeping the selected name selected (no notification)."
	| previous match |
	previous := fields selection isNil ifTrue: [nil] ifFalse: [fields selection name].
	fields items: aCollection.
	match := previous isNil ifTrue: [nil] ifFalse: [aCollection detect: [:each | each name = previous] ifNone: [nil]].
	match isNil ifTrue: [match := aCollection isEmpty ifTrue: [nil] ifFalse: [aCollection at: (defaultIndex min: aCollection size)]].
	fields selection: match.
	self showValue
!
selectFieldNamed: aString
	(fields items detect: [:each | each name = aString] ifNone: [nil]) ifNotNil: [:field | fields select: field]
!
showValue
	| field |
	field := fields selection.
	valuePane text: (field isNil ifTrue: [''] ifFalse: [field valueText])
! !

!DebuggerInspector methodsFor: 'evaluating'!
evaluate: aString printing: printing inspecting: inspecting
	| result failed interval |
	evaluateBlock isNil ifTrue: [^self].
	failed := nil.
	result := [evaluateBlock value: aString]
		on: Error, Halt
		do: [:e | failed := e. e return: nil].
	failed isNil ifFalse: [
		interval := evaluator insertAfterSelection: ' ', (self describeError: failed) select: true.
		evaluator addMark: interval style: #error.
		^self].
	printing ifTrue: [
		interval := evaluator insertAfterSelection: ' ', ([result printStringLimitedTo: 5000] on: Error do: [:e | e return: '<error printing>']) select: true.
		evaluator addMark: interval style: #result].
	inspecting ifTrue: [Tools inspect: result].
	afterEvaluation isNil ifFalse: [afterEvaluation value]
!
describeError: anException
	| text |
	text := [anException messageText asString] on: Error do: [:e | e return: ''].
	text isEmpty ifTrue: [text := anException class name asString].
	^'‹', text, ' →›'
! !

!DebuggerInspector methodsFor: 'remote control'!
remoteRole
	^#inspector
!
remoteLabel
	^header title
!
remoteIsTransparent
	^false
! !
