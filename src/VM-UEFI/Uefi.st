VMCoreModule subclass: #UefiModule
	instanceVariableNames: 'firmware'
	classVariableNames: 'EFI_ALLOCATE_ANY_PAGES EFI_EVT_NOTIFY_SIGNAL EFI_EVT_TIMER EFI_FILE_MODE_CREATE EFI_FILE_MODE_READ EFI_FILE_MODE_WRITE EFI_LOADER_CODE EFI_LOADER_DATA EFI_MEMORY_RO EFI_MEMORY_WB EFI_MEMORY_XP EFI_RESET_SHUTDOWN EFI_TIMER_CANCEL EFI_TIMER_PERIODIC EFI_TIMER_RELATIVE EFI_TPL_CALLBACK STACK_BYTES'
	package: 'VM-UEFI'!

UefiModule comment: 'I am the abstract class of the modules of the VM on UEFI (VMTranslator generateVMInto:os:arch: with #uefi): a VM that is the firmware''s application, with no operating system and no C library under it. The firmware''s services are tables of function pointers (EfiSystemTable, EfiBootServices, ...) that take the Microsoft calling convention on x86-64 and the standard one on AArch64, where ms_abi changes nothing (EfiFn0 ... EfiFn6: every argument a 64-bit word); efi: fn with: ... calls one.

UefiFirmware is the entry (efi_main); UefiLibC, UefiLibM and UefiPosix take the place of the C libraries the core calls, UefiWindows, UefiEvents, UefiVsync, UefiGpu and UefiNoIO that of the platform layer''s SDL and POSIX modules (replaces); UefiTicker, UefiJitPlatform and UefiPlatform implement the core''s interfaces, UefiCpu what differs between the CPUs; UefiScreen, UefiInput, UefiVirtioInput and UefiImageStore drive the firmware''s devices.'!

!UefiModule class methodsFor: 'declaring'!
declarations
	^#((firmware UefiFirmware))
!
isAbstractModule
	^self == UefiModule
!
targetOS
	^#uefi
!
isSimulated
	^false
!
typedefs
	^#((EfiFn0 'uint64_t (__attribute__((ms_abi)) *)(void)')
		(EfiFn1 'uint64_t (__attribute__((ms_abi)) *)(uint64_t)')
		(EfiFn2 'uint64_t (__attribute__((ms_abi)) *)(uint64_t, uint64_t)')
		(EfiFn3 'uint64_t (__attribute__((ms_abi)) *)(uint64_t, uint64_t, uint64_t)')
		(EfiFn4 'uint64_t (__attribute__((ms_abi)) *)(uint64_t, uint64_t, uint64_t, uint64_t)')
		(EfiFn5 'uint64_t (__attribute__((ms_abi)) *)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t)')
		(EfiFn6 'uint64_t (__attribute__((ms_abi)) *)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t)'))
!
initialize
	EFI_LOADER_CODE := 1.
	EFI_LOADER_DATA := 2.
	EFI_ALLOCATE_ANY_PAGES := 0.
	EFI_EVT_TIMER := 16r80000000.
	EFI_EVT_NOTIFY_SIGNAL := 16r200.
	EFI_TPL_CALLBACK := 8.
	EFI_TIMER_CANCEL := 0.
	EFI_TIMER_PERIODIC := 1.
	EFI_TIMER_RELATIVE := 2.
	EFI_FILE_MODE_READ := 1.
	EFI_FILE_MODE_WRITE := 2.
	EFI_FILE_MODE_CREATE := 16r8000000000000000.
	EFI_MEMORY_WB := 8.
	EFI_MEMORY_XP := 16r4000.
	EFI_MEMORY_RO := 16r20000.
	EFI_RESET_SHUTDOWN := 2.
	STACK_BYTES := 8 * 1024 * 1024
! !

!UefiModule methodsFor: 'calling the firmware'!
efi: fn
	^(self cCoerce: fn to: 'EfiFn0') call
