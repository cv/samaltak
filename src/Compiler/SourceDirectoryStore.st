Object subclass: #SourceDirectoryStore
	instanceVariableNames: 'root'
	classVariableNames: ''
	package: 'Compiler'!

SourceDirectoryStore comment: 'I am SourceFiler''s store for a local source directory (root, the src/ that holds packages.txt): paths are file paths under it, written at once. git keeps the change set, so I have none: commit and discard are git''s.

The store protocol (GitHubSourceStore has it too): root, textAt: (nil when there is no file), fileNamesIn: (the names of the files in a directory), at:putText:, removeFileAt:, noteChange: (a description of what changed: ''Integer>>gcd:''), pendingChanges, discardChanges, commit:pullRequest:.'!

!SourceDirectoryStore methodsFor: 'initialization'!
setRoot: aPath
	root := aPath
! !

!SourceDirectoryStore methodsFor: 'files'!
root
	^root
!
textAt: aPath
	^(File exists: aPath) ifTrue: [File readText: aPath] ifFalse: [nil]
!
at: aPath putText: aString
	| dir |
	dir := File directoryOf: aPath.
	(File isDirectory: dir) ifFalse: [Directory create: dir].
	File writeText: aString to: aPath
!
removeFileAt: aPath
	File deleteIfExists: aPath
!
noteChange: aString
	"git shows what changed."
!
fileNamesIn: aPath
	"The names of the files directly in the directory aPath, sorted."
	^(File isDirectory: aPath)
		ifTrue: [(Directory fileNames: aPath) asSortedCollection asArray]
		ifFalse: [#()]
!
at: aPath putBytes: aByteArray
	| dir |
	dir := File directoryOf: aPath.
	(File isDirectory: dir) ifFalse: [Directory create: dir].
	File writeBytes: aByteArray to: aPath
! !

!SourceDirectoryStore methodsFor: 'changes'!
pendingChanges
	^#()
!
discardChanges
	^self error: 'The sources are the files in ', root, ': discard changes with git'
!
commit: aString pullRequest: aBoolean
	^self error: 'The sources are the files in ', root, ': commit with git'
! !

!SourceDirectoryStore methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a SourceDirectoryStore on '; nextPutAll: root
! !

!SourceDirectoryStore class methodsFor: 'instance creation'!
on: aPath
	^self new setRoot: aPath
! !
