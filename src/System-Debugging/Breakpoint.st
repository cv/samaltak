Object subclass: #Breakpoint
	instanceVariableNames: 'id mode expression enabled hits evaluator evaluatorNames scope'
	classVariableNames: 'Registry NextId Ignored Listeners ProcessFilter Suppressed'
	package: 'System-Debugging'!

Breakpoint comment: 'I am an image-side breakpoint; the VM knows nothing about me. A MethodBreakpoint replaces its method by a copy whose bytecodes start with a prologue sending Breakpoint hit: id in: thisContext; an ObjectBreakpoint moves one object into an anonymous subclass of its class whose methods carry that prologue. Removing me restores the original method or class.

mode is #break, #once (removed at the first hit), #log (evaluate expression in the frame and show it on the Transcript without stopping) or #condition (stop only when expression, typically block source like ''[a > 10]'', answers true; arguments, temporaries and self are bound). A stop signals BreakpointHalt, which opens a debugger on the process (or prints the stack when headless).

	Breakpoint on: Integer selector: #gcd:.
	Breakpoint onceOn: Integer selector: #gcd:.
	Breakpoint on: Integer selector: #gcd: log: ''a printString, '' '', anInteger printString''.
	Breakpoint on: Integer selector: #gcd: condition: ''[anInteger > 10]''.
	Breakpoint onObject: aPoint selector: #x:.
	Breakpoint onObject: aPoint.	"any message"
	Breakpoint all; allHits; removeAll

A condition block may take the method''s arguments, or the receiver followed by them: ''[:window | window title = ''''Transcript'''']'' on Window>>redraw.

Breakpoints and watchpoints only act in processes accepted by processFilter (a one-argument block; nil, the default, accepts all) and not ignored (ignoreProcess:, ignoreDuring:). In other processes they neither stop, log, count hits nor consume a #once breakpoint; debugger tools use that for the window system and their own evaluations. A breakpoint can target processes deliberately instead (its scope): inProcess: aProcess acts only in aProcess, inAllProcesses in every process, the window system''s and the debuggers'' included; both ignore processFilter and ignoreProcess:, never ignoreDuring:.

	Breakpoint on: Window selector: #redraw condition: ''[:window | window title = ''''Transcript'''']'' scope: #all.
	Breakpoint on: Debugger selector: #stepOver inProcess: aDebuggerWindow process.
	aBreakpoint inAllProcesses; inProcess: aProcess; inUserProcesses'!

!Breakpoint methodsFor: 'accessing'!
id
	^id
!
scope
	"nil: user processes (see the class comment); #all: every process; a Process: only that one."
	^scope
!
isTargeted
	"Whether I deliberately act in the processes the debugging tools otherwise shield (window system, debuggers)."
	^scope notNil
!
scope: aScope
	"nil (user processes), #all or a Process."
	scope := aScope.
	self class changed: self
!
inProcess: aProcess
	"Act only in aProcess (also a window's or a debugger's)."
	self scope: aProcess
!
inAllProcesses
	"Act in every process, the window system's and the debuggers' included."
	self scope: #all
!
inUserProcesses
	"The default: act in the processes the filter accepts and that are not ignored."
	self scope: nil
!
actsIn: aProcess
	^self class scope: scope accepts: aProcess
!
mode
	^mode
!
expression
	^expression
!
hits
	^hits
!
isEnabled
	^enabled
!
enable
	enabled := true.
	self class changed: self
!
disable
	enabled := false.
	self class changed: self
!
isInstalled
	^Registry notNil and: [(Registry at: id ifAbsent: [nil]) == self]
!
isMethodBreakpoint
	^false
!
isObjectBreakpoint
	^false
!
description
	"Answer a short description such as 'Integer>>gcd: (break once)' or 'Window>>redraw (break in all processes)'."
	^self locationDescription, ' (', self modeDescription, self scopeDescription, ')'
!
scopeDescription
	scope isNil ifTrue: [^''].
	scope == #all ifTrue: [^' in all processes'].
	^' in ', scope name printString
!
locationDescription
	^self subclassResponsibility
!
modeDescription
	mode == #once ifTrue: [^'break once'].
	mode == #log ifTrue: [^'log ', expression].
	mode == #condition ifTrue: [^'if ', expression].
	^'break'
! !

!Breakpoint methodsFor: 'removing'!
remove
	"Uninstall me and forget me."
	self uninstall.
	Registry removeKey: id ifAbsent: [nil].
	self class changed: self
! !

!Breakpoint methodsFor: 'hitting'!
hitIn: aContext
	"aContext reached me. Check the condition (only hits where it holds count), count the hit, log, or stop by signaling BreakpointHalt."
	| process |
	process := Processor activeProcess.
	(enabled and: [self actsIn: process]) ifFalse: [^nil].
	mode == #condition ifTrue: [
		(self class ignoreDuring: [self conditionHoldsIn: aContext]) ifFalse: [^nil]].
	hits := hits + 1.
	self class changed: self.
	mode == #log ifTrue: [
		self class ignoreDuring: [self log: aContext].
		^nil].
	mode == #once ifTrue: [self remove].
	^BreakpointHalt new
		breakpoint: self;
		context: aContext;
		signal: 'Breakpoint: ', self locationDescription
