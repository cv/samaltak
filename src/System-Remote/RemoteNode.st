Object subclass: #RemoteNode
	instanceVariableNames: 'widget role label state bounds name text children parent ref'
	classVariableNames: ''
	package: 'System-Remote'!

RemoteNode comment: 'I am one widget in a RemoteSnapshot: what the widget answered to the remote protocol (role, label, state, bounds, name, text), my child nodes (and raw String lines), and the ref assigned to me.'!

!RemoteNode methodsFor: 'accessing'!
widget
	^widget
!
widget: anObject
	widget := anObject
!
role
	^role
!
role: aString
	role := aString
!
label
	^label
!
label: aString
	label := aString
!
state
	^state
!
state: anArray
	state := anArray
!
bounds
	^bounds
!
bounds: aRectangle
	bounds := aRectangle
!
name
	^name
!
name: aString
	name := aString
!
text
	^text
!
text: aString
	text := aString
!
children
	"My child RemoteNodes and raw Strings, in order."
	^children
!
children: aCollection
	children := aCollection
!
childNodes
	^children reject: [:each | each isString]
!
parent
	^parent
!
parent: aNode
	parent := aNode
!
ref
	"My ref without the leading @."
	^ref
!
ref: aString
	ref := aString
!
atRef
	^'@', ref
! !

!RemoteNode methodsFor: 'testing'!
hasState: aString
	^state anySatisfy: [:each | each = aString]
!
isWindow
	^role = 'window'
! !

!RemoteNode methodsFor: 'converting'!
boundsDictionary
	bounds isNil ifTrue: [^nil].
	^Dictionary new
		at: 'x' put: bounds left rounded;
		at: 'y' put: bounds top rounded;
		at: 'w' put: bounds width rounded;
		at: 'h' put: bounds height rounded;
		yourself
!
summary
	"Answer ref, role and label as a Dictionary (for find and state)."
	^Dictionary new
		at: 'ref' put: self atRef;
		at: 'role' put: role;
		at: 'label' put: label;
		yourself
! !

!RemoteNode methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a RemoteNode '; nextPutAll: role.
	ref isNil ifFalse: [aStream nextPutAll: ' @'; nextPutAll: ref]
! !