!
efi: fn with: a
	^(self cCoerce: fn to: 'EfiFn1') call: (self cCoerce: a to: 'uint64_t')
!
efi: fn with: a with: b
	^(self cCoerce: fn to: 'EfiFn2') call: (self cCoerce: a to: 'uint64_t') with: (self cCoerce: b to: 'uint64_t')
!
efi: fn with: a with: b with: c
	^(self cCoerce: fn to: 'EfiFn3') call: (self cCoerce: a to: 'uint64_t') with: (self cCoerce: b to: 'uint64_t') with: (self cCoerce: c to: 'uint64_t')
!
efi: fn with: a with: b with: c with: d
	^(self cCoerce: fn to: 'EfiFn4') call: (self cCoerce: a to: 'uint64_t') with: (self cCoerce: b to: 'uint64_t') with: (self cCoerce: c to: 'uint64_t') with: (self cCoerce: d to: 'uint64_t')
!
efi: fn with: a with: b with: c with: d with: e
	^(self cCoerce: fn to: 'EfiFn5') call: (self cCoerce: a to: 'uint64_t') with: (self cCoerce: b to: 'uint64_t') with: (self cCoerce: c to: 'uint64_t') with: (self cCoerce: d to: 'uint64_t') with: (self cCoerce: e to: 'uint64_t')
!
efiFailed: status
	"EFI_ERROR: the high bit."
	^(status >> 63) ~= 0
!
boot
	^firmware bootServices
!
runtime
	^firmware runtimeServices
! !

UefiModule subclass: #UefiFirmware
	instanceVariableNames: 'imageHandle systemTable bootServices runtimeServices conOut root store cpu serial screenOwned'
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiFirmware comment: 'The VM''s entry on UEFI, efi_main: makes its image writable and executable (unprotect:bootServices:), keeps the system table, turns off the boot manager''s watchdog (it resets the machine after 5 minutes), switches to a stack of STACK_BYTES (the firmware''s is 128 KB, and the JIT''s code keeps a native frame per activation), opens the volume the VM was loaded from (its root directory is the current directory: fopen of a relative path), finds the image store (UefiImageStore), reads the command line from samaltak.args there (one argument a line; without it: disk: --headless, or samaltak.image --headless if there is no store) and runs VMMain>>main:argv:. What it answers is the exit status (UefiLibC>>exit:).'!

!UefiFirmware class methodsFor: 'declaring'!
declarations
	^#((imageHandle 'void *') (systemTable 'EfiSystemTable *') (bootServices 'EfiBootServices *') (runtimeServices 'EfiRuntimeServices *')
		(conOut 'EfiTextOutput *') (root 'EfiFile *') (store UefiImageStore) (cpu UefiCpu) (serial 'EfiSerialIo *') (screenOwned bool))
! !

