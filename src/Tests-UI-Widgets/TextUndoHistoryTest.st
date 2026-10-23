TestCase subclass: #TextUndoHistoryTest
	instanceVariableNames: 'history'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

TextUndoHistoryTest comment: 'I test TextUndoHistory headlessly: grouping of typing, backspaces and forward deletes, what undo and redo hand back, and the size limit.'!

!TextUndoHistoryTest methodsFor: 'running'!
setUp
	history := TextUndoHistory new
!
type: aString at: pos
	history record: #typing position: pos removed: '' inserted: aString
		before: (Array with: pos with: pos) after: (Array with: pos + aString size with: pos + aString size)
!
undo
	| got |
	history undoWith: [:start :stop :aString :selection | got := Array with: start with: stop with: aString with: selection].
	^got
!
redo
	| got |
	history redoWith: [:start :stop :aString :selection | got := Array with: start with: stop with: aString with: selection].
	^got
! !

!TextUndoHistoryTest methodsFor: 'tests'!
testTypingIsGrouped
	self type: 'a' at: 0; type: 'b' at: 1; type: 'c' at: 2.
	self assert: history undoCount equals: 1.
	self assert: self undo equals: #(0 3 '' #(0 0)).
	self deny: history canUndo.
	self assert: self redo equals: #(0 0 'abc' #(3 3))
!
testWhiteSpaceAfterAWordStartsAGroup
	self type: 'ab' at: 0; type: ' ' at: 2; type: ' ' at: 3; type: 'c' at: 4.
	self assert: history undoCount equals: 2.
	self assert: self undo equals: #(2 5 '' #(2 2)).
	self assert: self undo equals: #(0 2 '' #(0 0))
!
testTypingElsewhereStartsAGroup
	self type: 'a' at: 0; type: 'b' at: 5.
	self assert: history undoCount equals: 2
!
testBackspacesAndDeletesAreGrouped
	history record: #backspace position: 4 removed: 'o' inserted: '' before: #(5 5) after: #(4 4).
	history record: #backspace position: 3 removed: 'l' inserted: '' before: #(4 4) after: #(3 3).
	history record: #forwardDelete position: 0 removed: 'h' inserted: '' before: #(0 0) after: #(0 0).
	history record: #forwardDelete position: 0 removed: 'e' inserted: '' before: #(0 0) after: #(0 0).
	self assert: history undoCount equals: 2.
	self assert: self undo equals: #(0 0 'he' #(0 0)).
	self assert: self undo equals: #(3 3 'lo' #(5 5))
!
testRecordingClearsRedo
	self type: 'a' at: 0.
	self undo.
	self assert: history canRedo.
	history record: #paste position: 0 removed: '' inserted: 'xy' before: #(0 0) after: #(2 2).
	self deny: history canRedo.
	self assert: self redo isNil
!
testOtherKindsAreNotGrouped
	history record: #paste position: 0 removed: '' inserted: 'x' before: #(0 0) after: #(1 1).
	history record: #paste position: 1 removed: '' inserted: 'y' before: #(1 1) after: #(2 2).
	self assert: history undoCount equals: 2
!
testLimit
	1 to: 250 do: [:i | history record: #edit position: 0 removed: '' inserted: 'x' before: #(0 0) after: #(1 1)].
	self assert: history undoCount equals: 200
!
testReset
	self type: 'a' at: 0.
	history reset.
	self deny: history canUndo.
	self assert: self undo isNil
! !
