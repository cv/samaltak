Object subclass: #TextUndoHistory
	instanceVariableNames: 'undoStack redoStack'
	classVariableNames: ''
	package: 'UI-Widgets'!

TextUndoHistory comment: 'I am a TextEditor''s undo and redo history (at most 200 edits). Each edit records its kind, gap position, the removed and inserted text and the selection ({anchor. caret}) before and after it. Consecutive typing (until white space follows a word), backspaces and forward deletes are grouped into one edit.

	history record: #typing position: 0 removed: '''' inserted: ''a'' before: #(0 0) after: #(1 1).
	history undoWith: [:start :stop :replacement :selection | ...]   "replace start..stop (gap positions) with replacement"'!

!TextUndoHistory methodsFor: 'initialization'!
initialize
	self reset
!
reset
	undoStack := OrderedCollection new.
	redoStack := OrderedCollection new
! !

!TextUndoHistory methodsFor: 'recording'!
record: kind position: pos removed: removed inserted: inserted before: before after: after
	"Record an edit (clears the redo history); join it to the last one when it continues the same typing, backspacing or forward deleting."
	| last |
	redoStack := OrderedCollection new.
	last := undoStack isEmpty ifTrue: [nil] ifFalse: [undoStack last].
	(last notNil and: [kind == #typing and: [(last at: 1) == #typing and: [removed isEmpty
		and: [(last at: 2) + (last at: 4) size = pos and: [(inserted allSatisfy: [:c | c isSeparator]) not or: [(last at: 4) last isSeparator]]]]]])
		ifTrue: [
			last at: 4 put: (last at: 4) , inserted.
			last at: 6 put: after.
			^self].
	(last notNil and: [kind == #backspace and: [(last at: 1) == #backspace and: [inserted isEmpty
		and: [pos + removed size = (last at: 2)]]]])
		ifTrue: [
			last at: 2 put: pos.
			last at: 3 put: removed , (last at: 3).
			last at: 6 put: after.
			^self].
	(last notNil and: [kind == #forwardDelete and: [(last at: 1) == #forwardDelete and: [inserted isEmpty
		and: [pos = (last at: 2)]]]])
		ifTrue: [
			last at: 3 put: (last at: 3) , removed.
			last at: 6 put: after.
			^self].
	undoStack add: (Array with: kind with: pos with: removed with: inserted with: before with: after).
	undoStack size > 200 ifTrue: [undoStack removeFirst]
! !

!TextUndoHistory methodsFor: 'undoing'!
canUndo
	^undoStack notEmpty
!
canRedo
	^redoStack notEmpty
!
undoCount
	^undoStack size
!
undoWith: aBlock
	"Move the last edit to the redo history; aBlock receives the gap positions of its inserted text, the removed text to put back and the selection before it. Answer false if there is nothing to undo."
	| r |
	undoStack isEmpty ifTrue: [^false].
	r := undoStack removeLast.
	redoStack add: r.
	aBlock value: (r at: 2) value: (r at: 2) + (r at: 4) size value: (r at: 3) value: (r at: 5).
	^true
!
redoWith: aBlock
	"Move the last undone edit back; aBlock receives the gap positions of its removed text, the inserted text and the selection after it. Answer false if there is nothing to redo."
	| r |
	redoStack isEmpty ifTrue: [^false].
	r := redoStack removeLast.
	undoStack add: r.
	aBlock value: (r at: 2) value: (r at: 2) + (r at: 3) size value: (r at: 4) value: (r at: 6).
	^true
! !
