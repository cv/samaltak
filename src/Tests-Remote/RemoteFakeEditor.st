RemoteFakeWidget subclass: #RemoteFakeEditor
	instanceVariableNames: 'selectSpecs'
	classVariableNames: ''
	package: 'Tests-Remote'!

RemoteFakeEditor comment: 'I am a fake editor that records remoteSelect: specs.'!

!RemoteFakeEditor methodsFor: 'remote protocol'!
remoteSelect: aSpec
	selectSpecs isNil ifTrue: [selectSpecs := OrderedCollection new].
	selectSpecs add: aSpec.
	^Dictionary new at: 'selected' put: aSpec; yourself
!
selectSpecs
	^selectSpecs ifNil: [#()]
! !
