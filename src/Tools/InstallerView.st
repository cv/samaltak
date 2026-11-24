ToolPane subclass: #InstallerView
	instanceVariableNames: 'disk choices list output running'
	classVariableNames: ''
	package: 'Tools'!

InstallerView comment: 'I am the World''s "Install Samaltak…" (SamaltakInstaller, docs/uefi.md, Installing): the machine''s disks, partitions and boot options; where the image store goes (a new partition in the free space at the end of the disk, or an empty partition there is); Dry run, which shows the plan and writes nothing; Install…, which saves the image, then asks before each step (ConfirmDialog: the disk, the partition, the size) and shows what it did.'!

!InstallerView class methodsFor: 'opening'!
open
	| view |
	view := self new setUp.
	view openIn: (Tools placeAt: nil extent: 760 @ 520) title: 'Install Samaltak'.
	^view
! !

!InstallerView methodsFor: 'initialization'!
setUp
	| installer buttons |
	running := false.
	installer := SamaltakInstaller new.
	disk := installer defaultDisk.
	choices := self choicesFor: installer.
	list := ListView new name: 'store'; title: 'Image store'; yourself.
	list items: choices; labelBlock: [:c | c first].
	choices isEmpty ifFalse: [list select: choices first].
	output := ToolTextEditor new name: 'output'; title: 'output'; yourself.
	output text: (String streamContents: [:s | installer surveyLines do: [:l | s nextPutAll: l; nextPut: Character lf]]).
	output readOnly: true; highlighting: false.
	buttons := Row with: (Array
		with: (Widget new flex: 1)
		with: ((Button label: 'Dry run' action: [self runDry: true]) beDefault; sizeToContent; yourself)
		with: ((Button label: 'Install…' action: [self runDry: false]) sizeToContent; yourself)).
	buttons spacing: 6; padding: (12 @ 5 corner: 12 @ 6); fixed: 33.
	self separators: true.
	self addAll: (Array
		with: ((self pane: list title: 'Where the image store goes') fixed: 110; yourself)
		with: (self pane: output title: 'Disks, plan and log')
		with: buttons)
!
choicesFor: anInstaller
	"{label. #end or a partition number} for each place the store can go on the disk."
	| gpt result |
	disk isNil ifTrue: [^#()].
	gpt := anInstaller gptOf: disk.
	gpt isString ifTrue: [^#()].
	result := OrderedCollection new.
	gpt freeAtEnd ifNotNil: [:f |
		result add: {'a new partition at the end of the disk (', (SamaltakInstaller sizeText: f last - f first + 1 * gpt blockSize), ' free)'. #end}].
	gpt partitions do: [:p | | content |
		content := [anInstaller contentOf: p on: disk] on: Error do: [:e | e return: #unreadable].
		((#(#empty #imageStore) includes: content) and: [p isEfiSystem not]) ifTrue: [
			result add: {'partition ', p number printString, ' ', p name printString, ' (', (SamaltakInstaller sizeText: p blockCount * gpt blockSize), ', ', (anInstaller contentText: content), ')'. p number}]].
	^result asArray
! !

!InstallerView methodsFor: 'running'!
runDry: aBoolean
	running ifTrue: [^self].
	running := true.
	[[self install: aBoolean] ensure: [running := false]] forkAt: Processor userSchedulingPriority named: 'installer'
!
install: dry
	| installer choice result |
	installer := SamaltakInstaller new.
	disk isNil ifFalse: [installer disk: (installer disks detect: [:d | d devicePath = disk devicePath] ifNone: [nil])].
	choice := list selection ifNil: [{nil. #end}].
	choice last == #end ifTrue: [installer storeAtEnd] ifFalse: [installer storePartition: choice last].
	installer dryRun: dry; saveFirst: dry not.
	installer lineBlock: [:l | self show: l].
	installer confirmBlock: [:title :details | ConfirmDialog confirm: title details: details action: 'Do it'].
	dry ifFalse: [
		(ConfirmDialog confirm: 'Install Samaltak on this machine?'
			details: 'The image is saved first, then each step asks before it writes: the partition table, the image store, the EFI system partition, the firmware''s boot options. Ubuntu stays the default boot; "Reboot into Samaltak" in the World menu › System boots this once.'
			action: 'Continue') ifFalse: [^self show: 'cancelled']].
	result := installer run.
	self show: result
!
show: aString
	| w |
	w := self window.
	w isNil ifFalse: [w do: [
		output readOnly: false; appendText: aString, (String with: Character lf); readOnly: true.
		output scrollOffset: (output scrollTotal - output scrollVisible max: 0)]]
! !
