Object subclass: #FirmwareBoot
	instanceVariableNames: 'variables'
	classVariableNames: ''
	package: 'System-Storage'!

FirmwareBoot comment: 'I am the firmware''s boot manager as its variables describe it (UEFI 2.10, 3.1): the load options Boot#### (EfiLoadOption), BootOrder, BootNext and BootCurrent, and OsIndications. Samaltak''s option is the one for \EFI\samaltak\BOOTAA64.EFI (BOOTX64.EFI) or described Samaltak, Ubuntu''s the one described ubuntu or for \EFI\ubuntu\shim or grub. rebootInto: sets BootNext, which the firmware boots once and deletes, then resets the machine: BootOrder never changes, so the default stays what it was. rebootToFirmwareSetup sets OsIndications'' EFI_OS_INDICATIONS_BOOT_TO_FW_UI where OsIndicationsSupported has it.

	FirmwareBoot current ubuntuNumber
	FirmwareBoot rebootInto: #ubuntu        "or #samaltak; answers why not if it cannot"
	FirmwareBoot rebootToFirmwareSetup'!

!FirmwareBoot class methodsFor: 'instance creation'!
current
	"The boot manager's variables, or nil without a firmware."
	^FirmwareVariables current ifNotNil: [:v | self on: v]
!
on: aFirmwareVariables
	^self new setVariables: aFirmwareVariables
! !

!FirmwareBoot class methodsFor: 'paths'!
bootFileName
	"The EFI application's name for this CPU (removable media's default)."
	^Smalltalk vm jitArchitecture == #x86_64 ifTrue: ['BOOTX64.EFI'] ifFalse: ['BOOTAA64.EFI']
!
samaltakDirectory
	^'\EFI\samaltak'
!
samaltakPath
	^self samaltakDirectory, '\', self bootFileName
!
ubuntuPaths
	^#('\EFI\ubuntu\shimaa64.efi' '\EFI\ubuntu\grubaa64.efi' '\EFI\ubuntu\shimx64.efi' '\EFI\ubuntu\grubx64.efi')
!
optionName: anInteger
	^'Boot', ((anInteger printString: 16) asUppercase padLeftTo: 4 with: $0)
! !

!FirmwareBoot class methodsFor: 'rebooting'!
rebootInto: aSymbol
	"Reboot once into #ubuntu or #samaltak (BootNext); answer why not if there is no such option (or no firmware)."
	^self current
		ifNil: ['not on UEFI']
		ifNotNil: [:boot | (boot numberOf: aSymbol)
			ifNil: ['no boot option for ', aSymbol]
			ifNotNil: [:n | boot rebootInto: n]]
!
rebootToFirmwareSetup
	"Reboot into the firmware's setup; answer why not if it cannot."
	^self current
		ifNil: ['not on UEFI']
		ifNotNil: [:boot | boot canBootToFirmwareSetup
			ifTrue: [boot rebootToFirmwareSetup]
			ifFalse: ['the firmware cannot boot to its setup (OsIndicationsSupported)']]
! !

!FirmwareBoot methodsFor: 'initialization'!
setVariables: aFirmwareVariables
	variables := aFirmwareVariables
! !

!FirmwareBoot methodsFor: 'accessing'!
variables
	^variables
!
optionNumbers
	"The numbers of the Boot#### variables there are, in order."
	^((variables names select: [:a | a value = FirmwareVariables globalGuid and: [self isOptionName: a key]])
		collect: [:a | Integer readFrom: (a key copyFrom: 5 to: 8) base: 16]) asSortedCollection asArray
!
optionAt: anInteger
	"The load option Boot#### for anInteger, or nil."
	^EfiLoadOption fromBytes: (variables at: (self class optionName: anInteger))
!
bootOrder
	^self words: (variables at: 'BootOrder')
!
bootNext
	^(self words: (variables at: 'BootNext')) ifEmpty: [nil] ifNotEmpty: [:w | w first]
!
bootCurrent
	^(self words: (variables at: 'BootCurrent')) ifEmpty: [nil] ifNotEmpty: [:w | w first]
!
numberOf: aSymbol
	aSymbol == #ubuntu ifTrue: [^self ubuntuNumber].
	aSymbol == #samaltak ifTrue: [^self samaltakNumber].
	^self error: 'Unknown boot target: ', aSymbol printString
