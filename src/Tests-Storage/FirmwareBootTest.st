TestCase subclass: #FirmwareBootTest
	instanceVariableNames: 'vars boot'
	classVariableNames: ''
	package: 'Tests-Storage'!

FirmwareBootTest comment: 'FirmwareBoot on stubbed variables (FirmwareVariablesTestStub): Ubuntu''s option found by description or path, Samaltak''s added at the lowest free number and replaced in place without touching BootOrder, removed with its BootOrder and BootNext, BootNext set before a reset, the firmware setup''s indication.'!

!FirmwareBootTest methodsFor: 'running'!
setUp
	| esp |
	vars := FirmwareVariablesTestStub new.
	boot := FirmwareBoot on: vars.
	esp := GptPartition number: 1 type: (GptDisk guidBytes: GptDisk efiSystemType) unique: GptDisk randomGuidBytes first: 2048 last: 4095 name: 'EFI'.
	vars at: 'Boot0000' put: (EfiLoadOption description: 'UEFI Shell' devicePath: EfiLoadOption endNode) bytes.
	vars at: 'Boot0001' put: (EfiLoadOption description: 'ubuntu' partition: esp file: '\EFI\ubuntu\shimaa64.efi') bytes.
	vars at: 'Boot0003' put: (EfiLoadOption description: 'Linux Boot Manager' partition: esp file: '\EFI\ubuntu\grubx64.efi') bytes.
	vars at: 'BootOrder' put: #[1 0 0 0 3 0]
! !

!FirmwareBootTest methodsFor: 'tests'!
testFindsUbuntu
	self assert: boot optionNumbers equals: #(0 1 3).
	self assert: boot bootOrder equals: #(1 0 3).
	self assert: boot ubuntuNumber equals: 1.
	vars at: 'Boot0001' put: #[].
	self assert: boot ubuntuNumber equals: 3.
	self assert: boot samaltakNumber isNil
!
testInstallKeepsBootOrder
	| esp n again |
	esp := GptPartition number: 1 type: (GptDisk guidBytes: GptDisk efiSystemType) unique: GptDisk randomGuidBytes first: 2048 last: 4095 name: 'EFI'.
	n := boot install: (EfiLoadOption description: 'Samaltak' partition: esp file: FirmwareBoot samaltakPath).
	self assert: n equals: 2.
	self assert: boot samaltakNumber equals: 2.
	self assert: boot bootOrder equals: #(1 0 3).
	again := boot install: (EfiLoadOption description: 'Samaltak' partition: esp file: FirmwareBoot samaltakPath).
	self assert: again equals: 2.
	self assert: boot optionNumbers equals: #(0 1 2 3).
	self assert: (boot describe includes: 'BootOrder 0001,0000,0003')
!
testRemoveSamaltak
	boot install: (EfiLoadOption description: 'Samaltak' devicePath: EfiLoadOption endNode).
	vars at: 'BootOrder' put: #[1 0 2 0].
	boot bootNext: 2.
	self assert: boot removeSamaltak equals: 2.
	self assert: boot bootOrder equals: #(1).
	self assert: boot bootNext isNil.
	self assert: boot samaltakNumber isNil
!
testRebootInto
	boot rebootInto: 1.
	self assert: boot bootNext equals: 1.
	self assert: vars resets equals: 1.
	self assert: boot bootOrder equals: #(1 0 3)
!
testFirmwareSetup
	self deny: boot canBootToFirmwareSetup.
	vars at: 'OsIndicationsSupported' put: #[16r45 0 0 0 0 0 0 0].
	vars at: 'OsIndications' put: #[4 0 0 0 0 0 0 0].
	self assert: boot canBootToFirmwareSetup.
	boot rebootToFirmwareSetup.
	self assert: (vars at: 'OsIndications') equals: #[5 0 0 0 0 0 0 0].
	self assert: vars resets equals: 1
! !
