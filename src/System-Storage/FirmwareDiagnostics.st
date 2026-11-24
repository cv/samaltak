Object subclass: #FirmwareDiagnostics
	instanceVariableNames: 'firmware file fileNote echo'
	classVariableNames: ''
	package: 'System-Storage'!

FirmwareDiagnostics comment: 'I report what a machine''s UEFI firmware offers the image, for a first boot on new hardware (docs/uefi.md, Real hardware): the firmware''s vendor and revision, its configuration tables, SMBIOS (BIOS, system, board, processors, memory), ACPI (tables, PSCI in the FADT, CPUs in the MADT, the serial console in the SPCR), MP services, the memory map, memory protection (EFI_MEMORY_ATTRIBUTE_PROTOCOL, the CPU architectural protocol, the memory attributes table), the timer''s period and what a 1 ms Delay takes, EFI_RNG_PROTOCOL, the graphics outputs and their modes (size, pixel format, framebuffer or Blt only, the monitor''s EDID), PCI functions, block devices and partitions (the image store among them), the ext4 volumes FirmwareVolumes mounts, the simple network protocol''s NICs (link, UNDI), and a DHCP attempt with the image''s network stack.

Each line, prefixed diag, goes to the console (stderr: the serial port if there is one, else the firmware''s console; with a serial port also the firmware''s console, so a screen shows it) and to samaltak-diag.txt on the volume with samaltak.args (the boot stick''s EFI system partition), flushed after each section, so a hang leaves what came before it. A section that fails says why and the next one runs. Reading is all I do but for the network section, which starts the network stack (NetworkStack active) as the World would. make usb-image USB_DIAG=1 boots into runThenWorld.

	FirmwareDiagnostics run			"the report"
	FirmwareDiagnostics runThenWorld	"then, after a key or 30 s, the World"
	FirmwareDiagnostics runThenWaitForKey	"then power off after a key"'!

!FirmwareDiagnostics class methodsFor: 'running'!
run
	^self new run
!
runThenQuit
	"For --eval: the report, then the VM quits (evaluateAndQuit)."
	self run.
	^'diagnostics done'
!
runThenWorld
	"The report, then the World (the main action) after a key or 30 s, so the screen can be read first."
	self new run; waitForKeyOrSeconds: 30 saying: 'press a key to start the World (or wait 30 s)'.
	Smalltalk runMainAction
!
runThenWaitForKey
	"The report, then power off after a key."
	self new run; waitForKeyOrSeconds: nil saying: 'press a key to power off'.
	Smalltalk quit: 0
!
fileName
	^'samaltak-diag.txt'
! !

!FirmwareDiagnostics class methodsFor: 'guids'!
guids
	"Protocols and configuration tables by name."
	^Dictionary new
		at: #serialIo put: 'bb25cf6f-f1d4-11d2-9a0c-0090273fc1fd';
		at: #simpleFileSystem put: '964e5b22-6459-11d2-8e39-00a0c969723b';
		at: #devicePath put: '09576e91-6d3f-11d2-8e39-00a0c969723b';
		at: #devicePathToText put: '8b843e20-8132-4852-90cc-551a4e4a7f1c';
		at: #mpServices put: '3fdda605-a76e-4f46-ad29-12f4531b3d08';
		at: #memoryAttribute put: 'f4560cf6-40ec-4b4a-a192-bf1d57d0b189';
		at: #cpuArch put: '26baccb1-6f42-11d4-bce7-0080c73c8881';
		at: #timerArch put: '26baccb3-6f42-11d4-bce7-0080c73c8881';
		at: #rng put: '3152bca5-eade-433d-862e-c01cdc291f44';
		at: #gop put: '9042a9de-23dc-4a38-96fb-7aded080516a';
		at: #edidDiscovered put: '1c0c34f6-d380-41fa-a049-8ad06c1a66aa';
		at: #edidActive put: 'bd8c1056-9f36-44ec-92a8-a6337f817986';
		at: #snp put: 'a19832b9-ac25-11d3-9a2d-0090273fc14d';
		at: #nii put: '1aced566-76ed-4218-bc81-767f1f977a89';
		at: #pciIo put: '4cf5b200-68b8-4ca5-9eec-b23e3f50029a';
		at: #blockIo put: '964e5b21-6459-11d2-8e39-00a0c969723b';
		yourself
