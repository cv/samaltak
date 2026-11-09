ToolPane subclass: #SystemBrowser
	instanceVariableNames: 'packages classes sideToggle protocols methods code status evaluator package theClass side protocol selector pill pillTimer breakpointListener showTests filterBar filterField filterCount filterWords filterReturnFocus'
	classVariableNames: ''
	package: 'Tools'!

SystemBrowser comment: 'I am the System Browser (prototypes/1-classic/tools.js openBrowser): packages grouped by layer (test and demo packages only with "show tests and demos" from the package list''s menu), classes (with the instance / ? / class switch), protocols (-- all -- first) and methods with a breakpoint gutter; below, the code pane and a status bar (Integer>>gcd:  [0] Kernel · Kernel-Numbers · -- all --).

The code pane shows what is selected: a package''s description, a class definition, its comment (?), the class side''s instance variables, a method template, or a method''s source. ⌘S accepts it for real: a method is compiled into the selected class (syntax errors are marked inline and the pane stays dirty), a definition is evaluated, a comment is set; and SourceFiler writes the change into the package''s chunk file in src/. ⌘D / ⌘P / ⌘I evaluate in the code pane, ⌘B browses.

⌘F opens the filter bar. What you type narrows the lists as you type: its words are looked for, ignoring case, in the class names and selectors (Integer gcd finds Integer>>gcd:), all of them in the name of a class, its selector or both. Classes come from all packages, those named by the filter first; the selection and the code pane stay until you pick something. Return, Tab or ↓ go to the first class, ← and → between the classes and its methods. Escape shows the whole system again at what was picked.

The gutter dot of a method toggles a real breakpoint (Breakpoint on:selector:); right-click a method for break once, logpoint, conditional breakpoint, senders and implementors.

	SystemBrowser openOnClass: Integer selector: #gcd:'!

!SystemBrowser methodsFor: 'initialization'!
initialize
	super initialize.
	side := #instance.
	self build.
	packages items: self sortedPackages.
	self showText: '"Samaltak — ', Smalltalk packages size printString, ' packages on 6 layers. Select a package."' readOnly: true.
	self updateStatus
