!SystemBrowser methodsFor: '*Tools-Agent'!
agentContext
	"The selected class (its metaclass on the class side) as self; the selected selector, method and package, and the selected text."
	^super agentContext
		receiver: self selectedBehavior;
		bind: #selector to: selector;
		bind: #method to: self selectedMethod;
		bind: #package to: package;
		selection: (code hasSelection ifTrue: [code selectedText]);
		yourself
! !