!
log: aContext
	| value text |
	text := [value := self evaluateIn: aContext.
			value isString ifTrue: [value] ifFalse: [value printString]]
		on: Error
		do: [:e | e return: 'logpoint error: ', e messageText asString].
	Transcript show: text; cr
!
conditionHoldsIn: aContext
	"Errors in the condition count as true, so they are noticed."
	| value |
	value := [self evaluateIn: aContext] on: Error do: [:e |
		Transcript show: 'breakpoint condition error: ', e messageText asString; cr.
		e return: true].
	(value isKindOf: BlockClosure) ifTrue: [
		value := [value numArgs = 0
				ifTrue: [value value]
				ifFalse: [value valueWithArguments: (value numArgs = (aContext arguments size + 1)
					ifTrue: [(Array with: aContext receiver), aContext arguments]
					ifFalse: [aContext arguments])]]
			on: Error do: [:e | e return: true]].
	^value == true
!
evaluateIn: aContext
	"Evaluate expression with self and the frame's variables bound. The expression is compiled once (as a method taking the variables as arguments) per frame shape."
	| slots names values selector source |
	slots := aContext tempSlots.
	names := slots collect: [:slot | slot at: 1].
	(evaluator isNil or: [evaluatorNames ~= names]) ifTrue: [
		names isEmpty
			ifTrue: [source := 'doIt']
			ifFalse: [
				source := String new: 100 streamContents: [:s |
					names doWithIndex: [:name :i |
						s nextPutAll: (i = 1 ifTrue: ['doIt: '] ifFalse: [' with: ']); nextPutAll: name]]].
		source := source, (String with: Character lf), '^', expression.
		evaluator := Compiler compileMethod: source in: aContext method methodClass classified: 'breakpoint'.
		evaluatorNames := names].
	values := slots collect: [:slot | (slot at: 2) tempAt: (slot at: 3)].
	^Context executeMethod: evaluator receiver: aContext receiver arguments: values
! !

!Breakpoint methodsFor: 'private'!
setScope: aScope
	scope := aScope
!
setId: anInteger mode: aSymbol expression: aStringOrNil
	id := anInteger.
	mode := aSymbol.
	expression := aStringOrNil.
	enabled := true.
	hits := 0
!
install
	self subclassResponsibility
!
uninstall
	self subclassResponsibility
! !

