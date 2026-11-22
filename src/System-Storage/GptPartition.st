Object subclass: #GptPartition
	instanceVariableNames: 'number typeGuid uniqueGuid firstLba lastLba attributes name'
	classVariableNames: ''
	package: 'System-Storage'!

GptPartition comment: 'I am an entry of a GUID partition table (UEFI 2.10, 5.3.3) as GptDisk reads it: my number (the entry''s index from 1: the firmware''s HD(n,GPT,...) node, Linux''s nvme0n1pN), the type and unique GUIDs (16 bytes each, as on the disk: GptDisk guidString: makes text of them), the first and last block (both inclusive), the attribute bits and the name (36 UTF-16 characters at most).'!

!GptPartition class methodsFor: 'instance creation'!
number: anInteger bytes: entry
	"The partition of the table entry entry (a ByteArray of at least 128 bytes)."
	| chars |
	chars := WriteStream on: (String new: 36).
	57 to: 127 by: 2 do: [:i | | c |
		c := entry uint16At: i.
		c = 0 ifTrue: [^self number: anInteger entry: entry name: chars contents].
		chars nextPut: (Character value: c)].
	^self number: anInteger entry: entry name: chars contents
!
number: anInteger entry: entry name: aString
	^self new setNumber: anInteger type: (entry copyFrom: 1 to: 16) unique: (entry copyFrom: 17 to: 32)
		first: (entry uint64At: 33) last: (entry uint64At: 41) attributes: (entry uint64At: 49) name: aString
!
number: anInteger type: typeBytes unique: uniqueBytes first: first last: last name: aString
	^self new setNumber: anInteger type: typeBytes unique: uniqueBytes first: first last: last attributes: 0 name: aString
! !

!GptPartition methodsFor: 'initialization'!
setNumber: anInteger type: typeBytes unique: uniqueBytes first: first last: last attributes: bits name: aString
	number := anInteger.
	typeGuid := typeBytes.
	uniqueGuid := uniqueBytes.
	firstLba := first.
	lastLba := last.
	attributes := bits.
	name := aString
! !

!GptPartition methodsFor: 'accessing'!
number
	^number
!
typeGuid
	^typeGuid
!
uniqueGuid
	^uniqueGuid
!
typeString
	^GptDisk guidString: typeGuid
!
uniqueString
	^GptDisk guidString: uniqueGuid
!
firstLba
	^firstLba
!
lastLba
	^lastLba
!
blockCount
	^lastLba - firstLba + 1
!
attributes
	^attributes
!
name
	^name
!
typeName
	"A short name of my type, or its GUID."
	^GptDisk typeNames at: self typeString ifAbsent: [self typeString]
! !

!GptPartition methodsFor: 'testing'!
isUsed
	^typeGuid anySatisfy: [:b | b ~= 0]
!
isEfiSystem
	^self typeString = GptDisk efiSystemType
!
isImageStore
	"Is my type the image store's (make usb-image, the installer)?"
	^self typeString = GptDisk imageStoreType
!
overlapsFrom: first to: last
	^firstLba <= last and: [first <= lastLba]
! !

!GptPartition methodsFor: 'converting'!
entryBytes: size
	"The table entry of size bytes (at least 128) that I am."
	| entry |
	entry := ByteArray new: size.
	entry replaceFrom: 1 to: 16 with: typeGuid startingAt: 1.
	entry replaceFrom: 17 to: 32 with: uniqueGuid startingAt: 1.
	entry uint64At: 33 put: firstLba.
	entry uint64At: 41 put: lastLba.
	entry uint64At: 49 put: attributes.
	(name copyFrom: 1 to: (name size min: 36)) doWithIndex: [:c :i | entry uint16At: 55 + (2 * i) put: (c value min: 16rFFFD)].
	^entry
! !

!GptPartition methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a GptPartition('; print: number; nextPutAll: ', '; print: name; nextPutAll: ', '; nextPutAll: self typeName;
		nextPutAll: ', '; print: firstLba; nextPutAll: '..'; print: lastLba; nextPut: $)
! !
