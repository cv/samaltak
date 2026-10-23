Object subclass: #Modifiers
	instanceVariableNames: 'bits'
	classVariableNames: 'Cache'
	package: 'UI-Windows'!

Modifiers comment: 'I am the set of modifier keys held during an input event, decoded from the platform bits (shift 1, ctrl 2, alt 4, cmd 8). commandKey is the platform''s command modifier (⌘ on macOS). I am immutable; Modifiers bits: n answers a shared instance.'!

!Modifiers methodsFor: 'private'!
setBits: anInteger
	bits := anInteger
! !

!Modifiers methodsFor: 'accessing'!
bits
	^bits
!
shift
	^(bits bitAnd: 1) ~= 0
!
control
	^(bits bitAnd: 2) ~= 0
!
option
	^(bits bitAnd: 4) ~= 0
!
command
	^(bits bitAnd: 8) ~= 0
!
commandKey
	"The platform's command modifier: ⌘ on macOS."
	^self command
!
isEmpty
	^bits = 0
!
onlyCommandKey
	"Answer whether the command key is the only modifier held (ignoring shift)."
	^self commandKey and: [(bits bitAnd: 6) = 0]
! !

!Modifiers methodsFor: 'comparing'!
= anObject
	^self class == anObject class and: [bits = anObject bits]
!
hash
	^bits hash
! !

!Modifiers methodsFor: 'printing'!
printOn: aStream
	| names |
	names := OrderedCollection new.
	self shift ifTrue: [names add: 'shift'].
	self control ifTrue: [names add: 'control'].
	self option ifTrue: [names add: 'option'].
	self command ifTrue: [names add: 'command'].
	aStream nextPutAll: 'Modifiers('.
	names do: [:each | aStream nextPutAll: each] separatedBy: [aStream space].
	aStream nextPut: $)
! !

!Modifiers class methodsFor: 'instance creation'!
bits: anInteger
	| n |
	n := (anInteger ifNil: [0]) bitAnd: 15.
	Cache isNil ifTrue: [Cache := (0 to: 15) asArray collect: [:i | self basicNew setBits: i]].
	^Cache at: n + 1
!
none
	^self bits: 0
! !
