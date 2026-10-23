Object subclass: #RemoteFakeWidget
	instanceVariableNames: 'role label state name children bounds text selections'
	classVariableNames: ''
	package: 'Tests-Remote'!

RemoteFakeWidget comment: 'I am a stand-in widget implementing the remote protocol, for testing RemoteSnapshot and RemoteUICommands without a UI.'!

!RemoteFakeWidget methodsFor: 'remote protocol'!
remoteRole
	^role
!
remoteLabel
	^label
!
remoteState
	^state
!
remoteName
	^name
!
remoteChildren
	^children
!
remoteBounds
	^bounds
!
remoteText
	^text
! !

!RemoteFakeWidget methodsFor: 'accessing'!
role: aSymbol
	role := aSymbol
!
label: aString
	label := aString
!
state: anArray
	state := anArray
!
name: aString
	name := aString
!
children
	^children
!
children: aCollection
	children := aCollection asOrderedCollection
!
add: aWidget
	children isNil ifTrue: [children := OrderedCollection new].
	children add: aWidget.
	^aWidget
!
bounds: aRectangle
	bounds := aRectangle
!
text: aString
	text := aString
! !

!RemoteFakeWidget class methodsFor: 'instance creation'!
role: aSymbol label: aString
	^self new role: aSymbol; label: aString; yourself
!
role: aSymbol label: aString name: aName
	^(self role: aSymbol label: aString) name: aName; yourself
! !
