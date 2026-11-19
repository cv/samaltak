CLibrary subclass: #LowtalkSampleLibrary
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

LowtalkSampleLibrary comment: 'A C library for LowtalkTest: LowtalkLibraryUser calls it, LowtalkLibraryOnUefi implements it for #uefi.'!

!LowtalkSampleLibrary class methodsFor: 'declaring'!
headers
	^#('<sample_library.h>')
! !

!LowtalkSampleLibrary methodsFor: 'functions'!
twice: x
	<c: 'int sample_twice(int x)'>
	^x * 2
! !

VMModule subclass: #LowtalkLibraryUser
	instanceVariableNames: 'library'
	classVariableNames: ''
	package: 'Tests-VM'!

LowtalkLibraryUser comment: 'A module for every OS that calls LowtalkSampleLibrary (LowtalkTest).'!

!LowtalkLibraryUser class methodsFor: 'declaring'!
declarations
	^#((library LowtalkSampleLibrary))
! !

!LowtalkLibraryUser methodsFor: 'running'!
answer
	<export>
	^library twice: 21
! !

VMModule subclass: #LowtalkLibraryOnUefi
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

LowtalkLibraryOnUefi comment: 'LowtalkSampleLibrary in Lowtalk, for #uefi (LowtalkTest).'!

!LowtalkLibraryOnUefi class methodsFor: 'declaring'!
targetOS
	^#uefi
!
implementsLibrary
	^LowtalkSampleLibrary
! !

!LowtalkLibraryOnUefi methodsFor: 'functions'!
twice: x
	<function>
	<var: #x type: 'int'>
	<returns: 'int'>
	^x + x
! !