!
ubuntuNumber
	"Ubuntu's option (DGX OS is Ubuntu), the first in BootOrder if there are several."
	^self firstNumberSuch: [:o | o isActive and: [(o description asLowercase includesSubstring: 'ubuntu')
		or: [self class ubuntuPaths anySatisfy: [:p | o isFile: p]]]]
!
samaltakNumber
	^self firstNumberSuch: [:o | o description = 'Samaltak' or: [o isFile: self class samaltakPath]]
!
firstNumberSuch: aBlock
	| order numbers |
	order := self bootOrder.
	numbers := order, (self optionNumbers reject: [:n | order includes: n]).
	^numbers detect: [:n | (self optionAt: n) ifNil: [false] ifNotNil: [:o | aBlock value: o]] ifNone: [nil]
!
describe
	"Lines saying what the boot manager has: each option, BootOrder, BootNext, BootCurrent."
	| lines |
	lines := OrderedCollection new.
	self optionNumbers do: [:n | | o |
		o := self optionAt: n.
		lines add: (self class optionName: n), (o isNil ifTrue: [' (not a load option)'] ifFalse: [
			(o isActive ifTrue: ['* '] ifFalse: ['  ']), o description printString,
				(o partitionNumber ifNil: [''] ifNotNil: [:p | ' partition ', p printString]),
				(o filePath ifNil: [''] ifNotNil: [:f | ' ', f])])].
	lines add: 'BootOrder ', (self hex: self bootOrder).
	lines add: 'BootNext ', (self bootNext ifNil: ['none'] ifNotNil: [:n | self hex: {n}]).
	lines add: 'BootCurrent ', (self bootCurrent ifNil: ['none'] ifNotNil: [:n | self hex: {n}]).
	^lines asArray
! !

!FirmwareBoot methodsFor: 'changing'!
install: anEfiLoadOption
	"Write anEfiLoadOption as Samaltak's option: over the one there is, else as the lowest free Boot####; BootOrder stays as it is. Answer its number."
	| n |
	n := self samaltakNumber ifNil: [(0 to: 16rFFFF) detect: [:i | (self optionNumbers includes: i) not]].
	variables at: (self class optionName: n) put: anEfiLoadOption bytes.
	^n
!
removeSamaltak
	"Delete Samaltak's option, and its number from BootOrder and BootNext; answer the number or nil."
	| n |
	n := self samaltakNumber.
	n isNil ifTrue: [^nil].
	variables removeKey: (self class optionName: n).
	(self bootOrder includes: n) ifTrue: [variables at: 'BootOrder' put: (self wordBytes: (self bootOrder copyWithout: n))].
	self bootNext = n ifTrue: [variables removeKey: 'BootNext'].
	^n
!
bootNext: anInteger
	variables at: 'BootNext' put: (self wordBytes: {anInteger})
!
rebootInto: anInteger
	"Boot the option anInteger once (BootNext), now."
	self bootNext: anInteger.
	self bootNext = anInteger ifFalse: [^'BootNext did not stick'].
	variables resetCold
!
canBootToFirmwareSetup
	^(variables at: 'OsIndicationsSupported') ifNil: [false] ifNotNil: [:b | b size >= 8 and: [((b uint64At: 1) bitAnd: 1) = 1]]
!
rebootToFirmwareSetup
	| bits |
	bits := (variables at: 'OsIndications') ifNil: [0] ifNotNil: [:b | b size >= 8 ifTrue: [b uint64At: 1] ifFalse: [0]].
	variables at: 'OsIndications' put: ((ByteArray new: 8) uint64At: 1 put: (bits bitOr: 1); yourself).
	variables resetCold
! !

!FirmwareBoot methodsFor: 'private'!
isOptionName: aString
	^aString size = 8 and: [(aString beginsWith: 'Boot') and: [(aString copyFrom: 5 to: 8) allSatisfy: [:c | c isDigit or: [c between: $A and: $F]]]]
!
words: aByteArrayOrNil
	aByteArrayOrNil isNil ifTrue: [^#()].
	^(1 to: aByteArrayOrNil size // 2) collect: [:i | aByteArrayOrNil uint16At: 2 * i - 1]
!
wordBytes: numbers
	| b |
	b := ByteArray new: 2 * numbers size.
	numbers doWithIndex: [:n :i | b uint16At: 2 * i - 1 put: n].
	^b
!
hex: numbers
	numbers isEmpty ifTrue: [^'(empty)'].
	^String streamContents: [:s |
		numbers do: [:n | s nextPutAll: ((n printString: 16) asUppercase padLeftTo: 4 with: $0)] separatedBy: [s nextPut: $,]]
! !
