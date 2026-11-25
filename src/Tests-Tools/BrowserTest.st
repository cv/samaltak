ToolsTestCase subclass: #BrowserTest
	instanceVariableNames: 'window browser'
	classVariableNames: ''
	package: 'Tests-Tools'!

BrowserTest comment: 'I test the System Browser: navigating to a method as a user does, the breakpoint gutter (a real Breakpoint), a double click on a method (its implementors; only on the same row), accepting an edit (the status says accepted at once; the method is recompiled, and written into a scratch copy of its source file; reverting restores the file byte for byte), syntax errors marked inline.'!

!BrowserTest methodsFor: 'running'!
setUp
	super setUp.
	window := self open: [SystemBrowser openIn: (40 @ 60 extent: 866 @ 468) onClass: nil selector: nil].
	browser := window content
! !

!BrowserTest methodsFor: 'support'!
browseTo: aClass selector: aSymbol
	"Select package, class, -- all --, method through the lists' user protocol (select: notifies like a click)."
	self in: window do: [
		(aClass packageName beginsWith: 'Tests-') ifTrue: [browser showTests: true].
		browser packageList select: (browser packageList items detect: [:p | p name = aClass packageName]).
		browser classList select: aClass.
		browser protocolList select: browser allProtocol.
		browser methodList select: aSymbol]
!
gutterPointOf: aSymbol
	| list i r |
	list := browser methodList.
	i := list items indexOf: aSymbol.
	self in: window do: [list scrollToShowIndex: i].
	r := list rowRect: i.
	^list localToScreen: (list paddingX + 5) @ r center y
! !

!BrowserTest methodsFor: 'filter'!
openFilter
	self key: $f modifiers: self commandModifier.
	self settle.
	self assert: (self in: window do: [window keyboardFocus]) == browser filterField
!
filter: aString
	self type: aString.
	self settle.
	self assert: browser filterField text equals: aString
!
type: aString
	DisplayWindow injectEvent: {7. nil. 0. 0. 0. 0. aString. world displayWindow windowId}
!
testFilterFindsMethodsAcrossPackagesAsYouType
	| found |
	self openFilter.
	self filter: 'gcd'.
	found := browser classList items.
	self assert: (found includes: Integer).
	self deny: (found includes: Object).
	self assert: (browser packageList items anySatisfy: [:p | p name = 'Kernel-Numbers']).
	self deny: (browser packageList items anySatisfy: [:p | p name = 'Tools']).
	self type: 'x'.
	self settle.
	self assert: browser classList items isEmpty.
	self assert: browser methodList items isEmpty
