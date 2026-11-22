Object subclass: #RfbInput
	instanceVariableNames: 'queue display ownsQueue scale heldKeys heldModifiers buttons altIsCmd clipboardBlock clipboardSetter lastClipboard'
	classVariableNames: 'Keys KeypadCharacters Modifiers ScanModifiers'
	package: 'System-Remote'!

RfbInput comment: 'I am a remote display client''s input (RFB, RFC 6143 7.5.4-7.5.6; one of me per connection, made after auth): its KeyEvents (X keysyms, pressed and released separately), PointerEvents (a button mask) and ClientCutText become the image''s input events and clipboard, as the hosted and firmware keyboards and pointers make them.

Keys: named keys (arrows, F1..F12, return, ...) become SDL keycodes (keycodeOf:); printable keysyms (Latin-1, 16r01000000 + Unicode, the keypad''s) a keyDown of the lowercase character, its text unless ctrl or cmd is held (alt is not: a Mac''s Option composes characters), and a keyUp when released; a capital adds shift. Modifiers are keys too (their SDL keycodes) and held state: Shift 1, Control 2, Alt 4 (cmd if altIsCmd), and cmd 8 from Meta_L/R (macOS Screen Sharing''s Command), Mode_switch (TigerVNC''s Command) and Super_L/R. A key pressed again while held is a repeat; a release of a key not held is ignored. QEMUExtendedKeyEvent (qemuKey:code:down:) maps the modifier keys by their XT scan code (16rDB/16rDC, the logo keys, are cmd), the rest by keysym.

The pointer: pointerAt:buttons: with the RFB mask (1 left, 2 middle, 4 right; a press of 8/16 a wheel notch up/down, of 32/64 left/right), in framebuffer pixels (scale: pixels a point).

Where events go: on UEFI the firmware display (display:; its pointer moves the arrow), on an operating system an InputQueue that forwards to a RemoteInputDevice (device:), which injects them with deliver: (the agent''s drawn pointer stays put), or any InputQueue (queue:, tests). forImage picks the first two.

Clipboard (Latin-1 both ways): cutText: sets the image''s clipboard (RemoteClipboard set:); once clipboardBlock: is set I watch the image''s clipboard and hand each change to the block for a ServerCutText (which sends it as Latin-1: other characters become ?, latin1BytesOf:); it runs in the Process that changed the clipboard, so it must not wait long. Text a client sent is not echoed back to it. Cut text is never logged. close releases what is held and stops watching.

For an RfbConnection (forConnection:, after authentication): key:down:, pointer:at:, cutText: and connectionClosed are its calls; the image''s clipboard goes to its sendCutText:.'!

!RfbInput methodsFor: 'initialization'!
setQueue: anInputQueue display: aDisplayOrNil owns: aBoolean
	queue := anInputQueue.
	display := aDisplayOrNil.
	ownsQueue := aBoolean.
	scale := 1.
	heldKeys := Dictionary new.
	heldModifiers := Dictionary new.
	buttons := 0.
	altIsCmd := false.
	clipboardSetter := [:s | RemoteClipboard set: s]
! !

!RfbInput methodsFor: 'accessing'!
queue
	^queue
!
extent: aPoint scale: aNumber
	"The framebuffer is aPoint pixels, aNumber pixels a point; a queue I made keeps the pointer inside it."
	scale := aNumber.
	ownsQueue ifTrue: [queue extent: (aPoint / aNumber) ceiling]
!
altIsCmd
	^altIsCmd
!
altIsCmd: aBoolean
	"Alt is cmd, as the firmware keyboard and Linux have it (default false: the Mac viewers send Command as Meta or Mode_switch)."
	altIsCmd := aBoolean
!
modifiers
	"The image's modifier bits held: 1 shift, 2 ctrl, 4 alt, 8 cmd."
	^heldModifiers inject: 0 into: [:m :bit | m bitOr: bit]
!
buttons
	"The RFB button mask last reported."
	^buttons
! !

!RfbInput methodsFor: 'keys'!
key: keysym down: down
	"A KeyEvent."
	| bit code ch mods text repeat |
	(Modifiers at: keysym ifAbsent: [nil]) ifNotNil: [:m |
		bit := ((m first = 4) and: [altIsCmd]) ifTrue: [8] ifFalse: [m first].
		down
			ifTrue: [
				repeat := heldModifiers includesKey: keysym.
				heldModifiers at: keysym put: bit.
				queue keyDown: m last modifiers: self modifiers repeat: repeat]
			ifFalse: [
				(heldModifiers includesKey: keysym) ifFalse: [^self].
				heldModifiers removeKey: keysym.
				queue keyUp: m last modifiers: self modifiers].
		^self].
	mods := self modifiers.
	code := self class keycodeOf: keysym.
	ch := code = 0 ifTrue: [self class characterOf: keysym] ifFalse: [nil].
	ch isNil ifFalse: [
		code := self class lowercaseOf: ch.
		code ~= ch ifTrue: [mods := mods bitOr: 1]].
	code = 0 ifTrue: [^self].
	down ifFalse: [
		(heldKeys includesKey: keysym)
			ifTrue: [code := heldKeys removeKey: keysym]
			ifFalse: [(heldKeys keyAtValue: code ifAbsent: [nil]) ifNil: [^self] ifNotNil: [:k | heldKeys removeKey: k]].
		^queue keyUp: code modifiers: mods].
	repeat := heldKeys includesKey: keysym.
	heldKeys at: keysym put: code.
	text := (ch notNil and: [ch >= 32 and: [ch ~= 127 and: [(mods bitAnd: 10) = 0]]])
		ifTrue: [(Character value: ch) asString].
	queue keyDown: code modifiers: mods repeat: repeat.
	text isNil ifFalse: [queue text: text modifiers: mods]