!Breakpoint methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a Breakpoint('; nextPutAll: self description; nextPut: $)
! !

!Breakpoint class methodsFor: 'class initialization'!
initialize
	Registry isNil ifTrue: [Registry := Dictionary new].
	NextId isNil ifTrue: [NextId := 0].
	Ignored isNil ifTrue: [Ignored := IdentitySet new].
	Suppressed isNil ifTrue: [Suppressed := IdentitySet new].
	Listeners isNil ifTrue: [Listeners := OrderedCollection new]
! !

!Breakpoint class methodsFor: 'method breakpoints'!
on: aClass selector: aSelector
	"Stop whenever aClass>>aSelector runs."
	^self on: aClass selector: aSelector mode: #break expression: nil
!
onceOn: aClass selector: aSelector
	"Stop the first time aClass>>aSelector runs, then remove the breakpoint."
	^self on: aClass selector: aSelector mode: #once expression: nil
!
on: aClass selector: aSelector log: aString
	"Logpoint: whenever aClass>>aSelector runs, show the value of the expression aString (evaluated in the frame) on the Transcript; do not stop."
	^self on: aClass selector: aSelector mode: #log expression: aString
!
on: aClass selector: aSelector condition: aString
	"Stop when aClass>>aSelector runs and aString (an expression or block source, evaluated in the frame) answers true."
	^self on: aClass selector: aSelector mode: #condition expression: aString
!
on: aClass selector: aSelector inProcess: aProcess
	"Stop whenever aClass>>aSelector runs in aProcess (also a window's or a debugger's), and nowhere else."
	^self on: aClass selector: aSelector mode: #break expression: nil scope: aProcess
!
on: aClass selector: aSelector condition: aString scope: aScope
	"A conditional breakpoint acting in aScope: #all (every process, the window system's included) or a Process."
	^self on: aClass selector: aSelector mode: #condition expression: aString scope: aScope
!
on: aClass selector: aSelector mode: aSymbol expression: aStringOrNil
	^self on: aClass selector: aSelector mode: aSymbol expression: aStringOrNil scope: nil
!
on: aClass selector: aSelector mode: aSymbol expression: aStringOrNil scope: aScope
	| method bp |
	method := aClass compiledMethodAt: aSelector ifAbsent: [^self error: aClass name, '>>', aSelector, ' does not exist'].
	(self forClass: aClass selector: aSelector) ifNotNil: [:old | old remove].
	bp := MethodBreakpoint basicNew
		setId: self nextId mode: aSymbol expression: aStringOrNil;
		setClass: aClass selector: aSelector;
		setScope: aScope;
		yourself.
	^self register: bp
! !

!Breakpoint class methodsFor: 'object breakpoints'!
onObject: anObject
	"Stop whenever anObject receives any message."
	^self onObject: anObject selector: nil
!
onObject: anObject selector: aSelectorOrNil
	"Stop whenever anObject (and no other instance of its class) receives aSelectorOrNil (nil: any message)."
	(self forObject: anObject) ifNotNil: [:old | old remove].
	^self register: (ObjectBreakpoint basicNew
		setId: self nextId mode: #break expression: nil;
		setObject: anObject selector: aSelectorOrNil;
		yourself)
! !

!Breakpoint class methodsFor: 'registry'!
all
	"Answer all breakpoints, oldest first."
	^(Registry values asSortedCollection: [:a :b | a id <= b id]) asArray
!
allHits
	"Answer breakpoint -> hit count Associations, oldest breakpoint first."
	^self all collect: [:each | each -> each hits]
!
withId: anInteger
	^Registry at: anInteger ifAbsent: [nil]
!
forClass: aClass selector: aSelector
	^Registry detect: [:each | each isMethodBreakpoint and: [each methodClass == aClass and: [each selector == aSelector]]]
		ifNone: [nil]
!
forMethod: aCompiledMethod
	"Answer the breakpoint installed on aCompiledMethod's selector in its class, also when aCompiledMethod is the patched or the original method."
	^self forClass: aCompiledMethod methodClass selector: aCompiledMethod selector
!
forObject: anObject
	^Registry detect: [:each | each isObjectBreakpoint and: [each object == anObject]] ifNone: [nil]
!
removeAll
	self all do: [:each | each remove]
!
register: aBreakpoint
	aBreakpoint install.
	Registry at: aBreakpoint id put: aBreakpoint.
	self changed: aBreakpoint.
	^aBreakpoint
!
nextId
	^NextId := NextId + 1
! !

!Breakpoint class methodsFor: 'ignoring'!
ignoreProcess: aProcess
	"Breakpoints and watchpoints never stop aProcess (a debugger's own process)."
	Ignored add: aProcess
!
unignoreProcess: aProcess
	Ignored remove: aProcess ifAbsent: [nil]
!
isIgnoring: aProcess
	"Breakpoints and watchpoints in user scope do nothing in aProcess (checked before a hit is counted)."
	(Suppressed notNil and: [Suppressed includes: aProcess]) ifTrue: [^true].
	(Ignored notNil and: [Ignored includes: aProcess]) ifTrue: [^true].
	ProcessFilter isNil ifTrue: [^false].
	^([ProcessFilter value: aProcess] on: Error do: [:e | e return: true]) ~~ true
!
processFilter
	^ProcessFilter
!
processFilter: aBlockOrNil
	"Breakpoints and watchpoints act only in processes for which aBlockOrNil answers true (nil: all processes). An error in the block counts as true."
	ProcessFilter := aBlockOrNil
!
ignoreProcessesSatisfying: aBlock
	"Breakpoints and watchpoints do nothing in processes for which aBlock answers true."
	self processFilter: [:process | (aBlock value: process) ~~ true]
!
ignoreDuring: aBlock
	"Evaluate aBlock with all breakpoints and watchpoints ignored in the active process, targeted ones included."
	| process |
	process := Processor activeProcess.
	(Suppressed includes: process) ifTrue: [^aBlock value].
	Suppressed add: process.
	^aBlock ensure: [Suppressed remove: process ifAbsent: [nil]]
!
scope: aScope accepts: aProcess
	"Whether a breakpoint or watchpoint with aScope (nil: user processes, #all, or a Process) acts in aProcess."
	(Suppressed notNil and: [Suppressed includes: aProcess]) ifTrue: [^false].
	aScope isNil ifTrue: [^(self isIgnoring: aProcess) not].
	aScope == #all ifTrue: [^true].
	^aScope == aProcess
! !

!Breakpoint class methodsFor: 'change notification'!
addListener: aBlock
	"aBlock receives a Breakpoint whenever one is added, removed, hit, enabled or disabled."
	Listeners add: aBlock
!
removeListener: aBlock
	Listeners remove: aBlock ifAbsent: [nil]
!
changed: aBreakpoint
	Listeners copy do: [:each | each cull: aBreakpoint]
! !

!Breakpoint class methodsFor: 'hitting'!
hit: anInteger in: aContext
	"Sent by the prologue of a breakpointed method."
	| bp |
	bp := Registry at: anInteger ifAbsent: [^nil].
	^bp hitIn: aContext
!
forward: anInteger selector: aSelector receiver: anObject arguments: anArray
	"Sent by the wrapper an ObjectBreakpoint installs for a primitive method: run the original method."
	| bp |
	bp := Registry at: anInteger ifAbsent: [nil].
	^Context
		executeMethod: (bp isNil
			ifTrue: [anObject class lookupSelector: aSelector]
			ifFalse: [bp originalMethodFor: aSelector])
		receiver: anObject
		arguments: anArray
! !

!Breakpoint class methodsFor: 'patching'!
prologueSize
	^9
!
patch: aCompiledMethod id: anInteger
	"Answer a copy of aCompiledMethod whose bytecodes start with: Breakpoint hit: anInteger in: thisContext (result popped). Source maps, temp-name maps and inlined-temp scopes are shifted; source and class stay."
	| literals base patched shift map tempMap props |
	literals := aCompiledMethod literals.
	base := literals size.
	base + 3 > 256 ifTrue: [^self error: 'Too many literals for a breakpoint in ', aCompiledMethod printString].
	literals := literals , (Array with: (Smalltalk associationAt: #Breakpoint) with: anInteger with: #hit:in:).
	shift := self prologueSize.
	patched := aCompiledMethod copy.
	patched literals: literals.
	patched bytecodes: (ByteArray new: shift) , aCompiledMethod bytecodes.
	#(16r83 nil 16r82 nil 16r76 16r8D nil 2 16r78) doWithIndex: [:byte :i |
		byte isNil ifFalse: [patched bytecodes at: i put: byte]].
	patched bytecodes at: 2 put: base; at: 4 put: base + 1; at: 7 put: base + 2.
	patched frameSize: (aCompiledMethod frameSize max: aCompiledMethod numArgs + aCompiledMethod numTemps + 3).
	map := aCompiledMethod sourceMap.
	map isNil ifFalse: [
		map := map copy.
		1 to: map size by: 3 do: [:i | map at: i put: (map at: i) + shift].
		patched sourceMap: map].
	tempMap := self tempMapOf: aCompiledMethod.
	props := aCompiledMethod properties isNil
		ifTrue: [IdentityDictionary new]
		ifFalse: [aCompiledMethod properties copy].
	tempMap isNil ifFalse: [
		tempMap := tempMap copy.
		1 to: tempMap size by: 3 do: [:i |
			(tempMap at: i) = 0 ifFalse: [tempMap at: i put: (tempMap at: i) + shift].
			tempMap at: i + 1 put: (tempMap at: i + 1) + shift].
		props at: #tempNames put: tempMap].
	(props at: #inlinedTemps ifAbsent: [nil]) ifNotNil: [:scopes |
		props at: #inlinedTemps put: ((1 to: scopes size) collect: [:i |
			i \\ 3 = 0 ifTrue: [scopes at: i] ifFalse: [(scopes at: i) + shift]])].
	props at: #breakpointPrologueSize put: shift.
	props at: #breakpointId put: anInteger.
	props at: #originalMethod put: aCompiledMethod.
	patched properties: props.
	^patched
!
tempMapOf: aCompiledMethod
	| map recompiled |
	map := aCompiledMethod propertyAt: #tempNames.
	map isNil ifFalse: [^map].
	aCompiledMethod sourceCode isNil ifTrue: [^nil].
	recompiled := [Compiler compileMethod: aCompiledMethod sourceCode in: aCompiledMethod methodClass classified: aCompiledMethod category]
		on: Error do: [:e | e return: nil].
	(recompiled isNil or: [recompiled bytecodes ~= aCompiledMethod bytecodes]) ifTrue: [^nil].
	^recompiled propertyAt: #tempNames
! !
