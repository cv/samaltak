ToolPane subclass: #Inspector
	instanceVariableNames: 'object fields valueView valueHeader evalHeader evalEditor evaluator lastValueText pixelView pixelHeader pixelStatus'
	classVariableNames: ''
	package: 'Tools'!

Inspector comment: 'I am an Inspector (prototypes/1-classic/tools.js openInspector): the fields of an object on the left (self, class, instance variables, indexed slots or dictionary keys), the selected field''s printString on the right, and below an evaluator with self bound to the object (⌘D ⌘P ⌘I, in a Process of its own). Double-click a field to inspect its value in a new Inspector. Right-click a field: Halt on write (a real Watchpoint on that instance variable; the field then shows a "halt on write" tag; "all processes" also halts the window system''s Processes, e.g. the window manager storing a Window''s bounds), Break when this object receives… (a per-object Breakpoint), Breakpoints…. I re-read the values twice a second, so a changing object shows its current state. A Form also shows its pixels magnified (PixelView, remote name pixels); the pixel under the pointer and its value are in the status line below.

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
	top := (anObject isKindOf: Form)
		ifTrue: [self pixelRowOn: anObject]
		ifFalse: [
			(Row with: (Array
				with: ((self pane: fields title: 'Fields') flex: 0.8)
				with: ((Column with: (Array with: valueHeader with: valueView)) flex: 1.2))) percent: 64].
	top separators: true.
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

!Inspector methodsFor: 'pixels'!
pixelRowOn: aForm
	"Fields over the value on the left, the pixels on the right."
	pixelView := PixelView new name: 'pixels'; form: aForm; yourself.
	pixelView onChange: [:view | self pixelsChanged].
	pixelHeader := PaneHeader title: 'Pixels'.
	pixelHeader name: 'pixels-header'.
	pixelStatus := StatusBar new name: 'pixel-status'; yourself.
	self pixelsChanged.
	^(Row with: (Array
		with: ((Column with: (Array
			with: ((self pane: fields title: 'Fields') flex: 1)
			with: ((Column with: (Array with: valueHeader with: valueView)) flex: 0.5))) separators: true; flex: 0.7)
		with: ((Column with: (Array with: pixelHeader with: pixelView with: pixelStatus)) flex: 1.3))) percent: 78
!
pixelsChanged
	pixelHeader rightText: pixelView summary.
	pixelStatus clear.
	pixelView hover isNil
		ifTrue: [pixelStatus add: 'hover a pixel · wheel or + − 0 zoom']
		ifFalse: [pixelStatus add: pixelView hoverText style: #mono]
!
pixelView
	^pixelView
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
!
agentContext
	"The selected field is the receiver when the fields list has focus."
	| field |
	field := fields selection.
	^super agentContext
		receiver: ((field notNil and: [self window keyboardFocus == fields])
			ifTrue: [self valueOf: field]
			ifFalse: [object]);
		bind: #field to: (field ifNotNil: [self valueOf: field]);
		yourself
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
	fields invalidate.
	pixelView isNil ifFalse: [pixelView refresh]
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
	self toggleHaltOnWrite: aField scope: nil
!
toggleHaltOnWrite: aField scope: aScope
	"aScope nil: stores from user Processes halt; #all: also the window system's (e.g. the window manager moving a window)."
	| wp |
	wp := self watchpointFor: aField.
	wp isNil
		ifTrue: [
			(Watchpoint on: object instVarNamed: aField name) scope: aScope.
			Tools toast: 'Watchpoint: ', (self shortPrintOf: object limit: 20), ' is read-only now; a store into ', aField name, (aScope isNil ifTrue: [''] ifFalse: [' from any process']), ' halts']
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
			ifFalse: [
				(m add: 'Halt on write' description: 'watchpoint' action: [self toggleHaltOnWrite: aField]) name: 'halt-on-write'.
				(m add: 'Halt on write, all processes' description: 'window system too' action: [self toggleHaltOnWrite: aField scope: #all]) name: 'halt-on-write-everywhere']].
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
	^self openOn: anObject in: (Tools placeNear: aWindowOrNil extent: ((anObject isKindOf: Form) ifTrue: [720 @ 540] ifFalse: [450 @ 290])) bindings: aDictionaryOrNil
!
article: aString
	^((aString notEmpty and: ['AEIOU' includes: aString first]) ifTrue: ['an '] ifFalse: ['a ']), aString
! !

!Inspector methodsFor: 'events'!
keyDown: anEvent
	| field key |
	(self window keyboardFocus == fields and: [anEvent modifiers commandKey]) ifTrue: [
		field := fields selection.
		field ifNotNil: [
			key := anEvent key.
			key = $i ifTrue: [self dive: field. ^true].
			key = $b ifTrue: [Tools browseClass: (self valueOf: field) class. ^true]]].
	^super keyDown: anEvent
! !
