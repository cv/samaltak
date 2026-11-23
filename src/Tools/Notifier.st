Column subclass: #Notifier
	instanceVariableNames: 'session header buttons stack done'
	classVariableNames: ''
	package: 'Tools'!

Notifier comment: 'I am the small window that first reports an error, a halt, a doesNotUnderstand: or a user interrupt (prototype notifier): the reason (DebuggerHeader), the buttons Proceed (default), Abandon, Debug and, for a doesNotUnderstand:, Create (the full Debugger takes my place with a menu "Define #zork in…" of the receiver''s class and its superclasses: the method is created, the message resent, and the Debugger stops at the start of the new method), and a short stack (double-click: Debug). The faulting Process is suspended; other Processes keep running. Closing me abandons it.

	Notifier openOn: aDebugSession

Save report writes the error, the Process and its stack, the VM and the heap to samaltak-crash-<n>.txt (CrashReport: on UEFI the boot volume, /esp) and says where.

Remote names: buttons proceed abandon debug create save-report, list stack.'!

!Notifier methodsFor: 'initialization'!
setSession: aSession
	| note |
	session := aSession.
	done := false.
	buttons := Dictionary new.
	header := DebuggerHeader new.
	header fixed: 62.
	header iconKind: (DebuggerTools iconKindFor: aSession) title: (DebuggerTools titleFor: aSession) message: (DebuggerTools messageFor: aSession).
	note := DebuggerNote text: 'other Processes keep running' font: #smallItalic.
	note name: 'note'; color: #ink3; align: #right; flex: 1.
	stack := DebuggerStackList new.
	stack name: 'stack'; title: 'Stack'.
	stack labelBlock: [:ctx | Debugger labelOfFrame: ctx].
	stack items: (aSession stackOfSize: 12).
	stack onDoubleClick: [:ctx | self debug].
	self addAll: {
		header.
		DebuggerRule new.
		(Row with: {
			(self button: 'Proceed' named: 'proceed' action: [self proceed]) beDefault; fixed: 70; yourself.
			self button: 'Abandon' named: 'abandon' action: [self abandon].
			self button: 'Debug' named: 'debug' action: [self debug].
			(self button: 'Create' named: 'create' action: [self openCreateMenu]) visible: aSession kind == #dnu; yourself.
			self button: 'Save report' named: 'save-report' action: [self saveReport].
			note})
				spacing: 5; padding: (12 @ 6 corner: 12 @ 6); background: #paper; fixed: 32; yourself.
		DebuggerRule new.
		stack}
!
button: aString named: slug action: aBlock
	| b |
	b := Button label: aString action: aBlock.
	b name: slug.
	b fixed: ((b font widthOf: aString) + 16) ceiling.
	buttons at: slug put: b.
	^b
! !

!Notifier methodsFor: 'accessing'!
session
	^session
!
buttonNamed: aString
	^buttons at: aString ifAbsent: [nil]
!
stackList
	^stack
!
headerTitle
	^header title
!
isDone
	^done
!
agentContext
	"The selected frame, together with the exception and its suspended session."
	^AgentContext new
		frame: (stack selection ifNil: [session interruptedContext]);
		label: session label;
		bind: #session to: session;
		bind: #exception to: session exception;
		yourself
! !

!Notifier methodsFor: 'actions'!
saveReport
	"Write a CrashReport of the stopped Process; say where."
	| path |
	path := [(CrashReport forSession: session) write] on: Error do: [:e | ^self toast: 'No report: ', e messageText asString].
	self toast: 'Report saved: ', path
!
proceed
	done ifTrue: [^self].
	done := true.
	[session proceed] on: Error do: [:e | self toast: e messageText asString. e return: nil].
	self closeWindow
!
abandon
	done ifTrue: [^self].
	done := true.
	self abandonSession.
	self closeWindow
!
debug
	"Replace me by the full Debugger on the same session."
	^self debugThen: nil
!
debugThen: aBlockOrNil
	| w d |
	done ifTrue: [^nil].
	done := true.
	w := Debugger openOn: session bounds: (self window bounds origin extent: Debugger defaultExtent).
	d := w content.
	aBlockOrNil isNil ifFalse: [w do: [aBlockOrNil value: d]].
	self closeWindow.
	^w
!
openCreateMenu
	| b point |
	session kind == #dnu ifFalse: [^self].
	"The full Debugger takes my place, with the Create menu open where my Create button was."
	b := buttons at: 'create'.
	point := b screenPointFrom: 0 @ (b height + 2).
	self debugThen: [:d | d openCreateMenuAt: point]
!
closeWindow
	| w |
	w := self window.
	w isNil ifFalse: [w close]
!
abandonSession
	| w |
	session isSuspended ifFalse: [^self].
	w := session process window.
	[session abandon] on: Error do: [:e | e return: nil].
	DebuggerTools restartWindow: w
!
windowClosed
	done ifTrue: [^self].
	done := true.
	self abandonSession
! !

!Notifier methodsFor: 'remote control'!
remoteRole
	^#notifier
!
remoteLabel
	^header title
! !

!Notifier class methodsFor: 'opening'!
openOn: aSession
	| notifier window |
	notifier := self new setSession: aSession.
	window := Desktop newWindow.
	window title: notifier headerTitle; content: notifier; bounds: (DebuggerTools boundsFor: 480 @ 226); minExtent: 360 @ 180.
	window whenClosed: [notifier windowClosed].
	window open.
	DebuggerTools ignore: window.
	^window
! !
