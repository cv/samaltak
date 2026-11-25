ToolPane subclass: #CuOptWindow
	instanceVariableNames: 'routing program tabs stack routingPane programPane map vehiclesToggle routeList distanceLabel editor examples variablesTable constraintsTable status pending lastResult'
	classVariableNames: ''
	package: 'Tools-CUDA'!

CuOptWindow comment: 'I am the cuOpt window (World menu › Apps › GPU): NVIDIA cuOpt solving on the GPU what one edits here, as one edits it. Routing: a depot and stops on a map (CuOptRouteMap: click to add, drag to move, shift-click to remove) and a number of vehicles; each change is solved (CuOptRouting, a mixed-integer program) and the routes drawn. Linear program: the program as text (CuOptProgram: an objective, constraints, integer declarations), solved shortly after each edit, with the objective, the variables and the constraints'' activities beside it. The status bar says the problem''s size, cuOpt''s answer and how long it took. cuOptSolve blocks the VM while it runs: tenths of a second for a linear program, up to the time limit (1 s for routes) for an integer one.

	CuOptWindow open'!

!CuOptWindow methodsFor: 'initialization'!
initialize
	super initialize.
	routing := CuOptRouting example.
	routing timeLimit: 1.
	self build
!
build
	| toolbar side |
	tabs := Tabs options: {#routing -> 'Routing'. #program -> 'Linear program'}.
	tabs name: 'tabs'; selection: #routing; onChange: [:key | self showTab: key].
	toolbar := Row with: {tabs sizeToContent. (Label text: (CuOpt isAvailable ifTrue: ['cuOpt ' , ([CuOpt version] on: Error do: [:e | e return: '?'])] ifFalse: ['no cuOpt here']) font: #smallItalic) color: #ink3; align: #right; flex: 1; yourself}.
	toolbar spacing: 6; padding: (8 @ 5 corner: 8 @ 5); fixed: 30.
	map := CuOptRouteMap new name: 'map'; yourself.
	map tool: self.
	vehiclesToggle := ToggleGroup options: {1 -> '1'. 2 -> '2'. 3 -> '3'. 4 -> '4'}.
	vehiclesToggle name: 'vehicles'; selection: routing vehicles; onChange: [:k | routing vehicles: k. self solveRouting].
	routeList := ListView new name: 'routes'; title: 'Routes'; yourself.
	routeList labelBlock: [:r | r first]; rightBlock: [:r | r last].
	routeList emptyText: 'not solved yet'.
	distanceLabel := Label new name: 'distance'; font: #readout; yourself.
	side := Column with: {
		PaneHeader title: 'Vehicles' right: 'at most'.
		(Row with: {vehiclesToggle flex: 1; yourself}) padding: (8 @ 5 corner: 8 @ 5); fixed: 30; yourself.
		(Row with: {
			(Button label: 'Solve' action: [self solveRouting]) name: 'solve'; flex: 1; yourself.
			(Button label: 'Shuffle' action: [self shuffle]) name: 'shuffle'; flex: 1; yourself.
			(Button label: 'Clear' action: [self clearStops]) name: 'clear'; flex: 1; yourself}) spacing: 6; padding: (8 @ 3 corner: 8 @ 5); fixed: 30; yourself.
		PaneHeader title: 'Distance' right: 'all vehicles'.
		(Row with: {distanceLabel flex: 1; yourself}) padding: (10 @ 2 corner: 8 @ 2); fixed: 34; yourself.
		PaneHeader title: 'Routes' right: 'stops · distance'.
		routeList flex: 1; yourself.
		(Label text: 'click adds · drag moves · shift-click removes' font: #smallItalic) color: #ink3; fixed: 22; yourself}.
	routingPane := (Row with: {map flex: 1; yourself. side fixed: 250; yourself}) separators: true; name: 'routing'; yourself.
	editor := ToolTextEditor new name: 'program'; title: 'program'; highlighting: false; yourself.
	editor onChange: [:e | self programEdited].
	examples := ToggleGroup options: (CuOptProgram examples collect: [:e | e key -> e key]).
	examples name: 'examples'; onChange: [:k | self loadExample: k].
	variablesTable := TableView new name: 'variables'; title: 'Variables'; yourself.
	variablesTable
		addColumn: (TableColumn title: 'Variable' flex: 1 text: [:v | v first]);
		addColumn: ((TableColumn title: 'Value' width: 90 text: [:v | self format: (v at: 2)]) align: #right; yourself);
		addColumn: ((TableColumn title: 'Kind' width: 70 text: [:v | v last]) align: #right; yourself).
	constraintsTable := TableView new name: 'constraints'; title: 'Constraints'; yourself.
	constraintsTable
		addColumn: (TableColumn title: 'Constraint' flex: 1 text: [:c | c first]);
		addColumn: ((TableColumn title: 'Activity' width: 80 text: [:c | self format: (c at: 2)]) align: #right; yourself);
		addColumn: ((TableColumn title: 'Bound' width: 80 text: [:c | c at: 3]) align: #right; yourself);
		addColumn: ((TableColumn title: 'Slack' width: 70 text: [:c | self format: (c at: 4)]) align: #right; yourself).
	programPane := (Row with: {
		(self pane: editor title: 'Program' right: 'maximize / minimize · name: a + 2 b <= 4 · integer · binary') flex: 1.1; yourself.
		(Column with: {
			PaneHeader title: 'Examples'.
			(Row with: {examples flex: 1; yourself}) padding: (8 @ 5 corner: 8 @ 5); fixed: 30; yourself.
			(self pane: variablesTable title: 'Variables' right: 'at the optimum') flex: 1; yourself.
			(self pane: constraintsTable title: 'Constraints' right: 'activity · bound · slack') flex: 1; yourself}) flex: 1; yourself}) separators: true; name: 'linear-program'; yourself.
	programPane visible: false.
	stack := Stack with: {routingPane. programPane}.
	status := StatusBar new name: 'status'; yourself.
	self addAll: {toolbar. ProfilerRule new. stack flex: 1; yourself. status}.
	self loadExample: CuOptProgram examples first key
!
minimumWindowExtent
	^640 @ 440
! !

!CuOptWindow methodsFor: 'accessing'!
routing
	^routing
!
program
	^program
!
map
	^map
!
editor
	^editor
!
statusBar
	^status
!
variablesTable
	^variablesTable
!
constraintsTable
	^constraintsTable
!
routeList
	^routeList
!
lastResult
	^lastResult
!
tab
	^tabs selection
! !

!CuOptWindow methodsFor: 'tabs'!
showTab: aSymbol
	tabs selection: aSymbol.
	routingPane visible: aSymbol == #routing.
	programPane visible: aSymbol == #program.
	stack layout.
	self invalidate.
	aSymbol == #program ifTrue: [editor focus. self solveProgram] ifFalse: [self showRouting]
! !

!CuOptWindow methodsFor: 'routing'!
addStop: aPoint
	routing addStop: aPoint.
	self solveRouting
!
removeStop: index
	routing removeStopAt: index.
	self solveRouting
!
routingMoved
	"A stop moves: show the old routes grey until it is let go."
	map invalidate
!
shuffle
	| r |
	r := Random new.
	1 to: routing stops size do: [:i | routing stopAt: i put: (r next * 0.9 + 0.05) @ (r next * 0.9 + 0.05)].
	self solveRouting
!
clearStops
	[routing stops isEmpty] whileFalse: [routing removeStopAt: routing stops size].
	self solveRouting
!
solveRouting
	"Solve the routes now (blocking the VM for cuOpt's time) and show them."
	map markStale.
	routing stops isEmpty ifTrue: [routing solve. ^self showRouting].
	CuOpt isAvailable ifFalse: [^self showUnavailable].
	self showSolving: 'MILP: ' , routing stops size printString , ' stops, ' , routing vehicles printString , ' vehicles'.
	[routing solve] on: CudaError do: [:e | ^self showError: e messageText].
	lastResult := routing result.
	self showRouting
!
showRouting
	| rows |
	map markFresh.
	rows := routing routes isNil
		ifTrue: [#()]
		ifFalse: [routing routes collectWithIndex: [:route :k |
			{'vehicle ' , k printString , ': ' , (route inject: '' into: [:s :i | s isEmpty ifTrue: [i printString] ifFalse: [s , ' ' , i printString]]).
			route size printString , ' · ' , ((routing distanceOf: route) printShowingDecimalPlaces: 3)}]].
	routeList items: rows.
	distanceLabel text: (routing totalDistance isNil ifTrue: ['—'] ifFalse: [routing totalDistance printShowingDecimalPlaces: 3]).
	routing result isNil
		ifTrue: [status text: (routing stops isEmpty ifTrue: ['no stops: click the map to add some'] ifFalse: ['not solved'])]
		ifFalse: [self showResult: routing result of: 'MILP ' , (routing legs size + routing stops size) printString , ' variables, ' , routing stops size printString , ' stops']
! !

!CuOptWindow methodsFor: 'linear programs'!
loadExample: aString
	| e |
	e := CuOptProgram examples detect: [:each | each key = aString] ifNone: [^self].
	examples selection: aString.
	editor text: e value.
	self tab == #program ifTrue: [self solveProgram]
!
programEdited
	"Solve once typing pauses."
	pending isNil ifFalse: [pending cancel].
	pending := self after: 600 do: [pending := nil. self solveProgram]
!
solveProgram
	| p |
	p := [CuOptProgram fromText: editor text] on: CuOptSyntaxError do: [:e | ^self showError: e messageText].
	program := p.
	CuOpt isAvailable ifFalse: [self showProgram. ^self showUnavailable].
	self showSolving: p summary.
	[p solve] on: CudaError do: [:e | ^self showError: e messageText].
	lastResult := p result.
	self showProgram.
	self showResult: p result of: p summary
!
showProgram
	| p |
	p := program.
	p isNil ifTrue: [^self].
	variablesTable items: (p variables collect: [:v | {v. p valueOf: v. (p isInteger: v) ifTrue: ['integer'] ifFalse: ['real']}]).
	constraintsTable items: ((1 to: p rows size) collect: [:i | | a b |
		a := p activityOf: i.
		b := p rhs at: i.
		{p rowNames at: i. a.
		(#('<= ' '>= ' '= ') at: ('LGE' indexOf: (p senses at: i))) , (self format: b).
		a isNil ifTrue: [nil] ifFalse: [(b - a) abs]}])
! !

!CuOptWindow methodsFor: 'status'!
showSolving: aString
	"Say so, and let the compositor show it before cuOpt blocks the VM."
	| w |
	status clear.
	status add: 'solving on the GPU' style: #pillBusy.
	status add: aString style: #text.
	w := self window.
	w isNil ifTrue: [^self].
	w redraw.
	(Delay forMilliseconds: 40) wait
!
showResult: aResult of: aString
	status clear.
	status add: aResult statusName style: (aResult hasSolution ifTrue: [#mono] ifFalse: [#pillSuspended]).
	aResult hasSolution ifTrue: [status add: 'objective ' , (self format: aResult objective) style: #mono].
	status add: aString style: #text.
	status addRight: (CudaComparison milliseconds: aResult wallSeconds * 1000) , ' (cuOpt ' , (CudaComparison milliseconds: aResult seconds * 1000) , ')' style: #mono
!
showError: aString
	status clear.
	status add: 'error' style: #pillSuspended.
	status add: aString style: #text
!
showUnavailable
	status clear.
	status add: 'no cuOpt' style: #pillSuspended.
	status add: 'install its wheel and name its lib64 in SAMALTAK_CUDA_LIBS (docs/cuda.md)' style: #text
!
format: aNumber
	aNumber isNil ifTrue: [^''].
	(aNumber - aNumber rounded) abs < 1.0e-6 ifTrue: [^aNumber rounded printString].
	^aNumber printShowingDecimalPlaces: 3
! !

!CuOptWindow class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPointOrNil
	^self openIn: (Tools placeAt: aPointOrNil extent: 900 @ 620)
!
openIn: aRectangle
	| tool window |
	tool := self new.
	window := tool openIn: aRectangle title: 'cuOpt'.
	window do: [tool solveRouting].
	^window
!
initialize
	ToolsMenu register: 'cuOpt' description: 'routes · linear programs' group: #gpu order: 20 action: [:point | self openAt: point].
	Tools registerOpener: #cuopt with: [:arg | self open]
! !
