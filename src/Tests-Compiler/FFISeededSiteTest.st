TestCase subclass: #FFISeededSiteTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Compiler'!

!FFISeededSiteTest methodsFor: 'fixtures'!
seededSqrt
	<ffiSite>
	^self ffiSite: #(call 'libm' 'sqrt' (f64) f64)
!
anotherSqrt
	<ffiSite>
	^self ffiSite: #(call 'libm' 'sqrt' (f64) f64)
!
unavailableSite
	<ffiSite>
	^self ffiSite: #(call 'vm:core' 'unregistered_seeded_site' () void)
!
unannotatedSite
	^self ffiSite: #unannotated
!
ffiSite: value
	^value
! !

!FFISeededSiteTest methodsFor: 'tests'!
testDistinctSymbolicLiterals
	| binding |
	binding := self seededSqrt.
	self assert: binding class identicalTo: FFIBinding.
	self assert: self seededSqrt identicalTo: binding.
	self deny: self anotherSqrt == binding.
	self assert: self unannotatedSite identicalTo: #unannotated.
	self assert: binding descriptor fourth equals: 6.
	self should: [binding descriptor at: 4 put: 1] raise: Error.
	self should: [binding descriptor third at: 1 put: 1] raise: Error.
	self assert: self unavailableSite tryInvoke0 identicalTo: false
!
testSeededPositionalCall
	Machine hasFirmware ifTrue: [^self].
	self assert: (self seededSqrt tryInvoke1: 81.0) equals: 9.0.
	self assert: (self seededSqrt tryInvoke1: 'invalid') identicalTo: false
!
testCompilerRejectsMalformedSite
	self should: [
		Compiler compile: 'badSeed: runtimeDescriptor <ffiSite> ^self ffiSite: runtimeDescriptor'
			in: self class] raise: SyntaxError.
	self should: [
		Compiler compile: 'badSeed <ffiSite> ^self ffiSite: #(call ''libm'' ''sqrt'' (ptr) f64)'
			in: self class] raise: SyntaxError
! !