!UefiFirmware methodsFor: 'entry'!
efiMain: anImageHandle systemTable: aSystemTable
	"What the firmware calls (C's efi_main, the image's entry point)."
	<export>
	<abi: 'ms_abi'>
	<returns: 'uint64_t'>
	<var: #anImageHandle type: 'void *'>
	<var: #aSystemTable type: 'EfiSystemTable *'>
	| stack run |
	self unprotect: anImageHandle bootServices: aSystemTable bootServices.
	imageHandle := anImageHandle.
	systemTable := aSystemTable.
	bootServices := aSystemTable bootServices.
	runtimeServices := aSystemTable runtimeServices.
	conOut := aSystemTable conOut.
	self efi: bootServices setWatchdogTimer with: 0 with: 0 with: 0 with: self null.
	run := self cCoerce: (self functionPointer: #run) to: 'void *'.
	stack := self local: 'uint64_t'.
	(self efiFailed: (self efi: bootServices allocatePages with: EFI_ALLOCATE_ANY_PAGES with: EFI_LOADER_DATA with: STACK_BYTES >> 12 with: stack)) ifTrue: [
		^(self cCoerce: run to: 'uint64_t (*)(void)') call].
	^cpu call: run onStack: (self cCoerce: stack value + STACK_BYTES to: 'void *')
!
run
	"The VM, on the stack efi_main gave it."
	<function>
	<returns: 'uint64_t'>
	| argv argc |
	libc start.
	posix start.
	self openRoot.
	self openSerial.
	store start.
	argv := self local: 'char *[64]'.
	argc := self arguments: argv max: 64.
	libc exit: (vmMain main: argc argv: argv).
	^0
!
unprotect: anImageHandle bootServices: services
	"Make the VM's image writable and executable where the firmware protects it by its sections (edk2 on AArch64 makes the one section, code, read-only): with EFI_MEMORY_ATTRIBUTE_PROTOCOL, else (ArmVirtQemu uninstalls that) with the CPU architectural protocol's SetMemoryAttributes, as edk2 protects it, write-back and nothing else. Before anything writes a global."
	<function>
	<var: #anImageHandle type: 'void *'>
	<var: #services type: 'EfiBootServices *'>
	| guid image attributes base size cpuArch |
	guid := self local: 'EfiGuid'.
	image := self local: 'EfiLoadedImage *'.
	self guid: guid data1: 16r5B1B31A1 data2: 16r9562 data3: 16r11D2 data4: 16r8E3F00A0C969723B.
	(self efiFailed: (self efi: services handleProtocol with: anImageHandle with: guid with: image)) ifTrue: [^self].
	base := image value imageBase.
	size := image value imageSize + 4095 bitClear: 4095.
	attributes := self local: 'EfiMemoryAttribute *'.
	self guid: guid data1: 16rF4560CF6 data2: 16r40EC data3: 16r4B4A data4: 16rA192BF1D57D0B189.
	(self efiFailed: (self efi: services locateProtocol with: guid with: self null with: attributes)) ifFalse: [
		self efi: attributes value clearMemoryAttributes with: attributes value with: base with: size with: (EFI_MEMORY_RO bitOr: EFI_MEMORY_XP).
		^self].
	cpuArch := self local: 'EfiCpuArch *'.
	self guid: guid data1: 16r26BACCB1 data2: 16r6F42 data3: 16r11D4 data4: 16rBCE70080C73C8881.
	(self efiFailed: (self efi: services locateProtocol with: guid with: self null with: cpuArch)) ifTrue: [^self].
	self efi: cpuArch value setMemoryAttributes with: cpuArch value with: base with: size with: EFI_MEMORY_WB
!
openRoot
	"The root directory of the volume the VM was loaded from."
	| guid image fs dir |
	guid := self local: 'EfiGuid'.
	image := self local: 'EfiLoadedImage *'.
	self guid: guid data1: 16r5B1B31A1 data2: 16r9562 data3: 16r11D2 data4: 16r8E3F00A0C969723B.
	(self efiFailed: (self efi: bootServices handleProtocol with: imageHandle with: guid with: image)) ifTrue: [^self].
	fs := self local: 'EfiFileSystem *'.
	self guid: guid data1: 16r964E5B22 data2: 16r6459 data3: 16r11D2 data4: 16r8E3900A0C969723B.
	(self efiFailed: (self efi: bootServices handleProtocol with: image value deviceHandle with: guid with: fs)) ifTrue: [^self].
	dir := self local: 'EfiFile *'.
	(self efiFailed: (self efi: fs value openVolume with: fs value with: dir)) ifTrue: [^self].
	root := dir value
!
arguments: argv max: max
	"Fill argv from samaltak.args in the root directory, one argument a line; answer argc."
	<function>
	<var: #argv type: 'char **'>
	<var: #max type: 'int'>
	<returns: 'int'>
	| f buf n argc i start |
	argv at: 0 put: 'samaltak'.
	argc := 1.
	f := libc fopen: 'samaltak.args' mode: 'rb'.
	f isNull ifTrue: [
		argv at: 1 put: (store isPresent ifTrue: ['disk:'] ifFalse: ['samaltak.image']).
		argv at: 2 put: '--headless'.
		^3].
	buf := self cCoerce: (libc malloc: 65536) to: 'char *'.
	n := (libc fread: buf size: 1 count: 65535 file: f) asInt64.
	libc fclose: f.
	buf at: n put: 0.
	i := 0.
	start := 0.
	[i <= n and: [argc < (max - 1)]] whileTrue: [
		((buf at: i) = 0 or: [(buf at: i) = 10 or: [(buf at: i) = 13]]) ifTrue: [
			buf at: i put: 0.
			i > start ifTrue: [
				argv at: argc put: buf + start.
				argc := argc + 1].
			start := i + 1].
		i := i + 1].
	argv at: argc put: self null.
	^argc asInt32
!
guid: g data1: a data2: b data3: c data4: d
	"d's bytes, most significant first, are data4[0..7]."
	| bytes |
	g data1: a.
	g data2: b.
	g data3: c.
	bytes := self cCoerce: (g fieldAddress: #data4) to: 'uint8_t *'.
	0 to: 7 do: [:k | bytes at: k put: ((d >> (56 - (8 * k))) bitAnd: 255)]
! !

!UefiFirmware methodsFor: 'accessing'!
bootServices
	^bootServices
!
runtimeServices
	^runtimeServices
!
root
	"The volume's root directory (EfiFile), null if there is none."
	<function>
	^root
!
conInHandle
	^systemTable conInHandle
!
screenOwned: aBoolean
	"Once the VM draws on the screen the firmware's console must not (UefiScreen)."
	<function>
	<var: #aBoolean type: 'bool'>
	screenOwned := aBoolean
!
openSerial
	"The first serial port, where the console goes when there is one."
	<function>
	| guid p |
	guid := self local: 'EfiGuid'.
	p := self local: 'void *'.
	self guid: guid data1: 16rBB25CF6F data2: 16rF1D4 data3: 16r11D2 data4: 16r9A0C0090273FC1FD.
	(self efiFailed: (self efi: bootServices locateProtocol with: guid with: self null with: p))
		ifFalse: [serial := self cCoerce: p value to: 'EfiSerialIo *']
!
writeConsole: bytes count: n
	"UTF-8 to the serial port (LF as CR LF); without one, nothing (the caller uses the console then); answer whether it went somewhere."
	<function>
	<var: #bytes type: 'const char *'>
	<var: #n type: 'int64_t'>
	<returns: 'bool'>
	| crlf size start |
	serial isNull ifTrue: [^false].
	crlf := self local: 'char[2]'.
	crlf at: 0 put: 13.
	crlf at: 1 put: 10.
	size := self local: 'uint64_t'.
	start := 0.
	0 to: n - 1 do: [:i |
		(bytes at: i) = 10 ifTrue: [
			size value: (i - start) asUInt64.
			self efi: serial writeSerial with: serial with: size with: bytes + start.
			size value: 2.
			self efi: serial writeSerial with: serial with: size with: crlf.
			start := i + 1]].
	start < n ifTrue: [
		size value: (n - start) asUInt64.
		self efi: serial writeSerial with: serial with: size with: bytes + start].
	^true
!
isScreenOwned
	<function>
	<returns: 'bool'>
	^screenOwned
!
outputString: aUcs2String
	"Write a NUL-terminated UCS-2 string to the console (on QEMU with -nographic, the serial port)."
	<function>
	<var: #aUcs2String type: 'uint16_t *'>
	conOut isNull ifTrue: [^self].
	self efi: conOut outputString with: conOut with: aUcs2String
!
timerNotifying: notify context: context
	"A timer event whose notification function (ms_abi) the firmware calls with context at TPL_CALLBACK; null if there is none."
	<function>
	<var: #notify type: 'void *'>
	<var: #context type: 'void *'>
	<returns: 'void *'>
	| event |
	event := self local: 'void *'.
	(self efiFailed: (self efi: bootServices createEvent with: (EFI_EVT_TIMER bitOr: EFI_EVT_NOTIFY_SIGNAL) with: EFI_TPL_CALLBACK
		with: notify with: context with: event)) ifTrue: [^self null].
	^event value
!
setTimer: event microseconds: us periodic: periodic
	"Signal event after us (every us if periodic); us < 0 cancels it."
	<function>
	<var: #event type: 'void *'>
	<var: #us type: 'int64_t'>
	<var: #periodic type: 'bool'>
	us < 0 ifTrue: [
		self efi: bootServices setTimer with: event with: EFI_TIMER_CANCEL with: 0.
		^self].
	self efi: bootServices setTimer with: event with: (periodic ifTrue: [EFI_TIMER_PERIODIC] ifFalse: [EFI_TIMER_RELATIVE])
		with: (us < 1 ifTrue: [1] ifFalse: [us]) * 10
!
shutdown: status
	"Power off (QEMU exits); status goes to ResetSystem."
	<function>
	<noreturn>
	<var: #status type: 'int'>
	self efi: runtimeServices resetSystem with: EFI_RESET_SHUTDOWN with: status asInt64 with: 0 with: self null.
	[true] whileTrue
! !

VMStruct subclass: #EfiGuid
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!EfiGuid class methodsFor: 'declaring'!
fields
	^#((data1 uint32_t) (data2 uint16_t) (data3 uint16_t) (data4 'uint8_t[8]'))
! !

VMStruct subclass: #EfiTime
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!EfiTime class methodsFor: 'declaring'!
fields
	^#((year uint16_t) (month uint8_t) (day uint8_t) (hour uint8_t) (minute uint8_t) (second uint8_t) (pad1 uint8_t)
		(nanosecond uint32_t) (timeZone int16_t) (daylight uint8_t) (pad2 uint8_t))
! !

VMStruct subclass: #EfiSystemTable
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiSystemTable comment: 'EFI_SYSTEM_TABLE (UEFI 2.10, 4.3).'!

!EfiSystemTable class methodsFor: 'declaring'!
fields
	^#((hdrSignature uint64_t) (hdrRevision uint32_t) (hdrSize uint32_t) (hdrCrc32 uint32_t) (hdrReserved uint32_t)
		(firmwareVendor 'uint16_t *') (firmwareRevision uint32_t) (conInHandle 'void *') (conIn 'void *')
		(conOutHandle 'void *') (conOut 'EfiTextOutput *') (stdErrHandle 'void *') (stdErr 'EfiTextOutput *')
		(runtimeServices 'EfiRuntimeServices *') (bootServices 'EfiBootServices *')
		(tableEntries uint64_t) (configurationTable 'void *'))
