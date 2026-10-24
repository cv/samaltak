RemoteFakeWidget subclass: #RemoteFakeEditor
	instanceVariableNames: 'selectSpecs'
	classVariableNames: ''
	package: 'Tests-Remote'!

RemoteFakeEditor comment: 'I am a fake editor that records remoteSelect: specs and answers remotePointAt: ''x,y'' as that offset from my top-left.'!

!RemoteFakeEditor methodsFor: 'remote protocol'!
remoteSelect: aSpec
	selectSpecs isNil ifTrue: [selectSpecs := OrderedCollection new].
	selectSpecs add: aSpec.
	^Dictionary new at: 'selected' put: aSpec; yourself
!
selectSpecs
	^selectSpecs ifNil: [#()]
!
remotePointAt: aSpec
	| parts |
	parts := aSpec substrings: ','.
	parts size = 2 ifFalse: [^nil].
	^self remoteBounds origin + (parts first asNumber @ parts last asNumber)
! !
