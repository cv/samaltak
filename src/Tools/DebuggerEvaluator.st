TextEditor subclass: #DebuggerEvaluator
	instanceVariableNames: 'placeholder'
	classVariableNames: ''
	package: 'Tools'!

DebuggerEvaluator comment: 'I am the small evaluator under a Debugger inspector: a TextEditor that shows a muted italic placeholder (evaluate in this frame · temps are live) while I am empty.'!

!DebuggerEvaluator methodsFor: 'accessing'!
placeholder: aString
	placeholder := aString.
	self invalidate
! !

!DebuggerEvaluator methodsFor: 'drawing'!
drawSelfOn: aCanvas
	super drawSelfOn: aCanvas.
	(self text isEmpty and: [placeholder notNil]) ifTrue: [
		aCanvas drawString: placeholder at: (self theme metric: #editorPaddingX) @ ((self theme metric: #editorPaddingY) + 2)
			font: (self theme font: #smallItalic) color: (self theme color: #ink4)]
! !
