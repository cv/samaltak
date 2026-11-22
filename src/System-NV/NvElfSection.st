Object subclass: #NvElfSection
	instanceVariableNames: 'name type flags address offset size link info entrySize data'
	classVariableNames: ''
	package: 'System-NV'!

NvElfSection comment: 'I am one section of an ELF file NvCubin reads: its name, type, flags, address, offset and size in the file, link, info and entry size, and data (a ByteArray; empty for NOBITS sections, which take memory but no file space).'!

!NvElfSection methodsFor: 'accessing'!
name
	^name
!
type
	^type
!
flags
	^flags
!
address
	^address
!
offset
	^offset
!
size
	^size
!
link
	^link
!
info
	^info
!
entrySize
	^entrySize
!
data
	^data
!
isNoBits
	^type = 8
!
printOn: aStream
	aStream nextPutAll: 'NvElfSection('; nextPutAll: name; nextPutAll: ' '; print: size; nextPutAll: ')'
! !

!NvElfSection methodsFor: 'initialization'!
setName: aString type: t flags: f address: a offset: o size: s link: l info: i entrySize: e data: bytes
	name := aString. type := t. flags := f. address := a. offset := o. size := s. link := l. info := i.
	entrySize := e. data := bytes
! !