!
configurationTableNames
	^Dictionary new
		at: '8868e871-e4f1-11d3-bc22-0080c73c8881' put: 'acpi2';
		at: 'eb9d2d30-2d88-11d3-9a16-0090273fc14d' put: 'acpi1';
		at: 'eb9d2d31-2d88-11d3-9a16-0090273fc14d' put: 'smbios';
		at: 'f2fd1544-9794-4a2c-992e-e5bbcf20e394' put: 'smbios3';
		at: 'b1b621d5-f19c-41a5-830b-d9152c69aae0' put: 'devicetree';
		at: 'dcfa911d-26eb-469f-a220-38b7dc461220' put: 'memory-attributes';
		at: '05ad34ba-6f02-4214-952e-4da0398e2bb9' put: 'dxe-services';
		at: 'b122a263-3661-4f68-9929-78f8b0d62180' put: 'esrt';
		at: 'eb66918a-7eef-402a-842e-931d21c38ae9' put: 'rt-properties';
		at: '49152e77-1ada-4764-b7a2-7afefed95e8b' put: 'debug-image-info';
		at: '7739f24c-93d7-11d4-9a3a-0090273fc14d' put: 'hob-list';
		at: '4c19049f-4137-4dd3-9c10-8b97a83ffdfa' put: 'memory-type-info';
		at: 'ee4e5898-3914-4259-9d6e-dc7bd79403cf' put: 'lzma';
		yourself
! !

!FirmwareDiagnostics methodsFor: 'running'!
run
	"Every section, in order of risk (the network last)."
	self runSections: #(#firmwareInfo #smbios #acpi #cpus #memoryMap #memoryProtection #timer #rng #graphics #pci #blockDevices #volumes #snp #network)