! !

VMStruct subclass: #EfiBootServices
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiBootServices comment: 'EFI_BOOT_SERVICES (UEFI 2.10, 4.4), up to LocateProtocol: function pointers, each called with efi:with:...'!

!EfiBootServices class methodsFor: 'declaring'!
fields
	^#((hdrSignature uint64_t) (hdrRevision uint32_t) (hdrSize uint32_t) (hdrCrc32 uint32_t) (hdrReserved uint32_t)
		(raiseTpl 'void *') (restoreTpl 'void *') (allocatePages 'void *') (freePages 'void *') (getMemoryMap 'void *')
		(allocatePool 'void *') (freePool 'void *') (createEvent 'void *') (setTimer 'void *') (waitForEvent 'void *')
		(signalEvent 'void *') (closeEvent 'void *') (checkEvent 'void *') (installProtocolInterface 'void *')
		(reinstallProtocolInterface 'void *') (uninstallProtocolInterface 'void *') (handleProtocol 'void *')
		(reservedService 'void *') (registerProtocolNotify 'void *') (locateHandle 'void *') (locateDevicePath 'void *')
		(installConfigurationTable 'void *') (loadImage 'void *') (startImage 'void *') (exitImage 'void *')
		(unloadImage 'void *') (exitBootServices 'void *') (getNextMonotonicCount 'void *') (stall 'void *')
		(setWatchdogTimer 'void *') (connectController 'void *') (disconnectController 'void *') (openProtocol 'void *')
		(closeProtocol 'void *') (openProtocolInformation 'void *') (protocolsPerHandle 'void *')
		(locateHandleBuffer 'void *') (locateProtocol 'void *'))
