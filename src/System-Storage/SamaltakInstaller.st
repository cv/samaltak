Object subclass: #SamaltakInstaller
	instanceVariableNames: 'firmware devices disk diskIndex gpt esp espDevice espFs storeChoice storeMB storeFirst storeLast storeNumber bootArgs dryRun confirmBlock lineBlock log bootVolume bootPath appBytes argsBytes source sourceSlot saveFirst boot done'
	classVariableNames: ''
	package: 'System-Storage'!

SamaltakInstaller comment: 'I install Samaltak from the boot stick onto a disk of the machine next to the operating system there (docs/uefi.md, Installing): the disk''s EFI system partition gets \EFI\samaltak\BOOTAA64.EFI (BOOTX64.EFI), the running EFI application, and samaltak.args beside it (the running command line without --eval and --test); an image store partition gets the current image (the newest slot of the store the VM booted from: saveFirst snapshots first); the firmware gets a load option Boot#### "Samaltak" for the file (FirmwareBoot), BootOrder unchanged, so the operating system stays the default. The store is a partition the user names (storePartition:, empty or an image store already) or one I add in the free space after the last partition (storeAtEnd, the default; storeMB: its size, else 4 GB or what is free). I never move, resize or delete a partition.

run checks everything first (SamaltakInstallError: what is wrong, before any write), reports the plan (dryRun, the default, stops there), then runs each step after confirmBlock agrees to its title and details (disk, partition, size): add the partition (GptDisk: both GPT copies), write the store (only inside the partition: BlockDeviceRegion; read back and its CRC compared), the two files (read back), the load option (read back). Each line goes to lineBlock (the console, prefixed install, by default) and log.

	SamaltakInstaller runScript: ''dry-run''                      "the console: the disks, the plan"
	SamaltakInstaller runScript: ''yes store=end mb=8192''        "no questions: for scripts and tests"
	SamaltakInstaller runScript: ''yes store=4 reboot=samaltak''  "an empty partition 4, then boot the installed Samaltak once"
	SamaltakInstaller new storeAtEnd; confirmBlock: [:title :details | ...]; dryRun: false; run'!

!SamaltakInstaller class methodsFor: 'scripting'!
runScript: aString
	"Install by words: dry-run (only the plan) or yes (every step confirmed), store=end or store=N (partition N of the disk), mb=N (a new store's size), disk=N (the survey's disk N), save (snapshot first), reboot=samaltak, ubuntu or firmware (after installing). The lines go to the console; answer the outcome."
	| installer words dry yes reboot result |
	installer := self new.
	words := aString substrings.
	dry := words includes: 'dry-run'.
	yes := words includes: 'yes'.
	(dry or: [yes]) ifFalse: [^'install: say yes or dry-run'].
	words do: [:w |
		(w beginsWith: 'store=') ifTrue: [(w copyFrom: 7 to: w size) = 'end' ifTrue: [installer storeAtEnd] ifFalse: [installer storePartition: (w copyFrom: 7 to: w size) asInteger]].
		(w beginsWith: 'mb=') ifTrue: [installer storeMB: (w copyFrom: 4 to: w size) asInteger].
		(w beginsWith: 'disk=') ifTrue: [installer diskIndex: (w copyFrom: 6 to: w size) asInteger].
		(w beginsWith: 'reboot=') ifTrue: [reboot := (w copyFrom: 8 to: w size) asSymbol].
		w = 'save' ifTrue: [installer saveFirst: true]].
	installer dryRun: dry.
	yes ifTrue: [installer confirmAll].
	installer surveyLines do: [:l | installer line: l].
	result := installer run.
	installer line: result.
	(reboot notNil and: [dry not and: [installer isDone]]) ifTrue: [
		installer line: 'rebooting into ', reboot.
		result := reboot == #firmware ifTrue: [FirmwareBoot rebootToFirmwareSetup] ifFalse: [FirmwareBoot rebootInto: reboot].
		installer line: 'reboot failed: ', result printString].
	^'install ', result
!
survey
	"The disks, partitions and boot options, on the console."
	| installer |
	installer := self new.
	installer surveyLines do: [:l | installer line: l].
	^'survey done'
