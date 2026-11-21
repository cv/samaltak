Object subclass: #Ext4DirectoryEntry
	instanceVariableNames: 'rawName name inodeNumber fileTypeCode'
	classVariableNames: ''
	package: 'System-Storage'!

Ext4DirectoryEntry comment: 'I am an entry of an ext2/3/4 directory (Ext4Volume directoryEntriesAt:, Ext4Inode directoryEntries): name (a String, decoded from UTF-8), rawName (its bytes as a ByteString), inodeNumber, fileType (#file #directory #symlink #charDevice #blockDevice #fifo #socket, or nil where the file system records no types: ask the inode).'!

!Ext4DirectoryEntry methodsFor: 'accessing'!
name
	name isNil ifTrue: [name := rawName asByteArray utf8Decoded].
	^name
!
rawName
	^rawName
!
inodeNumber
	^inodeNumber
!
fileType
	(fileTypeCode isNil or: [fileTypeCode = 0]) ifTrue: [^nil].
	^#(#file #directory #charDevice #blockDevice #fifo #socket #symlink) at: fileTypeCode ifAbsent: [nil]
!
isDirectory
	"Whether the entry says it is a directory (false where the file system records no types)."
	^fileTypeCode = 2
!
isDotOrDotDot
	^rawName = '.' or: [rawName = '..']
! !

!Ext4DirectoryEntry methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an Ext4DirectoryEntry('; print: self name; space; print: inodeNumber; nextPut: $)
! !

!Ext4DirectoryEntry methodsFor: 'private'!
setRawName: aByteString inodeNumber: anInteger fileTypeCode: aCode
	rawName := aByteString.
	inodeNumber := anInteger.
	fileTypeCode := aCode
! !

!Ext4DirectoryEntry class methodsFor: 'instance creation'!
rawName: aByteString inodeNumber: anInteger fileTypeCode: aCode
	^self new setRawName: aByteString inodeNumber: anInteger fileTypeCode: aCode
! !