! !

VMStruct subclass: #EfiRuntimeServices
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiRuntimeServices comment: 'EFI_RUNTIME_SERVICES (UEFI 2.10, 4.5), up to ResetSystem.'!

!EfiRuntimeServices class methodsFor: 'declaring'!
fields
	^#((hdrSignature uint64_t) (hdrRevision uint32_t) (hdrSize uint32_t) (hdrCrc32 uint32_t) (hdrReserved uint32_t)
		(getTime 'void *') (setTime 'void *') (getWakeupTime 'void *') (setWakeupTime 'void *')
		(setVirtualAddressMap 'void *') (convertPointer 'void *') (getVariable 'void *') (getNextVariableName 'void *')
		(setVariable 'void *') (getNextHighMonotonicCount 'void *') (resetSystem 'void *'))
! !

VMStruct subclass: #EfiTextOutput
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiTextOutput comment: 'EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL (UEFI 2.10, 12.4).'!

!EfiTextOutput class methodsFor: 'declaring'!
fields
	^#((reset 'void *') (outputString 'void *') (testString 'void *') (queryMode 'void *') (setMode 'void *')
		(setAttribute 'void *') (clearScreen 'void *') (setCursorPosition 'void *') (enableCursor 'void *') (mode 'void *'))
! !

VMStruct subclass: #EfiLoadedImage
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiLoadedImage comment: 'EFI_LOADED_IMAGE_PROTOCOL (UEFI 2.10, 9.1).'!

