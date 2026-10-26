Object subclass: #RemoteInputPlanner
	instanceVariableNames: 'pointer windowId travelMilliseconds dragMilliseconds stepMilliseconds typeDelayMilliseconds pressMilliseconds timeScale'
	classVariableNames: 'KeyNames'
	package: 'System-Remote'!

RemoteInputPlanner comment: 'I turn high-level input (click at a point, drag, key combo, typing, wheel) into RemoteInputPlans of platform events (vm/platform/README.md, "Events"). Pointer travel is a series of mouseMove events over travelMilliseconds (default 100, every stepMilliseconds = 16, eased; a drag''s move with the button held takes dragMilliseconds, default 250), so the UI can animate the pointer (timeScale times slower: the UI''s slow motion); pointer is where the previous plan left it (nil: jump straight to the target). Typing is one textInput event per character, typeDelayMilliseconds apart (newline and tab are Return and Tab keys).

Key combos: ''Meta+p'', ''Shift+Meta+z'', ''Escape'', ''Meta+.'', ''Ctrl++''. Modifiers: Meta/Cmd/Command/Mod (cmd 8), Ctrl/Control (ctrl 2), Alt/Option/Opt (alt 4), Shift (shift 1). Keys: one character, or a name (Enter Return Escape Esc Tab Backspace Delete Space Up Down Left Right Home End PageUp PageDown Insert F1-F12 Plus). A combo sends keyDown for each modifier key, keyDown of the key (with textInput when it types a character: no Meta/Ctrl/Alt), keyUp, and the modifier keyUps in reverse.'!

!RemoteInputPlanner methodsFor: 'initialization'!
initialize
	travelMilliseconds := 100.
	dragMilliseconds := 250.
	stepMilliseconds := 16.
	typeDelayMilliseconds := 8.
	pressMilliseconds := 30.
	timeScale := 1
! !

!RemoteInputPlanner methodsFor: 'accessing'!
pointer
	^pointer
!
pointer: aPointOrNil
	pointer := aPointOrNil
!
windowId: anIntegerOrNil
	windowId := anIntegerOrNil
!
travelMilliseconds: anInteger
	travelMilliseconds := anInteger
!
dragMilliseconds: anInteger
	dragMilliseconds := anInteger
!
stepMilliseconds: anInteger
	stepMilliseconds := anInteger max: 1
!
typeDelayMilliseconds: anInteger
	typeDelayMilliseconds := anInteger
!
pressMilliseconds: anInteger
	pressMilliseconds := anInteger
!
timeScale: aNumber
	"Travel aNumber times slower."
	timeScale := aNumber
! !

!RemoteInputPlanner methodsFor: 'events'!
event: type at: aPoint key: key modifiers: mods extra: extra
	^{type. nil. aPoint x asFloat. aPoint y asFloat. key. mods. extra. windowId}
!
keyEvent: type key: keycode modifiers: mods
	^self event: type at: (pointer ifNil: [0 @ 0]) key: keycode modifiers: mods extra: false
! !

!RemoteInputPlanner methodsFor: 'pointer'!
moveTo: aPoint
	^self moveTo: aPoint buttons: 0 modifiers: 0
!
moveTo: aPoint buttons: buttonMask modifiers: mods
	"Plan mouseMoves from pointer to aPoint over travelMilliseconds times timeScale (one move if pointer is unknown, none if it is already there)."
	| plan start n t eased |
	plan := RemoteInputPlan new.
	start := pointer.
	start = aPoint ifTrue: [^plan].
	(start isNil or: [travelMilliseconds <= 0])
		ifTrue: [plan add: (self event: 1 at: aPoint key: buttonMask modifiers: mods extra: nil) after: 0]
		ifFalse: [
			n := (travelMilliseconds * timeScale / stepMilliseconds) rounded max: 1.
			1 to: n do: [:i |
				t := i / n.
				eased := t < (1/2) ifTrue: [2 * t * t] ifFalse: [1 - ((-2 * t + 2) squared / 2)].
				plan
					add: (self event: 1
						at: (i = n
							ifTrue: [aPoint]
							ifFalse: [(start x + ((aPoint x - start x) * eased)) @ (start y + ((aPoint y - start y) * eased))])
						key: buttonMask modifiers: mods extra: nil)
					after: (i = 1 ifTrue: [0] ifFalse: [stepMilliseconds])]].
	pointer := aPoint.
	^plan
