TestCase subclass: #RfbInputTest
	instanceVariableNames: 'queue input'
	classVariableNames: ''
	package: 'Tests-Remote'!

RfbInputTest comment: 'A remote display client''s input (RfbInput): RFB key sequences as macOS Screen Sharing and TigerVNC send them (keysyms; Command as Meta_L or Mode_switch) make the events the firmware keyboard would (InputQueueTest), pointer masks the pointer''s, and cut text the clipboard, both ways in Latin-1.'!

!RfbInputTest methodsFor: 'running'!
setUp
	queue := InputQueue new.
	queue extent: 100 @ 80.
	input := RfbInput queue: queue
!
tearDown
	input close
!
events
	"The queued events, without their times."
	| a all |
	all := OrderedCollection new.
	[(a := queue next: (Array new: 8)) notNil] whileTrue: [
		a at: 2 put: nil.
		all add: a].
	^all asArray
!
keys
	"The key events as {type. key. modifiers. extra}."
	^self events collect: [:e | {e first. e at: 5. e at: 6. e at: 7}]
!
type: keysyms
	"Press and release each keysym."
	keysyms do: [:k | input key: k down: true. input key: k down: false]
! !

!RfbInputTest methodsFor: 'tests'!
testALetterIsKeyDownTextKeyUp
	self type: #(16r61).
	self assert: self events equals: {
		{5. nil. 50.0. 40.0. 97. 0. false. 1}.
		{7. nil. 50.0. 40.0. 0. 0. 'a'. 1}.
		{6. nil. 50.0. 40.0. 97. 0. false. 1}}
!
testShiftAndCapitals
	"Shift is a key and held state; a capital is shift and the small letter, with its text."
	input key: 16rFFE1 down: true.
	self type: #(16r41).
	input key: 16rFFE1 down: false.
	self assert: self keys equals: {
		{5. 16r400000E1. 1. false}. {5. 97. 1. false}. {7. 0. 1. 'A'}. {6. 97. 1. false}. {6. 16r400000E1. 0. false}}.
	self type: #(16rC9).
	self assert: self keys equals: {{5. 16rE9. 1. false}. {7. 0. 1. (Character value: 16rC9) asString}. {6. 16rE9. 1. false}}
!
testCommandFromBothViewers
	"macOS Screen Sharing sends Command as Meta_L, TigerVNC as Mode_switch; Super too: cmd, and cmd-c types no text."
	#(16rFFE7 16rFF7E 16rFFEB 16rFFE8 16rFFEC) do: [:cmd |
		input key: cmd down: true.
		self type: #(16r63).
		input key: cmd down: false.
		self assert: (self keys collect: [:e | {e first. e at: 3}]) equals: #(#(5 8) #(5 8) #(6 8) #(6 0))]
!
testControlAndAlt
	"Control-c is ctrl and c without text; Option (Alt_L) composes: its character's text with alt; altIsCmd makes it cmd."
	input key: 16rFFE3 down: true.
	self type: #(16r63).
	input key: 16rFFE3 down: false.
	self assert: self keys equals: {{5. 16r400000E0. 2. false}. {5. 99. 2. false}. {6. 99. 2. false}. {6. 16r400000E0. 0. false}}.
	input key: 16rFFE9 down: true.
	self type: #(16rE9).
	input key: 16rFFE9 down: false.
	self assert: self keys equals: {{5. 16r400000E2. 4. false}. {5. 16rE9. 4. false}. {7. 0. 4. (Character value: 16rE9) asString}. {6. 16rE9. 4. false}. {6. 16r400000E2. 0. false}}.
	input altIsCmd: true.
	input key: 16rFFEA down: true.
	self type: #(16r71).
	self assert: (self keys collect: [:e | {e first. e at: 2. e at: 3}]) equals: #(#(5 16r400000E6 8) #(5 113 8) #(6 113 8))
!
testNamedKeys
	"Arrows, home, end, the page keys, insert, delete, F1 .. F12, escape, return, tab, backspace, the keypad's: keycodes without text."
	#(16rFF52 16r40000052 16rFF54 16r40000051 16rFF53 16r4000004F 16rFF51 16r40000050 16rFF50 16r4000004A 16rFF57 16r4000004D
		16rFF55 16r4000004B 16rFF56 16r4000004E 16rFF63 16r40000049 16rFFFF 127 16rFFBE 16r4000003A 16rFFC9 16r40000045
		16rFF1B 27 16rFF0D 13 16rFF8D 13 16rFF09 9 16rFF08 8 16rFF97 16r40000052) pairsDo: [:sym :code |
		self type: {sym}.
		self assert: self keys equals: {{5. code. 0. false}. {6. code. 0. false}}].
	self type: #(16rFFB7 16rFFAB).
	self assert: (self keys select: [:e | e first = 7]) equals: #(#(7 0 0 '7') #(7 0 0 '+')).
	self type: #(16rFE52 16rFFE5 0).
	self assert: self events isEmpty
!
testUnicodeKeysyms
	"16r01000000 + a code point, and the legacy EuroSign."
	| euro |
	euro := (Character value: 16r20AC) asString.
	self type: #(16r010020AC 16r20AC).
	self assert: (self keys collect: [:e | {e first. e at: 2. e at: 4}]) equals: {
		{5. 16r20AC. false}. {7. 0. euro}. {6. 16r20AC. false}. {5. 16r20AC. false}. {7. 0. euro}. {6. 16r20AC. false}}
