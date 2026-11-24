Object subclass: #ToolsMenu
	instanceVariableNames: ''
	classVariableNames: 'Entries'
	package: 'Tools'!

ToolsMenu comment: 'I build the World menu (a click on the desk). Tools register what they open, sorted by order, in a group: #open (the top section, the default) or the #tools, #apps or #settings submenu (groups). The rest of the menu is mine: in Tools, long computation and user interrupt; in Settings, slow motion (every animation 10× slower); arrange, save; in System, rebuild the VM and reboot and, on UEFI, the firmware''s: install Samaltak onto the machine''s disk, reboot into Ubuntu, Samaltak or the firmware''s setup (FirmwareBoot: BootNext, once), restart, warm restart or power off (Firmware reset:); help, quit.

	ToolsMenu register: ''Profiler'' description: ''samples · frames'' group: #tools order: 60 action: [:aPoint | ...]
	ToolsMenu unregister: ''Profiler''

aPoint is the screen point that was clicked (nil when the menu is opened otherwise); place the new window there (Tools placeAt:extent:). Core orders: System Browser 10, Workspace 20, Transcript 30, Process Browser 40 (#tools), Mandelbrot 50 (#apps).'!

!ToolsMenu class methodsFor: 'registering'!
entries
	^Entries ifNil: [Entries := OrderedCollection new]
!
register: aString description: descriptionOrNil order: aNumber action: aBlock
	"Add (or replace) the item aString."
	self register: aString description: descriptionOrNil group: #open order: aNumber action: aBlock
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
!
register: aString description: descriptionOrNil group: aSymbol order: aNumber action: aBlock
	"Add (or replace) the item aString in the section aSymbol: #open (the items at the top) or a submenu of the groups."
	self unregister: aString.
	self entries add: (Array with: aString with: descriptionOrNil with: aNumber with: aBlock with: aSymbol)
! !

!ToolsMenu class methodsFor: 'building'!
worldMenuAt: aPoint
	| menu tools apps settings |
	menu := Menu title: 'World'.
	self add: #open to: menu at: aPoint.
	menu addSeparator.
	tools := self add: #tools to: Menu new at: aPoint.
	tools isEmpty ifFalse: [tools addSeparator].
	tools add: 'Run long computation' description: 'fork ''crunch''' action: [self run: [Tools runLongComputation]].
	tools add: 'User interrupt' key: '⌘.' action: [self run: [Tools userInterrupt]].
	menu add: 'Tools' submenu: tools.
	apps := self add: #apps to: Menu new at: aPoint.
	apps isEmpty ifFalse: [menu add: 'Apps' submenu: apps].
	settings := self add: #settings to: Menu new at: aPoint.
	settings add: 'Slow motion' checked: Desktop animationTimeScale > 1 action: [Desktop animationTimeScale: (Desktop animationTimeScale > 1 ifTrue: [1] ifFalse: [10])].
	menu add: 'Settings' submenu: settings.
	menu addSeparator.
	menu add: 'Arrange windows' action: [self run: [Tools arrangeWindows]].
	menu add: 'Save image' description: Tools imageName action: [self run: [Tools saveImage]].
	menu add: 'System' submenu: self systemMenu.
	menu addSeparator.
	menu add: 'Help…' key: '?' action: [self run: [Tools showHelp]].
	menu add: 'Quit' action: [self run: [Tools quit]].
	^menu
!
addFirmwareItemsTo: aMenu
	"On UEFI: the installer, the reboots into each system (docs/uefi.md, Installing), and restarting or powering off by the firmware (Firmware reset:)."
	aMenu addSeparator.
	aMenu add: 'Install Samaltak…' description: 'onto this machine''s disk' action: [self run: [Tools openInstaller]].
	aMenu add: 'NVIDIA GPU probe' description: 'read only' action: [self run: [Tools openWorkspaceWith: (String new join: ((FirmwareDiagnostics nvidiaLines) collect: [:each | each, (String with: Character lf)]))]].
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
