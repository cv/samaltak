TestCase subclass: #KmsDisplayTest
	instanceVariableNames: 'screen display input'
	classVariableNames: ''
	package: 'Tests-Devices'!

KmsDisplayTest comment: 'The appliance''s screen and input without a DRM device or evdev nodes (docs/linux-appliance.md): a KmsScreen whose buffer is memory (offscreen:) flushes only the damaged rectangles and the pointer''s (what DIRTYFB would be told); EvdevInput turns Linux key codes into the image''s key events (SDL keycodes, Shift/Ctrl/Alt-as-cmd, text by the US keymap, Caps Lock, repeats) and a mouse''s, tablet''s and touchpad''s events into pointer events; KmsDisplay is not asked for without SAMALTAK_SCREEN, and a DRM device that is not there is no screen.'!

!KmsDisplayTest methodsFor: 'running'!
setUp
	screen := (KmsScreen path: '/nonexistent/card0') setOffscreen: 1000 @ 600; yourself.
	display := KmsDisplay new setScreen: screen.
	display queue extent: 1000 @ 600.
	input := EvdevInput display: display
!
tearDown
	screen freeOffscreen
!
events
	| out e |
	out := OrderedCollection new.
	[(e := display queue next: (Array new: 8)) notNil] whileTrue: [out add: e].
	^out
! !

!KmsDisplayTest methodsFor: 'tests'!
testDamageFlushed
	"A present of two rectangles flushes them (and the pointer's), not the frame."
	| frame counts |
	frame := Machine allocate: 1000 * 600 * 4.
	[screen present: frame width: 1000 height: 600 rects: {{0. 0. 10. 10}. {900. 500. 20. 10}}.
	counts := screen counts.
	self assert: (counts at: #presents) equals: 1.
	self assert: (counts at: #rects) equals: 2.
	self assert: (counts at: #pixels) equals: 300.
	screen moveCursorTo: 5 @ 5.
	self assert: (screen counts at: #rects) equals: 4.
	self assert: (screen counts at: #pixels) equals: 300 + (2 * 12 * 19)]
		ensure: [Machine free: frame]
!
testKeys
	"a, then Shift+a, Ctrl+c, Alt (cmd) + q; Caps Lock; a held key repeats; a named key."
	| e |
	input key: 30 value: 1; key: 30 value: 0.
	e := self events.
	self assert: (e collect: [:x | x first]) asArray equals: #(5 7 6).
	self assert: (e first at: 5) equals: $a value.
	self assert: ((e at: 2) at: 7) equals: 'a'.
	input key: 42 value: 1; key: 30 value: 1; key: 30 value: 0; key: 42 value: 0.
	e := self events select: [:x | x first = 7].
	self assert: (e collect: [:x | x at: 7]) asArray equals: #('A').
	input key: 29 value: 1; key: 46 value: 1; key: 46 value: 0; key: 29 value: 0.
	e := self events.
	self assert: (e noneSatisfy: [:x | x first = 7]).
	self assert: ((e detect: [:x | x first = 5 and: [(x at: 5) = $c value]]) at: 6) equals: 2.
	input key: 56 value: 1; key: 16 value: 1; key: 16 value: 0; key: 56 value: 0.
	e := self events.
	self assert: ((e detect: [:x | x first = 5 and: [(x at: 5) = $q value]]) at: 6) equals: 8.
	self assert: (e noneSatisfy: [:x | x first = 7]).
	input key: 58 value: 1; key: 58 value: 0; key: 30 value: 1; key: 30 value: 0; key: 2 value: 1; key: 2 value: 0; key: 58 value: 1; key: 58 value: 0.
	e := self events select: [:x | x first = 7].
	self assert: (e collect: [:x | x at: 7]) asArray equals: #('A' '1').
	input key: 30 value: 1; key: 30 value: 2; key: 30 value: 0.
	e := self events select: [:x | x first = 5].
	self assert: (e collect: [:x | x at: 7]) asArray equals: #(false true).
	input key: 103 value: 1; key: 103 value: 0; key: 28 value: 1.
	e := self events select: [:x | x first = 5].
	self assert: (e collect: [:x | x at: 5]) asArray equals: #(16r40000052 13)
!
testMouseAndTablet
	"Relative motion, a click, the wheel; an absolute device's point scaled to the screen."
	| e tablet |
	input device: nil type: 2 code: 0 value: 10; device: nil type: 2 code: 1 value: -5; device: nil type: 0 code: 0 value: 0.
	self assert: display pointerPosition equals: 510 @ 295.
	input device: nil type: 1 code: 16r110 value: 1; device: nil type: 0 code: 0 value: 0.
	input device: nil type: 1 code: 16r110 value: 0; device: nil type: 0 code: 0 value: 0.
	input device: nil type: 2 code: 8 value: 1; device: nil type: 0 code: 0 value: 0.
	e := self events.
	self assert: (e collect: [:x | x first]) asArray equals: #(1 2 3 4).
	self assert: ((e at: 2) at: 5) equals: 1.
	self assert: (e last at: 7) equals: 0.0 @ 1.0.
	tablet := EvdevDevice new.
	tablet instVarNamed: #absolute put: true; instVarNamed: #touchpad put: false; instVarNamed: #direct put: false.
	tablet instVarNamed: #minX put: 0; instVarNamed: #maxX put: 32767; instVarNamed: #minY put: 0; instVarNamed: #maxY put: 32767.
	input device: tablet type: 3 code: 0 value: 16384; device: tablet type: 3 code: 1 value: 8192; device: tablet type: 0 code: 0 value: 0.
	self assert: display pointerPosition equals: 500 @ 150
!
testTouchpad
	"A touchpad's finger moves the pointer by its motion; lifting it and landing elsewhere does not jump."
	| pad start |
	pad := EvdevDevice new.
	pad instVarNamed: #absolute put: true; instVarNamed: #touchpad put: true; instVarNamed: #direct put: false; instVarNamed: #touching put: false.
	pad instVarNamed: #minX put: 0; instVarNamed: #maxX put: 1000; instVarNamed: #minY put: 0; instVarNamed: #maxY put: 600.
	start := display pointerPosition.
	input device: pad type: 1 code: 16r14A value: 1.
	input device: pad type: 3 code: 0 value: 500; device: pad type: 0 code: 0 value: 0.
	input device: pad type: 3 code: 0 value: 550; device: pad type: 0 code: 0 value: 0.
	self assert: display pointerPosition x equals: start x + 50.
	input device: pad type: 1 code: 16r14A value: 0.
	input device: pad type: 1 code: 16r14A value: 1.
	input device: pad type: 3 code: 0 value: 100; device: pad type: 0 code: 0 value: 0.
	self assert: display pointerPosition x equals: start x + 50
!
testNotAskedFor
	"Without SAMALTAK_SCREEN no KMS display; a device that is not there is no screen, and says why."
	| s |
	(Smalltalk vm getenv: 'SAMALTAK_SCREEN') isNil ifTrue: [self assert: KmsDisplay requested isNil].
	PosixDevice isAvailable ifFalse: [^self].
	self assert: (KmsScreen choose: #('/nonexistent/card0')) isNil.
	s := KmsScreen path: '/nonexistent/card0'.
	self deny: s probe.
	self assert: s failure notEmpty
! !
