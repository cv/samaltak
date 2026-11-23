TestCase subclass: #PlatformPrimitiveAdapterTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

!PlatformPrimitiveAdapterTest methodsFor: 'tests'!
testGeneratedMethodsAreOrdinarySimulationPrimitives
	| sim platform entries |
	sim := VMSimulation modules: VMModule vmModules.
	platform := sim module: PlatformPrimitives.
	entries := Dictionary new.
	sim primitiveEntries do: [:entry |
		(entry at: 4) == platform ifTrue: [
			self deny: (entries includesKey: entry first).
			entries at: entry first put: entry]].
	PlatformPrimitives adapterGroups do: [:group |
		group last do: [:row |
			| entry selector method |
			entry := entries at: row first.
			selector := ('prim', row second asString capitalized) asSymbol.
			self assert: (entry at: 2) equals: 2.
			self assert: (entry at: 3) equals: row second asString.
			self assert: (entry at: 5) equals: selector.
			method := PlatformPrimitives compiledMethodAt: selector.
			self assert: (method category beginsWith: 'adapters - ')]].
	"Still callable by saved images, even when current facades use another path."
	#(401 404 406 407 408 409 419 563 566 571) do: [:id | self assert: (entries includesKey: id)]
!
testRegenerationRejectsDuplicateNumbersAndRemovesStaleMethods
	| groups |
	groups := #(('test' ((699 example self yourself receiver ())))).
	[PlatformPrimitiveAdapter install: groups in: self class.
	 self assert: (self class includesSelector: #primExample).
	 self should: [
		PlatformPrimitiveAdapter install: #(('test' ((699 another self yourself receiver ()) (699 duplicate self yourself receiver ())))) in: self class]
		raise: Error.
	 self deny: (self class includesSelector: #primAnother).
	 self assert: (self class includesSelector: #primExample)]
		ensure: [PlatformPrimitiveAdapter install: #() in: self class].
	self deny: (self class includesSelector: #primExample).
	self assert: (self class includesSelector: #testRegenerationRejectsDuplicateNumbersAndRemovesStaleMethods)
! !
