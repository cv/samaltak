ToolTextEditor subclass: #FileViewer
	instanceVariableNames: 'numbered'
	classVariableNames: ''
	package: 'Tools'!

FileViewer comment: 'I am the File Browser''s viewer: a read-only text editor with line numbers in a gutter (each line''s at its first row; the selected lines'' in ink), highlighting Smalltalk (#smalltalk: the Scanner) or C (#c: CSourceScanner) or nothing. I draw only the rows shown, so a long file scrolls as a short one. Remote control: state top= (the first line shown), the selection and the lines shown as text.

	viewer show: ''int x;'' kind: #c'!

!FileViewer methodsFor: 'initialization'!
initialize
	super initialize.
	numbered := false.
	self readOnly: true
! !

!FileViewer methodsFor: 'showing'!
show: aString kind: aSymbol
	"Show aString from its first line: #smalltalk and #c highlighted and numbered, #text numbered, anything else (#binary: a hex dump) plain."
	highlighter scanner: (aSymbol == #c ifTrue: [CSourceScanner] ifFalse: [nil]).
	self highlighting: (aSymbol == #smalltalk or: [aSymbol == #c]).
	numbered := #(#smalltalk #c #text) includes: aSymbol.
	self text: aString.
	textLayout gutter: (numbered ifTrue: [(self lineCount printString size max: 3) * (self font advanceOf: $0) + textLayout padX] ifFalse: [0]).
	self layout.
	self invalidate
!
topLine
	"The line shown at my top edge."
	^buffer lineIndexOf: (textLayout rowStart: (textLayout rowAtY: 0))
!
bottomLine
	^buffer lineIndexOf: (textLayout rowStart: (textLayout rowAtY: self height - 1))
! !

!FileViewer methodsFor: 'drawing'!
drawSelfOn: aCanvas
	super drawSelfOn: aCanvas.
	numbered ifTrue: [self drawLineNumbersOn: aCanvas]
!
drawLineNumbersOn: aCanvas
	| right advance first last selFirst selLast |
	right := textLayout textLeft - textLayout padX.
	advance := self font advanceOf: $0.
	selFirst := buffer lineIndexOf: self selectionStart.
	selLast := self hasSelection ifTrue: [buffer lineIndexOf: self selectionStop - 1] ifFalse: [0].
	first := textLayout rowAtY: aCanvas clipRect top.
	last := textLayout rowAtY: aCanvas clipRect bottom.
	first to: last do: [:r | | start line digits |
		start := textLayout rowStart: r.
		line := buffer lineIndexOf: start.
		(buffer lineStarts at: line) = start ifTrue: [
			digits := line printString.
			aCanvas drawString: digits at: (right - (digits size * advance)) @ ((textLayout rowTop: r) - textLayout offset)
				font: self font color: ((line between: selFirst and: selLast) ifTrue: [self theme ink] ifFalse: [self theme color: #ink4])]]
! !

!FileViewer methodsFor: 'remote control'!
remoteState
	^super remoteState copyWith: 'top=', self topLine printString
!
remoteChildren
	"The selection and the lines shown, not the whole file."
	| kids |
	kids := OrderedCollection new.
	self hasSelection ifTrue: [kids add: (WidgetPart of: self role: #selection label: (self cut: self selectedText to: 240))].
	self topLine to: self bottomLine do: [:i | kids add: '| ', (buffer lineAt: i)].
	^kids asArray
! !
