Object subclass: #MountTable
	instanceVariableNames: 'mounts everything loader lock'
	classVariableNames: ''
	package: 'System-Files'!

MountTable comment: 'I put volumes into the file name space for File, FileStream and Directory (File mountTable:): each at a mount point, an absolute path. A path under a mount point is that volume''s, the rest of it the path within the volume (from its /); the deepest mount point wins. The directories above mount points exist (the mount points are their entries, with the entries of a volume mounted above them). Covering everything (coversEverything: true, as FirmwareVolumes does on UEFI) every path is mine: a relative one is relative to /, and / is a directory even with nothing mounted; else only the paths under my mount points are, the others the platform''s.

Volumes are read-only: opening for writing, deleting, renaming and creating directories signal FileError (Read-only file system). Paths are resolved lexically first (. and .. against their names, so .. of a mount point is the directory it is in), then by the volume, which follows its symbolic links (an absolute one from its own root). A loader block (loader:) runs once, before the first lookup: FirmwareVolumes looks for the disks then.

A volume answers (Ext4Volume does; paths are absolute within it):
	stat: path			the file, symbolic links followed: an object (Ext4Inode) answering isDirectory, size, modificationTime (UTC microseconds) and readFrom: offset count: n (up to n of its bytes from the 0-based offset); FileError (FileDoesNotExist) if there is none
	entriesAt: path		the names in a directory

	| t | t := MountTable new. t mount: (Ext4Volume on: (FileBlockDevice on: ''disk.img'')) at: ''/tmp/disk''. File mountTable: t'!

!MountTable methodsFor: 'initialization'!
initialize
	mounts := OrderedCollection new.
	everything := false.
	lock := Semaphore forMutualExclusion
! !

!MountTable methodsFor: 'mounting'!
mount: aVolume at: aPath
	"Mount aVolume at the absolute path aPath (in place of one mounted there)."
	| point |
	(aPath notEmpty and: [aPath first = $/]) ifFalse: [^self error: 'A mount point is an absolute path: ', aPath].
	point := self componentsOf: aPath.
	mounts := (mounts reject: [:m | m key = point]) asOrderedCollection.
	mounts add: point -> aVolume.
	mounts := (mounts asSortedCollection: [:a :b | a key size >= b key size]) asOrderedCollection.
	^aVolume
!
unmount: aPath
	| point |
	point := self componentsOf: aPath.
	mounts := (mounts reject: [:m | m key = point]) asOrderedCollection
!
coversEverything: aBoolean
	"Whether every path is mine (UEFI), or only those under my mount points."
	everything := aBoolean
!
loader: aBlock
	"aBlock value: me, once, before the first lookup."
	loader := aBlock
! !

!MountTable methodsFor: 'accessing'!
mounts
	"The mount points (Strings) -> their volumes, sorted by mount point."
	^((self table collect: [:m | (self pathOf: m key) -> m value]) asSortedCollection: [:a :b | a key <= b key]) asArray
!
volumeAt: aPath
	"The volume mounted at aPath, or nil."
	| point |
	point := self componentsOf: aPath.
	^(self table detect: [:m | m key = point] ifNone: [^nil]) value
!
coversEverything
	^everything
!
covers: aPath
	"Is aPath mine rather than the platform's?"
	everything ifTrue: [^true].
	(aPath notEmpty and: [aPath first = $/]) ifFalse: [^false].
	^(self mountFor: (self componentsOf: aPath)) notNil
!
currentDirectory
	^'/'
! !

!MountTable methodsFor: 'files'!
stat: aPath
	"{exists. isDirectory. size. modification time in UTC microseconds}, as File stat: answers."
	| comps found st |
	comps := self componentsOf: aPath.
	found := self locate: comps.
	found notNil ifTrue: [
		st := found third.
		^Array with: true with: st isDirectory with: st size with: st modificationTime].
	(self isAboveMountPoint: comps) ifTrue: [^Array with: true with: true with: 0 with: 0].
	^Array with: false with: false with: 0 with: 0
!
entries: aPath
	"The names in the directory aPath (without . and ..), sorted."
	| comps found names exists |
	comps := self componentsOf: aPath.
	names := Set new.
	exists := everything and: [comps isEmpty].
	found := self locate: comps.
	found notNil ifTrue: [
		found third isDirectory ifFalse: [^FileError signal: 'Not a directory: ', aPath path: aPath].
		names addAll: ((found first entriesAt: found second) reject: [:n | n = '.' or: [n = '..']]).
		exists := true].
	self table do: [:m |
		(m key size > comps size and: [(m key copyFrom: 1 to: comps size) = comps]) ifTrue: [
			names add: (m key at: comps size + 1).
			exists := true]].
	exists ifFalse: [^FileDoesNotExist signal: 'No such directory: ', aPath path: aPath].
	^names asSortedCollection asArray
!
open: aPath mode: mode
	"A VolumeFile to read aPath (mode 0); FileError for any other mode."
	| found |
	mode = 0 ifFalse: [^self readOnly: aPath].
	found := self locate: (self componentsOf: aPath).
	found isNil ifTrue: [
		^(self isAboveMountPoint: (self componentsOf: aPath))
			ifTrue: [FileError signal: 'Is a directory: ', aPath path: aPath]
			ifFalse: [FileDoesNotExist signal: 'No such file: ', aPath path: aPath]].
	found third isDirectory ifTrue: [^FileError signal: 'Is a directory: ', aPath path: aPath].
	^VolumeFile on: found third name: aPath
!
delete: aPath
	^self readOnly: aPath
!
rename: oldPath to: newPath
	^self readOnly: oldPath
!
createDirectory: aPath
	^self readOnly: aPath
! !

!MountTable methodsFor: 'private'!
table
	"The mounts (mount point components -> volume, the deepest first), after the loader ran."
	loader notNil ifTrue: [
		lock critical: [loader notNil ifTrue: [| block | block := loader. loader := nil. block value: self]]].
	^mounts
!
readOnly: aPath
	^FileError signal: 'Read-only file system: ', aPath path: aPath
!
componentsOf: aPath
	"aPath's names from /, without . and .. (a relative path is relative to /)."
	^self components: (aPath subStrings: '/') from: #()
!
components: names from: base
	| comps |
	comps := OrderedCollection withAll: base.
	names do: [:n |
		n = '..'
			ifTrue: [comps isEmpty ifFalse: [comps removeLast]]
			ifFalse: [(n isEmpty or: [n = '.']) ifFalse: [comps add: n]]].
	^comps asArray
!
pathOf: comps
	comps isEmpty ifTrue: [^'/'].
	^String streamContents: [:s | comps do: [:n | s nextPut: $/; nextPutAll: n]]
!
mountFor: comps
	"The mount (point -> volume) comps are under, or nil."
	^self table detect: [:m | m key size <= comps size and: [(comps copyFrom: 1 to: m key size) = m key]] ifNone: [nil]
!
isAboveMountPoint: comps
	(everything and: [comps isEmpty]) ifTrue: [^true].
	^self table anySatisfy: [:m | m key size > comps size and: [(m key copyFrom: 1 to: comps size) = comps]]
!
locate: comps
	"{volume. path within it. its stat} of the file at comps; nil if there is none."
	| m inner st |
	m := self mountFor: comps.
	m isNil ifTrue: [^nil].
	inner := self pathOf: (comps copyFrom: m key size + 1 to: comps size).
	st := [m value stat: inner] on: FileError do: [:e | e return: nil].
	^st isNil ifTrue: [nil] ifFalse: [Array with: m value with: inner with: st]
! !

!MountTable class methodsFor: 'instance creation'!
new
	^self basicNew initialize
! !
