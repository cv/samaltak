!SystemBrowser methodsFor: '*Tools-Agent'!
agentContext
	"The most specific selection is self; retain its browser context as bindings."
	| method receiver |
	method := self selectedMethod.
	receiver := method ifNil: [
		protocol ifNil: [self selectedBehavior]].
	^super agentContext
		receiver: receiver;
		bind: #behavior to: self selectedBehavior;
		bind: #protocol to: protocol;
		bind: #selector to: selector;
		bind: #method to: method;
		bind: #package to: package;
		selection: (code hasSelection ifTrue: [code selectedText]);
		yourself
! !