!
arrivalMilliseconds
	"The pause between the end of a travel and the press there, so the UI's pointer arrives first."
	^(stepMilliseconds * timeScale) rounded
!
click: aPoint
	^self click: aPoint button: 1 count: 1 modifiers: 0
!
click: aPoint button: button count: clicks modifiers: mods
	"Travel to aPoint, then mouseDown/mouseUp clicks times (button 1 left, 2 middle, 3 right; the click count rises 1, 2, ...)."
	| plan |
	plan := self moveTo: aPoint.
	1 to: clicks do: [:k |
		plan add: (self event: 2 at: aPoint key: button modifiers: mods extra: k) after: (k = 1 ifTrue: [plan isEmpty ifTrue: [0] ifFalse: [self arrivalMilliseconds]] ifFalse: [pressMilliseconds]).
		plan add: (self event: 3 at: aPoint key: button modifiers: mods extra: k) after: pressMilliseconds].
	^plan
!
drag: fromPoint to: toPoint modifiers: mods
	"Travel to fromPoint, press the left button, move to toPoint over dragMilliseconds with the button held, release."
	| plan travel |
	plan := self moveTo: fromPoint.
	plan add: (self event: 2 at: fromPoint key: 1 modifiers: mods extra: 1) after: (plan isEmpty ifTrue: [0] ifFalse: [self arrivalMilliseconds]).
	travel := travelMilliseconds.
	travelMilliseconds := dragMilliseconds.
	[(self moveTo: toPoint buttons: 1 modifiers: mods) steps do: [:step |
		plan add: step last after: (step first max: stepMilliseconds)]] ensure: [travelMilliseconds := travel].
	plan add: (self event: 3 at: toPoint key: 1 modifiers: mods extra: 1) after: self arrivalMilliseconds.
	^plan
!
scroll: aPoint delta: aDelta modifiers: mods
	"Travel to aPoint and send one wheel event; aDelta is in wheel units (+y = scroll up)."
	| plan |
	plan := self moveTo: aPoint.
	plan add: (self event: 4 at: aPoint key: 0 modifiers: mods extra: aDelta x asFloat @ aDelta y asFloat) after: (plan isEmpty ifTrue: [0] ifFalse: [self arrivalMilliseconds]).
	^plan
! !

!RemoteInputPlanner methodsFor: 'keyboard'!
keyCombo: aString
	"Plan the key combo aString (see my class comment)."
	| combo plan keycode mods text held modifierKeys |
	combo := self class parseCombo: aString.
	keycode := combo first.
	mods := combo at: 2.
	text := combo at: 3.
	plan := RemoteInputPlan new.
	held := 0.
	modifierKeys := self class modifierKeysIn: mods.
	modifierKeys do: [:each |
		held := held bitOr: each first.
		plan add: (self keyEvent: 5 key: each last modifiers: held) after: 0].
	plan add: (self keyEvent: 5 key: keycode modifiers: mods) after: 0.
	text isNil ifFalse: [plan add: (self textEvent: text) after: 0].
	plan add: (self keyEvent: 6 key: keycode modifiers: mods) after: pressMilliseconds.
	modifierKeys reverseDo: [:each |
		held := held bitAnd: each first bitInvert.
		plan add: (self keyEvent: 6 key: each last modifiers: held) after: 0].
	^plan
!
keyCombos: aCollection
	| plan |
	plan := RemoteInputPlan new.
	aCollection do: [:each | plan addAll: (self keyCombo: each)].
	^plan
!
typeText: aString
	"One textInput event per character; newline and tab become Return and Tab key presses."
	^self typeText: aString delay: typeDelayMilliseconds
!
typeText: aString delay: milliseconds
	"Like typeText:, milliseconds between characters (typing like a person: about 45 to 125)."
	| plan first |
	plan := RemoteInputPlan new.
	first := true.
	aString do: [:c | | delay |
		delay := first ifTrue: [0] ifFalse: [milliseconds].
		first := false.
		(c = Character lf or: [c = Character cr])
			ifTrue: [self addPress: 13 to: plan after: delay]
			ifFalse: [
				c = Character tab
					ifTrue: [self addPress: 9 to: plan after: delay]
					ifFalse: [plan add: (self textEvent: c asString) after: delay]]].
	^plan
