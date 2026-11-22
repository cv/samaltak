Object subclass: #ToolsMenu
	instanceVariableNames: ''
	classVariableNames: 'Entries'
	package: 'Tools'!

ToolsMenu comment: 'I build the World menu (a click on the desk). Tools register what they open in its "open…" section, sorted by order; the rest of the menu (long computation, user interrupt, arrange, slow motion (every animation 10× slower), save, rebuild the VM and reboot, on UEFI the firmware''s: install Samaltak onto the machine''s disk and reboot into Ubuntu, Samaltak or the firmware''s setup (FirmwareBoot: BootNext, once), restart, warm restart or power off (Firmware reset:), help, quit) is mine.

	ToolsMenu register: ''Profiler'' description: ''samples · frames'' order: 60 action: [:aPoint | ...]
	ToolsMenu unregister: ''Profiler''

aPoint is the screen point that was clicked (nil when the menu is opened otherwise); place the new window there (Tools placeAt:extent:). Core orders: System Browser 10, Workspace 20, Transcript 30, Process Browser 40, Mandelbrot 50.'!

!ToolsMenu class methodsFor: 'registering'!
entries
	^Entries ifNil: [Entries := OrderedCollection new]
!
register: aString description: descriptionOrNil order: aNumber action: aBlock
	"Add (or replace) the open… item aString."
	self unregister: aString.
	self entries add: (Array with: aString with: descriptionOrNil with: aNumber with: aBlock)
!
register: aString order: aNumber action: aBlock
	self register: aString description: nil order: aNumber action: aBlock
!
unregister: aString
	Entries isNil ifTrue: [^self].
	Entries := Entries reject: [:each | each first = aString]
!
labels
	^self sortedEntries collect: [:each | each first]
!
sortedEntries
	^(self entries asSortedCollection: [:a :b | (a at: 3) <= (b at: 3)]) asArray
! !

!ToolsMenu class methodsFor: 'building'!
worldMenuAt: aPoint
	| menu |
	menu := Menu title: 'World'.
	menu addHeader: 'open…'.
	self sortedEntries do: [:each |
		| action |
		action := each at: 4.
		(each at: 2) isNil
			ifTrue: [menu add: each first action: [self run: [action cull: aPoint]]]
			ifFalse: [menu add: each first description: (each at: 2) action: [self run: [action cull: aPoint]]]].
	menu addSeparator.
	menu add: 'Run long computation' description: 'fork ''crunch''' action: [self run: [Tools runLongComputation]].
	menu add: 'User interrupt' key: '⌘.' action: [self run: [Tools userInterrupt]].
	menu addSeparator.
	menu add: 'Arrange windows' action: [self run: [Tools arrangeWindows]].
	menu add: 'Slow motion' checked: Desktop animationTimeScale > 1 action: [Desktop animationTimeScale: (Desktop animationTimeScale > 1 ifTrue: [1] ifFalse: [10])].
	menu add: 'Save image' description: Tools imageName action: [self run: [Tools saveImage]].
	menu add: 'Rebuild VM & reboot' description: 'translate · cc · exec' action: [self run: [VMRebuilder openAndRebuild]].
	Machine hasFirmware ifTrue: [self addFirmwareItemsTo: menu].
	menu add: 'Help…' key: '?' action: [self run: [Tools showHelp]].
	menu add: 'Quit' action: [self run: [Tools quit]].
	^menu
!
addFirmwareItemsTo: aMenu
	"On UEFI: the installer, the reboots into each system (docs/uefi.md, Installing), and restarting or powering off by the firmware (Firmware reset:)."
	aMenu addSeparator.
	aMenu add: 'Install Samaltak…' description: 'onto this machine''s disk' action: [self run: [Tools openInstaller]].
	aMenu add: 'Reboot into Ubuntu' description: 'BootNext, once' action: [self run: [Tools rebootInto: #ubuntu]].
	aMenu add: 'Reboot into Samaltak' description: 'from the disk' action: [self run: [Tools rebootInto: #samaltak]].
	aMenu add: 'Reboot to firmware setup' action: [self run: [Tools rebootToFirmwareSetup]].
	aMenu add: 'Restart' description: 'firmware reset' action: [self run: [Firmware restart]].
	aMenu add: 'Warm restart' description: 'firmware warm reset' action: [self run: [Firmware warmRestart]].
	aMenu add: 'Power off' description: 'firmware shutdown' action: [self run: [Firmware powerOff]].
	aMenu addSeparator
!
run: aBlock
	"Run a World menu action in a Process of its own: the menu's invoker window may be busy."
	[aBlock value] forkAt: Processor userSchedulingPriority named: 'World menu'
! !