!
testFilterPickShowsTheMatchingMethodOnItsSide
	"Return goes to the first class, which shows the method found; a class-side method turns the switch."
	self openFilter.
	self filter: 'integer gcd'.
	self assert: browser classList items first equals: Integer.
	self key: #return modifiers: 0.
	self settle.
	self assert: (self in: window do: [window keyboardFocus]) == browser classList.
	self assert: browser selectedClass equals: Integer.
	self assert: browser methodList items equals: #(#gcd:).
	self assert: browser selectedSelector equals: #gcd:.
	self assert: browser selectedProtocol equals: browser allProtocol.
	self assert: browser code text equals: (Integer >> #gcd:) source.
	self in: window do: [browser openFilter. browser filterField text: 'readFrom'. browser filterChanged].
	self in: window do: [browser classPicked: Number].
	self assert: browser side equals: #class.
	self assert: (browser methodList items allSatisfy: [:s | s asLowercase includesSubstring: 'readfrom'])
!
testFilterNamingAClassShowsItsDefinitionAndAllMethods
	self openFilter.
	self filter: 'orderedcoll'.
	self assert: browser classList items first equals: OrderedCollection.
	self key: #down modifiers: 0.
	self settle.
	self assert: (browser code text includesSubstring: 'subclass: #OrderedCollection').
	self assert: browser methodList items size equals: OrderedCollection selectors size.
	"a method picked here has the protocol -- all --, so that it is accepted as a method"
	self in: window do: [browser methodList select: #add:].
	self assert: browser selectedProtocol equals: browser allProtocol.
	self assert: browser code text equals: (OrderedCollection >> #add:) source
!
testFilterKeepsTheCodePaneUntilSomethingIsPicked
	self browseTo: ToolsTestFixture selector: #answer.
	self in: window do: [browser code text: 'answer
	^43'. browser code dirty: true].
	self openFilter.
	self filter: 'gcd'.
	self assert: browser code text equals: 'answer
	^43'.
	self assert: browser code isDirty.
	self assert: browser selectedClass equals: ToolsTestFixture.
	self assert: browser selectedSelector equals: #answer
!
testEscapeShowsTheWholeSystemAtWhatWasPicked
	| focus |
	self in: window do: [browser code focus].
	self openFilter.
	self filter: 'gcd'.
	self key: #escape modifiers: 0.
	self settle.
	self deny: browser isFiltering.
	self assert: (self in: window do: [window keyboardFocus]) == browser code description: 'the focus went back'.
	self assert: browser packageList items size equals: browser sortedPackages size.
	self openFilter.
	self filter: 'integer gcd'.
	self key: #return modifiers: 0.
	self settle.
	focus := self in: window do: [window keyboardFocus].
	self key: #escape modifiers: 0.
	self settle.
	self deny: browser isFiltering.
	self deny: (window content widgetNamed: 'filter-bar') isVisible.
	self assert: (self in: window do: [window keyboardFocus]) == focus.
	self assert: browser packageList selection name equals: 'Kernel-Numbers'.
	self assert: browser classList items equals: browser selectedPackage classes asArray.
	self assert: browser classList selection equals: Integer.
	self assert: browser methodList selection equals: #gcd:.
	self assert: browser protocolList items size equals: browser protocolItems size
!
testFilterArrowsMoveBetweenClassesAndMethods
	self openFilter.
	self filter: 'integer gcd'.
	self key: #return modifiers: 0.
	self settle.
	self key: #right modifiers: 0.
	self settle.
	self assert: (self in: window do: [window keyboardFocus]) == browser methodList.
	self key: #left modifiers: 0.
	self settle.
	self assert: (self in: window do: [window keyboardFocus]) == browser classList
! !

!BrowserTest methodsFor: 'tests'!
testBrowseToGcd
	self browseTo: Integer selector: #gcd:.
	self assert: browser selectedClass equals: Integer.
	self assert: browser selectedProtocol equals: '-- all --'.
	self assert: browser code text equals: (Integer >> #gcd:) source.
	self assert: window title equals: 'System Browser: Integer'.
	self assert: ((window content widgetNamed: 'status') fullText includesSubstring: 'Integer>>gcd:').
	self assert: ((window content widgetNamed: 'status') fullText includesSubstring: 'Kernel-Numbers')
!
testDoubleClickBrowsesImplementorsOnlyOnTheSameRow
	"Presses the platform counts as one multi-click: 4 points apart across the border of the rows #answer and #value, 6 points apart on #answer; then too slow."
	| list r answer value |
	self browseTo: ToolsTestFixture selector: #value.
	list := browser methodList.
	r := list rowRect: (list items indexOf: #answer).
	self assert: (list rowRect: (list items indexOf: #value)) top equals: r bottom.
	answer := list localToScreen: (r left + 60) @ (r bottom - 2).
	value := answer + (0 @ 4).
	self click: value platformCount: 1; click: answer platformCount: 2.
	self click: answer platformCount: 1; click: answer + (6 @ 0) platformCount: 2.
	self click: answer platformCount: 1; click: answer platformCount: 1.
	self settle.
	self assert: browser selectedSelector equals: #answer.
	self assert: (self windowsOf: MethodBrowser) isEmpty description: 'a double click on another row, too far apart or too slow'.
	self click: answer platformCount: 1; click: answer platformCount: 2.
	self assert: (self waitFor: [(self windowsOf: MethodBrowser) notEmpty]) description: 'no implementors window'.
	self assert: (self windowsOf: MethodBrowser) first title equals: 'Implementors of #answer'
!
testPackagesGroupedByLayer
	| items layers |
	items := browser packageList items.
	layers := items collect: [:p | p layer ifNil: [0]].
	self assert: layers first equals: 5.
	self assert: layers last equals: 0.
	1 to: layers size - 1 do: [:i | self assert: (layers at: i) >= (layers at: i + 1)].
	self assert: (items anySatisfy: [:p | p name = 'Tools']).
	"test packages only on request"
	self deny: (items anySatisfy: [:p | p name beginsWith: 'Tests-']).
	self in: window do: [browser showTests: true].
	self assert: (browser packageList items anySatisfy: [:p | p name = 'Tests-Tools'])
!
testGutterClickTogglesARealBreakpoint
	"Integer>>gcd: is used everywhere (Fractions): this test process must not stop at it."
	Breakpoint ignoreDuring: [self gutterClickOnGcd]
!
gutterClickOnGcd
	| point |
	self browseTo: Integer selector: #gcd:.
	self assert: (Breakpoint forClass: Integer selector: #gcd:) isNil.
	point := self gutterPointOf: #gcd:.
	self click: point.
	self assert: (self waitFor: [(Breakpoint forClass: Integer selector: #gcd:) notNil]) description: 'no breakpoint after the gutter click'.
	self assert: (browser breakpointModeOf: #gcd:) equals: #break.
	self assert: (self waitFor: [window queue isEmpty]).
	self click: point.
	self assert: (self waitFor: [(Breakpoint forClass: Integer selector: #gcd:) isNil]) description: 'the second click did not remove it'
!
testMethodMenuSetsLogpointMode
	| menu |
	self browseTo: ToolsTestFixture selector: #answer.
	menu := self in: window do: [browser methodMenuFor: #answer].
	self assert: (menu itemLabeled: 'break once') notNil.
	self assert: (menu itemLabeled: 'senders') notNil.
	self in: window do: [browser setBreakpoint: #answer mode: #once expression: nil].
	self assert: (Breakpoint forClass: ToolsTestFixture selector: #answer) mode equals: #once.
	self in: window do: [browser setBreakpoint: #answer mode: #log expression: 'self printString'].
	self assert: (Breakpoint forClass: ToolsTestFixture selector: #answer) mode equals: #log.
	self assert: (browser breakpointModeOf: #answer) equals: #log
!
testMethodMenuShowsMachineCode
	| menu item listing text |
	self browseTo: ToolsTestFixture selector: #answer.
	menu := self in: window do: [browser methodMenuFor: #answer].
	item := menu itemLabeled: 'machine code'.
	self assert: item name equals: 'machine-code'.
	self in: window do: [item action value].
	self assert: (self waitFor: [(self windowTitled: 'Machine code: ToolsTestFixture>>answer') notNil]) description: 'no machine code window'.
	listing := self windowTitled: 'Machine code: ToolsTestFixture>>answer'.
	self assert: (self waitFor: [listing isOpen]) description: 'the machine code window did not open'.
	text := self in: listing do: [listing content text].
	self assert: (text includesSubstring: 'pc 0: ') description: 'no bytecode in the listing'.
	self assert: (text includesSubstring: 'entry:') description: 'no entry in the listing'.
	self assert: (self in: listing do: [listing content editor tokenTypeAt: (text indexOfSubCollection: 'pc 0: ')]) equals: #return
!
testAcceptWritesTheMethodAndRevertRestoresTheFile
	| real scratch original path |
	real := SourceFiler findSourceDirectory.
	real isNil ifTrue: [^self skip: 'no source directory'].
	original := File readText: real, '/Tests-Tools/ToolsTestFixture.st'.
	scratch := self scratchDirectory.
	Directory create: scratch, '/Tests-Tools'.
	path := scratch, '/Tests-Tools/ToolsTestFixture.st'.
	File writeText: original to: path.
	SourceFiler default: (SourceFiler new sourceDirectory: scratch; yourself).
	[self browseTo: ToolsTestFixture selector: #answer.
	 self assert: ToolsTestFixture new answer equals: 42.
	 self in: window do: [browser code text: 'answer
	"The answer."
	^43'. browser code accept].
	 self assert: ToolsTestFixture new answer equals: 43.
	 self assert: (ToolsTestFixture >> #answer) category equals: 'accessing'.
	 self assert: ((File readText: path) includesSubstring: '^43').
	 self assert: (File readText: path) size equals: original size.
	 self in: window do: [browser code text: 'answer
	"The answer."
	^42'. browser code accept].
	 self assert: ToolsTestFixture new answer equals: 42.
	 self assert: (File readText: path) equals: original]
		ensure: [
			Compiler compile: 'answer
	"The answer."
	^42' in: ToolsTestFixture classified: 'accessing'.
			File deleteIfExists: path]
!
testMethodMenuBreaksInAWindowsProcess
	| menu sub item bp |
	self browseTo: ToolsTestFixture selector: #answer.
	menu := self in: window do: [browser methodMenuFor: #answer].
	sub := (menu itemLabeled: 'break in window') submenu.
	item := sub itemLabeled: window title.
	self assert: item notNil.
	[self in: window do: [item action value].
	 bp := Breakpoint forClass: ToolsTestFixture selector: #answer.
	 self assert: bp scope == window process.
	 self in: window do: [(menu itemLabeled: 'break in all processes') action value].
	 self assert: (Breakpoint forClass: ToolsTestFixture selector: #answer) scope equals: #all.
	 "accepting keeps the scope"
	 self in: window do: [browser code accept].
	 self assert: (Breakpoint forClass: ToolsTestFixture selector: #answer) scope equals: #all]
		ensure: [self removeBreakpoints]
!
testAcceptShowsAccepted
	"⌘S on an edit: the status says accepted at once, not unaccepted edits."
	| status |
	self browseTo: ToolsTestFixture selector: #answer.
	status := window content widgetNamed: 'status'.
	self in: window do: [browser code dirty: true. browser updateStatus].
	self assert: (status fullText includesSubstring: 'unaccepted edits').
	self in: window do: [browser code accept].
	self deny: (status fullText includesSubstring: 'unaccepted').
	self assert: (status fullText includesSubstring: 'accepted')
!
testAcceptKeepsABreakpoint
	self browseTo: ToolsTestFixture selector: #answer.
	Breakpoint on: ToolsTestFixture selector: #answer.
	[self in: window do: [browser code accept].
	 self assert: (Breakpoint forClass: ToolsTestFixture selector: #answer) notNil.
	 self assert: (Breakpoint ignoreDuring: [ToolsTestFixture new answer]) equals: 42]
		ensure: [self removeBreakpoints]
!
testSyntaxErrorIsMarkedInline
	| errors |
	self browseTo: ToolsTestFixture selector: #answer.
	self in: window do: [browser code text: 'answer
	^(42'. browser code accept].
	errors := self markTexts: #error in: browser code.
	self assert: errors size equals: 1.
	self assert: (errors first includesSubstring: 'expected').
	self assert: browser code isDirty.
	self assert: ToolsTestFixture new answer equals: 42
!
testClassDefinitionAndComment
	self in: window do: [
		browser browseClass: ToolsTestFixture selector: nil].
	self assert: (browser code text beginsWith: 'Object subclass: #ToolsTestFixture').
	self assert: (browser code text includesSubstring: 'instanceVariableNames: ''value''').
	self in: window do: [browser selectSide: #comment].
	self assert: browser code text equals: ToolsTestFixture comment.
	self in: window do: [browser selectSide: #class].
	self assert: (browser code text beginsWith: 'ToolsTestFixture class')
!
testAgentContextUsesMostSpecificSelection
	| context |
	self browseTo: Integer selector: #gcd:.
	context := browser agentContext.
	self assert: context receiver equals: (Integer >> #gcd:).
	browser selectProtocol: 'arithmetic'.
	context := browser agentContext.
	self assert: context receiver equals: 'arithmetic'.
	self assert: (context bindings at: #behavior) value equals: Integer.
	browser selectProtocol: nil.
	self assert: browser agentContext receiver equals: Integer
! !
