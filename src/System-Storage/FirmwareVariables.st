Object subclass: #FirmwareVariables
	instanceVariableNames: 'firmware runtime lock'
	classVariableNames: ''
	package: 'System-Storage'!

FirmwareVariables comment: 'I am the firmware''s variables (UEFI 2.10, 8.2) through its runtime services: GetVariable, GetNextVariableName, SetVariable, and ResetSystem. Names are Strings, vendor GUIDs text (FirmwareVariables globalGuid, EFI_GLOBAL_VARIABLE, for Boot####, BootOrder, BootNext, OsIndications), values ByteArrays. at:put: writes non-volatile, boot service and runtime access (NV+BS+RT: 7), as the boot manager''s variables are. FirmwareVariables current is nil on an operating system.

	FirmwareVariables current at: ''BootOrder''
	FirmwareVariables current names'!

!FirmwareVariables class methodsFor: 'instance creation'!
current
	"The firmware's variables, or nil without a firmware."
	^Firmware current ifNotNil: [:f | self new setFirmware: f]
! !

!FirmwareVariables class methodsFor: 'constants'!
globalGuid
	"EFI_GLOBAL_VARIABLE."
	^'8be4df61-93ca-11d2-aa0d-00e098032b8c'
!
bootAttributes
	"EFI_VARIABLE_NON_VOLATILE | BOOTSERVICE_ACCESS | RUNTIME_ACCESS."
	^7
! !

!FirmwareVariables methodsFor: 'initialization'!
setFirmware: aFirmware
	firmware := aFirmware.
	runtime := Machine uint64At: firmware systemTable + 88.
	lock := Semaphore forMutualExclusion
! !

!FirmwareVariables methodsFor: 'reading'!
at: aName
	^self at: aName guid: self class globalGuid
!
at: aName guid: aGuidString
	"The value of the variable, or nil if there is none."
	^(self getVariable: aName guid: aGuidString) ifNotNil: [:pair | pair last]
!
attributesOf: aName guid: aGuidString
	^(self getVariable: aName guid: aGuidString) ifNotNil: [:pair | pair first]
!
names
	"Every variable: Associations of its name and its vendor GUID's text (GetNextVariableName)."
	| result |
	result := OrderedCollection new.
	lock critical: [| capacity name size guid status |
		capacity := 2048.
		name := Machine allocate: capacity.
		size := Machine allocate: 8.
		guid := Machine allocate: 16.
		[[Machine uint64At: size put: capacity.
			status := Machine call: (self function: 80) with: size with: name with: guid.
			status = 16r8000000000000005 ifTrue: [| bigger |
				capacity := (Machine uint64At: size) max: capacity * 2.
				bigger := Machine allocate: capacity.
				Machine copy: 2048 from: name at: 0 to: bigger at: 0.
				Machine free: name.
				name := bigger.
				Machine uint64At: size put: capacity.
				status := Machine call: (self function: 80) with: size with: name with: guid].
			firmware isError: status] whileFalse: [
				result add: (FirmwareBlockDevice utf16At: name maxCharacters: capacity // 2) -> (FirmwareBlockDevice guidAt: guid)]]
			ensure: [Machine free: name; free: size; free: guid]].
	^result asArray
! !

!FirmwareVariables methodsFor: 'writing'!
at: aName put: aByteArray
	^self at: aName guid: self class globalGuid put: aByteArray attributes: self class bootAttributes
!
at: aName guid: aGuidString put: aByteArray attributes: bits
	"Set the variable (SetVariable); an empty value deletes it. Error if the firmware refuses."
	| status |
	status := self setVariable: aName guid: aGuidString attributes: bits bytes: aByteArray.
	(firmware isError: status) ifTrue: [
		^self error: 'SetVariable ', aName, ' failed (status 16r', (status printString: 16), ')'].
	^aByteArray
!
removeKey: aName
	^self remove: aName guid: self class globalGuid
!
remove: aName guid: aGuidString
	"Delete the variable if it is there."
	(self getVariable: aName guid: aGuidString) ifNotNil: [:pair |
		self at: aName guid: aGuidString put: ByteArray new attributes: pair first]
! !

!FirmwareVariables methodsFor: 'resetting'!
reset: aType
	"ResetSystem: 0 cold, 1 warm, 2 shutdown. Does not return."
	Machine call: (self function: 104) with: aType with: 0 with: 0 with: 0
!
resetCold
	self reset: 0
! !

!FirmwareVariables methodsFor: 'private'!
function: offset
	^Machine uint64At: runtime + offset
!
ucs2: aString
	"A NUL-terminated UCS-2 copy of aString outside the heap (the caller frees it)."
	| p |
	p := Machine allocate: aString size + 1 * 2.
	aString doWithIndex: [:c :i | Machine uint16At: p + (2 * (i - 1)) put: (c value min: 16rFFFD)].
	^p
!
getVariable: aName guid: aGuidString
	"{attributes. value} or nil."
	^lock critical: [| name attrs size data status result |
		name := self ucs2: aName.
		attrs := Machine allocate: 8.
		size := Machine allocate: 8.
		data := 0.
		[Machine uint64At: size put: 0.
		status := Machine call: (self function: 72) with: name with: (firmware guid: aGuidString) with: attrs with: size with: 0.
		status = 16r8000000000000005 ifTrue: [
			data := Machine allocate: ((Machine uint64At: size) max: 1).
			status := Machine call: (self function: 72) with: name with: (firmware guid: aGuidString) with: attrs with: size with: data].
		result := (firmware isError: status) ifFalse: [
			{Machine uint32At: attrs. data = 0 ifTrue: [ByteArray new] ifFalse: [Machine bytesAt: data count: (Machine uint64At: size)]}]]
			ensure: [Machine free: name; free: attrs; free: size. data = 0 ifFalse: [Machine free: data]].
		result]
!
setVariable: aName guid: aGuidString attributes: bits bytes: aByteArray
	^lock critical: [| name data |
		name := self ucs2: aName.
		data := Machine allocate: (aByteArray size max: 1).
		Machine bytesAt: data put: aByteArray.
		[Machine call: (self function: 88) with: name with: (firmware guid: aGuidString) with: bits with: aByteArray size with: data]
			ensure: [Machine free: name; free: data]]
! !
