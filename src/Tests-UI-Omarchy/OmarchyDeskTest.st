TestCase subclass: #OmarchyDeskTest
	instanceVariableNames: 'desk'
	classVariableNames: ''
	package: 'Tests-UI-Omarchy'!

OmarchyDeskTest comment: 'Tests OmarchyDesk: the layout file read, moved in, arranged and written as the desktop-cards plugin''s Layout.js does it (its tests/layout.test.js, ported), the free area from Hyprland''s monitor, a desk of cards (OmarchyDeskTestCard) on hidden host windows that follows a card''s height, edits of the layout file, and dragging a card to another stack with the platform''s own pointer events. Desks here read and write a layout file in the scratch directory, never the user''s.'!

!OmarchyDeskTest methodsFor: 'running'!
tearDown
	desk isNil ifFalse: [desk stop].
	Profiler resume.
	super tearDown
!
timeLimitMilliseconds
	^30000
!
deskWith: aJSONString
	"A hidden desk on a 1512 × 950 free area, its layout file aJSONString (nil: none): columns 490 wide, the cards from 10 @ 10."
	| path |
	path := self scratchPath: 'desktop-cards.json'.
	aJSONString isNil ifFalse: [File writeText: aJSONString to: path].
	desk := OmarchyDesk new path: path; area: (0 @ 0 extent: 1512 @ 950); yourself.
	desk runHidden: true.
	desk cards do: [:app | self assert: (app world waitUntilSettled: 5000)].
	^desk
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
testNormalizeAsLayoutTests
	"tests/layout.test.js: bad input falls back, unknown cards go to the right column, duplicates and bad ids are dropped, maxHeight is at least 80."
	| available layout cards |
	available := #('weather' 'agents' 'notes').
	layout := OmarchyDesk normalize: 'not json' available: available.
	self assert: ((layout at: 'cards') collect: [:c | c at: 'id']) equals: available.
	self assert: ((layout at: 'cards') allSatisfy: [:c | (c at: 'column') = 2 and: [(c at: 'edge') = 'top']]).
	layout := OmarchyDesk normalize: '{"cards": [
		{"id": "agents", "column": 9, "edge": "bottom"},
		{"id": "agents", "column": 0},
		{"id": "../evil"},
		{"id": "weather", "column": 0, "hidden": true, "settings": {"unit": "metric"}}]}' available: available.
	cards := layout at: 'cards'.
	self assert: (cards collect: [:c | c at: 'id']) equals: #('agents' 'weather' 'notes').
	self assert: ((cards at: 1) at: 'column') equals: 2.
	self assert: ((cards at: 1) at: 'edge') equals: 'bottom'.
	self assert: ((cards at: 2) at: 'hidden') equals: true.
	self assert: (((cards at: 2) at: 'settings') at: 'unit') equals: 'metric'.
	layout := OmarchyDesk normalize: '{"cards": [{"id": "agents", "maxHeight": 500}, {"id": "weather", "maxHeight": 10}, {"id": "notes", "maxHeight": "x"}]}' available: available.
	cards := layout at: 'cards'.
	self assert: ((cards at: 1) at: 'maxHeight') equals: 500.
	self assert: ((cards at: 2) at: 'maxHeight') equals: 80.
	self deny: ((cards at: 3) includesKey: 'maxHeight').
	self assert: ((OmarchyDesk find: (OmarchyDesk move: layout id: 'agents' column: 0 edge: #bottom index: 0 available: available) id: 'agents') at: 'maxHeight') equals: 500.
	"columns as parseInt reads them, opacity within 0.2 and 1"
	layout := OmarchyDesk normalize: '{"opacity": 0.1, "cards": [{"id": "a", "column": "1"}, {"id": "b", "column": 1.7}, {"id": "c", "column": "x"}, {"id": 5}]}' available: #().
	self assert: ((layout at: 'cards') collect: [:c | c at: 'column']) equals: #(1 1 2 2).
	self assert: ((layout at: 'cards') collect: [:c | c at: 'id']) equals: #('a' 'b' 'c' '5').
	self assert: (layout at: 'opacity') equals: 0.2
!
testMoveAsLayoutTests
	| available layout moved |
	available := #('weather' 'agents' 'notes').
	layout := OmarchyDesk normalize: '{"cards": [
		{"id": "weather", "column": 0, "edge": "top"},
		{"id": "agents", "column": 0, "edge": "top"},
		{"id": "notes", "column": 1, "edge": "bottom"}]}' available: available.
	self assert: (OmarchyDesk stack: layout column: 0 edge: #top available: available) equals: #('weather' 'agents').
	moved := OmarchyDesk move: layout id: 'agents' column: 0 edge: #top index: 0 available: available.
	self assert: (OmarchyDesk stack: moved column: 0 edge: #top available: available) equals: #('agents' 'weather').
	moved := OmarchyDesk move: layout id: 'weather' column: 1 edge: #bottom index: 1 available: available.
	self assert: (OmarchyDesk stack: moved column: 1 edge: #bottom available: available) equals: #('notes' 'weather').
	self assert: (OmarchyDesk stack: moved column: 0 edge: #top available: available) equals: #('agents').
	moved := OmarchyDesk move: layout id: 'notes' column: 2 edge: #top index: 5 available: available.
	self assert: (OmarchyDesk stack: moved column: 2 edge: #top available: available) equals: #('notes')
!
testArrangeAndDropTargetAsLayoutTests
	| available layout heights a t |
	available := #('weather' 'agents' 'notes').
	layout := OmarchyDesk normalize: '{"cards": [
		{"id": "weather", "column": 0, "edge": "top"},
		{"id": "agents", "column": 0, "edge": "top"},
		{"id": "notes", "column": 1, "edge": "bottom"}]}' available: available.
	heights := Dictionary new at: 'weather' put: 100; at: 'agents' put: 50; at: 'notes' put: 80; yourself.
	a := OmarchyDesk arrangement: (OmarchyDesk entriesOf: layout) heights: heights width: 320 height: 500 gap: 10 columns: 3 skip: nil.
	self assert: (a at: #colWidth) equals: 100.
	self assert: ((a at: #slots) at: 'weather') equals: (0 @ 0 extent: 100 @ 100).
	self assert: ((a at: #slots) at: 'agents') equals: (0 @ 110 extent: 100 @ 50).
	self assert: ((a at: #slots) at: 'notes') equals: (110 @ 420 extent: 100 @ 80).
	self assert: (((a at: #stacks) at: '0:top') at: #height) equals: 160.
	"arranged without the dragged card"
	a := OmarchyDesk arrangement: (OmarchyDesk entriesOf: layout) heights: heights width: 320 height: 500 gap: 10 columns: 3 skip: 'agents'.
	t := OmarchyDesk dropTarget: a x: 50 y: 20 height: 500 gap: 10 columns: 3 heights: heights.
	self assert: {t at: #column. t at: #edge. t at: #index} equals: #(0 #top 0).
	t := OmarchyDesk dropTarget: a x: 50 y: 80 height: 500 gap: 10 columns: 3 heights: heights.
	self assert: {t at: #column. t at: #edge. t at: #index} equals: #(0 #top 1).
	t := OmarchyDesk dropTarget: a x: 160 y: 300 height: 500 gap: 10 columns: 3 heights: heights.
	self assert: {t at: #column. t at: #edge. t at: #index} equals: #(1 #bottom 0).
	t := OmarchyDesk dropTarget: a x: 300 y: 100 height: 500 gap: 10 columns: 3 heights: heights.
	self assert: {t at: #column. t at: #edge. t at: #index. t at: #lineY} equals: #(2 #top 0 0).
	t := OmarchyDesk dropTarget: a x: 300 y: 400 height: 500 gap: 10 columns: 3 heights: heights.
	self assert: {t at: #column. t at: #edge. t at: #lineY} equals: #(2 #bottom 500)
!
testSerializeAsThePluginWritesIt
	"JSON.stringify(…, null, 2): what the plugin wrote is written back unchanged (but for the order of the keys of settings, which JSON reads into a Dictionary: sorted), and read back the same."
	| file layout |
	file := '{
  "screen": "",
  "cards": [
    {
      "id": "agents",
      "column": 0,
      "edge": "bottom"
    },
    {
      "id": "wodify",
      "column": 2,
      "edge": "bottom",
      "maxHeight": 600,
      "settings": {
        "empty": [],
        "hide": [
          "Warm Up",
          "Stretching"
        ]
      }
    },
    {
      "id": "weather",
      "column": 0,
      "edge": "top",
      "hidden": true
    }
  ],
  "opacity": 0.95
}
' copyReplaceAll: (String with: Character cr) with: (String with: Character lf).
	layout := OmarchyDesk normalize: file available: #('agents' 'wodify' 'weather').
	self assert: (OmarchyDesk serialize: layout) equals: file.
	self assert: ((OmarchyDesk normalize: (OmarchyDesk serialize: layout) available: #()) at: 'cards') equals: (layout at: 'cards').
	self assert: (OmarchyDesk serialize: (OmarchyDesk normalize: nil available: #())) equals: ('{
  "screen": "",
  "cards": []
}
' copyReplaceAll: (String with: Character cr) with: (String with: Character lf))
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
	"The card opens on its own hidden host window, not the application's main one, and its stack follows its height. The layout file gets the cards it did not name."
	| card |
	self deskWith: '{"screen": "", "cards": [{"id": "samaltak-test", "column": 1, "edge": "bottom"}]}'.
	card := desk cards at: 'samaltak-test'.
	self assert: (card isKindOf: OmarchyDeskTestCard).
	self deny: card world isMain.
	self assert: card world extent equals: 300 @ 120.
	self assert: (desk placeOf: 'samaltak-test') equals: 510 @ (950 - 10 - 120).
	self assert: ((OmarchyDesk entriesIn: (File readText: desk path) available: #()) collect: [:e | e first]) equals: OmarchyDesk cardIds.
	card height: 180.
	card window do: [card fitToContent].
	self assert: (self waitFor: [card world extent = (300 @ 180)]).
	self assert: (self waitFor: [(desk placeOf: 'samaltak-test') = (510 @ (950 - 10 - 180))]).
	desk stop.
	self assert: (self waitFor: [card world isRunning not]).
	desk := nil
!
testAnEditOfTheFileShows
	"Hiding a card in the file closes it; the other one slides into its place."
	| first second |
	self deskWith: '{"screen": "", "cards": [{"id": "samaltak-test", "column": 0}, {"id": "samaltak-test-2", "column": 0}]}'.
	first := desk cards at: 'samaltak-test'.
	second := desk cards at: 'samaltak-test-2'.
	self assert: (desk placeOf: 'samaltak-test-2') equals: 10 @ 140.
	desk animates: true.
	(Delay forMilliseconds: 20) wait.
	File writeText: '{"screen": "", "cards": [{"id": "samaltak-test", "column": 0, "hidden": true}, {"id": "samaltak-test-2", "column": 0}]}' to: desk path.
	self assert: (self waitFor: [(desk cards includesKey: 'samaltak-test') not]).
	self assert: (self waitFor: [first world isRunning not]).
	self assert: (self waitFor: [(desk placeOf: 'samaltak-test-2') = (10 @ 10)]).
	self assert: second world isRunning
!
testDraggingACardToAnotherStack
	"Press a card, move past the threshold and on to the bottom of the right column, release: the card follows the pointer, the target is that stack, the file says so, and the cards settle. The events are the platform's, relative to where each host window was when they happened."
	| first second press layout |
	self deskWith: '{"screen": "", "cards": [{"id": "samaltak-test", "column": 0}, {"id": "samaltak-test-2", "column": 0}]}'.
	first := desk cards at: 'samaltak-test'.
	second := desk cards at: 'samaltak-test-2'.
	self assert: (desk placeOf: 'samaltak-test') equals: 10 @ 10.
	press := 60 @ 60.
	self pointer: 2 at: press button: 1 on: first.
	"within the threshold (6): no drag yet"
	self pointer: 1 at: press + (3 @ 2) button: 1 on: first.
	self assert: (self waitFor: [first world isSettled]).
	self assert: desk dragged isNil.
	self pointer: 1 at: press + (20 @ 0) button: 1 on: first.
	self assert: (self waitFor: [desk dragged = 'samaltak-test']).
	"The threshold-crossing motion already moves the card."
	self assert: (desk placeOf: 'samaltak-test') equals: 30 @ 10.
	"the other card closes up"
	self assert: (self waitFor: [(desk placeOf: 'samaltak-test-2') = (10 @ 10)]).
	self pointer: 1 at: 1200 @ 900 button: 1 on: first.
	"kept within the area: its bottom a gap below the area's"
	(self waitFor: [(desk placeOf: 'samaltak-test') = (1150 @ 830)]) ifFalse: [self assert: (desk placeOf: 'samaltak-test') equals: 1150 @ 830].
	self assert: (self waitFor: [desk target notNil and: [(desk target at: #column) = 2]]).
	self assert: (desk target at: #edge) equals: #bottom.
	self assert: (desk target at: #lineY) equals: 930.
	"SDL can reuse local coordinates from before the window moved. Keep the previewed slot."
	self pointer: 3 at: 200 @ 100 button: 1 on: first.
	self assert: (self waitFor: [desk dragged isNil]).
	(self waitFor: [(desk placeOf: 'samaltak-test') = (1010 @ 820)]) ifFalse: [self assert: (desk placeOf: 'samaltak-test') equals: 1010 @ 820].
	self assert: (desk placeOf: 'samaltak-test-2') equals: 10 @ 10.
	"The file is written after the cards are placed: wait for it."
	self assert: (self waitFor: [
		layout := OmarchyDesk normalize: (File readText: desk path) available: #().
		((OmarchyDesk find: layout id: 'samaltak-test') at: 'column') = 2]).
	self assert: ((OmarchyDesk find: layout id: 'samaltak-test') at: 'edge') equals: 'bottom'.
	self assert: first clicks equals: 0
!
testAClickIsNoDrag
	"A press released where it was runs the card's action, on the release."
	| first |
	self deskWith: '{"screen": "", "cards": [{"id": "samaltak-test", "column": 0}]}'.
	first := desk cards at: 'samaltak-test'.
	self pointer: 2 at: 60 @ 60 button: 1 on: first.
	self assert: (self waitFor: [first world isSettled]).
	self assert: first clicks equals: 0.
	self pointer: 3 at: 61 @ 60 button: 1 on: first.
	self assert: (self waitFor: [first clicks = 1]).
	self assert: desk dragged isNil.
	self assert: (desk placeOf: 'samaltak-test') equals: 10 @ 10
! !

!OmarchyDeskTest methodsFor: 'input'!
pointer: type at: aScreenPoint button: button on: anApplication
	"Inject a platform pointer event (1 move with button held, 2 down, 3 up) for anApplication's host window, at aScreenPoint on the screen: relative to where the desk last put the window, as the compositor would send it."
	| local origin |
	origin := desk placeOf: anApplication class cardId.
	DisplayWindow injectEvent: {17. nil. origin x asFloat. origin y asFloat. 0. 0. nil. anApplication world displayWindow windowId}.
	local := aScreenPoint - origin.
	DisplayWindow injectEvent: {type. nil. local x asFloat. local y asFloat. button. 0. type = 1 ifTrue: [nil] ifFalse: [1]. anApplication world displayWindow windowId}
! !