!
build
	| top classPane |
	packages := PackageListView new name: 'packages'; title: 'Packages'; yourself.
	packages onSelect: [:p | self selectPackage: p];
		itemMenuBlock: [:p | self packageMenu].
	classes := ListView new name: 'classes'; title: 'Classes'; yourself.
	classes labelBlock: [:c | c name]; onSelect: [:c | self classPicked: c]; emptyText: 'no match';
		itemMenuBlock: [:c | self classMenuFor: c].
	sideToggle := ToggleGroup options: (Array with: #instance -> 'instance' with: #comment -> '?' with: #class -> 'class') selected: 1.
	sideToggle framed: true; name: 'side'; fixed: 25; onChange: [:key | self selectSide: key].
	protocols := ListView new name: 'protocols'; title: 'Protocols'; yourself.
	protocols onSelect: [:p | self selectProtocol: p];
		styleBlock: [:p | p = self allProtocol ifTrue: [#muted] ifFalse: [nil]].
	methods := MethodListView new name: 'methods'; title: 'Methods'; yourself.
	methods
		labelBlock: [:sel | sel asString];
		remoteNameBlock: [:sel | sel asString];
		onSelect: [:sel | self selectMethod: sel];
		onDoubleClick: [:sel | self browseImplementors: sel];
		itemMenuBlock: [:sel | self methodMenuFor: sel];
		breakpointBlock: [:sel | self breakpointModeOf: sel];
		onGutterClick: [:sel | self toggleBreakpoint: sel].
	classPane := Column with: (Array with: (PaneHeader title: 'Classes') with: classes with: sideToggle).
	top := Row with: (Array
		with: ((self pane: packages title: 'Packages' right: 'by layer') flex: 1.25)
		with: (classPane flex: 1)
		with: ((self pane: protocols title: 'Protocols') flex: 1)
		with: ((self pane: methods title: 'Methods') flex: 1.1)).
	top separators: true; percent: 58.
	code := ToolTextEditor new name: 'code'; title: 'code'; yourself.
	code onAccept: [:text | self accept: text].
	code onChange: [:editor | self updateStatus].
	evaluator := CodeEvaluator new processName: 'Browser doIt'; yourself.
	evaluator install: code.
	status := StatusBar new name: 'status'; yourself.
	self buildFilterBar.
	self addAll: (Array with: filterBar with: top with: Splitter new with: code with: status)
!
buildFilterBar
	filterField := ToolTextEditor new name: 'filter'; title: 'filter'; yourself.
	filterField highlighting: false;
		onChange: [:editor | self filterChanged];
		onKey: [:evt | self filterKey: evt].
	filterCount := Label text: '' font: #smallItalic.
	filterCount name: 'filter-count'; color: #ink3; align: #right; padding: (6 @ 0 corner: 8 @ 0); fixed: 130.
	filterBar := Row with: (Array
		with: ((Label text: 'Filter' font: #uiBold) padding: (8 @ 0 corner: 0 @ 0); fixed: 52; yourself)
		with: (filterField flex: 1; yourself)
		with: filterCount).
	filterBar name: 'filter-bar'; fixed: 34; visible: false
!
minimumWindowExtent
	^520 @ 300
! !

!SystemBrowser methodsFor: 'accessing'!
selectedPackage
	^package
!
selectedClass
	^theClass
!
selectedBehavior
	"The class or its metaclass, by the instance / class switch."
	theClass isNil ifTrue: [^nil].
	^side == #class ifTrue: [theClass class] ifFalse: [theClass]
!
selectedProtocol
	^protocol
!
selectedSelector
	^selector
!
selectedMethod
	| b |
	b := self selectedBehavior.
	(b isNil or: [selector isNil]) ifTrue: [^nil].
	^b compiledMethodAt: selector ifAbsent: [nil]
!
side
	^side
!
code
	^code
!
allProtocol
	^'-- all --'
!
packageList
	^packages
!
classList
	^classes
!
protocolList
	^protocols
!
methodList
	^methods
! !

!SystemBrowser methodsFor: 'lists'!
packageMenu
	^(Menu title: 'Packages')
		add: 'show tests and demos' checked: self showsTests action: [self showTests: self showsTests not];
		yourself
!
showsTests
	"Whether the test packages (Tests-*) and the Demos package are listed; off by default."
	^showTests == true
!
isAuxiliary: aPackage
	"Tests and demos: not part of the system, listed only on request."
	^(aPackage name beginsWith: 'Tests-') or: [aPackage name = 'Demos']
!
showTests: aBoolean
	| selected |
	showTests := aBoolean.
	self isFiltering ifTrue: [^self showFilterResults].
	selected := packages selection.
	packages items: self sortedPackages.
	(selected notNil and: [packages items includes: selected]) ifTrue: [packages selection: selected]
!
sortedPackages
	"Layer 5 first; within a layer the packages in load order, tests and demos last (only when showsTests)."
	| all |
	all := Smalltalk packages asArray.
	self showsTests ifFalse: [all := all reject: [:p | self isAuxiliary: p]].
	^(all asSortedCollection: [:a :b |
		| la lb ta tb |
		la := a layer ifNil: [0].
		lb := b layer ifNil: [0].
		ta := self isAuxiliary: a.
		tb := self isAuxiliary: b.
		la ~= lb
			ifTrue: [la > lb]
			ifFalse: [ta ~= tb ifTrue: [tb] ifFalse: [(all indexOf: a) <= (all indexOf: b)]]]) asArray
!
protocolItems
	| b cats |
	b := self selectedBehavior.
	b isNil ifTrue: [^#()].
	cats := b categories.
	self isFiltering ifTrue: [cats := cats select: [:c | (self selectorsPassingFilter: (b selectorsInCategory: c)) notEmpty]].
	^(Array with: self allProtocol), cats
!
methodItems
	| b sels |
	b := self selectedBehavior.
	(b isNil or: [protocol isNil and: [self isFiltering not or: [side == #comment]]]) ifTrue: [^#()].
	sels := (protocol isNil or: [protocol = self allProtocol])
		ifTrue: [b selectors]
		ifFalse: [b selectorsInCategory: protocol].
	self isFiltering ifTrue: [sels := self selectorsPassingFilter: sels].
	^(sels asSortedCollection: [:x :y | x <= y]) asArray
!
refreshLists
	"Re-read protocols and methods (after an accept or a change made elsewhere), keeping the selection."
	| sel |
	sel := selector.
	protocols items: self protocolItems.
	(protocol notNil and: [(protocols items includes: protocol) not]) ifTrue: [protocol := self allProtocol. protocols selection: protocol].
	methods items: self methodItems.
	methods selection: sel.
	selector := methods selection
! !

!SystemBrowser methodsFor: 'selecting'!
selectPackage: aPackage
	package := aPackage.
	theClass := nil.
	protocol := nil.
	selector := nil.
	classes items: (aPackage isNil ifTrue: [#()] ifFalse: [self classesOf: aPackage]).
	classes selection: nil.
	protocols items: #().
	methods items: #().
	aPackage isNil ifFalse: [self showText: (self descriptionOf: aPackage) readOnly: true].
	self updateStatus
!
selectClass: aClass
	theClass := aClass.
	protocol := nil.
	selector := nil.
	self isFiltering ifTrue: [self followPackageOf: aClass].
	protocols items: self protocolItems.
	protocols selection: nil.
	methods items: self methodItems selected: nil.
	aClass isNil ifFalse: [self showClassOrFirstMatch].
	self updateStatus
!
selectSide: aSymbol
	side := aSymbol.
	sideToggle selection: aSymbol.
	theClass isNil ifFalse: [self selectClass: theClass]
!
selectProtocol: aString
	protocol := aString.
	selector := nil.
	methods items: self methodItems.
	methods selection: nil.
	aString isNil ifFalse: [self showMethodTemplate].
	self updateStatus
!
selectMethod: aSymbol
	| m |
	selector := aSymbol.
	(aSymbol notNil and: [protocol isNil]) ifTrue: [
		protocol := self allProtocol.
		protocols selection: protocol].
	m := self selectedMethod.
	m isNil ifFalse: [self showMethodSource: m].
	self updateStatus
!
browseClass: aClass selector: aSymbolOrNil
	"Select aClass (its package first) and, if given, its method aSymbolOrNil under -- all --."
	| cls pkg |
	cls := aClass theNonMetaClass.
	pkg := self packageOf: cls.
	(pkg notNil and: [(packages items includes: pkg) not]) ifTrue: [self showTests: true].
	packages selection: pkg.
	self selectPackage: pkg.
	(classes items includes: cls) ifFalse: [classes items: (classes items copyWith: cls)].
	classes selection: cls.
	aClass isMeta ifTrue: [side := #class. sideToggle selection: #class] ifFalse: [side == #class ifTrue: [side := #instance. sideToggle selection: #instance]].
	self selectClass: cls.
	aSymbolOrNil isNil ifTrue: [^self].
	(self selectedBehavior includesSelector: aSymbolOrNil) ifFalse: [^self].
	protocols selection: self allProtocol.
	self selectProtocol: self allProtocol.
	methods selection: aSymbolOrNil.
	self selectMethod: aSymbolOrNil
!
browseClass: aClass protocol: aString selector: aSymbol
	"Select like the prototype''s start: package, class, protocol, method."
	self browseClass: aClass selector: nil.
	(protocols items includes: aString) ifFalse: [^self].
	protocols selection: aString.
	self selectProtocol: aString.
	(methods items includes: aSymbol) ifFalse: [^self].
	methods selection: aSymbol.
	self selectMethod: aSymbol
! !

!SystemBrowser methodsFor: 'filtering'!
isFiltering
	^filterWords notNil
!
filterField
	^filterField
!
openFilter
	"⌘F: the filter bar, its text selected, so that typing starts a new filter."
	| focus |
	focus := self window keyboardFocus.
	focus == filterField ifFalse: [filterReturnFocus := focus].
	filterBar visible: true.
	filterField focus.
	filterField selectAll.
	self showFilterCount
!
closeFilter
	"The whole system again, at what was picked; the focus goes back if it was still in the filter bar."
	self window keyboardFocus == filterField ifTrue: [(filterReturnFocus ifNil: [classes]) focus].
	filterReturnFocus := nil.
	filterField text: ''.
	filterBar visible: false.
	filterWords := nil.
	self showUnfiltered
!
filterChanged
	| words |
	words := filterField text asLowercase substrings.
	words := words isEmpty ifTrue: [nil] ifFalse: [words].
	words = filterWords ifTrue: [^self].
	filterWords := words.
	self isFiltering ifTrue: [self showFilterResults] ifFalse: [self showUnfiltered].
	self showFilterCount
!
filterKey: anEvent
	"Answer whether I handled a key of the filter field."
	| key |
	key := anEvent key.
	key == #escape ifTrue: [self closeFilter. ^true].
	(#(#return #enter #tab #down) includes: key) ifTrue: [self goToFirstResult. ^true].
	^false
!
goToFirstResult
	classes items isEmpty ifTrue: [^self].
	classes focus.
	classes selectionIndex: 1.
	self classPicked: classes selection
!
showFilterCount
	| n |
	self isFiltering ifFalse: [^filterCount text: 'class or method names'].
	n := classes items size.
	filterCount text: n printString, (n = 1 ifTrue: [' class'] ifFalse: [' classes'])
!
showFilterResults
	"Only the lists change: what the code pane shows, and would accept into, stays until something is picked."
	| found names |
	found := self classesPassingFilter.
	names := (found collect: [:c | c packageName]) asSet.
	packages items: (self sortedPackages select: [:p | names includes: p name]) selected: package.
	classes items: found selected: theClass.
	classes selection isNil
		ifTrue: [
			protocols items: #().
			methods items: #()]
		ifFalse: [self showFilteredMembers].
	self showFilterCount
!
showFilteredMembers
	protocols items: self protocolItems selected: protocol.
	methods items: self methodItems selected: selector
!
showUnfiltered
	packages items: self sortedPackages selected: package.
	classes items: (package isNil ifTrue: [#()] ifFalse: [package classes]) selected: theClass.
	self showFilteredMembers
!
classesPassingFilter
	"Of the listed packages. The classes the filter names first, those beginning with its first word first of them, then the classes with a method it names; else by name."
	| found named |
	found := OrderedCollection new.
	self sortedPackages do: [:p | found addAll: (self classesOf: p)].
	named := found select: [:c | (self wordsMissingFrom: c name) isEmpty].
	^(self sortByFilter: named), (self sortByFilter: (found reject: [:c | named includes: c]))
!
sortByFilter: someClasses
	| word |
	word := filterWords first.
	^(someClasses asSortedCollection: [:a :b |
		| pa pb |
		pa := a name asLowercase beginsWith: word.
		pb := b name asLowercase beginsWith: word.
		pa = pb ifTrue: [a name <= b name] ifFalse: [pa]]) asArray
!
classesOf: aPackage
	self isFiltering ifFalse: [^aPackage classes].
	^aPackage classes select: [:c | self passesFilter: c]
!
passesFilter: aClass
	| missing |
	missing := self wordsMissingFrom: aClass name.
	^missing isEmpty or: [(self behavior: aClass hasSelectorWith: missing) or: [self behavior: aClass class hasSelectorWith: missing]]
!
wordsMissingFrom: aName
	"The filter's words not in aName (a class name): a selector has to have those."
	| lower |
	lower := aName asLowercase.
	^filterWords reject: [:w | lower includesSubstring: w]
!
selector: aSymbol hasAll: words
	| lower |
	lower := aSymbol asLowercase.
	^words allSatisfy: [:w | lower includesSubstring: w]
!
behavior: aBehavior hasSelectorWith: words
	^aBehavior selectors anySatisfy: [:s | self selector: s hasAll: words]
!
selectorsPassingFilter: selectors
	"Those of selectors (of the selected class) the filter admits: all if it names the class."
	| missing |
	missing := self wordsMissingFrom: theClass name.
	missing isEmpty ifTrue: [^selectors].
	^selectors select: [:s | self selector: s hasAll: missing]
!
classPicked: aClass
	(self isFiltering and: [aClass notNil]) ifTrue: [self showSideWithMatchesOf: aClass].
	self selectClass: aClass
!
showSideWithMatchesOf: aClass
	"A class found by a method: the side of the switch that method is on (the current one if it has some)."
	| missing |
	missing := self wordsMissingFrom: aClass name.
	missing isEmpty ifTrue: [^self].
	(side ~~ #comment and: [self behavior: (side == #class ifTrue: [aClass class] ifFalse: [aClass]) hasSelectorWith: missing]) ifTrue: [^self].
	side := (self behavior: aClass hasSelectorWith: missing) ifTrue: [#instance] ifFalse: [#class].
	sideToggle selection: side
!
followPackageOf: aClassOrNil
	aClassOrNil isNil ifTrue: [^self].
	package := self packageOf: aClassOrNil.
	packages selection: package
!
packageOf: aClass
	^Smalltalk packages detect: [:p | p name = aClass packageName] ifNone: [nil]
!
showClassOrFirstMatch
	"Filtered: a class found by a method shows its first such method."
	(self isFiltering and: [methods items notEmpty and: [(self wordsMissingFrom: theClass name) notEmpty]])
		ifFalse: [^self showClassText].
	methods selection: methods items first.
	self selectMethod: methods items first
! !

!SystemBrowser methodsFor: 'events'!
keyDown: anEvent
	| key focus |
	key := anEvent key.
	(anEvent modifiers commandKey and: [key = $f]) ifTrue: [self openFilter. ^true].
	(key == #escape and: [filterBar isVisible]) ifTrue: [self closeFilter. ^true].
	self isFiltering ifTrue: [
		focus := self window keyboardFocus.
		(key == #right and: [focus == classes and: [methods items notEmpty]]) ifTrue: [
			methods selectionIndex = 0 ifTrue: [methods moveSelection: 1].
			methods focus.
			^true].
		(key == #left and: [focus == methods]) ifTrue: [classes focus. ^true]].
	^super keyDown: anEvent
! !

!SystemBrowser methodsFor: 'code pane'!
showText: aString readOnly: aBoolean
	code text: aString.
	code readOnly: aBoolean.
	self clearPill
!
showClassText
	side == #comment ifTrue: [
		code highlighting: false; methodMode: false.
		^self showText: (theClass comment ifNil: ['']) readOnly: false].
	code highlighting: true; methodMode: false.
	side == #class ifTrue: [^self showText: (self classSideDefinitionOf: theClass) readOnly: false].
	self showText: (self definitionOf: theClass) readOnly: false
!
showMethodTemplate
	code highlighting: true; methodMode: true.
	self showText: 'message selector and argument names
	"comment stating purpose of message"

	| temporary variable names |
	statements' readOnly: false
!
showMethodSource: aCompiledMethod
	code highlighting: true; methodMode: true.
	self showText: (self sourceOf: aCompiledMethod) readOnly: false
!
sourceOf: aCompiledMethod
	| bp |
	aCompiledMethod source isNil ifFalse: [^aCompiledMethod source].
	bp := Breakpoint forMethod: aCompiledMethod.
	(bp notNil and: [bp originalMethod source notNil]) ifTrue: [^bp originalMethod source].
	^'"no source for ', aCompiledMethod printString, '"'
!
descriptionOf: aPackage
	| cls n ext |
	cls := aPackage classes.
	n := cls inject: 0 into: [:sum :c | sum + c selectors size + c class selectors size].
	ext := aPackage extensionMethods size.
	^'"', aPackage name, ' — layer ', (aPackage layer ifNil: [0]) printString, ' (', (self class layerName: aPackage layer), ')

', (self class layerDescription: aPackage layer), '
', cls size printString, ' classes, ', n printString, ' methods', (ext = 0 ifTrue: [''] ifFalse: [', ', ext printString, ' extension methods']), '.
Layer n may only use layer n-1 and the Kernel."'
!
definitionOf: aClass
	| s kind |
	kind := aClass isImmediateClass ifTrue: ['immediateSubclass:']
		ifFalse: [aClass isWeak ifTrue: ['weakSubclass:']
		ifFalse: [aClass isBytes ifTrue: ['variableByteSubclass:']
		ifFalse: [aClass isWords ifTrue: ['variableWordSubclass:']
		ifFalse: [aClass isDoubleWords ifTrue: ['variableDoubleWordSubclass:']
		ifFalse: [aClass isVariable ifTrue: ['variableSubclass:'] ifFalse: ['subclass:']]]]]].
	s := WriteStream on: (String new: 200).
	s nextPutAll: (aClass superclass isNil ifTrue: ['nil'] ifFalse: [aClass superclass name]);
		space; nextPutAll: kind; nextPutAll: ' #'; nextPutAll: aClass name; nextPut: Character lf; tab;
		nextPutAll: 'instanceVariableNames: '; print: (self join: aClass instVarNames); nextPut: Character lf; tab;
		nextPutAll: 'classVariableNames: '; print: (self join: (aClass classVarNames asSortedCollection: [:a :b | a <= b]) asArray); nextPut: Character lf; tab;
		nextPutAll: 'package: '; print: (aClass packageName ifNil: ['']).
	^s contents
!
classSideDefinitionOf: aClass
	^aClass name, ' class
	instanceVariableNames: ', (self join: aClass class instVarNames) printString
!
join: aCollection
	^String new: 40 streamContents: [:s |
		aCollection do: [:each | s nextPutAll: each asString] separatedBy: [s space]]
! !

!SystemBrowser methodsFor: 'accepting'!
accept: aString
	"⌘S. Answer false to keep the pane dirty (an error)."
	theClass isNil ifTrue: [Tools toast: 'Select a class first'. ^false].
	(protocol notNil and: [side ~~ #comment]) ifTrue: [^self acceptMethod: aString].
	side == #comment ifTrue: [^self acceptComment: aString].
	side == #class ifTrue: [^self acceptClassSide: aString].
	^self acceptDefinition: aString
!
acceptMethod: aString
	| b method sel category old bp written |
	b := self selectedBehavior.
	method := [Compiler compileMethod: aString in: b classified: 'as yet unclassified']
		on: SyntaxError do: [:e |
			self markSyntaxError: e.
			^false].
	sel := method selector.
	old := b compiledMethodAt: sel ifAbsent: [nil].
	category := (protocol isNil or: [protocol = self allProtocol])
		ifTrue: [(old notNil and: [old category notNil]) ifTrue: [old category] ifFalse: ['as yet unclassified']]
		ifFalse: [protocol].
	method category: category.
	bp := Breakpoint forClass: b selector: sel.
	bp isNil ifFalse: [bp remove].
	b addSelector: sel withMethod: method.
	bp isNil ifFalse: [
		[Breakpoint on: b selector: sel mode: bp mode expression: bp expression scope: bp scope] on: Error do: [:e | e return: nil]].
	written := self writeMethod: method replacing: old.
	Transcript show: b name, '>>', sel, ' accepted', (written isNil ifTrue: [''] ifFalse: [' → ', (self shortPath: written)]); cr.
	selector := sel.
	self refreshLists.
	methods selection: sel.
	selector := sel.
	self showPill: 'accepted' style: #pillOk.
	self updateStatus.
	^true
!
writeMethod: aCompiledMethod replacing: oldMethodOrNil
	"Write the method into src/ (moving it if its file changed). Answer the path written or nil."
	| filer path oldPath |
	filer := SourceFiler default.
	filer isEnabled ifFalse: [^nil].
	^[path := filer pathForMethod: aCompiledMethod.
	  (oldMethodOrNil notNil and: [oldMethodOrNil category notNil]) ifTrue: [
		oldPath := filer pathForMethod: oldMethodOrNil.
		oldPath = path ifFalse: [filer removeMethod: oldMethodOrNil selector class: aCompiledMethod methodClass category: oldMethodOrNil category]].
	  filer writeMethod: aCompiledMethod]
		on: Error do: [:e |
			Tools toast: 'Source not written: ', e messageText asString.
			e return: nil]
!
shortPath: aPath
	| i |
	i := aPath indexOfSubCollection: '/src/'.
	^i = 0 ifTrue: [aPath] ifFalse: [aPath copyFrom: i + 1 to: aPath size]
!
acceptComment: aString
	| written |
	theClass comment: aString.
	written := [SourceFiler default writeCommentOf: theClass] on: Error do: [:e | Tools toast: 'Source not written: ', e messageText asString. e return: nil].
	Transcript show: theClass name, ' comment accepted', (written isNil ifTrue: [''] ifFalse: [' → ', (self shortPath: written)]); cr.
	self showPill: 'accepted' style: #pillOk.
	^true
!
acceptDefinition: aString
	| result written |
	result := [Compiler evaluate: aString]
		on: SyntaxError do: [:e | self markSyntaxError: e. ^false].
	(result isKindOf: Class) ifFalse: [Tools toast: 'Not a class definition'. ^false].
	written := [SourceFiler default writeDefinition: (self definitionOf: result) of: result]
		on: Error do: [:e | Tools toast: 'Source not written: ', e messageText asString. e return: nil].
	Transcript show: result name, ' defined', (written isNil ifTrue: [''] ifFalse: [' → ', (self shortPath: written)]); cr.
	self isFiltering
		ifTrue: [self showFilterResults]
		ifFalse: [
			result packageName = package name
				ifTrue: [classes items: package classes]
				ifFalse: [classes items: (classes items copyWith: result)]].
	classes selection: result.
	theClass := result.
	self showPill: 'accepted' style: #pillOk.
	self updateStatus.
	^true
!
acceptClassSide: aString
	"aClass class instanceVariableNames: '...'"
	[Compiler evaluate: aString] on: SyntaxError do: [:e | self markSyntaxError: e. ^false].
	self showPill: 'accepted' style: #pillOk.
	^true
!
markSyntaxError: aSyntaxError
	| gap text range |
	gap := ((aSyntaxError position ifNil: [1]) - 1 max: 0) min: code size.
	text := '‹', aSyntaxError messageText asString, ' →›'.
	(gap > 0 and: [(code text at: gap) isSeparator not]) ifTrue: [text := ' ', text].
	code selectFrom: gap + 1 to: gap.
	range := code insertAfterSelection: text select: true.
	code addMark: range style: #error.
	self showPill: 'syntax error' style: #pillDirty
! !

!SystemBrowser methodsFor: 'breakpoints'!
breakpointModeOf: aSelector
	| b bp |
	b := self selectedBehavior.
	b isNil ifTrue: [^nil].
	bp := Breakpoint forClass: b selector: aSelector.
	bp isNil ifTrue: [^nil].
	bp isEnabled ifFalse: [^nil].
	^bp mode
!
toggleBreakpoint: aSelector
	| b bp |
	b := self selectedBehavior.
	b isNil ifTrue: [^nil].
	bp := Breakpoint forClass: b selector: aSelector.
	bp isNil
		ifTrue: [
			bp := Breakpoint on: b selector: aSelector.
			self toast: 'Breakpoint on ', b name, '>>', aSelector]
		ifFalse: [
			bp remove.
			bp := nil.
			self toast: 'Breakpoint removed'].
	methods invalidate.
	^bp
!
setBreakpoint: aSelector mode: aSymbol expression: aStringOrNil
	self setBreakpoint: aSelector mode: aSymbol expression: aStringOrNil scope: nil
!
setBreakpoint: aSelector mode: aSymbol expression: aStringOrNil scope: aScope
	"aScope: nil (user processes), #all, or a Process (see Breakpoint)."
	| b old |
	b := self selectedBehavior.
	old := Breakpoint forClass: b selector: aSelector.
	old isNil ifFalse: [old remove].
	Breakpoint on: b selector: aSelector mode: aSymbol expression: aStringOrNil scope: aScope.
	methods invalidate
!
removeBreakpoint: aSelector
	| bp |
	bp := Breakpoint forClass: self selectedBehavior selector: aSelector.
	bp isNil ifFalse: [bp remove].
	methods invalidate
!
breakpointsChanged
	| w |
	w := self window.
	w isNil ifFalse: [w do: [methods invalidate]]
!
installBreakpointListener
	breakpointListener isNil ifFalse: [^self].
	breakpointListener := [:bp | self breakpointsChanged].
	Breakpoint addListener: breakpointListener
!
windowClosed
	breakpointListener isNil ifFalse: [Breakpoint removeListener: breakpointListener].
	breakpointListener := nil
! !

!SystemBrowser methodsFor: 'menus'!
methodMenuFor: aSelector
	| m mode b |
	aSelector isNil ifTrue: [^nil].
	b := self selectedBehavior.
	mode := self breakpointModeOf: aSelector.
	m := Menu title: b name, '>>', aSelector.
	mode isNil
		ifTrue: [(m add: 'break' description: 'stop at entry' action: [self setBreakpoint: aSelector mode: #break expression: nil]) name: 'break']
		ifFalse: [(m add: 'remove breakpoint' action: [self removeBreakpoint: aSelector]) name: 'remove-breakpoint'].
	(m add: 'break once' action: [self setBreakpoint: aSelector mode: #once expression: nil]) name: 'break-once'.
	(m add: 'logpoint…' description: 'log, don''t stop' action: [self requestLogpoint: aSelector]) name: 'logpoint'.
	(m add: 'conditional…' description: 'stop if true' action: [self requestCondition: aSelector]) name: 'conditional'.
	(m add: 'break in window' submenu: (self windowProcessMenuFor: aSelector)) name: 'break-in-window'.
	(m add: 'break in all processes' description: 'window system too' action: [self setBreakpoint: aSelector mode: #break expression: nil scope: #all]) name: 'break-everywhere'.
	(m add: 'breakpoints…' action: [Tools open: #breakpoints]) name: 'breakpoints'.
	m addSeparator.
	(m add: 'senders' action: [Tools sendersOf: aSelector]) name: 'senders'.
	(m add: 'implementors' action: [Tools implementorsOf: aSelector]) name: 'implementors'.
	(m add: 'inspect method' action: [Tools inspect: (b compiledMethodAt: aSelector) near: self window]) name: 'inspect-method'.
	(m add: 'machine code' action: [TextView openOn: (b compiledMethodAt: aSelector) machineCode title: 'Machine code: ', b name, '>>', aSelector near: self window scanner: MachineCodeScanner]) name: 'machine-code'.
	^m
!
windowProcessMenuFor: aSelector
	"One item per window: break in that window's Process only (debuggers and the window system included)."
	| m |
	m := Menu title: 'Break in the Process of'.
	Desktop current isNil ifTrue: [^m].
	Desktop current windows do: [:w |
		w process isNil ifFalse: [
			m add: w title action: [self setBreakpoint: aSelector mode: #break expression: nil scope: w process]]].
	^m
!
classMenuFor: aClass
	| m |
	aClass isNil ifTrue: [^nil].
	m := Menu title: aClass name.
	m add: 'browse in new window' action: [Tools browseClass: aClass].
	m add: 'references' action: [MethodBrowser openReferencesTo: aClass name].
	m add: 'inspect class' action: [Tools inspect: aClass near: self window].
	^m
!
requestLogpoint: aSelector
	| b |
	b := self selectedBehavior.
	Tools request: 'Logpoint on ', b name, '>>', aSelector, ' — expression to log'
		initialAnswer: (self defaultLogExpressionFor: aSelector)
		then: [:answer | self setBreakpoint: aSelector mode: #log expression: answer]
!
requestCondition: aSelector
	| b |
	b := self selectedBehavior.
	Tools request: 'Break in ', b name, '>>', aSelector, ' when'
		initialAnswer: '[', (aSelector numArgs = 0 ifTrue: ['true'] ifFalse: [(self argumentNamesOf: aSelector) first, ' isNil']), ']'
		then: [:answer | self setBreakpoint: aSelector mode: #condition expression: answer]
!
defaultLogExpressionFor: aSelector
	| names |
	names := self argumentNamesOf: aSelector.
	names isEmpty ifTrue: [^'self printString'].
	^'''', aSelector, ' '', ', names first, ' printString'
!
argumentNamesOf: aSelector
	| m |
	m := self selectedBehavior compiledMethodAt: aSelector ifAbsent: [^#()].
	^[(m tempNamesAt: 0) first: aSelector numArgs] on: Error do: [:e | e return: #()]
!
browseImplementors: aSelector
	Tools implementorsOf: aSelector
! !

!SystemBrowser methodsFor: 'status'!
updateStatus
	| crumb layer |
	crumb := theClass isNil
		ifTrue: [package isNil ifTrue: ['Samaltak image'] ifFalse: [package name]]
		ifFalse: [
			selector isNil
				ifTrue: [self selectedBehavior name]
				ifFalse: [self selectedBehavior name, '>>', selector]].
	status clear.
	status add: crumb style: #mono.
	package isNil ifFalse: [
		layer := package layer ifNil: [0].
		status add: layer printString style: #chip.
		status add: (self class layerName: layer), ' · ', package name, (protocol isNil ifTrue: [''] ifFalse: [' · ', protocol])].
	code isDirty
		ifTrue: [status addRight: 'unaccepted edits · ⌘S' style: #pillDirty]
		ifFalse: [pill isNil ifFalse: [status addRight: pill first style: pill last]].
	self windowTitle: (theClass isNil ifTrue: ['System Browser'] ifFalse: ['System Browser: ', theClass name])
!
showPill: aString style: aSymbol
	pill := Array with: aString with: aSymbol.
	pillTimer isNil ifFalse: [pillTimer cancel].
	pillTimer := self afterAnimationTime: 1600 do: [pill := nil. pillTimer := nil. self updateStatus].
	self updateStatus
!
clearPill
	pill := nil
! !

!SystemBrowser class methodsFor: 'layers'!
layerName: anInteger
	^#('Kernel' '3D' '2D' 'Windows' 'Widgets' 'Tools') at: ((anInteger ifNil: [0]) max: 0) + 1 ifAbsent: ['?']
!
layerDescription: anInteger
	^#('objects · numbers · processes' 'Graphics-GPU' 'Graphics-Canvas' 'compositor · windows' 'UI-Widgets' 'development tools')
		at: ((anInteger ifNil: [0]) max: 0) + 1 ifAbsent: ['']
! !

!SystemBrowser class methodsFor: 'opening'!
openIn: aRectangle onClass: aClass protocol: aStringOrNil selector: aSymbolOrNil
	"Open a browser; select aClass and its method aSymbolOrNil (in protocol aStringOrNil, else under -- all --)."
	| browser window |
	browser := self new.
	window := browser openIn: aRectangle title: 'System Browser'.
	window do: [
		browser installBreakpointListener.
		aClass isNil ifFalse: [
			aStringOrNil isNil
				ifTrue: [browser browseClass: aClass selector: aSymbolOrNil]
				ifFalse: [browser browseClass: aClass protocol: aStringOrNil selector: aSymbolOrNil]]].
	^window
!
openIn: aRectangle onClass: aClass selector: aSymbolOrNil
	^self openIn: aRectangle onClass: aClass protocol: nil selector: aSymbolOrNil
!
openOnClass: aClass selector: aSymbolOrNil
	^self openIn: (Tools placeAt: nil extent: 860 @ 500) onClass: aClass selector: aSymbolOrNil
!
open
	^self openOnClass: nil selector: nil
!
initialize
	ToolsMenu register: 'System Browser' order: 10 action: [:point |
		self openIn: (Tools placeAt: point extent: 860 @ 500) onClass: nil selector: nil]
! !
