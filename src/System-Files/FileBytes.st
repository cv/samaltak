Object subclass: #FileBytes
	instanceVariableNames: 'path size stamp pages'
	classVariableNames: ''
	package: 'System-Files'!

FileBytes comment: 'I am the bytes of a file, read a page (4 KB) at a time when first needed and kept: what mapping a file gives a C program (FreeType maps its fonts), in Smalltalk. A large file of which a program reads little, such as a font with ten thousand glyphs of which it draws fifty, costs only the pages read. I answer at:, size, copyFrom:to:, the big-endian readers and contents as a ByteArray does (1-based), so a reader written against a ByteArray reads me unchanged.

	bytes := FileBytes on: ''/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf''.
	bytes uint32BigEndianAt: 1.
	bytes residentSize          "the bytes read so far"

The file must not change while I am in use: a page read from a file whose modification time changed signals an error. The pages read stay valid across image restarts (the file is opened for each page read).'!

!FileBytes methodsFor: 'initialization'!
setPath: aPath
	path := aPath.
	size := File sizeOf: aPath.
	stamp := File modificationTime: aPath.
	pages := Array new: size + self class pageSize - 1 // self class pageSize
! !

!FileBytes methodsFor: 'accessing'!
path
	^path
!
size
	^size
!
at: index
	| page |
	(index between: 1 and: size) ifFalse: [^self errorSubscriptBounds: index].
	page := pages at: index - 1 // self class pageSize + 1.
	page isNil ifTrue: [page := self readPage: index - 1 // self class pageSize + 1].
	^page at: index - 1 \\ self class pageSize + 1
!
uint16BigEndianAt: index
	^((self at: index) bitShift: 8) + (self at: index + 1)
!
int16BigEndianAt: index
	| v |
	v := self uint16BigEndianAt: index.
	^v >= 16r8000 ifTrue: [v - 16r10000] ifFalse: [v]
!
uint32BigEndianAt: index
	^((self uint16BigEndianAt: index) bitShift: 16) + (self uint16BigEndianAt: index + 2)
!
copyFrom: start to: stop
	"A ByteArray of the bytes start..stop."
	| result |
	result := ByteArray new: (stop - start + 1 max: 0).
	start to: stop do: [:i | result at: i - start + 1 put: (self at: i)].
	^result
!
contents
	"All my bytes as a ByteArray (read from the file at once)."
	| result |
	result := File readBytes: path.
	result size = size ifFalse: [^self error: path, ' changed while in use'].
	^result
!
residentSize
	"How many of my bytes have been read."
	^(pages count: [:each | each notNil]) * self class pageSize min: size
! !

!FileBytes methodsFor: 'testing'!
isEmpty
	^size = 0
! !

!FileBytes methodsFor: 'private'!
readPage: n
	| stream bytes |
	(File modificationTime: path) = stamp ifFalse: [^self error: path, ' changed while in use'].
	stream := FileStream readOnlyFileNamed: path.
	[stream binary.
	 stream position: n - 1 * self class pageSize.
	 bytes := stream nextBytes: self class pageSize] ensure: [stream close].
	pages at: n put: bytes.
	^bytes
! !

!FileBytes methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a FileBytes('; nextPutAll: path; nextPutAll: ', '; print: self residentSize; nextPutAll: ' of '; print: size; nextPutAll: ' bytes read)'
! !

!FileBytes class methodsFor: 'instance creation'!
on: aPath
	^self new setPath: aPath
!
pageSize
	^4096
! !
