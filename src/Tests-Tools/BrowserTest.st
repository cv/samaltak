ToolsTestCase subclass: #BrowserTest
	instanceVariableNames: 'window browser'
	classVariableNames: ''
	package: 'Tests-Tools'!

BrowserTest comment: 'I test the System Browser: navigating to a method as a user does, the breakpoint gutter (a real Breakpoint), accepting an edit (the method is recompiled, and written into a scratch copy of its source file; reverting restores the file byte for byte), syntax errors marked inline.'!

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
	| menu item listing |
	self browseTo: ToolsTestFixture selector: #answer.
	menu := self in: window do: [browser methodMenuFor: #answer].
	item := menu itemLabeled: 'machine code'.
	self assert: item name equals: 'machine-code'.
	self in: window do: [item action value].
	self assert: (self waitFor: [(self windowTitled: 'Machine code: ToolsTestFixture>>answer') notNil]) description: 'no machine code window'.
	listing := self windowTitled: 'Machine code: ToolsTestFixture>>answer'.
	self assert: (self waitFor: [listing isOpen and: [listing queue isEmpty]]) description: 'the window did not settle'.
	self assert: (listing content text includesSubstring: 'pc 0: ').
	self assert: (listing content text includesSubstring: 'entry:')
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
		ensure: [Breakpoint removeAll]
!
testAcceptKeepsABreakpoint
	self browseTo: ToolsTestFixture selector: #answer.
	Breakpoint on: ToolsTestFixture selector: #answer.
	[self in: window do: [browser code accept].
	 self assert: (Breakpoint forClass: ToolsTestFixture selector: #answer) notNil.
	 self assert: (Breakpoint ignoreDuring: [ToolsTestFixture new answer]) equals: 42]
		ensure: [Breakpoint removeAll]
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
! !
