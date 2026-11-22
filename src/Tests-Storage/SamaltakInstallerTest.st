TestCase subclass: #SamaltakInstallerTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Storage'!

SamaltakInstallerTest comment: 'What SamaltakInstaller decides without a firmware: the command line it installs, what a partition holds, sizes, and that it refuses to run off UEFI. The installation itself is tested under QEMU (make test-install).'!

!SamaltakInstallerTest class methodsFor: 'make test-install'!
addUbuntuOption
	"Under QEMU (tests/uefi/install-test.sh), what Ubuntu's installer leaves: a boot option ubuntu for \EFI\ubuntu\grub on the target disk's EFI system partition, first in BootOrder."
	| boot disk esp n |
	boot := FirmwareBoot current.
	disk := SamaltakInstaller new defaultDisk.
	esp := (GptDisk on: disk) efiSystemPartitions first.
	n := (1 to: 16rFFFF) detect: [:i | (boot optionNumbers includes: i) not].
	boot variables at: (FirmwareBoot optionName: n) put: (EfiLoadOption description: 'ubuntu' partition: esp
		file: (Smalltalk vm jitArchitecture == #x86_64 ifTrue: ['\EFI\ubuntu\grubx64.efi'] ifFalse: ['\EFI\ubuntu\grubaa64.efi'])) bytes.
	boot variables at: 'BootOrder' put: (boot wordBytes: {n}, boot bootOrder).
	Smalltalk vm stderrWrite: 'test: ubuntu is ', (FirmwareBoot optionName: n), (String with: Character lf)
! !

!SamaltakInstallerTest methodsFor: 'tests'!
testFilterArgs
	| i |
	i := SamaltakInstaller new.
	self assert: (i filterArgs: ('--max-heap', (String with: Character lf), '2048', (String with: Character lf), 'disk:', (String with: Character lf), '--eval', (String with: Character lf), 'SamaltakInstaller runScript: ''yes''', (String with: Character lf), '--window-size', (String with: Character lf), '1920x1080') asByteArray)
		equals: #('--max-heap' '2048' 'disk:' '--window-size' '1920x1080').
	self assert: (i filterArgs: ('disk:', (String with: Character lf), '--headless', (String with: Character lf), '--test', (String with: Character lf), 'FooTest') asByteArray) equals: #('disk:' '--headless').
	self assert: (i filterArgs: nil) equals: #('disk:')
!
testContent
	| i b |
	i := SamaltakInstaller new.
	self assert: (i contentOfBytes: (ByteArray new: 69632)) equals: #empty.
	b := ByteArray new: 69632.
	b uint16At: 1081 put: 16rEF53.
	self assert: (i contentOfBytes: b) equals: #ext4.
	b := ByteArray new: 69632.
	b replaceFrom: 1 to: 8 with: 'SAMSTORE' asByteArray startingAt: 1.
	self assert: (i contentOfBytes: b) equals: #imageStore.
	b := ByteArray new: 69632.
	b at: 30000 put: 1.
	self assert: (i contentOfBytes: b) equals: #unknown
!
testSizes
	self assert: (SamaltakInstaller sizeText: 3 * 1048576) equals: '3 MB'.
	self assert: (SamaltakInstaller sizeText: 1536 * 1048576) equals: '1.5 GB'
!
testRefusesWithoutFirmware
	Machine hasFirmware ifTrue: [^self].
	self assert: (SamaltakInstaller new dryRun: true; run) equals: 'refused: not on UEFI'.
	self assert: (SamaltakInstaller runScript: 'install') equals: 'install: say yes or dry-run'
! !
