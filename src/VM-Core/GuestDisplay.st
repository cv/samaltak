CLibrary subclass: #GuestDisplay
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

GuestDisplay comment: 'The guest''s display (DisplayPrimitives), simulated only: the method bodies draw into and read input from the screen the simulation was given (VMSimulation>>display:, the VM Simulator''s screen pane), which clips. The C VM has no such library: its headers define every call as failing, and displayOpen fails first, so the other primitives never get here.

The screen answers open: w height: h (the character cell, a Point, or nil), fillX:y:width:height:rule:, copyX:y:width:height:toX:y:, text:x:y:rule:, bits:x:y:width:height:rule:, nextEvent (an Array of 5 integers, or nil) and flush.'!

!GuestDisplay class methodsFor: 'declaring'!
headers
	^#('#define guest_display_open(w, h, cell) ((void)(w), (void)(h), (void)(cell), false)'
		'#define guest_display_fill(x, y, w, h, rule) ((void)(x), (void)(y), (void)(w), (void)(h), (void)(rule))'
		'#define guest_display_copy(x, y, w, h, to_x, to_y) ((void)(x), (void)(y), (void)(w), (void)(h), (void)(to_x), (void)(to_y))'
		'#define guest_display_text(bytes, n, x, y, rule) ((void)(bytes), (void)(n), (void)(x), (void)(y), (void)(rule))'
		'#define guest_display_bits(bytes, x, y, w, h, rule) ((void)(bytes), (void)(x), (void)(y), (void)(w), (void)(h), (void)(rule))'
		'#define guest_display_next_event(event) ((void)(event), false)'
		'#define guest_display_flush() ((void)0)')
! !

!GuestDisplay methodsFor: 'display'!
open: w height: h cell: cell
	"Open the screen, white; cell[0] and cell[1] get the character cell's width and height."
	<c: 'bool guest_display_open(int w, int h, int32_t *cell)'>
	| extent |
	sim display isNil ifTrue: [^false].
	extent := sim display open: w height: h.
	extent isNil ifTrue: [^false].
	cell at: 0 put: extent x.
	cell at: 1 put: extent y.
	^true
!
fillX: x y: y width: w height: h rule: rule
	<c: 'void guest_display_fill(int x, int y, int w, int h, int rule)'>
	sim display fillX: x y: y width: w height: h rule: rule
!
copyX: x y: y width: w height: h toX: toX y: toY
	<c: 'void guest_display_copy(int x, int y, int w, int h, int to_x, int to_y)'>
	sim display copyX: x y: y width: w height: h toX: toX y: toY
!
text: bytes size: n x: x y: y rule: rule
	<c: 'void guest_display_text(const uint8_t *bytes, size_t n, int x, int y, int rule)'>
	sim display text: (self memory bytesAt: (self memory addressOf: bytes) count: n) asString x: x y: y rule: rule
!
bits: bytes x: x y: y width: w height: h rule: rule
	<c: 'void guest_display_bits(const uint8_t *bytes, int x, int y, int w, int h, int rule)'>
	sim display bits: (self memory bytesAt: (self memory addressOf: bytes) count: w + 7 // 8 * h) x: x y: y width: w height: h rule: rule
!
nextEvent: event
	"Fill event[0..4] with the next input event; false if there is none."
	<c: 'bool guest_display_next_event(int64_t *event)'>
	| e |
	e := sim display nextEvent.
	e isNil ifTrue: [^false].
	e doWithIndex: [:v :i | event at: i - 1 put: v].
	^true
!
flush
	<c: 'void guest_display_flush(void)'>
	sim display flush
! !
