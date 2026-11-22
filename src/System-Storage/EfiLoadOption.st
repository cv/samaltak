Object subclass: #EfiLoadOption
	instanceVariableNames: 'attributes description devicePath optionalData'
	classVariableNames: ''
	package: 'System-Storage'!

EfiLoadOption comment: 'I am the value of a Boot#### variable, an EFI_LOAD_OPTION (UEFI 2.10, 3.1.3): attributes (1, LOAD_OPTION_ACTIVE), the description the firmware''s boot menu shows, a device path (its nodes and the end node) and optional data (the application''s LoadOptions). description:partition:file: makes the short form efibootmgr writes and the firmware expands: the EFI system partition''s HD(number, GPT, unique GUID) node (start and size from its GPT entry), then the file''s path on it.

	(EfiLoadOption description: ''Samaltak'' partition: espPartition file: ''\EFI\samaltak\BOOTAA64.EFI'') bytes
	(EfiLoadOption fromBytes: (FirmwareVariables current at: ''Boot0001'')) filePath'!

!EfiLoadOption class methodsFor: 'instance creation'!
description: aString devicePath: pathBytes
	^self new setAttributes: 1 description: aString devicePath: pathBytes optionalData: ByteArray new
!
description: aString partition: aGptPartition file: aPath
	^self description: aString devicePath: (self hardDriveNode: aGptPartition), (self filePathNode: aPath), self endNode
!
fromBytes: bytes
	"The load option bytes hold, or nil if they are not one."
	| pathLength i description |
	(bytes isNil or: [bytes size < 8]) ifTrue: [^nil].
	pathLength := bytes uint16At: 5.
	i := 7.
	description := WriteStream on: (String new: 32).
	[i + 1 <= bytes size and: [(bytes uint16At: i) ~= 0]] whileTrue: [
		description nextPut: (Character value: (bytes uint16At: i)).
		i := i + 2].
	i := i + 2.
	i + pathLength - 1 <= bytes size ifFalse: [^nil].
	^self new setAttributes: (bytes uint32At: 1) description: description contents
		devicePath: (bytes copyFrom: i to: i + pathLength - 1)
		optionalData: (bytes copyFrom: i + pathLength to: bytes size)
! !

!EfiLoadOption class methodsFor: 'device paths'!
hardDriveNode: aGptPartition
	"HD(n,GPT,guid,start,size): media device path, hard drive (4, 1), 42 bytes."
	| node |
	node := ByteArray new: 42.
	node at: 1 put: 4; at: 2 put: 1; uint16At: 3 put: 42.
	node uint32At: 5 put: aGptPartition number.
	node uint64At: 9 put: aGptPartition firstLba.
	node uint64At: 17 put: aGptPartition blockCount.
	node replaceFrom: 25 to: 40 with: aGptPartition uniqueGuid startingAt: 1.
	node at: 41 put: 2; at: 42 put: 2.
	^node
!
filePathNode: aPath
	"A file path node (4, 4): the path in UCS-2 with its NUL, backslashes for slashes."
	| text node |
	text := (aPath copyReplaceAll: '/' with: '\'), (String with: (Character value: 0)).
	node := ByteArray new: 4 + (2 * text size).
	node at: 1 put: 4; at: 2 put: 4; uint16At: 3 put: node size.
	text doWithIndex: [:c :i | node uint16At: 3 + (2 * i) put: (c value min: 16rFFFD)].
	^node
!
endNode
	^#[16r7F 16rFF 4 0]
! !

!EfiLoadOption methodsFor: 'initialization'!
setAttributes: bits description: aString devicePath: pathBytes optionalData: dataBytes
	attributes := bits.
	description := aString.
	devicePath := pathBytes.
	optionalData := dataBytes
! !

!EfiLoadOption methodsFor: 'accessing'!
attributes
	^attributes
!
isActive
	^(attributes bitAnd: 1) = 1
!
description
	^description
!
devicePath
	^devicePath
!
optionalData
	^optionalData
!
bytes
	"The variable's value."
	| out |
	out := ByteArray new: 6 + (2 * (description size + 1)) + devicePath size + optionalData size.
	out uint32At: 1 put: attributes.
	out uint16At: 5 put: devicePath size.
	description doWithIndex: [:c :i | out uint16At: 5 + (2 * i) put: (c value min: 16rFFFD)].
	out replaceFrom: 7 + (2 * (description size + 1)) to: 6 + (2 * (description size + 1)) + devicePath size with: devicePath startingAt: 1.
	optionalData isEmpty ifFalse: [out replaceFrom: out size - optionalData size + 1 to: out size with: optionalData startingAt: 1].
	^out
! !

!EfiLoadOption methodsFor: 'device path'!
nodesDo: aBlock
	"aBlock value: type value: subtype value: the node's bytes after its 4-byte header, for each node before the end."
	| i |
	i := 1.
	[i + 3 <= devicePath size] whileTrue: [| len |
		len := devicePath uint16At: i + 2.
		(len < 4 or: [(devicePath at: i) = 16r7F]) ifTrue: [^self].
		aBlock value: (devicePath at: i) value: (devicePath at: i + 1) value: (devicePath copyFrom: i + 4 to: (i + len - 1 min: devicePath size)).
		i := i + len]
!
filePath
	"The text of the file path nodes, joined; nil if there are none."
	| path |
	path := nil.
	self nodesDo: [:type :subtype :data | (type = 4 and: [subtype = 4]) ifTrue: [| s |
		s := WriteStream on: (String new: 64).
		1 to: data size - 1 by: 2 do: [:k | | c | c := data uint16At: k. c = 0 ifFalse: [s nextPut: (Character value: c)]].
		path := path isNil
			ifTrue: [s contents]
			ifFalse: [(path endsWith: '\') ifTrue: [path, s contents] ifFalse: [path, '\', s contents]]]].
	^path
!
hardDriveNode
	"The bytes of the first hard drive node after its header, or nil."
	self nodesDo: [:type :subtype :data | (type = 4 and: [subtype = 1 and: [data size >= 38]]) ifTrue: [^data]].
	^nil
!
partitionNumber
	^self hardDriveNode ifNotNil: [:d | d uint32At: 1]
!
partitionGuid
	"The unique GUID of a GPT partition the hard drive node names (16 bytes), else nil."
	^self hardDriveNode ifNotNil: [:d | (d at: 38) = 2 ifTrue: [d copyFrom: 21 to: 36] ifFalse: [nil]]
!
isFile: aPath
	"Does my file path name aPath (case and slashes aside)?"
	^self filePath notNil and: [(self filePath copyReplaceAll: '/' with: '\') asLowercase = (aPath copyReplaceAll: '/' with: '\') asLowercase]
! !

!EfiLoadOption methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an EfiLoadOption('; print: description.
	self partitionNumber ifNotNil: [:n | aStream nextPutAll: ', partition '; print: n].
	self filePath ifNotNil: [:p | aStream nextPutAll: ', '; nextPutAll: p].
	self isActive ifFalse: [aStream nextPutAll: ', inactive'].
	aStream nextPut: $)
! !
