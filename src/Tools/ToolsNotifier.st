ToolPane subclass: #ToolsNotifier
	instanceVariableNames: 'session stack code'
	classVariableNames: ''
	package: 'Tools'!

ToolsNotifier comment: 'I am the fallback notifier for a DebugSession when no Debugger is installed (Tools installFallbackOpener): the stop''s title and where the Process is, Proceed / Abandon, the top of the stack and the selected frame''s source with its current expression marked. The real Debugger replaces me by installing its own DebugSession openerBlock.'!

!ToolsNotifier methodsFor: 'initialization'!
setSession: aDebugSession
	| head buttons |
	session := aDebugSession.
	head := Column with: (Array
		with: ((Label text: session label font: #uiBold) fixed: 22; padding: (12 @ 4 corner: 12 @ 0); yourself)
		with: ((Label text: 'Process ''', (session process name ifNil: ['a Process']), ''' · suspended · other Processes keep running' font: #smallItalic)
			color: #ink2; fixed: 20; padding: (12 @ 0 corner: 12 @ 2); yourself)).
	head fixed: 46.
	buttons := Row with: (Array
		with: ((Button label: 'Proceed' action: [self proceed]) beDefault; sizeToContent; yourself)
		with: ((Button label: 'Abandon' action: [self abandon]) sizeToContent; yourself)
		with: (Widget new flex: 1)).
	buttons spacing: 6; padding: (12 @ 5 corner: 12 @ 5); fixed: 32.
	stack := ListView new name: 'stack'; title: 'Stack'; font: #code12; yourself.
	stack items: (session stackOfSize: 12); onSelect: [:ctx | self showFrame: ctx].
	code := ToolTextEditor new name: 'source'; title: 'source'; readOnly: true; methodMode: true; yourself.
	self separators: true.
	self addAll: (Array with: head with: buttons with: (stack fixed: 120; yourself) with: code).
	stack items isEmpty ifFalse: [stack selectIndex: 1]
! !

!ToolsNotifier methodsFor: 'actions'!
showFrame: aContext
	| interval |
	aContext isNil ifTrue: [^code text: ''].
	code text: (session sourceOf: aContext).
	interval := [session intervalOf: aContext] on: Error do: [:e | e return: nil].
	interval isNil ifFalse: [code pcMark: interval]
!
proceed
	session proceed.
	self window close
!
abandon
	session abandon.
	self window close
!
windowClosed
	(session notNil and: [session process isSuspended]) ifTrue: [session abandon]
! !

!ToolsNotifier methodsFor: 'remote control'!
remoteRole
	^#notifier
! !

!ToolsNotifier class methodsFor: 'opening'!
openOn: aDebugSession
	| pane |
	pane := self new setSession: aDebugSession.
	^pane openIn: (Tools placeAt: nil extent: 520 @ 330) title: aDebugSession label
! !
