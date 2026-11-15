ToolsTestCase subclass: #InspectorTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

InspectorTest comment: 'I test the Inspector: its fields, diving into a field (a double-click opens an Inspector on the value), the field menu''s Halt on write (a real Watchpoint, shown as a tag) and per-object breakpoints, and the evaluator with self bound.'!

!InspectorTest methodsFor: 'tests'!
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
!
testFields
	| w inspector names |
	w := self open: [Inspector openOn: 3 @ 4 near: nil].
	inspector := w content.
	names := inspector fieldList items collect: [:f | f name].
	self assert: names asArray equals: #('self' 'class' 'x' 'y').
	self assert: w title equals: 'Inspector: a Point'.
	self in: w do: [inspector fieldList select: (inspector fieldNamed: 'x')].
	self assert: inspector valueView text equals: '3'
!
testDoubleClickDivesIntoAField
	| w inspector list row point new |
	w := self open: [Inspector openOn: {3/4. 3@4} near: nil].
	inspector := w content.
	list := inspector fieldList.
	row := list rowRect: (list items indexOf: (inspector fieldNamed: '1')).
	point := list localToScreen: row center.
	self moveTo: point.
	self inject: 2 at: point button: 1 count: 1 modifiers: 0.
	self inject: 3 at: point button: 1 count: 1 modifiers: 0.
	self inject: 2 at: point button: 1 count: 2 modifiers: 0.
	self inject: 3 at: point button: 1 count: 2 modifiers: 0.
	self assert: (self waitFor: [(self windowsOf: Inspector) size = 2]) description: 'no second Inspector'.
	new := (self windowsOf: Inspector) detect: [:each | each ~~ w].
	self assert: new title equals: 'Inspector: a Fraction'.
	self assert: new content object equals: 3/4
!
testHaltOnWriteSetsAWatchpoint
	| p w inspector field menu wp |
	p := 3 @ 4.
	w := self open: [Inspector openOn: p near: nil].
	inspector := w content.
	field := inspector fieldNamed: 'x'.
	menu := self in: w do: [inspector menuFor: field].
	self assert: (menu itemLabeled: 'Halt on write') notNil.
	self in: w do: [(menu itemLabeled: 'Halt on write') run].
	wp := (Watchpoint forObject: p) detect: [:each | each fieldName = 'x'] ifNone: [nil].
	self assert: wp notNil.
	self assert: (inspector tagOf: field) equals: 'halt on write'.
	self assert: (inspector tagOf: (inspector fieldNamed: 'y')) isNil.
	menu := self in: w do: [inspector menuFor: field].
	self assert: (menu itemLabeled: 'Remove halt on write') notNil.
	self in: w do: [(menu itemLabeled: 'Remove halt on write') run].
	self assert: (Watchpoint forObject: p) isEmpty
!
testEvaluatorHasSelfBound
	| w inspector |
	w := self open: [Inspector openOn: 3 @ 4 near: nil].
	inspector := w content.
	self assert: inspector evaluateEditor text equals: 'self x * self y'.
	self in: w do: [inspector evaluateEditor selectAll. inspector evaluateEditor printIt].
	self assert: (self waitFor: [(inspector evaluateEditor marksStyled: #result) notEmpty]).
	self assert: (self markTexts: #result in: inspector evaluateEditor) asArray equals: #('12')
!
testValuesAreLive
	| p w inspector |
	p := 3 @ 4.
	w := self open: [Inspector openOn: p near: nil].
	inspector := w content.
	self in: w do: [inspector fieldList select: (inspector fieldNamed: 'x')].
	p x: 7.
	self assert: (self waitFor: [inspector valueView text = '7'] timeout: 2000)
! !
