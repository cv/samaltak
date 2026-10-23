Object subclass: #MenuItem
	instanceVariableNames: 'kind label action keyText description enabled checked submenu name'
	classVariableNames: ''
	package: 'UI-Widgets'!

MenuItem comment: 'I am one entry of a Menu: an item (label, action block, key equivalent text like ''⌘D'', italic description, enabled, checked, optional submenu), a header (#header) or a separator (#separator). enabled and checked may be blocks, evaluated when the menu is shown.'!

!MenuItem methodsFor: 'accessing'!
kind
	^kind ifNil: [#item]
!
kind: aSymbol
	kind := aSymbol
!
isItem
	^self kind == #item
!
isHeader
	^kind == #header
!
isSeparator
	^kind == #separator
!
label
	^label ifNil: ['']
!
label: aString
	label := aString
!
action
	^action
!
action: aBlock
	action := aBlock
!
keyText
	^keyText
!
keyText: aString
	keyText := aString
!
description
	^description
!
description: aString
	description := aString
!
isEnabled
	enabled isNil ifTrue: [^true].
	^enabled isBlock ifTrue: [enabled value == true] ifFalse: [enabled == true]
!
enabled: aBooleanOrBlock
	enabled := aBooleanOrBlock
!
isChecked
	checked isNil ifTrue: [^false].
	^checked isBlock ifTrue: [checked value == true] ifFalse: [checked == true]
!
checked: aBooleanOrBlock
	checked := aBooleanOrBlock
!
hasCheck
	^checked notNil
!
submenu
	^submenu
!
submenu: aMenu
	submenu := aMenu
!
name
	^name
!
name: aString
	name := aString
!
isSelectable
	^self isItem and: [self isEnabled]
! !

!MenuItem methodsFor: 'running'!
run
	"Run my action (the menu view closes first)."
	action isNil ifFalse: [^action value]
! !

!MenuItem methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a MenuItem('; print: self kind; space; nextPutAll: self label; nextPut: $)
! !
