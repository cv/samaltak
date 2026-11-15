TestCase subclass: #EllipsisCutTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

EllipsisCutTest comment: 'I test the cuts with an ellipsis of pane header tails and window titles: they fit and end between grapheme clusters.'!

!EllipsisCutTest methodsFor: 'tests'!
testHeaderCutsKeepClustersWhole
	"The evaluator header's tail and window titles cut with an ellipsis end between grapheme clusters (here family emoji of 7 characters) and fit."
	| family s f cut |
	family := String withAll: (#(16r1F468 16r200D 16r1F469 16r200D 16r1F467 16r200D 16r1F466) collect: [:cp | Character value: cp]).
	s := 'ab', family, family, family.
	f := Font smallItalic.
	30 to: (f widthOf: s) by: 3 do: [:w |
		cut := MixedPaneHeader new truncate: s to: w font: f.
		self assert: (f widthOf: cut) <= w.
		self assert: (s isGraphemeClusterBoundaryAt: cut size - 1).
		cut := Window truncate: s to: w font: f.
		self assert: (s isGraphemeClusterBoundaryAt: cut size - 1)].
	self assert: (MixedPaneHeader new truncate: s to: (f widthOf: 'ab', family, '…') font: f) size equals: 10
! !