!
qemuKey: keysym code: scancode down: down
	"A QEMUExtendedKeyEvent: the modifier keys by their XT scan code (the logo keys are cmd), the others by keysym."
	self key: (ScanModifiers at: scancode ifAbsent: [keysym]) down: down
! !

!RfbInput methodsFor: 'pointer'!
pointerAt: aPoint buttons: mask
	"A PointerEvent: aPoint in framebuffer pixels, mask RFB's (1 left, 2 middle, 4 right, 8/16 wheel up/down, 32/64 wheel left/right: a press is a notch)."
	| pressed dx dy p |
	pressed := mask bitClear: buttons.
	dx := dy := 0.
	(pressed bitAnd: 8) ~= 0 ifTrue: [dy := dy + 1].
	(pressed bitAnd: 16) ~= 0 ifTrue: [dy := dy - 1].
	(pressed bitAnd: 32) ~= 0 ifTrue: [dx := dx - 1].
	(pressed bitAnd: 64) ~= 0 ifTrue: [dx := dx + 1].
	buttons := mask.
	p := scale = 1 ifTrue: [aPoint] ifFalse: [aPoint / scale].
	(display ifNil: [queue]) pointerAt: p buttons: (mask bitAnd: 7) wheel: (dx = 0 ifTrue: [dy] ifFalse: [dx @ dy])
! !

!RfbInput methodsFor: 'clipboard'!
cutText: aByteArrayOrString
	"A ClientCutText (Latin-1): the image's clipboard."
	| s |
	s := self class latin1StringOf: aByteArrayOrString.
	lastClipboard := s.
	clipboardSetter value: s
!
clipboardSetter: aBlock
	"aBlock value: aString sets the image's clipboard (default: RemoteClipboard set:)."
	clipboardSetter := aBlock
!
clipboardBlock: aBlockOrNil
	"Hand the image's clipboard, when it changes, to aBlock (value: aString; nil: stop watching)."
	clipboardBlock := aBlockOrNil.
	aBlockOrNil isNil
		ifTrue: [RemoteClipboard unwatch: self]
		ifFalse: [RemoteClipboard watch: self]
!
clipboardChanged: aString
	"The image's clipboard is aString: for the client, unless it came from it."
	| block |
	block := clipboardBlock.
	(block isNil or: [aString = lastClipboard]) ifTrue: [^self].
	lastClipboard := aString.
	block value: aString
! !

!RfbInput methodsFor: 'connection'!
pointer: mask at: aPoint
	"RfbConnection's PointerEvent."
	self pointerAt: aPoint buttons: mask
!
connectionClosed
	"The RfbConnection closed."
	self close
! !

!RfbInput methodsFor: 'closing'!
releaseAll
	"Release the keys and buttons the client holds (it went away)."
	heldKeys keys do: [:k | self key: k down: false].
	heldModifiers keys do: [:k | self key: k down: false].
	(buttons bitAnd: 7) ~= 0 ifTrue: [
		buttons := 0.
		(display ifNil: [queue]) pointerAt: queue position buttons: 0 wheel: 0].
	buttons := 0
!
close
	self releaseAll.
	self clipboardBlock: nil
! !

