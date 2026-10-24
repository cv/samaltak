Object subclass: #CodeEvaluator
	instanceVariableNames: 'editor receiverBlock bindings processName running children'
	classVariableNames: 'Sources'
	package: 'Tools'!

CodeEvaluator comment: 'I give a TextEditor do it / print it / inspect it / browse it (⌘D ⌘P ⌘I ⌘B). The selection (or the caret''s line) is compiled in the editor''s window Process; a SyntaxError is marked inline at its position. The code then runs in a fresh Process (processName, default ''Workspace doIt'', priority 40), so the window stays responsive and a halt, breakpoint or error stops only that Process (unhandled errors go to DebugSession and its opener). When it finishes, print it inserts the result after the selection, selected and marked #result; inspect it opens an Inspector.

	evaluator := CodeEvaluator new receiverBlock: [anObject]; bindings: aDictionary; yourself.
	evaluator install: aTextEditor.

running are my do-it Processes still alive; children the Processes they forked that still run (the Workspace footer shows both, each with its progress: ''in the Debugger'' while a debugger has it, else the counter of its source''s to:do: loop read from its stack, e.g. 181/400).'!

!CodeEvaluator methodsFor: 'initialization'!
initialize
	bindings := Dictionary new.
	processName := 'Workspace doIt'.
	running := OrderedCollection new.
	children := OrderedCollection new
! !

!CodeEvaluator methodsFor: 'accessing'!
editor
	^editor
!
bindings
	^bindings
!
bindings: aDictionary
	bindings := aDictionary
!
receiverBlock: aBlock
	receiverBlock := aBlock
!
receiver
	^receiverBlock isNil ifTrue: [nil] ifFalse: [receiverBlock value]
!
processName: aString
	processName := aString
!
running
	"My do-it Processes that have not finished (each removes itself, in my editor's window Process, after showing its result)."
	^running
!
children
	"Processes forked by my do-its that have not terminated."
	children := children reject: [:p | p isTerminated].
	^children
!
adopt: aProcess source: aString
	"Show aProcess (forked elsewhere from aString, e.g. the World menu's long computation) as one of mine."
	children add: aProcess.
	self class note: aProcess source: aString
!
isRunning
	^self running notEmpty
!
isComputing
	"A do-it of mine is running or ready to run (not stopped in a debugger)."
	^self running anySatisfy: [:p | p isSuspended not]
! !

