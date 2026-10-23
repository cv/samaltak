Object subclass: #DebuggerField
	instanceVariableNames: 'name value kind detail'
	classVariableNames: ''
	package: 'Tools'!

DebuggerField comment: 'I am one row of a Debugger inspector: a name, a value and a kind (#self #field #context #arg #temp #outer #return #watched, or #derived: a String computed from the receiver, shown as is). detail, when set, is the text shown in the value pane instead of the value''s printString (thisContext describes the frame).'!

!DebuggerField methodsFor: 'accessing'!
name
	^name
!
value
	^value
!
kind
	^kind
!
detail
	^detail
!
detail: aString
	detail := aString
!
key
	^name
!
valueText
	"The text of the value pane."
	detail isNil ifFalse: [^detail].
	kind == #derived ifTrue: [^value].
	^[value printStringLimitedTo: 20000] on: Error do: [:e | e return: '<error printing: ', e messageText asString, '>']
!
shortText
	"The muted text at the right of the row."
	kind == #context ifTrue: [^value printString].
	kind == #derived ifTrue: [^value].
	^[value printStringLimitedTo: 200] on: Error do: [:e | e return: '<error printing>']
! !

!DebuggerField methodsFor: 'private'!
setName: aString value: anObject kind: aSymbol
	name := aString.
	value := anObject.
	kind := aSymbol
! !

!DebuggerField methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a DebuggerField('; nextPutAll: name; nextPut: $)
! !

!DebuggerField class methodsFor: 'instance creation'!
name: aString value: anObject kind: aSymbol
	^self new setName: aString value: anObject kind: aSymbol
! !
