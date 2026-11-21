Object subclass: #MountTableTestVolume
	instanceVariableNames: 'nodes'
	classVariableNames: ''
	package: 'Tests-Kernel'!

MountTableTestVolume comment: 'I am a volume in memory for MountTableTest, with the protocol MountTable expects of a volume (stat:, entriesAt:): directories and files (MountTableTestStat) at absolute paths.'!

!MountTableTestVolume methodsFor: 'initialization'!
initialize
	nodes := Dictionary new.
	nodes at: '/' put: (MountTableTestStat data: nil)
! !

!MountTableTestVolume methodsFor: 'building'!
directory: aPath
	nodes at: aPath put: (MountTableTestStat data: nil)
!
file: aPath bytes: aByteArray
	nodes at: aPath put: (MountTableTestStat data: aByteArray)
!
file: aPath text: aString
	self file: aPath bytes: aString utf8Encoded
! !

!MountTableTestVolume methodsFor: 'volume'!
stat: aPath
	^nodes at: aPath ifAbsent: [FileDoesNotExist signal: 'No such file: ', aPath path: aPath]
!
entriesAt: aPath
	| prefix |
	(self stat: aPath) isDirectory ifFalse: [^FileError signal: 'Not a directory: ', aPath path: aPath].
	prefix := aPath = '/' ifTrue: [aPath] ifFalse: [aPath, '/'].
	^(nodes keys select: [:p | p size > prefix size and: [(p beginsWith: prefix) and: [((p copyFrom: prefix size + 1 to: p size) includes: $/) not]]])
		asArray collect: [:p | p copyFrom: prefix size + 1 to: p size]
! !

!MountTableTestVolume class methodsFor: 'instance creation'!
new
	^self basicNew initialize
! !