!CodeEvaluator methodsFor: 'installing'!
install: aTextEditor
	editor := aTextEditor.
	aTextEditor
		onDoIt: [:text :range | self evaluate: text at: range mode: #do];
		onPrintIt: [:text :range | self evaluate: text at: range mode: #print];
		onInspectIt: [:text :range | self evaluate: text at: range mode: #inspect];
		onBrowseIt: [:text :range | self browse: text]
! !

!CodeEvaluator methodsFor: 'evaluating'!
evaluate: aString at: anInterval mode: aSymbol
	"Compile aString here (syntax errors are marked inline), then run it in a new Process; answer that Process."
	| receiver method before process |
	(aString allSatisfy: [:c | c isSeparator]) ifTrue: [^nil].
	receiver := self receiver.
	method := [Compiler compileDoIt: aString in: receiver class bindings: bindings]
		on: SyntaxError do: [:e |
			self markSyntaxError: e at: anInterval.
			^nil].
	before := IdentitySet new.
	before addAll: Processor allProcesses.
	process := [
		[| value text |
		 value := Compiler new bindings: bindings; doIt: method source: aString; evaluate: aString for: receiver.
		 aSymbol == #print ifTrue: [text := self printStringOf: value].
		 self finished: process value: value text: text mode: aSymbol at: anInterval before: before]
			ensure: [editor inWindowDo: [running remove: process ifAbsent: [nil]. editor invalidate]]] newProcess.
	process priority: Processor userSchedulingPriority; name: processName.
	running add: process.
	self class note: process source: aString.
	aSymbol == #do ifTrue: [self flash: anInterval].
	process resume.
	^process
!
printStringOf: anObject
	^[anObject printString] on: Error do: [:e |
		e return: 'a ', anObject class name, ' (printString failed: ', e messageText asString, ')']
!
finished: aProcess value: anObject text: aStringOrNil mode: aSymbol at: anInterval before: aSet
	"Runs in the do-it Process: note forked Processes (not the window system's, which may have started meanwhile, e.g. when the image was resumed), then show the result in the editor's window (opening an Inspector is tool code: breakpoints do not stop it)."
	| forked |
	forked := Processor allProcesses reject: [:p |
		(aSet includes: p) or: [p == aProcess or: [p isTerminated or: [((p name ifNil: ['']) beginsWith: 'debugger') or: [DebuggerTools isUIProcess: p]]]]].
	children addAll: forked.
	forked do: [:p | self class note: p source: (self class sourceOf: aProcess)].
	aSymbol == #inspect ifTrue: [Breakpoint ignoreDuring: [Tools inspect: anObject near: editor window]].
	aSymbol == #print ifTrue: [editor inWindowDo: [self insertResult: aStringOrNil after: anInterval]]
!
insertResult: aString after: anInterval
	| range |
	anInterval last <= editor size ifTrue: [editor selectFrom: anInterval first to: anInterval last].
	range := editor insertAfterSelection: ' ', aString select: true.
	editor addMark: range style: #result.
	^range
!
flash: anInterval
	| mark |
	mark := editor addMark: anInterval style: #search.
	editor afterAnimationTime: 600 do: [editor removeMark: mark]
!
markSyntaxError: aSyntaxError at: anInterval
	"Insert the message at the error's position (Squeak style), selected and marked #error."
	| gap text range |
	gap := anInterval first - 1 + ((aSyntaxError position ifNil: [1]) - 1).
	gap := (gap max: 0) min: editor size.
	text := '‹', aSyntaxError messageText asString, ' →›'.
	(gap > 0 and: [(editor text at: gap) isSeparator not]) ifTrue: [text := ' ', text].
	editor selectFrom: gap + 1 to: gap.
	range := editor insertAfterSelection: text select: true.
	editor addMark: range style: #error.
	^range
!
browse: aString
	"⌘B: browse the class named aString, else the implementors of the selector."
	| name value selector |
	name := aString trimBoth.
	name isEmpty ifTrue: [^nil].
	(name first = $#) ifTrue: [name := name allButFirst].
	value := Smalltalk at: name asSymbol ifAbsent: [nil].
	(value notNil and: [value isBehavior]) ifTrue: [^Tools browseClass: value].
	selector := (name includes: $:)
		ifTrue: [(name substrings select: [:w | w last = $:]) inject: '' into: [:acc :w | acc, w]]
		ifFalse: [name substrings first].
	(Smalltalk implementorsOf: selector asSymbol) isEmpty ifTrue: [^Tools toast: 'No class or implementor named ', name].
	^Tools implementorsOf: selector asSymbol
! !

!CodeEvaluator methodsFor: 'status'!
statusText
	"'Workspace doIt' running · 'crunch' running ... (empty when nothing runs)."
	| parts |
	parts := OrderedCollection new.
	self running do: [:p | parts add: (self describe: p)].
	self children do: [:p | parts add: (self describe: p)].
	^String new: 60 streamContents: [:s |
		parts do: [:each | s nextPutAll: each] separatedBy: [s nextPutAll: '   ']]
!
describe: aProcess
	| progress |
	progress := self class progressOf: aProcess.
	^'''', (aProcess name ifNil: ['a Process']), ''' ',
		(aProcess isSuspended ifTrue: ['suspended'] ifFalse: [aProcess isWaiting ifTrue: ['waiting'] ifFalse: ['running']]),
		(progress isNil ifTrue: [''] ifFalse: [' · ', progress])
!
allSuspended
	| all |
	all := self running, self children.
	^all notEmpty and: [all allSatisfy: [:p | p isSuspended]]
! !

!CodeEvaluator class methodsFor: 'progress'!
note: aProcess source: aString
	"Remember the source a do-it Process (or a Process it forked) runs, for progressOf:."
	Sources isNil ifTrue: [Sources := IdentityDictionary new].
	Sources keys do: [:p | p isTerminated ifTrue: [Sources removeKey: p]].
	Sources at: aProcess put: aString
!
sourceOf: aProcess
	^Sources isNil ifTrue: [nil] ifFalse: [Sources at: aProcess ifAbsent: [nil]]
!
progressOf: aProcess
	"If aProcess's source has a loop 'to: <limit> do: [:<counter> |', the counter's current value read from aProcess's stack, e.g. '181/400'; else 'in the Debugger' while a debugger has aProcess; else nil."
	| loop ctx debugged |
	debugged := (DebugSession isDebugging: aProcess) ifTrue: ['in the Debugger'] ifFalse: [nil].
	(aProcess isActiveProcess or: [aProcess isTerminated]) ifTrue: [^nil].
	loop := self loopIn: ((self sourceOf: aProcess) ifNil: [^debugged]).
	loop isNil ifTrue: [^debugged].
	ctx := aProcess suspendedContext.
	[ctx notNil] whileTrue: [
		"n timesRepeat: [...] counts in Integer>>timesRepeat:'s count, called from the do-it"
		(loop last = '(counter)' and: [ctx method selector == #timesRepeat: and: [ctx sender notNil and: [ctx sender method selector == #DoIt]]]) ifTrue: [
			(ctx at: 2) isInteger ifTrue: [^(ctx at: 2) printString, '/', loop first printString]].
		ctx method selector == #DoIt ifTrue: [
			| names k |
			names := [ctx method tempNamesForContext: ctx] on: Error do: [:e | e return: #()].
			k := names indexOf: loop last.
			(k > 0 and: [(ctx at: k) isInteger]) ifTrue: [^(ctx at: k) printString, '/', loop first printString]].
		ctx := ctx sender].
	^debugged
!
loopIn: aString
	"{limit. counter name} of the first 'to: <integer> do: [:<name> |' or '<integer> timesRepeat:' ('(counter)': the count of the Integer>>timesRepeat: it calls) in aString, or nil."
	| i j limit name |
	i := aString indexOfSubCollection: ' timesRepeat:' startingAt: 1.
	i > 0 ifTrue: [
		j := i.
		[j > 1 and: [(aString at: j - 1) isDigit]] whileTrue: [j := j - 1].
		j < i ifTrue: [^Array with: (Integer readFrom: (aString copyFrom: j to: i - 1) ifFail: [^nil]) with: '(counter)']].
	i := aString indexOfSubCollection: ' to: ' startingAt: 1.
	i = 0 ifTrue: [^nil].
	j := i + 5.
	[j <= aString size and: [(aString at: j) isDigit]] whileTrue: [j := j + 1].
	j = (i + 5) ifTrue: [^nil].
	limit := Integer readFrom: (aString copyFrom: i + 5 to: j - 1) ifFail: [^nil].
	(aString indexOfSubCollection: ' do: [:' startingAt: j) = j ifFalse: [^nil].
	j := j + 7.
	i := j.
	[j <= aString size and: [(aString at: j) isLetter or: [(aString at: j) isDigit]]] whileTrue: [j := j + 1].
	j = i ifTrue: [^nil].
	name := aString copyFrom: i to: j - 1.
	^Array with: limit with: name
! !
