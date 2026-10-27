Object subclass: #FileBrowserEntry
	instanceVariableNames: 'path name isDirectory size modified kind lines'
	classVariableNames: ''
	package: 'Tools'!

FileBrowserEntry comment: 'I am a row of the File Browser: a folder, or a file with its size, modification time, kind (#smalltalk .st, #c .c .h, #text; #binary: a NUL byte in its first 8 KB) and, for a text file of at most maxTextBytes, its lines (as an editor counts them: the line feeds, and a last line without one). Listing a folder reads its files for kind and lines.

	(FileBrowserEntry on: ''vm/gen/interpreter.c'') lines'!

!FileBrowserEntry methodsFor: 'initialization'!
setPath: aPath stat: anArray
	path := aPath.
	name := File baseName: aPath.
	isDirectory := anArray at: 2.
	size := anArray at: 3.
	modified := anArray at: 4.
	isDirectory ifFalse: [self classify]
!
classify
	"Unreadable files count as binary."
	| binary |
	binary := [(self readBytes: (size min: 8192)) includes: 0] on: FileError do: [:e | e return: true].
	binary ifTrue: [kind := #binary. ^self].
	kind := self class kindOfExtension: (File extensionOf: name).
	size <= self class maxTextBytes ifTrue: [
		lines := [self class lineCountOf: (self readBytes: size)] on: FileError do: [:e | e return: nil]]
! !

!FileBrowserEntry methodsFor: 'accessing'!
path
	^path
!
name
	^name
!
size
	^size
!
modificationTime
	"Microseconds since 1970, UTC."
	^modified
!
kind
	"#directory, #smalltalk, #c, #text or #binary."
	^isDirectory ifTrue: [#directory] ifFalse: [kind]
!
lines
	"The text's lines, or nil (a folder, a binary or too large a file)."
	^lines
!
isDirectory
	^isDirectory
!
isBinary
	^self kind == #binary
! !

!FileBrowserEntry methodsFor: 'reading'!
readBytes: count
	"The first count bytes. Nothing is read for none: a FIFO or a device (size 0) would block the VM."
	count = 0 ifTrue: [^ByteArray new].
	^FileStream readOnlyFileNamed: path do: [:s | s binary. s next: count]
!
text
	"The file decoded from UTF-8; of a larger file than maxTextBytes, that much up to its last line feed."
	| bytes cut |
	bytes := self readBytes: (size min: self class maxTextBytes).
	size > self class maxTextBytes ifTrue: [
		cut := bytes size.
		[cut > 0 and: [(bytes at: cut) ~= 10]] whileTrue: [cut := cut - 1].
		bytes := bytes copyFrom: 1 to: cut].
	^(self class isAscii: bytes) ifTrue: [bytes asString] ifFalse: [bytes utf8Decoded]
!
isTruncated
	^size > self class maxTextBytes
! !

!FileBrowserEntry methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a FileBrowserEntry('; nextPutAll: path; nextPut: $)
! !

!FileBrowserEntry class methodsFor: 'instance creation'!
on: aPath
	^self new setPath: aPath stat: (File stat: aPath)
! !

!FileBrowserEntry class methodsFor: 'files'!
maxTextBytes
	"Larger text files show this much, without their lines counted."
	^2097152
!
kindOfExtension: aString
	aString = 'st' ifTrue: [^#smalltalk].
	(aString = 'c' or: [aString = 'h']) ifTrue: [^#c].
	^#text
!
isAscii: aByteArray
	1 to: aByteArray size do: [:i | (aByteArray at: i) >= 128 ifTrue: [^false]].
	^true
!
lineCountOf: aByteArray
	| n |
	n := 0.
	1 to: aByteArray size do: [:i | (aByteArray at: i) == 10 ifTrue: [n := n + 1]].
	(aByteArray notEmpty and: [aByteArray last ~= 10]) ifTrue: [n := n + 1].
	^n
! !
