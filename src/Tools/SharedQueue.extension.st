!SharedQueue methodsFor: '*Tools'!
countItemsSatisfying: aBlock
	"Answer how many queued items satisfy aBlock (without taking them)."
	^accessProtect critical: [(items select: aBlock) size]
! !
