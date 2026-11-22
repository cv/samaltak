TestCase subclass: #PackageFileInTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Compiler'!

PackageFileInTest comment: 'Tests for Compiler fileInPackage: a package directory loads with every class defined before any method compiles, superclasses first whatever the file names, extensions last, and class-side initialize sent.'!

!PackageFileInTest methodsFor: 'tests'!
testFileInPackage
	| dir classes |
	dir := self scratchDirectory.
	File writeText: 'PackageProbeBase subclass: #APackageProbeSub
	instanceVariableNames: ''''
	classVariableNames: ''''
	package: ''Package-Probe''!!

APackageProbeSub comment: ''A subclass in a file sorted before its superclass''''s.''!!

!!APackageProbeSub methodsFor: ''accessing''!!
partner
	^PackageProbeBase
!! !!
' to: dir / 'APackageProbeSub.st'.
	File writeText: 'Object subclass: #PackageProbeBase
	instanceVariableNames: ''''
	classVariableNames: ''Initialized''
	package: ''Package-Probe''!!

!!PackageProbeBase class methodsFor: ''class initialization''!!
initialize
	Initialized := true
!!
initialized
	^Initialized
!! !!

!!PackageProbeBase methodsFor: ''accessing''!!
answer
	^42
!! !!
' to: dir / 'PackageProbeBase.st'.
	File writeText: '!!Object methodsFor: ''*Package-Probe''!!
packageProbeExtension
	^APackageProbeSub new answer
!! !!
' to: dir / 'Object.extension.st'.
	classes := Compiler fileInPackage: dir.
	[self assert: (classes collect: [:c | c name asString]) equals: #('PackageProbeBase' 'APackageProbeSub').
	 self assert: classes last superclass == classes first.
	 self assert: classes last new partner == classes first.
	 self assert: nil packageProbeExtension equals: 42.
	 self assert: classes first initialized.
	 self assert: classes first packageName equals: 'Package-Probe']
		ensure: [
			Object removeSelector: #packageProbeExtension.
			classes reverseDo: [:c | c removeFromSystem]]
!
testClassDefinitionIn
	self assert: (Compiler classDefinitionIn: 'Object subclass: #Foo instanceVariableNames: '''' classVariableNames: '''' package: ''P''') equals: #('Object' 'Foo').
	self assert: (Compiler classDefinitionIn: 'Foo comment: ''x''') isNil.
	self assert: (Compiler classDefinitionIn: 'Smalltalk at: #Bar put: 3') isNil
! !