!
runSections: selectors
	firmware := Firmware current.
	echo := false.
	firmware isNil ifTrue: [
		self line: 'no firmware: not on UEFI'.
		^self].
	echo := (self locate: #serialIo) notNil and: [firmware conOut ~= 0].
	self openFile.
	self line: 'samaltak firmware diagnostics, ', fileNote.
	selectors do: [:each | self section: each].
	self line: 'done'.
	self closeFile
!
section: aSelector
	[self perform: aSelector] on: Error do: [:e |
		self line: aSelector asString, ' failed: ', (e messageText ifNil: [e class name]) asString.
		e return: nil].
	self flushFile
!
waitForKeyOrSeconds: seconds saying: aString
	"Wait for a key on the firmware's console input, at most seconds (nil: forever)."
	| conIn key start |
	firmware isNil ifTrue: [^self].
	self line: aString.
	conIn := Machine uint64At: firmware systemTable + 48.
	conIn = 0 ifTrue: [^self].
	key := Machine allocate: 8.
	start := Time millisecondClockValue.
	[[(firmware isError: (Machine call: (firmware function: conIn at: 8) with: conIn with: key))
		and: [seconds isNil or: [Time millisecondClockValue - start < (seconds * 1000)]]]
			whileTrue: [(Delay forMilliseconds: 50) wait]]
		ensure: [Machine free: key]
! !

!FirmwareDiagnostics methodsFor: 'output'!
echoOnScreen: aString
	"aString also on the firmware's text console (the screen) where the VM's output goes to a serial port only (ControlServer: a token it made)."
	firmware := Firmware current.
	firmware isNil ifTrue: [^self].
	((self locate: #serialIo) notNil and: [firmware conOut ~= 0]) ifTrue: [self conOut: aString]
!
line: aString
	| text |
	text := 'diag ', aString.
	Smalltalk vm stderrWrite: text, (String with: Character lf).
	echo == true ifTrue: [self conOut: text].
	self fileWrite: text, (String with: Character lf)
!
conOut: aString
	"aString and CR LF on the firmware's text console (OutputString)."
	| out p |
	out := firmware conOut.
	p := Machine allocate: aString size + 3 * 2.
	aString doWithIndex: [:c :i | Machine uint16At: p + (2 * (i - 1)) put: (c value min: 16rFFFD)].
	Machine uint16At: p + (2 * aString size) put: 13.
	Machine uint16At: p + (2 * aString size) + 2 put: 10.
	[Machine call: (firmware function: out at: 8) with: out with: p] ensure: [Machine free: p]
!
openFile
	"samaltak-diag.txt, afresh, on the first simple file system that has samaltak.args."
	fileNote := 'no file: no volume with samaltak.args'.
	(firmware handlesSupporting: (self class guids at: #simpleFileSystem)) do: [:h |
		file isNil ifTrue: [| fs root |
			fs := firmware protocol: (self class guids at: #simpleFileSystem) on: h.
			root := fs ifNotNil: [firmware outWord: [:p | Machine call: (firmware function: fs at: 8) with: fs with: p]].
			root notNil ifTrue: [
				(self open: 'samaltak.args' in: root mode: 1) ifNotNil: [:args |
					self file: args call: 16.
					(self open: self class fileName in: root mode: 3) ifNotNil: [:old | self file: old call: 24].
					file := self open: self class fileName in: root mode: 16r8000000000000003.
					fileNote := file isNil
						ifTrue: ['no file: cannot create ', self class fileName, ' on ', (self pathText: h)]
						ifFalse: ['also in ', self class fileName, ' on ', (self pathText: h)]].
				self file: root call: 16]]]
!
open: aName in: aDirectory mode: mode
	"EFI_FILE_PROTOCOL.Open: the new file, or nil."
	| name |
	name := self ucs2: aName.
	^[firmware outWord: [:p | Machine call: (firmware function: aDirectory at: 8) with: aDirectory with: p with: name with: mode with: 0]]
		ensure: [Machine free: name]
!
file: aFile call: offset
	"Close (16), Delete (24) or Flush (80)."
	^Machine call: (firmware function: aFile at: offset) with: aFile
!
fileWrite: aString
	| n buffer size |
	file isNil ifTrue: [^self].
	n := aString size.
	buffer := Machine allocate: n + 8.
	size := buffer + n.
	aString doWithIndex: [:c :i | Machine uint8At: buffer + i - 1 put: (c value < 128 ifTrue: [c value] ifFalse: [63])].
	Machine uint64At: size put: n.
	[Machine call: (firmware function: file at: 40) with: file with: size with: buffer] ensure: [Machine free: buffer]
!
flushFile
	file isNil ifFalse: [self file: file call: 80]
!
closeFile
	file isNil ifFalse: [self file: file call: 16].
	file := nil
! !

!FirmwareDiagnostics methodsFor: 'sections'!
firmwareInfo
	| st revision minor tables |
	st := firmware systemTable.
	revision := Machine uint32At: st + 8.
	minor := revision bitAnd: 16rFFFF.
	self line: 'firmware ', (self ucs2At: (Machine uint64At: st + 24)), ' revision 16r', (self hex: (Machine uint32At: st + 32) digits: 8),
		', UEFI ', (revision bitShift: -16) printString, '.', (minor // 10) printString, (minor \\ 10 = 0 ifTrue: [''] ifFalse: ['.', (minor \\ 10) printString]).
	self line: 'vm ', (Smalltalk vm banner ifNil: ['?']) asString.
	tables := OrderedCollection new.
	self configurationTablesDo: [:guid :address | tables add: (self class configurationTableNames at: guid ifAbsent: [guid])].
	self line: 'configuration tables: ', (self join: tables)
!
smbios
	| ep address length version count memory |
	(ep := self configurationTable: 'f2fd1544-9794-4a2c-992e-e5bbcf20e394') notNil
		ifTrue: [
			address := Machine uint64At: ep + 16.
			length := Machine uint32At: ep + 12.
			version := (Machine uint8At: ep + 7) printString, '.', (Machine uint8At: ep + 8) printString]
		ifFalse: [
			(ep := self configurationTable: 'eb9d2d31-2d88-11d3-9a16-0090273fc14d') isNil ifTrue: [^self line: 'smbios: none'].
			address := Machine uint32At: ep + 24.
			length := Machine uint16At: ep + 22.
			version := (Machine uint8At: ep + 6) printString, '.', (Machine uint8At: ep + 7) printString].
	self line: 'smbios ', version.
	count := 0.
	memory := 0.
	self smbiosAt: address length: length do: [:type :p :s |
		type = 0 ifTrue: [self line: 'bios ', (self join: {s value: 4. s value: 5. s value: 8})].
		type = 1 ifTrue: [self line: 'system ', (self join: {s value: 4. s value: 5. s value: 6})].
		type = 2 ifTrue: [self line: 'board ', (self join: {s value: 4. s value: 5. s value: 6})].
		type = 4 ifTrue: [| len |
			len := Machine uint8At: p + 1.
			self line: 'processor ', (self join: {s value: 4. s value: 7. s value: 16}),
				(len > 37 ifTrue: [', ', (Machine uint8At: p + 35) printString, ' cores, ', (Machine uint8At: p + 36) printString, ' enabled, ', (Machine uint8At: p + 37) printString, ' threads'] ifFalse: ['']),
				', max ', (Machine uint16At: p + 20) printString, ' MHz, now ', (Machine uint16At: p + 22) printString, ' MHz'].
		type = 17 ifTrue: [| size |
			size := Machine uint16At: p + 12.
			(size ~= 0 and: [size ~= 16rFFFF]) ifTrue: [
				count := count + 1.
				memory := memory + (size = 16r7FFF
					ifTrue: [Machine uint32At: p + 28]
					ifFalse: [(size bitAnd: 16r8000) = 0 ifTrue: [size] ifFalse: [(size bitAnd: 16r7FFF) // 1024]])]]].
	self line: 'memory devices ', count printString, ', ', memory printString, ' MB'
!
acpi
	| rsdp xsdt rsdt tables names |
	rsdp := (self configurationTable: '8868e871-e4f1-11d3-bc22-0080c73c8881')
		ifNil: [self configurationTable: 'eb9d2d30-2d88-11d3-9a16-0090273fc14d'].
	rsdp isNil ifTrue: [^self line: 'acpi: none'].
	xsdt := (Machine uint8At: rsdp + 15) >= 2 ifTrue: [Machine uint64At: rsdp + 24] ifFalse: [0].
	rsdt := Machine uint32At: rsdp + 16.
	tables := xsdt ~= 0
		ifTrue: [(0 to: ((Machine uint32At: xsdt + 4) - 36) // 8 - 1) collect: [:i | Machine uint64At: xsdt + 36 + (8 * i)]]
		ifFalse: [(0 to: ((Machine uint32At: rsdt + 4) - 36) // 4 - 1) collect: [:i | Machine uint32At: rsdt + 36 + (4 * i)]].
	names := tables collect: [:t | self ascii: t count: 4].
	self line: 'acpi oem ', (self ascii: rsdp + 9 count: 6), ', tables ', (self join: names).
	tables do: [:t | | sig |
		sig := self ascii: t count: 4.
		sig = 'FACP' ifTrue: [self fadt: t].
		sig = 'APIC' ifTrue: [self madt: t].
		sig = 'SPCR' ifTrue: [
			self line: 'spcr: serial console interface type ', (Machine uint8At: t + 36) printString, ' at 16r', (self hex: (Machine uint64At: t + 44) digits: 1),
				', baud code ', (Machine uint8At: t + 58) printString]]
!
fadt: t
	| flags |
	(Machine uint32At: t + 4) < 131 ifTrue: [^self line: 'psci: FADT too short for ARM_BOOT_ARCH'].
	flags := Machine uint16At: t + 129.
	self line: 'psci: ARM_BOOT_ARCH 16r', (self hex: flags digits: 4),
		((flags bitAnd: 1) ~= 0 ifTrue: [' (PSCI compliant, ', ((flags bitAnd: 2) ~= 0 ifTrue: ['HVC'] ifFalse: ['SMC']), ' conduit)'] ifFalse: [' (no PSCI)'])
!
madt: t
	| p end enabled total mpidrs gic |
	p := t + 44.
	end := t + (Machine uint32At: t + 4).
	enabled := 0.
	total := 0.
	mpidrs := OrderedCollection new.
	[p + 2 <= end and: [(Machine uint8At: p + 1) >= 2]] whileTrue: [| type flags |
		type := Machine uint8At: p.
		type = 16r0B ifTrue: [
			flags := Machine uint32At: p + 12.
			total := total + 1.
			(flags bitAnd: 1) ~= 0 ifTrue: [enabled := enabled + 1].
			mpidrs add: (self hex: (Machine uint64At: p + 68) digits: 1)].
		type = 16r0C ifTrue: [gic := Machine uint8At: p + 20].
		type = 0 ifTrue: [
			total := total + 1.
			((Machine uint32At: p + 4) bitAnd: 1) ~= 0 ifTrue: [enabled := enabled + 1]].
		type = 9 ifTrue: [
			total := total + 1.
			((Machine uint32At: p + 8) bitAnd: 1) ~= 0 ifTrue: [enabled := enabled + 1]].
		p := p + (Machine uint8At: p + 1)].
	self line: 'madt cpus ', total printString, ', enabled ', enabled printString, (gic isNil ifTrue: [''] ifFalse: [', GIC version ', gic printString]).
	mpidrs isEmpty ifFalse: [self line: 'mpidr ', (self join: mpidrs)]
!
cpus
	| mp words |
	mp := self locate: #mpServices.
	mp isNil ifTrue: [^self line: 'mp services: none (the VM runs on the boot CPU only)'].
	words := Machine allocate: 16.
	[(firmware isError: (Machine call: (firmware function: mp at: 0) with: mp with: words with: words + 8))
		ifTrue: [self line: 'mp services: GetNumberOfProcessors failed']
		ifFalse: [self line: 'mp services: ', (Machine uint64At: words) printString, ' processors, ', (Machine uint64At: words + 8) printString, ' enabled']]
		ensure: [Machine free: words]
!
memoryMap
	| words size map n descriptorSize pages highest attributes kb |
	words := Machine allocate: 32.
	[firmware boot: 56 with: words with: 0 with: words + 8 with: words + 16 with: words + 24.
	size := (Machine uint64At: words) + (16 * 64).
	Machine uint64At: words put: size.
	map := Machine allocate: size.
	[(firmware isError: (firmware boot: 56 with: words with: map with: words + 8 with: words + 16 with: words + 24))
		ifTrue: [^self line: 'memory map: GetMemoryMap failed'].
	size := Machine uint64At: words.
	descriptorSize := Machine uint64At: words + 16.
	n := size // descriptorSize.
	pages := Array new: 16 withAll: 0.
	attributes := Dictionary new.
	highest := 0.
	0 to: n - 1 do: [:i | | d type count attribute |
		d := map + (i * descriptorSize).
		type := Machine uint32At: d.
		count := Machine uint64At: d + 24.
		attribute := Machine uint64At: d + 32.
		pages at: (type min: 15) + 1 put: (pages at: (type min: 15) + 1) + count.
		type = 7 ifTrue: [
			#(#(16r2000 'RP') #(16r4000 'XP') #(16r20000 'RO') #(16r8000 'WP')) do: [:a |
				(attribute bitAnd: a first) ~= 0 ifTrue: [attributes at: a last put: (attributes at: a last ifAbsent: [0]) + 1]]].
		(type ~= 11 and: [type ~= 12]) ifTrue: [highest := highest max: (Machine uint64At: d + 8) + (count * 4096)]]]
		ensure: [Machine free: map]]
		ensure: [Machine free: words].
	kb := [:types | (types inject: 0 into: [:sum :t | sum + (pages at: t + 1)]) * 4 // 1024].
	self line: 'memory map ', n printString, ' descriptors of ', descriptorSize printString, ' bytes (', size printString, ' bytes); MB: free ', (kb value: #(7)) printString,
		', loader ', (kb value: #(1 2)) printString, ', boot services ', (kb value: #(3 4)) printString, ', runtime ', (kb value: #(5 6)) printString,
		', acpi ', (kb value: #(9 10)) printString, ', reserved ', (kb value: #(0 8 14)) printString, ', mmio ', (kb value: #(11 12)) printString,
		'; highest RAM address 16r', (self hex: highest digits: 1).
	self line: 'memory map attribute capabilities of free descriptors: ',
		(attributes isEmpty ifTrue: ['none'] ifFalse: [self join: (attributes keys asSortedCollection collect: [:k | k, ' ', (attributes at: k) printString])])
!
memoryProtection
	| protocol raw page out table |
	protocol := self locate: #memoryAttribute.
	protocol isNil
		ifTrue: [self line: 'memory attribute protocol: none']
		ifFalse: [
			raw := Machine allocate: 3 * 4096.
			page := raw + 4095 // 4096 * 4096.
			out := raw + (2 * 4096) + 1024.
			[| status |
			status := Machine call: (firmware function: protocol at: 0) with: protocol with: page with: 4096 with: out.
			self line: 'memory attribute protocol: present; a pool page''s attributes ',
				((firmware isError: status)
					ifTrue: ['unknown (status 16r', (self hex: status digits: 1), ')']
					ifFalse: ['16r', (self hex: (Machine uint64At: out) digits: 1), ((Machine uint64At: out) = 0 ifTrue: [''] ifFalse: [' (', (self memoryAttributeNames: (Machine uint64At: out)), ')'])])]
				ensure: [Machine free: raw]].
	self line: 'cpu architectural protocol: ', ((self locate: #cpuArch) isNil ifTrue: ['none'] ifFalse: ['present']).
	table := self configurationTable: 'dcfa911d-26eb-469f-a220-38b7dc461220'.
	self line: 'memory attributes table: ', (table isNil
		ifTrue: ['none']
		ifFalse: ['version ', (Machine uint32At: table) printString, ', ', (Machine uint32At: table + 4) printString, ' entries, flags 16r', (self hex: (Machine uint32At: table + 12) digits: 1)])
!
timer
	| timer word start elapsed |
	timer := self locate: #timerArch.
	timer isNil
		ifTrue: [self line: 'timer architectural protocol: none']
		ifFalse: [
			word := Machine allocate: 8.
			[Machine call: (firmware function: timer at: 16) with: timer with: word.
			self line: 'timer period ', ((Machine uint64At: word) // 10) printString, ' us']
				ensure: [Machine free: word]].
	start := Time millisecondClockValue.
	20 timesRepeat: [(Delay forMilliseconds: 1) wait].
	elapsed := Time millisecondClockValue - start.
	self line: 'a 1 ms Delay takes ', (elapsed / 20.0) printString, ' ms (20 in ', elapsed printString, ' ms)'
!
rng
	| rng words buffer status |
	rng := self locate: #rng.
	rng isNil ifTrue: [^self line: 'rng: none (SecureRandom has no entropy: it signals CryptoError)'].
	words := Machine allocate: 8.
	buffer := Machine allocate: 1024.
	[Machine uint64At: words put: 1024.
	status := Machine call: (firmware function: rng at: 0) with: rng with: words with: buffer.
	self line: 'rng: ', ((firmware isError: status) ifTrue: ['GetInfo failed'] ifFalse: [((Machine uint64At: words) // 16) printString, ' algorithms']),
		', GetRNG of 32 bytes ', ((firmware isError: (Machine call: (firmware function: rng at: 8) with: rng with: 0 with: 32 with: buffer)) ifTrue: ['failed'] ifFalse: ['ok'])]
		ensure: [Machine free: words. Machine free: buffer]
!
graphics
	| handles |
	handles := firmware handlesSupporting: (self class guids at: #gop).
	handles isEmpty ifTrue: [^self line: 'gop: none (no screen; the World cannot open)'].
	handles doWithIndex: [:h :index | | gop mode info modes out edid |
		gop := firmware protocol: (self class guids at: #gop) on: h.
		mode := Machine uint64At: gop + 24.
		info := Machine uint64At: mode + 8.
		self line: 'gop ', index printString, ' on ', (self pathText: h), ': mode ', (Machine uint32At: mode + 4) printString, ' of ', (Machine uint32At: mode) printString,
			', ', (self modeText: info), ', ', ((Machine uint64At: mode + 24) = 0 ifTrue: ['no framebuffer'] ifFalse: ['framebuffer 16r', (self hex: (Machine uint64At: mode + 24) digits: 1), ' of ', (Machine uint64At: mode + 32) printString, ' bytes']).
		modes := OrderedCollection new.
		out := Machine allocate: 16.
		[0 to: ((Machine uint32At: mode) min: 64) - 1 do: [:i |
			(firmware isError: (Machine call: (firmware function: gop at: 0) with: gop with: i with: out with: out + 8)) ifFalse: [
				modes add: (self modeText: (Machine uint64At: out + 8)).
				firmware freePool: (Machine uint64At: out + 8)]]]
			ensure: [Machine free: out].
		self line: 'gop ', index printString, ' modes: ', (self join: modes).
		edid := (firmware protocol: (self class guids at: #edidActive) on: h) ifNil: [firmware protocol: (self class guids at: #edidDiscovered) on: h].
		edid notNil ifTrue: [self line: 'gop ', index printString, ' edid: ', (self edidText: edid)]]
!
pci
	| handles |
	handles := firmware handlesSupporting: (self class guids at: #pciIo).
	self line: 'pci functions: ', handles size printString.
	handles do: [:h | (PciDevice firmware: firmware handle: h) ifNotNil: [:d |
		[| class |
		class := (d config: 8 width: 4) bitShift: -8.
		self line: 'pci ', (d location ifNil: ['?']), ' ', (self hex: d vendor digits: 4), ':', (self hex: d deviceId digits: 4), ' class ', (self hex: class digits: 6), ' ', (self pciClassName: class),
			((firmware isManaged: h) ifTrue: [', driven by the firmware'] ifFalse: [''])]
			ensure: [d release]]]
!
blockDevices
	| handles |
	handles := firmware handlesSupporting: (self class guids at: #blockIo).
	self line: 'block devices: ', handles size printString.
	handles do: [:h | (FirmwareBlockDevice firmware: firmware handle: h) ifNotNil: [:d |
		d isMediaPresent
			ifFalse: [self line: 'block ', d description, ': no medium']
			ifTrue: [
				self line: 'block ', d description, ': ', d blockCount printString, ' x ', d blockSize printString, ' (', (d byteSize // 1048576) printString, ' MB)',
					(d isLogicalPartition ifTrue: [', partition ', d partitionNumber printString] ifFalse: [', disk']),
					(d partitionName ifNil: [''] ifNotNil: [:n | n isEmpty ifTrue: [''] ifFalse: [' ', n printString]]),
					(d partitionTypeGuid ifNil: [''] ifNotNil: [:g | ' type ', g]),
					(d isRemovable ifTrue: [', removable'] ifFalse: ['']), (d isReadOnly ifTrue: [', read-only'] ifFalse: ['']),
					((d blockSize > 0 and: [d isImageStore]) ifTrue: [', the image store'] ifFalse: [''])]]]
!
volumes
	| mounts |
	mounts := FirmwareVolumes mounts.
	self line: 'volumes: ', (mounts isEmpty ifTrue: ['none'] ifFalse: [self join: (mounts collect: [:m | m key, ' (', ([m value label] on: Error do: [:e | e return: '?']), ')'])]).
	FirmwareVolumes problems do: [:each | self line: 'volume problem: ', each]
!
snp
	| handles |
	handles := firmware handlesSupporting: (self class guids at: #snp).
	handles isEmpty ifTrue: [^self line: 'snp: none (the firmware has no network driver here; the image drives e1000e and virtio-net itself)'].
	handles doWithIndex: [:h :index | | snp mode size mac |
		snp := firmware protocol: (self class guids at: #snp) on: h.
		mode := Machine uint64At: snp + 120.
		size := (Machine uint32At: mode + 4) min: 32.
		mac := Machine bytesAt: mode + 552 count: size.
		self line: 'snp ', index printString, ' on ', (self pathText: h), ': state ', (#('stopped' 'started' 'initialized') at: ((Machine uint32At: mode) min: 2) + 1),
			', mac ', (self macText: mac), ', link ',
			((Machine uint8At: mode + 651) = 0 ifTrue: ['unknown (no media detection)'] ifFalse: [(Machine uint8At: mode + 652) = 0 ifTrue: ['down'] ifFalse: ['up']]),
			((firmware protocol: (self class guids at: #nii) on: h) isNil ifTrue: [''] ifFalse: [', UNDI'])]
!
network
	| stack start |
	stack := NetworkStack active.
	stack isNil ifTrue: [^self line: 'network: no interface (no NIC the image or the firmware drives)'].
	self line: 'network: ', stack interface class name, ', mac ', (self macText: stack macAddress), '; DHCP ...'.
	self flushFile.
	start := Time millisecondClockValue.
	[stack isConfigured or: [Time millisecondClockValue - start > 20000]] whileFalse: [(Delay forMilliseconds: 100) wait].
	stack isConfigured
		ifTrue: [self line: 'dhcp: ', (NetworkStack dotted: stack address), ' mask ', (NetworkStack dotted: stack netmask), ' gateway ', (NetworkStack dotted: stack gateway),
			', dns ', (self join: (stack nameServers collect: [:a | NetworkStack dotted: a])), ' in ', (Time millisecondClockValue - start) printString, ' ms']
		ifFalse: [self line: 'dhcp: no lease in 20 s (state ', stack dhcp state printString, ')']
! !

!FirmwareDiagnostics methodsFor: 'private'!
locate: aName
	^firmware locateProtocol: (self class guids at: aName)
!
configurationTablesDo: aBlock
	"aBlock value: each configuration table's GUID (text) value: its address."
	| st table |
	st := firmware systemTable.
	table := Machine uint64At: st + 112.
	0 to: (Machine uint64At: st + 104) - 1 do: [:i |
		aBlock value: (FirmwareBlockDevice guidAt: table + (24 * i)) value: (Machine uint64At: table + (24 * i) + 16)]
!
configurationTable: aGuid
	self configurationTablesDo: [:guid :address | guid = aGuid ifTrue: [^address]].
	^nil
!
smbiosAt: address length: length do: aBlock
	"aBlock value: each structure's type value: its address value: a block answering the string whose number is at an offset in it."
	| p end |
	p := address.
	end := address + length.
	[p + 4 <= end] whileTrue: [| type strings q s |
		type := Machine uint8At: p.
		strings := OrderedCollection new.
		q := p + (Machine uint8At: p + 1).
		[(Machine uint8At: q) ~= 0 and: [q < end]] whileTrue: [
			s := WriteStream on: String new.
			[(Machine uint8At: q) ~= 0 and: [q < end]] whileTrue: [
				s nextPut: (Character value: (Machine uint8At: q)).
				q := q + 1].
			strings add: s contents.
			q := q + 1].
		strings isEmpty ifTrue: [q := q + 1].
		aBlock value: type value: p value: [:offset | | n |
			n := (Machine uint8At: p + 1) > offset ifTrue: [Machine uint8At: p + offset] ifFalse: [0].
			(n between: 1 and: strings size) ifTrue: [(strings at: n) trimBoth] ifFalse: ['']].
		type = 127 ifTrue: [^self].
		p := q + 1]
!
pathText: aHandle
	"The firmware's text of the handle's device path."
	| path toText p |
	path := firmware protocol: (self class guids at: #devicePath) on: aHandle.
	path isNil ifTrue: [^'(no device path)'].
	toText := self locate: #devicePathToText.
	toText isNil ifTrue: [^'(no device path text)'].
	p := Machine call: (firmware function: toText at: 8) with: path with: 0 with: 0.
	p = 0 ifTrue: [^'?'].
	^[self ucs2At: p] ensure: [firmware freePool: p]
!
modeText: info
	"EFI_GRAPHICS_OUTPUT_MODE_INFORMATION as WxH format."
	^(Machine uint32At: info + 4) printString, 'x', (Machine uint32At: info + 8) printString, ' ',
		(#('RGBX' 'BGRX' 'BitMask' 'BltOnly' '?') at: ((Machine uint32At: info + 12) min: 4) + 1),
		((Machine uint32At: info + 32) = (Machine uint32At: info + 4) ifTrue: [''] ifFalse: [' stride ', (Machine uint32At: info + 32) printString])
!
edidText: anEdidProtocol
	"The size of an EDID and its first detailed timing (the monitor's preferred mode)."
	| size bytes |
	size := Machine uint32At: anEdidProtocol.
	(size < 128 or: [(Machine uint64At: anEdidProtocol + 8) = 0]) ifTrue: [^size printString, ' bytes'].
	bytes := Machine bytesAt: (Machine uint64At: anEdidProtocol + 8) count: 128.
	^size printString, ' bytes, manufacturer ', (self edidManufacturer: bytes), ', preferred ',
		((bytes at: 57) + (((bytes at: 59) bitShift: -4) bitShift: 8)) printString, 'x',
		((bytes at: 60) + (((bytes at: 62) bitShift: -4) bitShift: 8)) printString,
		' (pixel clock ', (((bytes at: 55) + ((bytes at: 56) bitShift: 8)) // 100) printString, ' MHz)'
!
edidManufacturer: bytes
	| id |
	id := ((bytes at: 9) bitShift: 8) + (bytes at: 10).
	^String withAll: ({10. 5. 0} collect: [:k | Character value: 64 + ((id bitShift: k negated) bitAnd: 31)])
!
pciClassName: aClass
	| base |
	base := aClass bitShift: -16.
	(aClass bitShift: -8) = 16r0C03 ifTrue: [^'usb'].
	(aClass bitShift: -8) = 16r0108 ifTrue: [^'nvme'].
	^#('legacy' 'storage' 'network' 'display' 'multimedia' 'memory' 'bridge' 'communication' 'system' 'input' 'docking' 'processor' 'serial bus' 'wireless')
		at: base + 1 ifAbsent: ['other']
!
memoryAttributeNames: anInteger
	^self join: (#(#(16r1 'UC') #(16r8 'WB') #(16r1000 'WP') #(16r2000 'RP') #(16r4000 'XP') #(16r20000 'RO'))
		select: [:a | (anInteger bitAnd: a first) ~= 0] thenCollect: [:a | a last])
!
macText: bytes
	^self join: (bytes asArray collect: [:b | self hex: b digits: 2]) with: ':'
!
hex: anInteger digits: n
	^(anInteger printString: 16) asLowercase padLeftTo: n with: $0
!
ascii: address count: n
	^String withAll: ((Machine bytesAt: address count: n) asArray collect: [:b | (b between: 32 and: 126) ifTrue: [Character value: b] ifFalse: [$?]])
!
ucs2At: address
	address = 0 ifTrue: [^''].
	^FirmwareBlockDevice utf16At: address maxCharacters: 4096
!
ucs2: aString
	"aString as a NUL-terminated UCS-2 string outside the heap; the caller frees it."
	| p |
	p := Machine allocate: aString size + 1 * 2.
	aString doWithIndex: [:c :i | Machine uint16At: p + (2 * (i - 1)) put: c value].
	^p
!
join: strings
	^self join: strings with: ', '
!
join: strings with: separator
	^String streamContents: [:s |
		strings do: [:each | s nextPutAll: each asString] separatedBy: [s nextPutAll: separator]]
! !
