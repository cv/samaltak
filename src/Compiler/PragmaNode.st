ParseNode subclass: #PragmaNode
	instanceVariableNames: 'selector arguments'
	classVariableNames: ''
	package: 'Compiler'!

PragmaNode comment: 'I am a method pragma other than <primitive:>, such as <menu: ''Open'' order: 3>. arguments holds literal values.'!

!PragmaNode class methodsFor: 'instance creation'!
selector: aSymbol arguments: anArray start: startInteger stop: stopInteger
	^self new setSelector: aSymbol arguments: anArray; start: startInteger stop: stopInteger
! !

!PragmaNode methodsFor: 'accessing'!
selector
	^selector
!
arguments
	^arguments
!
setSelector: aSymbol arguments: anArray
	selector := aSymbol.
	arguments := anArray
! !