!RfbInput class methodsFor: 'class initialization'!
initialize
	"X keysyms (X11 keysymdef.h) to SDL keycodes; the keypad's printable keys; modifiers {bit. SDL keycode}; XT scan codes of the modifier keys to their keysyms."
	| m |
	Keys := Dictionary new.
	#(16rFF08 8 16rFF09 9 16rFE20 9 16rFF0D 13 16rFF8D 13 16rFF1B 27 16rFFFF 127 16rFF9F 127
		16rFF50 16r4000004A 16rFF51 16r40000050 16rFF52 16r40000052 16rFF53 16r4000004F 16rFF54 16r40000051
		16rFF55 16r4000004B 16rFF56 16r4000004E 16rFF57 16r4000004D 16rFF63 16r40000049
		16rFF95 16r4000004A 16rFF96 16r40000050 16rFF97 16r40000052 16rFF98 16r4000004F 16rFF99 16r40000051
		16rFF9A 16r4000004B 16rFF9B 16r4000004E 16rFF9C 16r4000004D 16rFF9E 16r40000049 16rFF89 9)
		pairsDo: [:sym :code | Keys at: sym put: code].
	0 to: 11 do: [:i | Keys at: 16rFFBE + i put: 16r4000003A + i].
	KeypadCharacters := Dictionary new.
	#(16rFF80 32 16rFFAA 42 16rFFAB 43 16rFFAC 44 16rFFAD 45 16rFFAE 46 16rFFAF 47 16rFFBD 61)
		pairsDo: [:sym :ch | KeypadCharacters at: sym put: ch].
	0 to: 9 do: [:i | KeypadCharacters at: 16rFFB0 + i put: 48 + i].
	Modifiers := Dictionary new.
	m := #(16rFFE1 1 16r400000E1 16rFFE2 1 16r400000E5 16rFFE3 2 16r400000E0 16rFFE4 2 16r400000E4
		16rFFE9 4 16r400000E2 16rFFEA 4 16r400000E6 16rFE03 4 16r400000E6
		16rFFE7 8 16r400000E3 16rFFE8 8 16r400000E7 16rFFEB 8 16r400000E3 16rFFEC 8 16r400000E7 16rFF7E 8 16r400000E3).
	1 to: m size by: 3 do: [:i | Modifiers at: (m at: i) put: {m at: i + 1. m at: i + 2}].
	ScanModifiers := Dictionary new.
	#(16r2A 16rFFE1 16r36 16rFFE2 16r1D 16rFFE3 16r9D 16rFFE4 16r38 16rFFE9 16rB8 16rFFEA 16rDB 16rFFEB 16rDC 16rFFEC)
		pairsDo: [:scan :sym | ScanModifiers at: scan put: sym]
! !

!RfbInput class methodsFor: 'translating'!
keycodeOf: keysym
	"The SDL keycode of a named (not printable) key's keysym; 0 if none."
	^Keys at: keysym ifAbsent: [0]
!
characterOf: keysym
	"The Unicode code point a printable keysym types, or nil: Latin-1 (keysym = code point), 16r01000000 + Unicode, EuroSign, the keypad's."
	((keysym between: 16r20 and: 16r7E) or: [keysym between: 16rA0 and: 16rFF]) ifTrue: [^keysym].
	(keysym between: 16r01000020 and: 16r0110FFFF) ifTrue: [^keysym - 16r01000000].
	keysym = 16r20AC ifTrue: [^keysym].
	^KeypadCharacters at: keysym ifAbsent: [nil]
!
lowercaseOf: codePoint
	"A capital's small letter (ASCII and Latin-1), else codePoint."
	((codePoint between: 65 and: 90) or: [(codePoint between: 16rC0 and: 16rDE) and: [codePoint ~= 16rD7]])
		ifTrue: [^codePoint + 32].
	^codePoint
!
isModifier: keysym
	^Modifiers includesKey: keysym
!
latin1StringOf: aByteArrayOrString
	"ClientCutText's Latin-1 bytes as a String."
	| s |
	aByteArrayOrString isString ifTrue: [^aByteArrayOrString].
	s := String new: aByteArrayOrString size.
	1 to: aByteArrayOrString size do: [:i | s at: i put: (Character value: (aByteArrayOrString at: i))].
	^s
!
latin1BytesOf: aString
	"aString as Latin-1 bytes for ServerCutText: characters beyond Latin-1 become ? (lossy)."
	| b |
	b := ByteArray new: aString size.
	1 to: aString size do: [:i | | v |
		v := (aString at: i) value.
		b at: i put: (v > 255 ifTrue: [63] ifFalse: [v])].
	^b
! !

!RfbInput class methodsFor: 'instance creation'!
queue: anInputQueue
	"Events into anInputQueue (its pointer too)."
	^self new setQueue: anInputQueue display: nil owns: false
!
display: aFirmwareDisplay
	"Keys into the firmware display's queue, the pointer through it (it moves the arrow)."
	^self new setQueue: aFirmwareDisplay queue display: aFirmwareDisplay owns: false
!
device: aRemoteInputDevice
	"Events made by an InputQueue of my own, injected by aRemoteInputDevice (deliver:) into its window (windowId)."
	| q |
	q := InputQueue new.
	q extent: 65536 @ 65536.
	q forwardTo: [:e |
		aRemoteInputDevice windowId ifNotNil: [:id | e at: 8 put: id].
		aRemoteInputDevice deliver: e].
	^self new setQueue: q display: nil owns: true
!
forImage
	"The firmware display's input on UEFI, else injection by the default RemoteInputDevice into the World's window (its points: the screen's pixels / its display scale)."
	| world input |
	FirmwareDisplay current ifNotNil: [:d | ^self display: d].
	input := self device: RemoteInputDevice default.
	world := (Smalltalk at: #World ifAbsent: [nil]) ifNotNil: [:c | c current].
	world isNil ifFalse: [input extent: world extent * world displayScale scale: world displayScale].
	^input
!
forConnection: anRfbConnection
	"The input of an authenticated RfbConnection: into the image (forImage); the image's clipboard to its client."
	^self forImage clipboardBlock: [:s | anRfbConnection sendCutText: s]; yourself
! !
