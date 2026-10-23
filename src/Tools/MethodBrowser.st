ToolPane subclass: #MethodBrowser
	instanceVariableNames: 'list code status label'
	classVariableNames: ''
	package: 'Tools'!

MethodBrowser comment: 'I list methods (senders, implementors, references) with their package on the right; the selected one''s source is below and can be edited and accepted (compiled into its class and written to src/ like the System Browser does). Double-click a method to open it in a System Browser.

	MethodBrowser openSendersOf: #gcd:'!

!MethodBrowser methodsFor: 'initialization'!
setLabel: aString methods: aCollection
	label := aString.
	list := ListView new name: 'methods'; title: aString; yourself.
	list
		labelBlock: [:m | m methodClass name, '>>', m selector];
		rightBlock: [:m | m methodClass theNonMetaClass packageName];
		remoteNameBlock: [:m | m methodClass name, '-', m selector];
		onSelect: [:m | self showMethod: m];
		onDoubleClick: [:m | Tools browseMethod: m];
		emptyText: 'none'.
	list items: ((aCollection asSortedCollection: [:a :b | a printString <= b printString]) asArray).
	code := ToolTextEditor new name: 'code'; title: 'code'; methodMode: true; yourself.
	code onAccept: [:text | self accept: text].
	(CodeEvaluator new processName: 'Browser doIt'; yourself) install: code.
	status := StatusBar new name: 'status'; yourself.
	status text: list items size printString, ' methods'.
	self addAll: (Array
		with: ((self pane: list title: aString right: list items size printString, ' methods') percent: 45; yourself)
		with: Splitter new
		with: code
		with: status).
	list items isEmpty ifFalse: [list selectIndex: 1]
! !

!MethodBrowser methodsFor: 'actions'!
showMethod: aCompiledMethod
	aCompiledMethod isNil ifTrue: [^code text: ''].
	code text: (aCompiledMethod source ifNil: ['"no source"']).
	status text: aCompiledMethod printString, ' · ', (aCompiledMethod category ifNil: ['']), ' · ', (aCompiledMethod methodClass theNonMetaClass packageName ifNil: [''])
!
accept: aString
	| old method |
	old := list selection.
	old isNil ifTrue: [^false].
	method := [Compiler compileMethod: aString in: old methodClass classified: (old category ifNil: ['as yet unclassified'])]
		on: SyntaxError do: [:e |
			| p |
			p := ((e position ifNil: [1]) max: 1) min: (code size max: 1).
			code addMark: (p to: p) style: #error.
			Tools toast: e messageText asString.
			^false].
	old methodClass addSelector: method selector withMethod: method.
	[SourceFiler default writeMethod: method] on: Error do: [:e | Tools toast: 'Source not written: ', e messageText asString. e return: nil].
	Transcript show: method printString, ' accepted'; cr.
	method selector = old selector ifTrue: [
		list items: (list items collect: [:m | m == old ifTrue: [method] ifFalse: [m]]).
		list selection: method].
	^true
! !

!MethodBrowser class methodsFor: 'opening'!
open: aCollection label: aString
	^(self new setLabel: aString methods: aCollection) openIn: (Tools placeAt: nil extent: 620 @ 420) title: aString
!
openSendersOf: aSymbol
	^self open: (Smalltalk sendersOf: aSymbol) label: 'Senders of #', aSymbol
!
openImplementorsOf: aSymbol
	^self open: (Smalltalk implementorsOf: aSymbol) label: 'Implementors of #', aSymbol
!
openReferencesTo: aSymbol
	^self open: (Smalltalk referencesTo: aSymbol) label: 'References to ', aSymbol
! !