!EfiLoadedImage class methodsFor: 'declaring'!
fields
	^#((revision uint32_t) (parentHandle 'void *') (systemTable 'void *') (deviceHandle 'void *') (filePath 'void *')
		(reservedPointer 'void *') (loadOptionsSize uint32_t) (loadOptions 'void *') (imageBase 'void *') (imageSize uint64_t)
		(imageCodeType uint32_t) (imageDataType uint32_t) (unload 'void *'))
! !

VMStruct subclass: #EfiMemoryAttribute
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiMemoryAttribute comment: 'EFI_MEMORY_ATTRIBUTE_PROTOCOL (UEFI 2.10, 37.7).'!

!EfiMemoryAttribute class methodsFor: 'declaring'!
fields
	^#((getMemoryAttributes 'void *') (setMemoryAttributes 'void *') (clearMemoryAttributes 'void *'))
! !

VMStruct subclass: #EfiCpuArch
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiCpuArch comment: 'EFI_CPU_ARCH_PROTOCOL (UEFI PI 1.8, volume 2, 12.3), up to SetMemoryAttributes.'!

!EfiCpuArch class methodsFor: 'declaring'!
fields
	^#((flushDataCache 'void *') (enableInterrupt 'void *') (disableInterrupt 'void *') (getInterruptState 'void *')
		(init 'void *') (registerInterruptHandler 'void *') (getTimerValue 'void *') (setMemoryAttributes 'void *'))
! !

VMStruct subclass: #EfiFileSystem
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiFileSystem comment: 'EFI_SIMPLE_FILE_SYSTEM_PROTOCOL (UEFI 2.10, 13.4).'!

!EfiFileSystem class methodsFor: 'declaring'!
fields
	^#((revision uint64_t) (openVolume 'void *'))
! !

VMStruct subclass: #EfiFile
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiFile comment: 'EFI_FILE_PROTOCOL (UEFI 2.10, 13.5), revision 1''s functions.'!

!EfiFile class methodsFor: 'declaring'!
fields
	^#((revision uint64_t) (open 'void *') (close 'void *') (delete 'void *') (read 'void *') (write 'void *')
		(getPosition 'void *') (setPosition 'void *') (getInfo 'void *') (setInfo 'void *') (flush 'void *'))
! !
