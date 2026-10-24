"Samaltak workloads as AWFY benchmarks."!

Benchmark subclass: #Recompile
	instanceVariableNames: 'methods'
	classVariableNames: ''
	package: 'AWFY'!

Benchmark subclass: #TextRendering
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

!Recompile methodsFor: 'benchmarking'!
initialize
	"The methods of Kernel-Collections (both sides, classes and selectors sorted)."
	methods := OrderedCollection new.
	(Smalltalk packageNamed: 'Kernel-Collections') classes do: [:cls |
		{cls. cls class} do: [:behavior |
			(behavior selectors asSortedCollection: [:a :b | a <= b]) do: [:sel |
				methods add: (behavior compiledMethodAt: sel)]]]
!
benchmark
	"Compile every method's source without installing it; answer how many came out as the installed bytecodes."
	| same |
	same := 0.
	methods do: [:each |
		(Compiler compileMethod: each sourceCode in: each methodClass classified: each category) bytecodes = each bytecodes
			ifTrue: [same := same + 1]].
	^same
!
verifyResult: result
	^result = methods size
! !

!TextRendering methodsFor: 'benchmarking'!
benchmark
	"40 lines of code-font text on a 900x500 canvas at scale 2, frozen into a DisplayList."
	| c txt |
	txt := 'The quick brown fox jumps over the lazy dog 0123456789 := ^self'.
	c := Canvas extent: 900 @ 500 scale: 2.
	1 to: 40 do: [:y | c drawString: txt at: 4 @ (y * 12) font: Font code color: Color black].
	^c displayList
!
verifyResult: result
	^result quadCount = 2080
! !
