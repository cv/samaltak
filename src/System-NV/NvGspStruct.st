NvStruct subclass: #NvGspStruct
	instanceVariableNames: 'layout'
	classVariableNames: ''
	package: 'System-NV'!

NvGspStruct comment: 'I am an NvStruct with an NvLayout: fields by their C names (NvGsp layouts, from NVIDIA''s headers) instead of offsets. at:put: writes an integer little-endian in the field''s size (1, 2, 4 or 8 bytes) or a ByteArray into an array field (shorter ones zero-padded); at: reads an integer field.

	(NvGsp struct: ''GspFwWprMeta'') at: ''magic'' put: NvGsp wprMetaMagic; at: ''magic'''!

!NvGspStruct class methodsFor: 'instance creation'!
layout: anNvLayout
	^(self new: anNvLayout size) setLayout: anNvLayout
! !

!NvGspStruct methodsFor: 'initialization'!
setLayout: anNvLayout
	layout := anNvLayout
! !

!NvGspStruct methodsFor: 'accessing'!
layout
	^layout
!
at: aName put: aValue
	| field |
	field := layout fieldAt: aName.
	aValue isInteger ifFalse: [
		aValue size > field last ifTrue: [^self error: aName, ': ', aValue size printString, ' bytes do not fit in ', field last printString].
		self bytesAt: field first put: aValue.
		^aValue].
	field last = 1 ifTrue: [^self u8At: field first put: aValue].
	field last = 2 ifTrue: [^self u16At: field first put: aValue].
	field last = 4 ifTrue: [^self u32At: field first put: aValue].
	field last = 8 ifTrue: [^self u64At: field first put: aValue].
	^self error: aName, ' is not an integer field'
!
at: aName
	| field |
	field := layout fieldAt: aName.
	field last = 1 ifTrue: [^self u8At: field first].
	field last = 2 ifTrue: [^self u16At: field first].
	field last = 4 ifTrue: [^self u32At: field first].
	field last = 8 ifTrue: [^self u64At: field first].
	^bytes copyFrom: field first + 1 to: field first + field last
! !
