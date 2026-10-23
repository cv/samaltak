ToolPane subclass: #Inspector
	instanceVariableNames: 'object fields valueView valueHeader evalHeader evalEditor evaluator lastValueText'
	classVariableNames: ''
	package: 'Tools'!

Inspector comment: 'I am an Inspector (prototypes/1-classic/tools.js openInspector): the fields of an object on the left (self, class, instance variables, indexed slots or dictionary keys), the selected field''s printString on the right, and below an evaluator with self bound to the object (⌘D ⌘P ⌘I, in a Process of its own). Double-click a field to inspect its value in a new Inspector. Right-click a field: Halt on write (a real Watchpoint on that instance variable; the field then shows a "halt on write" tag), Break when this object receives… (a per-object Breakpoint), Breakpoints…. I re-read the values twice a second, so a changing object shows its current state.

	Inspector openOn: 3 @ 4 near: nil'!

!Inspector methodsFor: 'initialization'!
setObject: anObject bindings: aDictionaryOrNil
	| top |
	object := anObject.
	fields := ListView new name: 'fields'; title: 'Fields'; yourself.
	fields
		labelBlock: [:f | f name];
		rightBlock: [:f | self tagOf: f];
		styleBlock: [:f | f isPseudo ifTrue: [#italic] ifFalse: [nil]];
		remoteNameBlock: [:f | f name];
		remoteStateBlock: [:f | (self isWatched: f) ifTrue: [#('halt-on-write')] ifFalse: [#()]];
		onSelect: [:f | self showField: f];
		onDoubleClick: [:f | self dive: f];
		itemMenuBlock: [:f | self menuFor: f];
		menuKeepsSelection: true.
	fields items: (InspectorField fieldsOf: anObject).
	valueView := ToolTextEditor new name: 'value'; title: 'value'; readOnly: true; highlighting: false; yourself.
	valueHeader := PaneHeader title: 'Value' right: (self className: anObject).
	top := Row with: (Array
		with: ((self pane: fields title: 'Fields') flex: 0.8)
		with: ((Column with: (Array with: valueHeader with: valueView)) flex: 1.2)).
	top separators: true; percent: 64.
	evalEditor := ToolTextEditor new name: 'evaluate'; title: 'evaluate'; yourself.
	evalEditor text: (self sampleExpressionFor: anObject).
	evaluator := CodeEvaluator new receiverBlock: [object]; processName: 'Inspector doIt'; yourself.
	aDictionaryOrNil isNil ifFalse: [evaluator bindings: aDictionaryOrNil].
	evaluator install: evalEditor.
	evalHeader := MixedPaneHeader title: 'Evaluate' right: '⌘D · ⌘P · ⌘I'.
	evalHeader tail: 'self = ', (self shortPrintOf: anObject limit: 40).
	evalHeader name: 'evaluate-header'.
	self addAll: (Array with: top with: Splitter new with: (Column with: (Array with: evalHeader with: evalEditor))).
	fields selectIndex: 1
!
minimumWindowExtent
	^300 @ 200
! !

!Inspector methodsFor: 'accessing'!
object
	^object
!
fieldList
	^fields
!
valueView
	^valueView
!
evaluateEditor
	^evalEditor
!
fieldNamed: aString
	^fields items detect: [:f | f name = aString] ifNone: [nil]
! !

!Inspector methodsFor: 'printing'!
className: anObject
	^anObject class name
!
printOf: anObject limit: anInteger
	^Breakpoint ignoreDuring: [
		[anObject printStringLimitedTo: anInteger]
			on: Error do: [:e | e return: 'a ', anObject class name, ' (printString failed: ', e messageText asString, ')']]
!
shortPrintOf: anObject limit: anInteger
	| s |
	s := self printOf: anObject limit: anInteger + 10.
	s := s copyReplaceAll: (String with: Character lf) with: ' '.
	s size > anInteger ifTrue: [s := (s first: anInteger), '…'].
	^s
!
shortPrintOf: anObject
	^self shortPrintOf: anObject limit: 40
!
sampleExpressionFor: anObject
	| samples |
	samples := Dictionary new.
	samples at: #Array put: 'self size';
		at: #Point put: 'self x * self y';
		at: #Fraction put: 'self reciprocal';
		at: #ByteString put: 'self asUppercase';
		at: #ByteSymbol put: 'self size';
		at: #SmallInteger put: 'self printString size';
		at: #LargePositiveInteger put: 'self printString size';
		at: #SmallFloat64 put: 'self rounded';
		at: #BoxedFloat64 put: 'self rounded';
		at: #Character put: 'self asInteger'.
	^samples at: anObject class name ifAbsent: ['self printString']
!
tagOf: aField
	| tags |
	tags := OrderedCollection new.
	(self isWatched: aField) ifTrue: [tags add: 'halt on write'].
	(aField kind == #self and: [(Breakpoint forObject: object) notNil]) ifTrue: [tags add: 'breakpoint'].
	^tags isEmpty ifTrue: [nil] ifFalse: [tags first]
! !

!Inspector methodsFor: 'fields'!
valueOf: aField
	^[aField valueIn: object] on: Error do: [:e | e return: nil]
!
showField: aField
	| text |
	aField isNil ifTrue: [valueView text: ''. lastValueText := nil. ^self].
	text := self printOf: (self valueOf: aField) limit: 100000.
	text = lastValueText ifTrue: [^self].
	lastValueText := text.
	valueView text: text.
	valueHeader rightText: (self className: (self valueOf: aField))
!
refresh
	"Re-read the selected field's value and the tags (my window's Process, twice a second)."
	fields selection isNil ifFalse: [self showField: fields selection].
	fields invalidate
!
dive: aField
	aField isNil ifTrue: [^nil].
	^Inspector openOn: (self valueOf: aField) near: self window bindings: evaluator bindings
!
watchpointFor: aField
	aField isInstVar ifFalse: [^nil].
	^(Watchpoint forObject: object) detect: [:w | w fieldName = aField name] ifNone: [nil]
!
isWatched: aField
	^(self watchpointFor: aField) notNil
!
toggleHaltOnWrite: aField
	| wp |
	wp := self watchpointFor: aField.
	wp isNil
		ifTrue: [
			Watchpoint on: object instVarNamed: aField name.
			Tools toast: 'Watchpoint: ', (self shortPrintOf: object limit: 20), ' is read-only now; a store into ', aField name, ' halts']
		ifFalse: [
			wp unwatch.
			Tools toast: 'No longer watching ', aField name].
	fields invalidate
!
breakOnReceive: aField
	| target |
	target := self valueOf: aField.
	target isNil ifTrue: [^Tools toast: 'nil is shared: no per-object breakpoint on it'].
	Tools request: 'Break when ', (self shortPrintOf: target limit: 30), ' receives (empty: any message)'
		initialAnswer: ''
		then: [:answer |
			| sel |
			sel := answer trimBoth.
			Breakpoint onObject: target selector: (sel isEmpty ifTrue: [nil] ifFalse: [sel asSymbol]).
			Tools toast: 'Breakpoint on ', (self shortPrintOf: target limit: 30), (sel isEmpty ifTrue: [''] ifFalse: [' >>', sel])]
!
menuFor: aField
	| m |
	aField isNil ifTrue: [^nil].
	m := Menu title: aField name.
	(m add: 'inspect' action: [self dive: aField]) name: 'inspect'.
	aField isInstVar ifTrue: [
		(self isWatched: aField)
			ifTrue: [(m add: 'Remove halt on write' action: [self toggleHaltOnWrite: aField]) name: 'remove-halt-on-write']
			ifFalse: [(m add: 'Halt on write' description: 'watchpoint' action: [self toggleHaltOnWrite: aField]) name: 'halt-on-write']].
	(m add: 'Break when this object receives…' action: [self breakOnReceive: aField]) name: 'break-on-receive'.
	(m add: 'Breakpoints…' action: [Tools open: #breakpoints]) name: 'breakpoints'.
	m addSeparator.
	(m add: 'browse class' action: [Tools browseClass: (self valueOf: aField) class]) name: 'browse-class'.
	^m
!
startRefreshing
	self every: 500 do: [self refresh]
! !

!Inspector class methodsFor: 'opening'!
openOn: anObject in: aRectangle bindings: aDictionaryOrNil
	| inspector window |
	inspector := self new setObject: anObject bindings: aDictionaryOrNil.
	window := inspector openIn: aRectangle title: 'Inspector: ', (self article: anObject class name).
	window do: [inspector startRefreshing].
	^window
!
openOn: anObject near: aWindowOrNil
	^self openOn: anObject near: aWindowOrNil bindings: nil
!
openOn: anObject near: aWindowOrNil bindings: aDictionaryOrNil
	^self openOn: anObject in: (Tools placeNear: aWindowOrNil extent: 450 @ 290) bindings: aDictionaryOrNil
!
article: aString
	^((aString notEmpty and: ['AEIOU' includes: aString first]) ifTrue: ['an '] ifFalse: ['a ']), aString
! !
