Object subclass: #Directory
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'System-Files'!

Directory comment: 'I answer questions about directories (class side): entries, creation, the working directory.'!

!Directory class methodsFor: 'accessing'!
current
	"Answer the working directory of the VM process."
	^File primCwd ifNil: [File signalErrorFor: '.']
!
entries: aPath
	"Answer the names in aPath (without . and ..), sorted."
	| names |
	names := File primDirEntries: aPath.
	names isNil ifTrue: [^File signalErrorFor: aPath].
	^names asSortedCollection asArray
!
fileNames: aPath
	^(self entries: aPath) reject: [:n | File isDirectory: (File join: aPath with: n)]
!
directoryNames: aPath
	^(self entries: aPath) select: [:n | File isDirectory: (File join: aPath with: n)]
!
allFilesUnder: aPath
	"Answer the paths of all files in aPath and its subdirectories, in order."
	| paths |
	paths := OrderedCollection new.
	(self entries: aPath) do: [:n | | path |
		path := File join: aPath with: n.
		(File isDirectory: path)
			ifTrue: [paths addAll: (self allFilesUnder: path)]
			ifFalse: [paths add: path]].
	^paths asArray
! !

!Directory class methodsFor: 'testing'!
exists: aPath
	^File isDirectory: aPath
! !

!Directory class methodsFor: 'creating'!
create: aPath
	(File primDirCreate: aPath) isNil ifTrue: [^File signalErrorFor: aPath]
!
ensureExists: aPath
	"Create aPath and any missing parent directories."
	(self exists: aPath) ifTrue: [^self].
	(File directoryOf: aPath) ifNotNil: [:parent |
		(parent ~= aPath and: [parent ~= '.' and: [parent ~= '/']]) ifTrue: [self ensureExists: parent]].
	self create: aPath
! !
