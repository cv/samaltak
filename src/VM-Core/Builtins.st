CLibrary subclass: #Builtins
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

Builtins comment: 'The C compiler''s builtins the VM calls (GCC and Clang have them, without a header).'!

!Builtins methodsFor: 'bits'!
ctz: x
	"The number of trailing zero bits of x, which is not 0."
	<c: 'int __builtin_ctz(unsigned x)'>
	^x lowBit - 1
!
ctz64: x
	"The number of trailing zero bits of x, which is not 0."
	<c: 'int __builtin_ctzll(unsigned long long x)'>
	^x lowBit - 1
! !
