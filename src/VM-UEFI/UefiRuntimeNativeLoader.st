UefiModule subclass: #UefiRuntimeNativeLoader
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

!UefiRuntimeNativeLoader class methodsFor: 'declaring'!
replaces
	^RuntimeNativeLoader
! !

!UefiRuntimeNativeLoader methodsFor: 'grants'!
configure
	<function>
	<returns: 'bool'>
	^true
!
lookupLibrary: library length: libLength symbol: symbol length: symLength types: types count: n result: result
	<function>
	<var: #library type: 'const uint8_t *'>
	<var: #libLength type: 'size_t'>
	<var: #symbol type: 'const uint8_t *'>
	<var: #symLength type: 'size_t'>
	<var: #types type: 'const uint8_t *'>
	<var: #n type: 'int32_t'>
	<var: #result type: 'int32_t'>
	<returns: 'void *'>
	^self null
! !
