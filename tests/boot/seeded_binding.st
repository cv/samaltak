Object subclass: #BootBindingFixture
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Boot'!

!BootBindingFixture methodsFor: 'fixtures'!
seededSite
	<ffiSite>
	^self ffiSite: #(call 'vm:core' 'core_getenv_text' (cText) ownedText)
! !
