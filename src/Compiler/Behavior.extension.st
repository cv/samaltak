!Behavior methodsFor: '*Compiler'!
isContextClass
	"My instances are Contexts: the compiler reads their sender, pc and stackp and stores into their instance variables with the bytecodes the VM mediates for a Context married to a frame."
	^self includesBehavior: Context
! !
