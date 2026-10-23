Column subclass: #DebuggerTestWorkspace
	instanceVariableNames: 'editor bindings processes'
	classVariableNames: ''
	package: 'Tests-Tools-Debugger'!

DebuggerTestWorkspace comment: 'I am a minimal workspace for the Debugger tests when the core tools'' Workspace is not loaded: an editor (remote name text) whose ⌘D / ⌘P compile the selection or line and run it in a fresh Process named ''Workspace doIt'' (so a breakpoint or an error stops that Process, not my window); print it inserts the result after the selection, marked #result. Workspace variables persist in my bindings.'!

!DebuggerTestWorkspace methodsFor: 'initialization'!
setText: aString
	bindings := Dictionary new.
	processes := OrderedCollection new.
	editor := TextEditor new.
	editor name: 'text'; title: 'text'; text: aString.
	editor onDoIt: [:text :range | self run: text printing: false].
	editor onPrintIt: [:text :range | self run: text printing: true].
	self add: editor
! !

!DebuggerTestWorkspace methodsFor: 'accessing'!
editor
	^editor
!
bindings
	^bindings
!
processes
	"My do-it Processes."
	^processes
! !

!DebuggerTestWorkspace methodsFor: 'evaluating'!
run: aString printing: aBoolean
	| method |
	method := Compiler compileDoIt: aString in: UndefinedObject bindings: bindings.
	processes add: ([| value |
		value := Compiler execute: method for: nil.
		aBoolean ifTrue: [
			self inWindowDo: [| interval |
				interval := editor insertAfterSelection: ' ', value printString select: true.
				editor addMark: interval style: #result]]]
		forkAt: Processor userSchedulingPriority named: 'Workspace doIt')
! !

!DebuggerTestWorkspace class methodsFor: 'opening'!
openOn: aString in: aWorld
	| w |
	w := Window new.
	w title: 'Workspace'; content: (self new setText: aString; yourself); bounds: (40 @ 60 extent: 560 @ 300).
	w openIn: aWorld.
	^w
! !
