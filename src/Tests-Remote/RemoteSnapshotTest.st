TestCase subclass: #RemoteSnapshotTest
	instanceVariableNames: 'root window list editor refTable'
	classVariableNames: ''
	package: 'Tests-Remote'!

RemoteSnapshotTest comment: 'Tests RemoteSnapshot rendering, ref assignment and stability (RemoteRefTable), find and ref resolution, on a tree of RemoteFakeWidgets.'!

!RemoteSnapshotTest methodsFor: 'running'!
setUp
	| w2 |
	refTable := RemoteRefTable new.
	root := RemoteFakeWidget role: #screen label: '1440x900'.
	root state: #('theme=blue-book' 'focus=@w1').
	window := root add: (RemoteFakeWidget role: #window label: 'System Browser' name: 'w1').
	window bounds: (18 @ 44 extent: 866 @ 468); state: #(#focused 'process=#1495 waiting').
	window add: 'controls @w1.title @w1.close'.
	list := window add: (RemoteFakeWidget role: #list label: 'Packages' name: 'packages').
	list state: #('sel="Kernel-Numbers"' 'n=3'); bounds: (20 @ 60 extent: 200 @ 300).
	list add: ((RemoteFakeWidget role: #item label: 'Kernel-Numbers') state: #(#selected); bounds: (20 @ 60 extent: 200 @ 20); yourself).
	list add: ((RemoteFakeWidget role: #item label: 'Kernel-Objects') bounds: (20 @ 80 extent: 200 @ 20); yourself).
	list add: ((RemoteFakeWidget role: #item label: 'Kernel Numbers') bounds: (20 @ 100 extent: 200 @ 20); yourself).
	editor := window add: (RemoteFakeEditor role: #editor label: 'code').
	editor state: #('caret=0'); text: 'Object subclass: #Point'; bounds: (230 @ 60 extent: 600 @ 400).
	window add: ((RemoteFakeWidget role: #button label: '+') bounds: (800 @ 30 extent: 20 @ 20); yourself).
	w2 := root add: (RemoteFakeWidget role: #window label: 'Transcript' name: 'w2').
	w2 bounds: (900 @ 44 extent: 400 @ 300)
!
snapshot
	^RemoteSnapshot root: root refTable: refTable
!
lines: aString
	^(aString subStrings: (String with: Character lf)) asArray
! !

!RemoteSnapshotTest methodsFor: 'tests'!
testRender
	| text |
	text := self snapshot renderDepth: 9 bounds: false maxItems: 60.
	self assert: (self lines: text) equals: #(
		'screen "1440x900" theme=blue-book focus=@w1'
		'window @w1 "System Browser" [18,44 866x468] focused process=#1495 waiting'
		'  controls @w1.title @w1.close'
		'  list @w1.packages "Packages" sel="Kernel-Numbers" n=3'
		'    item @w1.packages.kernel-numbers "Kernel-Numbers" selected'
		'    item @w1.packages.kernel-objects "Kernel-Objects"'
		'    item @w1.packages.kernel-numbers~2 "Kernel Numbers"'
		'  editor @w1.code "code" caret=0'
		'  button @w1.plus "+"'
		'window @w2 "Transcript" [900,44 400x300]')
!
testRenderBoundsAndDepth
	| text |
	text := self lines: (self snapshot renderDepth: 0 bounds: false maxItems: 60).
	self assert: text size equals: 3.
	self assert: (text at: 3) equals: 'window @w2 "Transcript" [900,44 400x300]'.
	text := self lines: (self snapshot renderDepth: 1 bounds: true maxItems: 60).
	self assert: text size equals: 7.
	self assert: (text at: 4) equals: '  list @w1.packages "Packages" [20,60 200x300] sel="Kernel-Numbers" n=3'
!
testRenderRef
	| text |
	text := self lines: (self snapshot renderRef: '@w1.packages' depth: 9 bounds: false maxItems: 60).
	self assert: text size equals: 4.
	self assert: text first equals: 'list @w1.packages "Packages" sel="Kernel-Numbers" n=3'.
	self assert: (text at: 2) equals: '  item @w1.packages.kernel-numbers "Kernel-Numbers" selected'.
	self should: [self snapshot renderRef: '@w9' depth: 9 bounds: false maxItems: 60] raise: RemoteError
!
testMaxItems
	| text |
	1 to: 70 do: [:i | list add: (RemoteFakeWidget role: #item label: 'Item ', i printString)].
	text := self lines: (self snapshot renderRef: 'w1.packages' depth: 9 bounds: false maxItems: 60).
	self assert: text size equals: 62.
	self assert: text last equals: '  more "13 more items"'
!
testRefStability
	| s first moved |
	s := self snapshot.
	first := list children first.
	self assert: (s resolve: '@w1.packages.kernel-numbers') widget == first.
	"a new widget with the same name in front does not steal the existing refs"
	list children addFirst: (RemoteFakeWidget role: #item label: 'Kernel-Numbers').
	s := self snapshot.
	self assert: (s resolve: '@w1.packages.kernel-numbers') widget == first.
	self assert: (s resolve: '@w1.packages.kernel-numbers~2') widget == (list children at: 4).
	self assert: (s resolve: '@w1.packages.kernel-numbers~3') widget == list children first.
	"removing a widget frees its ref; the others keep theirs"
	list children removeFirst.
	s := self snapshot.
	self assert: (s resolve: '@w1.packages.kernel-numbers') widget == first.
	self assert: (s resolve: '@w1.packages.kernel-numbers~2') widget == list children last.
	self assert: (s resolve: '@w1.packages.kernel-numbers~3') isNil.
	"a widget renamed under the same parent gets a fresh ref"
	moved := list children at: 2.
	moved label: 'Kernel-Classes'.
	s := self snapshot.
	self assert: (s resolve: '@w1.packages.kernel-classes') widget == moved
!
testResolve
	| s |
	s := self snapshot.
	self assert: (s resolve: '@w1') widget == window.
	self assert: (s resolve: 'w1.packages') widget == list.
	self assert: (s resolve: '  @w1.code ') widget == editor.
	self assert: (s resolve: '@w1.packages#1') label equals: 'Kernel-Objects'.
	self assert: (s resolve: '@w1#0') widget == list.
	self assert: (s resolve: '@w1.packages#3') isNil.
	self assert: (s resolve: '@nope') isNil.
	self assert: (s resolve: nil) isNil.
	self should: [s resolveOrFail: '@nope'] raise: RemoteError.
	self assert: ([s resolveOrFail: '@nope'] on: RemoteError do: [:e | e return: e code]) equals: 2
!
testFind
	| found |
	found := self snapshot find: 'KERNEL'.
	self assert: (found collect: [:n | n atRef]) asArray equals: #('@w1.packages.kernel-numbers' '@w1.packages.kernel-objects' '@w1.packages.kernel-numbers~2').
	found := self snapshot find: 'w2'.
	self assert: found size equals: 1.
	self assert: (found first summary at: 'label') equals: 'Transcript'.
	self assert: (self snapshot find: 'zzz') isEmpty
!
testAllTextAndWindows
	| s states |
	s := self snapshot.
	self assert: (s allText includesSubstring: 'Kernel-Objects').
	self assert: (s allText includesSubstring: 'subclass: #Point').
	self deny: (s allText includesSubstring: 'Morphic').
	states := s windowStates.
	self assert: states size equals: 2.
	self assert: (states first at: 'ref') equals: '@w1'.
	self assert: (states first at: 'focused').
	self assert: ((states first at: 'bounds') at: 'w') equals: 866.
	self deny: ((states at: 2) at: 'focused')
!
testSlugs
	self assert: (RemoteRefTable slug: 'Kernel-Numbers') equals: 'kernel-numbers'.
	self assert: (RemoteRefTable slug: '  System Browser: Window ') equals: 'system-browser-window'.
	self assert: (RemoteRefTable slug: 'do_it') equals: 'do_it'.
	self assert: (RemoteRefTable slug: '+') equals: 'plus'.
	self assert: (RemoteRefTable slug: '<=') equals: 'lt-eq'.
	self assert: (RemoteRefTable slug: (String new: 60 withAll: $a)) size equals: 40.
	self assert: (RemoteRefTable baseOf: 'w1.list~3') equals: 'w1.list'.
	self assert: (RemoteRefTable baseOf: 'w1~2.list') equals: 'w1~2.list'
!
testBrokenWidget
	"A widget whose remote methods fail still renders."
	| s |
	window add: (RemoteFakeWidget new role: #button; label: 3; yourself).
	window add: Object new.
	s := self snapshot.
	self assert: ((s renderDepth: 9 bounds: false maxItems: 60) includesSubstring: 'button @w1.3 "3"').
	self assert: ((s renderDepth: 9 bounds: false maxItems: 60) includesSubstring: 'widget @w1.widget')
! !