! !

!SamaltakInstaller class methodsFor: 'sizes'!
storeTypeGuid
	^GptDisk imageStoreType
!
defaultStoreBytes
	^4 * 1024 * 1048576
!
sizeText: bytes
	bytes >= (1024 * 1048576) ifTrue: [^(bytes / (1024 * 1048576.0) printShowingDecimalPlaces: 1), ' GB'].
	bytes >= 1048576 ifTrue: [^(bytes + 524288 // 1048576) printString, ' MB'].
	^(bytes + 512 // 1024) printString, ' KB'
! !

!SamaltakInstaller methodsFor: 'initialization'!
initialize
	firmware := Firmware current.
	devices := firmware isNil ifTrue: [#()] ifFalse: [FirmwareBlockDevice allIncludingStores].
	storeChoice := #end.
	dryRun := true.
	saveFirst := false.
	done := false.
	confirmBlock := [:title :details | false].
	lineBlock := [:s | Smalltalk vm stderrWrite: 'install ', s, (String with: Character lf)].
	log := OrderedCollection new.
	firmware isNil ifFalse: [self findBootImage]
! !

!SamaltakInstaller methodsFor: 'options'!
disk: aFirmwareBlockDevice
	disk := aFirmwareBlockDevice
!
diskIndex: anInteger
	diskIndex := anInteger
!
storeAtEnd
	storeChoice := #end
!
storePartition: anInteger
	storeChoice := anInteger
!
storeMB: anInteger
	storeMB := anInteger
!
bootArgs: aCollectionOfStrings
	bootArgs := aCollectionOfStrings
!
dryRun: aBoolean
	dryRun := aBoolean
!
saveFirst: aBoolean
	saveFirst := aBoolean
!
confirmAll
	confirmBlock := [:title :details | true]
!
confirmBlock: aBlock
	"[:title :details | answer whether to do this step]."
	confirmBlock := aBlock
!
lineBlock: aBlock
	lineBlock := aBlock
! !

!SamaltakInstaller methodsFor: 'accessing'!
log
	^log
!
isDone
	^done
!
disks
	"The whole disks."
	^devices reject: [:d | d isLogicalPartition]
!
targetDisk
	^disk
!
bootVolume
	^bootVolume
!
bootPath
	^bootPath
!
partitionDeviceOf: aDisk number: anInteger
	^devices detect: [:d | d isLogicalPartition and: [d diskPath = aDisk devicePath and: [d partitionNumber = anInteger]]] ifNone: [nil]
!
isBootDisk: aDisk
	^bootVolume notNil and: [bootVolume diskPath = aDisk devicePath]
!
gptOf: aDisk
	"The disk's GPT, or the GptError's text."
	^[GptDisk on: aDisk] on: GptError, FileError do: [:e | e return: e messageText]
!
candidateDisks
	"Disks with a GPT that has an EFI system partition, not the one booted from."
	^self disks select: [:d | (self isBootDisk: d) not and: [d isReadOnly not and: [| g |
		g := self gptOf: d.
		g isString not and: [g efiSystemPartitions notEmpty]]]]
!
defaultDisk
	"The first fixed candidate disk, else the first candidate."
	| candidates |
	candidates := self candidateDisks.
	^(candidates detect: [:d | d isRemovable not] ifNone: [nil]) ifNil: [candidates isEmpty ifTrue: [nil] ifFalse: [candidates first]]
! !

!SamaltakInstaller methodsFor: 'survey'!
surveyLines
	"What there is: each disk and its partitions, what booted, the boot options."
	| lines |
	lines := OrderedCollection new.
	firmware isNil ifTrue: [^#('not on UEFI: nothing to install onto')].
	lines add: 'booted from ', (bootVolume ifNil: ['?'] ifNotNil: [:v | v description]), ' ', (bootPath ifNil: ['?']).
	self disks doWithIndex: [:d :i | | g |
		lines add: 'disk ', i printString, ': ', d description, ', ', (self class sizeText: d byteSize), ' in ', d blockSize printString, '-byte blocks',
			((self isBootDisk: d) ifTrue: [', the boot disk'] ifFalse: ['']), (d isRemovable ifTrue: [', removable'] ifFalse: ['']), (d isReadOnly ifTrue: [', read-only'] ifFalse: ['']).
		g := self gptOf: d.
		g isString
			ifTrue: [lines add: '  no usable GPT: ', g]
			ifFalse: [
				lines add: '  GPT: ', g partitions size printString, ' partitions, ', (g freeAtEnd ifNil: ['no free space at the end'] ifNotNil: [:f | (self class sizeText: f last - f first + 1 * g blockSize), ' free at the end (blocks ', f first printString, '..', f last printString, ')']),
					(g problems isEmpty ifTrue: [''] ifFalse: [', read-only: ', g problems first]).
				g partitions do: [:p | lines add: '  ', (self describe: p on: d gpt: g)]]].
	FirmwareBoot current ifNotNil: [:b | [b describe do: [:l | lines add: 'boot ', l]] on: Error do: [:e | lines add: 'boot options unreadable: ', e messageText. e return: nil]].
	^lines asArray
!
describe: aPartition on: aDisk gpt: aGpt
	| content |
	content := [self contentOf: aPartition on: aDisk] on: FileError do: [:e | e return: #unreadable].
	^'partition ', aPartition number printString, ' ', aPartition name printString, ' ', aPartition typeName, ', ',
		(self class sizeText: aPartition blockCount * aGpt blockSize), ' (blocks ', aPartition firstLba printString, '..', aPartition lastLba printString, '), ',
		(self contentText: content),
		((bootVolume notNil and: [(self partitionDeviceOf: aDisk number: aPartition number) ifNil: [false] ifNotNil: [:pd | pd handle = bootVolume handle]]) ifTrue: [', booted from'] ifFalse: [''])
!
contentOf: aPartition on: aDisk
	"What the start of the partition holds: #imageStore, #ext4, #fat, #ntfs, #swap, #luks, #lvm, #xfs, #btrfs, #empty (zeros) or #unknown."
	| n bytes |
	n := 69632 min: aPartition blockCount * aDisk blockSize.
	bytes := (BlockDeviceRegion on: aDisk first: aPartition firstLba count: aPartition blockCount) readBytes: n at: 0.
	^self contentOfBytes: bytes
!
contentOfBytes: bytes
	| at |
	at := [:index :string | bytes size >= (index + string size - 1) and: [(bytes copyFrom: index to: index + string size - 1) = string asByteArray]].
	(at value: 1 value: 'SAMSTORE') ifTrue: [^#imageStore].
	(bytes size >= 1082 and: [(bytes uint16At: 1081) = 16rEF53]) ifTrue: [^#ext4].
	(at value: 4 value: 'NTFS') ifTrue: [^#ntfs].
	((at value: 55 value: 'FAT') or: [at value: 83 value: 'FAT']) ifTrue: [^#fat].
	(at value: 1 value: 'LUKS') ifTrue: [^#luks].
	(at value: 513 value: 'LABELONE') ifTrue: [^#lvm].
	(at value: 4087 value: 'SWAPSPACE2') ifTrue: [^#swap].
	(at value: 1 value: 'XFSB') ifTrue: [^#xfs].
	(at value: 65601 value: '_BHRfS_M') ifTrue: [^#btrfs].
	(bytes allSatisfy: [:b | b = 0]) ifTrue: [^#empty].
	^#unknown
!
contentText: aSymbol
	^Dictionary new
		at: #imageStore put: 'an image store'; at: #ext4 put: 'ext2/3/4'; at: #ntfs put: 'NTFS'; at: #fat put: 'FAT';
		at: #luks put: 'LUKS (encrypted)'; at: #lvm put: 'LVM'; at: #swap put: 'swap'; at: #xfs put: 'XFS'; at: #btrfs put: 'btrfs';
		at: #empty put: 'empty (zeros)'; at: #unknown put: 'data of an unknown kind'; at: #unreadable put: 'unreadable';
		at: aSymbol ifAbsent: [aSymbol asString]
! !

!SamaltakInstaller methodsFor: 'running'!
run
	"Check, report the plan, and unless dryRun do each step the confirm block agrees to; answer the outcome."
	| steps |
	done := false.
	(saveFirst and: [dryRun not]) ifTrue: [
		self line: 'saving the image first'.
		(Smalltalk snapshot: Smalltalk vm imagePath) == true ifTrue: [^'resumed (this image was saved by the installer)']].
	steps := [self prepare. self steps] on: SamaltakInstallError do: [:e | e return: e messageText].
	steps isString ifTrue: [
		self line: 'refused: ', steps.
		^'refused: ', steps].
	self line: (dryRun ifTrue: ['plan (dry run: nothing is written):'] ifFalse: ['plan:']).
	steps doWithIndex: [:s :i | self line: i printString, '. ', s first; line: '   ', (s at: 2)].
	dryRun ifTrue: [^'dry run: ', steps size printString, ' steps, nothing written'].
	steps do: [:s | | failed |
		(confirmBlock value: s first value: (s at: 2)) == true ifFalse: [
			self line: 'cancelled: ', s first.
			^'cancelled before: ', s first].
		self line: 'doing: ', s first.
		failed := [(s at: 3) value. nil] on: Error do: [:e | e return: (e messageText ifNil: [e class name]) asString].
		failed notNil ifTrue: [
			self line: 'failed: ', s first, ': ', failed.
			^'failed: ', s first, ': ', failed].
		self line: 'done: ', s first].
	done := true.
	^'done: Samaltak is installed as boot option ', (FirmwareBoot optionName: boot), ' on ', disk description
!
line: aString
	log add: aString.
	lineBlock value: aString
! !

!SamaltakInstaller methodsFor: 'checking'!
refuse: aString
	^SamaltakInstallError signal: aString
!
prepare
	"Find and check everything the steps need; SamaltakInstallError if something is wrong."
	firmware isNil ifTrue: [self refuse: 'not on UEFI'].
	disk isNil ifTrue: [
		disk := diskIndex isNil
			ifTrue: [self defaultDisk ifNil: [self refuse: 'no disk with a GPT and an EFI system partition (other than the one booted from)']]
			ifFalse: [self disks at: diskIndex ifAbsent: [self refuse: 'no disk ', diskIndex printString]]].
	disk isReadOnly ifTrue: [self refuse: disk description, ' is read-only'].
	(4096 \\ disk blockSize = 0) ifFalse: [self refuse: 'blocks of ', disk blockSize printString, ' bytes: not supported'].
	gpt := self gptOf: disk.
	gpt isString ifTrue: [self refuse: 'no usable GPT on ', disk description, ': ', gpt].
	self prepareEsp.
	self prepareApplication.
	self prepareSource.
	self prepareStore.
	boot := FirmwareBoot current.
	boot isNil ifTrue: [self refuse: 'no firmware variables'].
	[boot bootOrder] on: Error do: [:e | self refuse: 'cannot read BootOrder: ', e messageText]
!
prepareEsp
	| need |
	esp := gpt efiSystemPartitions ifEmpty: [self refuse: 'no EFI system partition on ', disk description].
	esp := esp detect: [:p | (self partitionDeviceOf: disk number: p number) notNil] ifNone: [self refuse: 'the firmware has no device for the EFI system partition'].
	espDevice := self partitionDeviceOf: disk number: esp number.
	espFs := self volumeOn: espDevice handle.
	espFs isNil ifTrue: [self refuse: 'the firmware cannot read the EFI system partition''s file system'].
	espFs isReadOnly ifTrue: [self refuse: 'the EFI system partition is read-only'].
	need := 1048576 * 2.
	espFs freeSpace + ((self sizeOf: FirmwareBoot samaltakPath on: espFs) ifNil: [0]) < need ifTrue: [
		self refuse: 'not enough room on the EFI system partition (', (self class sizeText: espFs freeSpace), ' free)']
!
prepareApplication
	| bootFs args |
	(bootVolume isNil or: [bootPath isNil]) ifTrue: [self refuse: 'cannot tell which EFI application is running'].
	bootFs := self volumeOn: bootVolume handle.
	bootFs isNil ifTrue: [self refuse: 'cannot read the volume booted from'].
	appBytes := self read: bootPath on: bootFs.
	(appBytes notNil and: [appBytes size > 4096 and: [(appBytes copyFrom: 1 to: 2) = 'MZ' asByteArray]])
		ifFalse: [self refuse: 'cannot read the EFI application ', bootPath].
	args := bootArgs ifNil: [
		self filterArgs: ((self read: (self directoryOf: bootPath), '\samaltak.args' on: bootFs) ifNil: [self read: '\samaltak.args' on: bootFs])].
	argsBytes := (String streamContents: [:s | args do: [:a | s nextPutAll: a; nextPut: Character lf]]) asByteArray
!
filterArgs: bytesOrNil
	"The lines of samaltak.args without --eval and its expression and --test and what follows; disk: if there was none."
	| lines out i |
	lines := bytesOrNil isNil ifTrue: [#()] ifFalse: [(bytesOrNil asString lines collect: [:l | l trimBoth]) reject: [:l | l isEmpty]].
	out := OrderedCollection new.
	i := 1.
	[i <= lines size] whileTrue: [| a |
		a := lines at: i.
		a = '--eval'
			ifTrue: [i := i + 2]
			ifFalse: [a = '--test' ifTrue: [i := lines size + 1] ifFalse: [out add: a. i := i + 1]]].
	(out includes: 'disk:') ifFalse: [out add: 'disk:'].
	^out asArray
!
prepareSource
	"The store the VM booted from and its newest slot."
	| stores |
	stores := devices select: [:d | d isImageStore].
	stores isEmpty ifTrue: [self refuse: 'no image store to copy the image from'].
	source := stores detect: [:d | bootVolume notNil and: [d diskPath = bootVolume diskPath or: [d devicePath = bootVolume diskPath]]] ifNone: [stores first].
	sourceSlot := self newestSlotOf: source.
	sourceSlot isNil ifTrue: [self refuse: 'the image store has no image']
!
newestSlotOf: aDevice
	"{start. length. sequence} of the newest valid slot of the store on aDevice, or nil."
	| slotBytes best |
	slotBytes := (aDevice byteSize - 1048576) // 2 bitClear: 4095.
	best := nil.
	0 to: 1 do: [:slot | | h seq len |
		h := aDevice readBytes: 32 at: 4096 * (slot + 1).
		seq := h uint64At: 9.
		len := h uint64At: 17.
		((h copyFrom: 1 to: 8) = 'SAMSLOT1' asByteArray and: [(h uint64At: 25) = (UefiImageStore slotCheckOf: seq length: len) and: [len <= slotBytes]])
			ifTrue: [(best isNil or: [seq > (best at: 3)]) ifTrue: [best := {1048576 + (slot * slotBytes). len. seq}]]].
	^best
!
minimumStoreBytes
	"1 MB and two slots of the image."
	^1048576 + (2 * ((sourceSlot at: 2) + 1048575 // 1048576 * 1048576))
!
prepareStore
	| bs |
	bs := disk blockSize.
	storeChoice == #end
		ifTrue: [| free wanted blocks align |
			gpt isEditable ifFalse: [self refuse: 'will not change the GPT of ', disk description, ': ', gpt problems first].
			free := gpt freeAtEnd.
			(free isNil or: [(free last - free first + 1) * bs < self minimumStoreBytes]) ifTrue: [
				self refuse: 'not enough free space at the end of ', disk description, ' (', (free ifNil: ['none'] ifNotNil: [:f | self class sizeText: f last - f first + 1 * bs]),
					'; the store needs ', (self class sizeText: self minimumStoreBytes), '): shrink a partition from Linux first, or name an empty one (store=N)'].
			wanted := storeMB isNil
				ifTrue: [self class defaultStoreBytes max: 3 * self minimumStoreBytes]
				ifFalse: [storeMB * 1048576].
			wanted < self minimumStoreBytes ifTrue: [self refuse: 'a store of ', (self class sizeText: wanted), ' is too small: it needs ', (self class sizeText: self minimumStoreBytes)].
			align := gpt alignment.
			blocks := (wanted // bs) // align * align min: free last - free first + 1.
			storeFirst := free first.
			storeLast := free first + blocks - 1.
			storeNumber := nil]
		ifFalse: [| p content |
			p := (gpt partitionNumbered: storeChoice) ifNil: [self refuse: 'no partition ', storeChoice printString, ' on ', disk description].
			p isEfiSystem ifTrue: [self refuse: 'partition ', p number printString, ' is the EFI system partition'].
			(source diskPath = disk devicePath and: [source partitionNumber = p number]) ifTrue: [self refuse: 'partition ', p number printString, ' is the store this image runs from'].
			(bootVolume notNil and: [bootVolume diskPath = disk devicePath and: [bootVolume partitionNumber = p number]]) ifTrue: [self refuse: 'partition ', p number printString, ' is the volume booted from'].
			content := self contentOf: p on: disk.
			(#(#empty #imageStore) includes: content) ifFalse: [
				self refuse: 'partition ', p number printString, ' ', p name printString, ' holds ', (self contentText: content), ': will not overwrite it (wipe it from Linux first if it is really free: wipefs -a)'].
			p blockCount * bs < self minimumStoreBytes ifTrue: [self refuse: 'partition ', p number printString, ' is too small (', (self class sizeText: p blockCount * bs), '; the store needs ', (self class sizeText: self minimumStoreBytes), ')'].
			storeFirst := p firstLba.
			storeLast := p lastLba.
			storeNumber := p number]
! !

!SamaltakInstaller methodsFor: 'steps'!
steps
	"{title. details. action} for each step, in order."
	| steps bs storeText order |
	steps := OrderedCollection new.
	bs := disk blockSize.
	storeText := (self class sizeText: storeLast - storeFirst + 1 * bs), ', blocks ', storeFirst printString, '..', storeLast printString.
	storeNumber isNil ifTrue: [
		steps add: {'Add a partition for the image store'.
			disk description, ' (', (self class sizeText: disk byteSize), '): a new partition "samaltak-image" (Samaltak image store), ', storeText,
				', in the free space after the last partition. No partition moves or changes size; both copies of the GPT are rewritten.'.
			[self addStorePartition]}].
	steps add: {'Write the image store'.
		disk description, ', ', (storeNumber isNil ifTrue: ['the new partition'] ifFalse: ['partition ', storeNumber printString, ' ', (gpt partitionNumbered: storeNumber) name printString]),
			' (', storeText, '): erased and written with the image (', (self class sizeText: (sourceSlot at: 2)), ', saved as number ', (sourceSlot at: 3) printString, ' on ', source description, ').'.
		[self writeStore]}.
	steps add: {'Copy Samaltak onto the EFI system partition'.
		disk description, ', partition ', esp number printString, ' ', esp name printString, ' (', (self class sizeText: esp blockCount * bs), ', ', (self class sizeText: espFs freeSpace), ' free): ',
			((self sizeOf: FirmwareBoot samaltakPath on: espFs) notNil ifTrue: ['replace '] ifFalse: ['write ']), FirmwareBoot samaltakPath, ' (', (self class sizeText: appBytes size), ') and ', FirmwareBoot samaltakDirectory, '\samaltak.args (',
			(argsBytes asString lines inject: '' into: [:a :l | a isEmpty ifTrue: [l] ifFalse: [a, ' ', l]]), '). Nothing else there changes.'.
		[self writeFiles]}.
	order := boot bootOrder.
	steps add: {'Add the boot option Samaltak'.
		(boot samaltakNumber ifNil: ['a new boot option'] ifNotNil: [:n | 'boot option ', (FirmwareBoot optionName: n), ' (replaced)']), ' "Samaltak": HD(', esp number printString, ',GPT,', esp uniqueString, ')/', FirmwareBoot samaltakPath,
			'. BootOrder stays ', (boot hex: order), (order isEmpty ifTrue: [''] ifFalse: [' (first: ', ((boot optionAt: order first) ifNil: ['?'] ifNotNil: [:o | o description printString]), ')']), '.'.
		[self addBootOption]}.
	^steps asArray
!
addStorePartition
	| before p after |
	before := gpt partitions collect: [:each | each entryBytes: gpt entrySize].
	p := gpt addPartition: 'samaltak-image' type: self class storeTypeGuid first: storeFirst last: storeLast.
	gpt write.
	after := GptDisk on: disk.
	after partitions size = (before size + 1) ifFalse: [^self error: 'the table read back has ', after partitions size printString, ' partitions'].
	(before allSatisfy: [:bytes | after partitions anySatisfy: [:q | (q entryBytes: after entrySize) = bytes]]) ifFalse: [^self error: 'a partition changed'].
	storeNumber := p number.
	gpt := after.
	self line: 'partition ', p number printString, ' added: ', p uniqueString
!
writeStore
	"The image into slot 0 of a fresh store in the partition: the first megabyte zeroed, the image, then the superblock and slot 0's header; read back."
	| region bs start length offset crc header check |
	region := BlockDeviceRegion on: disk first: storeFirst count: storeLast - storeFirst + 1.
	bs := region blockSize.
	start := sourceSlot at: 1.
	length := sourceSlot at: 2.
	length <= ((region size - 1048576) // 2 bitClear: 4095) ifFalse: [^self error: 'the image does not fit the store'].
	region write: 1048576 // bs blocksAt: 0 from: (ByteArray new: 1048576) startingAt: 1.
	region flush.
	offset := 0.
	crc := 16rFFFFFFFF.
	[offset < length] whileTrue: [| n bytes |
		n := length - offset min: 1048576.
		bytes := source readBytes: n at: start + offset.
		crc := Crc32 update: crc bytes: bytes from: 1 to: n.
		n \\ bs = 0 ifFalse: [bytes := bytes, (ByteArray new: bs - (n \\ bs))].
		region write: bytes size // bs blocksAt: 1048576 + offset // bs from: bytes startingAt: 1.
		offset := offset + n].
	region flush.
	header := ByteArray new: 8192.
	header replaceFrom: 1 to: 8 with: 'SAMSTORE' asByteArray startingAt: 1.
	header replaceFrom: 4097 to: 4104 with: 'SAMSLOT1' asByteArray startingAt: 1.
	header uint64At: 4105 put: 1.
	header uint64At: 4113 put: length.
	header uint64At: 4121 put: (UefiImageStore slotCheckOf: 1 length: length).
	region write: 8192 // bs blocksAt: 0 from: header startingAt: 1.
	region flush.
	(region readBytes: 8192 at: 0) = header ifFalse: [^self error: 'the store''s header did not read back'].
	check := 16rFFFFFFFF.
	offset := 0.
	[offset < length] whileTrue: [| n |
		n := length - offset min: 1048576.
		check := Crc32 update: check bytes: (region readBytes: n at: 1048576 + offset) from: 1 to: n.
		offset := offset + n].
	check = crc ifFalse: [^self error: 'the image did not read back the same'].
	self line: 'image store written: ', (self class sizeText: length), ', CRC-32 16r', ((crc bitXor: 16rFFFFFFFF) printString: 16)
!
writeFiles
	| dir |
	dir := FirmwareBoot samaltakDirectory.
	self makeDirectory: dir on: espFs.
	self write: FirmwareBoot samaltakPath bytes: appBytes on: espFs.
	self write: dir, '\samaltak.args' bytes: argsBytes on: espFs.
	(self read: FirmwareBoot samaltakPath on: espFs) = appBytes ifFalse: [^self error: FirmwareBoot samaltakPath, ' did not read back the same'].
	(self read: dir, '\samaltak.args' on: espFs) = argsBytes ifFalse: [^self error: 'samaltak.args did not read back the same']
!
addBootOption
	| option order n |
	option := EfiLoadOption description: 'Samaltak' partition: esp file: FirmwareBoot samaltakPath.
	order := boot bootOrder.
	n := boot install: option.
	(boot optionAt: n) bytes = option bytes ifFalse: [^self error: (FirmwareBoot optionName: n), ' did not read back the same'].
	boot bootOrder = order ifFalse: [^self error: 'BootOrder changed'].
	boot := n.
	self line: (FirmwareBoot optionName: n), ' "Samaltak" written; BootOrder unchanged'
! !

!SamaltakInstaller methodsFor: 'files'!
volumeOn: aHandle
	"The FAT volume (FirmwareFileSystem) of the partition aHandle, connecting the firmware's drivers to it first if it has none; nil if it has none then."
	(FirmwareFileSystem firmware: firmware handle: aHandle) ifNotNil: [:v | ^v].
	"ConnectController(handle, NULL, NULL, recursive)"
	firmware boot: 264 with: aHandle with: 0 with: 0 with: 1.
	^FirmwareFileSystem firmware: firmware handle: aHandle
!
fsPath: aPath
	"A volume path (/EFI/samaltak/...) for a firmware one (\EFI\samaltak\...)."
	| p |
	p := aPath copyReplaceAll: '\' with: '/'.
	^(p beginsWith: '/') ifTrue: [p] ifFalse: ['/', p]
!
read: aPath on: aVolume
	"The file's bytes, or nil if there is none."
	| f bytes n |
	f := [aVolume open: (self fsPath: aPath) mode: 0] on: FileError do: [:e | e return: nil].
	f isNil ifTrue: [^nil].
	[bytes := ByteArray new: f size.
	n := f readInto: bytes startingAt: 1 count: bytes size] ensure: [f close].
	n = bytes size ifFalse: [^self error: 'Short read of ', aPath].
	^bytes
!
write: aPath bytes: aByteArray on: aVolume
	"Replace the file with aByteArray, flushed."
	| f |
	f := aVolume open: (self fsPath: aPath) mode: 3.
	[(f writeFrom: aByteArray startingAt: 1 count: aByteArray size) = aByteArray size ifFalse: [^self error: 'Short write of ', aPath].
	f flush] ensure: [f close]
!
makeDirectory: aPath on: aVolume
	"Each directory of aPath that is not there."
	| path |
	path := ''.
	((self fsPath: aPath) substrings: '/') do: [:part |
		path := path, '/', part.
		[aVolume createDirectory: path] on: FileExists do: [:e | e return: nil]]
!
sizeOf: aPath on: aVolume
	"The file's size, or nil if there is none."
	^[(aVolume stat: (self fsPath: aPath)) size] on: FileError do: [:e | e return: nil]
! !

!SamaltakInstaller methodsFor: 'private'!
findBootImage
	"The volume and path of the running EFI application: the newest loaded image of code type EfiLoaderCode that was loaded from a file."
	| guid |
	guid := '5b1b31a1-9562-11d2-8e3f-00a0c969723b'.
	(firmware handlesSupporting: guid) do: [:h |
		(firmware protocol: guid on: h) ifNotNil: [:li | | path |
			((Machine uint32At: li + 80) = 1 and: [(Machine uint64At: li + 24) ~= 0 and: [(Machine uint64At: li + 32) ~= 0]]) ifTrue: [
				path := self filePathAt: (Machine uint64At: li + 32).
				(path notNil and: [path asLowercase endsWith: '.efi']) ifTrue: [
					(devices detect: [:d | d handle = (Machine uint64At: li + 24)] ifNone: [nil]) ifNotNil: [:v |
						bootVolume := v.
						bootPath := path]]]]]
!
filePathAt: anAddress
	"The text of the file path nodes of the device path at anAddress, or nil."
	| p path |
	p := anAddress.
	path := nil.
	[(Machine uint8At: p) ~= 16r7F and: [p - anAddress < 4096]] whileTrue: [| len |
		len := Machine uint16At: p + 2.
		len < 4 ifTrue: [^path].
		((Machine uint8At: p) = 4 and: [(Machine uint8At: p + 1) = 4]) ifTrue: [| s |
			s := FirmwareBlockDevice utf16At: p + 4 maxCharacters: len - 4 // 2.
			path := path isNil ifTrue: [s] ifFalse: [(path endsWith: '\') ifTrue: [path, s] ifFalse: [path, '\', s]]].
		p := p + len].
	^path
!
directoryOf: aPath
	| i |
	i := aPath findLast: [:c | c = $\].
	^i <= 1 ifTrue: [''] ifFalse: [aPath copyFrom: 1 to: i - 1]
! !
