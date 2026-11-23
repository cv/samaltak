TestCase subclass: #OmarchyDeskTest
	instanceVariableNames: 'desk'
	classVariableNames: ''
	package: 'Tests-UI-Omarchy'!

OmarchyDeskTest comment: 'Tests OmarchyDesk: the layout file read as the desktop-cards plugin''s Layout.js normalizes it, the cards placed as its arrange does, the free area from Hyprland''s monitor, and a desk of one card (OmarchyDeskTestCard) on a hidden host window that follows the card''s height.'!

!OmarchyDeskTest methodsFor: 'running'!
tearDown
	desk isNil ifFalse: [desk stop].
	Profiler resume
!
timeLimitMilliseconds
	^30000
! !

!OmarchyDeskTest methodsFor: 'tests'!
testEntriesAsLayoutJsNormalizesThem
	| entries |
	entries := OmarchyDesk entriesIn: '{"screen": "", "cards": [
		{"id": "agents", "column": 0, "edge": "bottom"},
		{"id": "wodify", "column": 7, "edge": "sideways", "maxHeight": 30, "settings": {"hide": ["Warm Up"]}},
		{"id": "agents", "column": 1},
		{"id": "notes", "hidden": true, "maxHeight": 600},
		{"column": 1}, 3]}' available: #('weather' 'agents').
	self assert: entries equals: #(
		#('agents' 0 #bottom false nil)
		#('wodify' 2 #top false 80)
		#('notes' 2 #top true 600)
		#('weather' 2 #top false nil)).
	self assert: (OmarchyDesk entriesIn: nil available: #('weather')) equals: #(#('weather' 2 #top false nil)).
	self assert: (OmarchyDesk entriesIn: 'not json' available: #()) equals: #()
!
testArrangeAsLayoutJs
	"The user's layout on a 1512 × 950 free area less the gaps: columns of floor((1492 - 20) / 3) = 490, a bottom stack ending at the bottom."
	| entries places |
	entries := #(#('agents' 0 #bottom false nil) #('wodify' 2 #bottom false nil) #('weather' 0 #top false nil)
		#('notes' 0 #top true nil) #('clock' 0 #top false nil) #('later' 1 #top false nil)).
	places := OmarchyDesk arrange: entries
		heights: (Dictionary new at: 'agents' put: 150; at: 'wodify' put: 500; at: 'weather' put: 200; at: 'notes' put: 99; at: 'clock' put: 50; yourself)
		width: 1492 height: 930 gap: 10 columns: 3.
	self assert: (places at: 'weather') equals: (0 @ 0 extent: 490 @ 200).
	self assert: (places at: 'clock') equals: (0 @ 210 extent: 490 @ 50).
	self assert: (places at: 'agents') equals: (0 @ 780 extent: 490 @ 150).
	self assert: (places at: 'wodify') equals: (1000 @ 430 extent: 490 @ 500).
	"hidden cards and cards of unknown height take no place"
	self deny: (places includesKey: 'notes').
	self deny: (places includesKey: 'later')
!
testFreeAreaOfAMonitor
	| monitor |
	monitor := Dictionary new.
	monitor at: 'width' put: 3024; at: 'height' put: 1964; at: 'scale' put: 2; at: 'reserved' put: #(0 32 0 0).
	self assert: (Omarchy freeAreaOfMonitor: monitor) equals: (0 @ 32 corner: 1512 @ 982).
	monitor at: 'reserved' put: 'nonsense'.
	self assert: (Omarchy freeAreaOfMonitor: monitor) equals: (0 @ 0 corner: 1512 @ 982)
!
testADeskOfOneCard
	"The card opens on its own hidden host window, not the application's main one, and its stack follows its height."
	| card |
	desk := OmarchyDesk new runHidden: true.
	card := desk cards at: 'samaltak-test'.
	self assert: (card isKindOf: OmarchyDeskTestCard).
	self deny: card world isMain.
	self assert: (card world waitUntilSettled: 5000).
	self assert: card world extent equals: 300 @ 120.
	card height: 180.
	card window do: [card fitToContent].
	self assert: (self waitFor: [card world extent = (300 @ 180)]).
	desk stop.
	self assert: (self waitFor: [card world isRunning not]).
	desk := nil
! !