!
testRepeatsAndStrayReleases
	"A key pressed again while held repeats (with its text); a release without a press is ignored; a release with another keysym of the same key (shift let go first) releases it."
	input key: 16r61 down: true.
	input key: 16r61 down: true.
	input key: 16r61 down: false.
	input key: 16r62 down: false.
	self assert: self keys equals: #(#(5 97 0 false) #(7 0 0 'a') #(5 97 0 true) #(7 0 0 'a') #(6 97 0 false)).
	input key: 16rFFE1 down: true.
	input key: 16r41 down: true.
	input key: 16rFFE1 down: false.
	input key: 16r61 down: false.
	self assert: (self keys collect: [:e | {e first. e at: 2}]) equals: #(#(5 16r400000E1) #(5 97) #(7 0) #(6 16r400000E1) #(6 97))
!
testQemuExtendedKeys
	"The logo keys' scan codes are cmd whatever the keysym; other keys go by keysym."
	input qemuKey: 0 code: 16rDB down: true.
	input qemuKey: 16r63 code: 16r2E down: true.
	input qemuKey: 16r63 code: 16r2E down: false.
	input qemuKey: 16rFF7E code: 16rDB down: false.
	self assert: self keys equals: {{5. 16r400000E3. 8. false}. {5. 99. 8. false}. {6. 99. 8. false}. {6. 16r400000E3. 0. false}}.
	input qemuKey: 16rFFE9 code: 16r38 down: true.
	self assert: self keys equals: {{5. 16r400000E2. 4. false}}
!
testThePointer
	"The button mask as the pointer's (left, middle, right); a press of 8/16 is a wheel notch up/down, of 32/64 left/right."
	input pointerAt: 10 @ 20 buttons: 1.
	input pointerAt: 10 @ 20 buttons: 0.
	input pointerAt: 10 @ 20 buttons: 2.
	input pointerAt: 12 @ 20 buttons: 0.
	input pointerAt: 12 @ 20 buttons: 4.
	input pointerAt: 12 @ 20 buttons: 0.
	self assert: (self events collect: [:e | {e first. e at: 3. e at: 4. e at: 5}]) equals: #(
		#(1 10.0 20.0 0) #(2 10.0 20.0 1) #(3 10.0 20.0 1) #(2 10.0 20.0 2) #(1 12.0 20.0 2) #(3 12.0 20.0 2) #(2 12.0 20.0 3) #(3 12.0 20.0 3)).
	#(8 16 32 64) with: {0.0 @ 1.0. 0.0 @ -1.0. -1.0 @ 0.0. 1.0 @ 0.0} do: [:mask :d |
		input pointerAt: 12 @ 20 buttons: mask.
		input pointerAt: 12 @ 20 buttons: 0.
		self assert: (self events collect: [:e | {e first. e at: 7}]) equals: {{4. d}}]
!
testScaleAndClamping
	input extent: 200 @ 160 scale: 2.
	input pointerAt: 20 @ 10 buttons: 0.
	input pointerAt: 900 @ 10 buttons: 0.
	self assert: (self events collect: [:e | (e at: 3) @ (e at: 4)]) equals: {10.0 @ 5.0. 99.0 @ 5.0}
!
testReleaseAll
	"A client that goes away leaves nothing held."
	input key: 16rFFE7 down: true.
	input key: 16r61 down: true.
	input pointerAt: 5 @ 5 buttons: 1.
	self events.
	input releaseAll.
	self assert: (self events collect: [:e | {e first. e at: 5}]) equals: #(#(6 97) #(6 16r400000E3) #(3 1)).
	self assert: input modifiers equals: 0.
	input key: 16r61 down: false.
	self assert: self events isEmpty
!
testForwardsThroughARemoteInputDevice
	"On an operating system the events are made by a queue of RfbInput's own and injected into the device's window without moving its drawn pointer."
	| device injected |
	injected := OrderedCollection new.
	device := RemoteInputDevice new injector: [:e | injected add: e]; windowId: 7; yourself.
	input := RfbInput device: device.
	input extent: 64 @ 48 scale: 1.
	input pointerAt: 3 @ 4 buttons: 0.
	input key: 16r78 down: true.
	self assert: (injected collect: [:e | {e first. e at: 3. e at: 4. e at: 8}]) asArray equals: #(#(1 3.0 4.0 7) #(5 3.0 4.0 7) #(7 3.0 4.0 7)).
	self assert: device pointer isNil.
	self assert: queue isEmpty
!
testCutTextBothWays
	"ClientCutText (Latin-1) sets the clipboard; the image's clipboard goes to the client as Latin-1 bytes, ? for what Latin-1 lacks, but not what the client sent."
	| set sent |
	set := OrderedCollection new.
	sent := OrderedCollection new.
	input clipboardSetter: [:s | set add: s. RemoteClipboard changed: s].
	input clipboardBlock: [:bytes | sent add: bytes].
	input cutText: #[104 233 10 120] asByteArray.
	self assert: set asArray equals: {'h', (Character value: 233) asString, (String with: Character lf), 'x'}.
	self assert: sent isEmpty.
	RemoteClipboard changed: 'a', (Character value: 16r20AC) asString, (Character value: 233) asString.
	self assert: sent asArray equals: {#[97 63 233]}.
	input clipboardBlock: nil.
	RemoteClipboard changed: 'b'.
	self assert: sent size equals: 1.
	self deny: (RemoteClipboard watchers includes: input)
! !