!
addPress: keycode to: aPlan after: milliseconds
	aPlan add: (self keyEvent: 5 key: keycode modifiers: 0) after: milliseconds.
	aPlan add: (self keyEvent: 6 key: keycode modifiers: 0) after: 0
!
textEvent: aString
	^self event: 7 at: (pointer ifNil: [0 @ 0]) key: 0 modifiers: 0 extra: aString
! !

!RemoteInputPlanner class methodsFor: 'class initialization'!
initialize
	KeyNames := Dictionary new.
	#(	'enter' 13 'return' 13 'escape' 27 'esc' 27 'tab' 9 'backspace' 8 'delete' 127 'del' 127 'space' 32
		'right' 16r4000004F 'left' 16r40000050 'down' 16r40000051 'up' 16r40000052
		'arrowright' 16r4000004F 'arrowleft' 16r40000050 'arrowdown' 16r40000051 'arrowup' 16r40000052
		'home' 16r4000004A 'end' 16r4000004D 'pageup' 16r4000004B 'pagedown' 16r4000004E 'insert' 16r40000049
		'plus' 43 'minus' 45)
			pairsDo: [:name :code | KeyNames at: name put: code].
	1 to: 12 do: [:i | KeyNames at: 'f', i printString put: 16r40000039 + i]
! !

!RemoteInputPlanner class methodsFor: 'keys'!
keyNamed: aString
	"Answer the SDL keycode for a key name (case-insensitive) or a single character, or nil."
	aString size = 1 ifTrue: [^aString first asLowercase value].
	^KeyNames at: aString asLowercase ifAbsent: [nil]
!
modifierBit: aString
	| m |
	m := aString asLowercase.
	(#('meta' 'cmd' 'command' 'mod' 'super') includes: m) ifTrue: [^8].
	(#('ctrl' 'control') includes: m) ifTrue: [^2].
	(#('alt' 'option' 'opt') includes: m) ifTrue: [^4].
	m = 'shift' ifTrue: [^1].
	^nil
!
modifiersFrom: aStringOrNil
	"Answer the modifier mask of 'Shift+Meta' (nil or empty: 0)."
	| mask |
	mask := 0.
	(aStringOrNil isNil or: [aStringOrNil isEmpty]) ifTrue: [^0].
	(aStringOrNil subStrings: '+') do: [:part |
		mask := mask bitOr: ((self modifierBit: part trimBoth) ifNil: [
			^RemoteError signal: 'unknown modifier ', part printString])].
	^mask
!
modifierKeysIn: mask
	"Answer {bit. keycode} pairs for the modifiers in mask, in press order."
	^(#(#(2 16r400000E0) #(4 16r400000E2) #(1 16r400000E1) #(8 16r400000E3))
		select: [:pair | (mask bitAnd: pair first) ~= 0]) asArray
!
parseCombo: aString
	"Answer {keycode. modifiers. text-or-nil} for a combo like 'Shift+Meta+z'."
	| parts key mods code text |
	aString isEmpty ifTrue: [^RemoteError signal: 'empty key combo'].
	parts := aString = '+' ifTrue: [OrderedCollection with: '+'] ifFalse: [(aString size > 1 and: [aString last = $+])
		ifTrue: [((aString allButLast: 2) subStrings: '+') asOrderedCollection addLast: '+'; yourself]
		ifFalse: [(aString subStrings: '+') asOrderedCollection]].
	parts isEmpty ifTrue: [^RemoteError signal: 'bad key combo ', aString printString].
	key := parts removeLast.
	mods := 0.
	parts do: [:part |
		mods := mods bitOr: ((self modifierBit: part trimBoth) ifNil: [
			^RemoteError signal: 'unknown modifier ', part printString, ' in ', aString printString])].
	code := self keyNamed: key.
	code isNil ifTrue: [^RemoteError signal: 'unknown key ', key printString, ' in ', aString printString].
	(key size = 1 and: [key first isUppercase]) ifTrue: [mods := mods bitOr: 1].
	text := nil.
	(code between: 32 and: 126) ifTrue: [
		(mods bitAnd: 2r1110) = 0 ifTrue: [
			text := key size = 1
				ifTrue: [(mods bitAnd: 1) = 0 ifTrue: [key] ifFalse: [key asUppercase]]
				ifFalse: [String with: (Character value: code)]]].
	^Array with: code with: mods with: text
! !
