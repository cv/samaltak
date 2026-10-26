Object subclass: #TopBar
	instanceVariableNames: 'world costs ends index count msText fpsText processCount procText lastUpdate fonts tagState'
	classVariableNames: ''
	package: 'UI-Windows'!

TopBar comment: 'I am the menu bar at the top of the World (Blue Book: white, a 1-point rule): the brand, the image name, the VM''s banner (Smalltalk vm banner), the hint "Click the desktop for the World menu", at the right the ? button (World helpHandler) and the REMOTE tag once a remote session acted on the image (it flashes at each command), the SLOW tag while animations run slowed down (Animation timeScale), and the compositor''s statistics — a sparkline of the last 64 frame times (ms between presented frames, the 16.7 ms budget as a hairline: a stutter shows as a spike), the mean frame time of the last 32 frames, the frames presented in the last second and the number of Processes. The Compositor feeds me FrameRecords-worth of numbers (noteFrame:end:) and draws me every frame.'!

!TopBar methodsFor: 'initialization'!
setWorld: aWorld
	world := aWorld.
	costs := Array new: 64 withAll: 0.
	ends := Array new: 64 withAll: 0.
	index := 0.
	count := 0.
	msText := '– ms'.
	fpsText := '– fps'.
	processCount := 0.
	procText := ''.
	lastUpdate := 0
! !

!TopBar methodsFor: 'accessing'!
height
	"26 points and the rule."
	^27
!
processCount
	^processCount
!
statsText
	^msText, ' ', fpsText, ' | ', procText
!
font: aSymbol
	fonts isNil ifTrue: [fonts := IdentityDictionary new].
	^fonts at: aSymbol ifAbsent: [
		fonts at: aSymbol put: (aSymbol == #mono
			ifTrue: [Font faceNamed: 'JetBrainsMono-Regular' size: 11]
			ifFalse: [aSymbol == #monoBold
				ifTrue: [Font faceNamed: 'JetBrainsMono-Bold' size: 11]
				ifFalse: [aSymbol == #brand
					ifTrue: [Font faceNamed: 'IosevkaEtoile-Italic' size: 14]
					ifFalse: [aSymbol == #italic
						ifTrue: [Font faceNamed: 'IosevkaEtoile-Italic' size: 13]
						ifFalse: [Font faceNamed: 'IosevkaEtoile-Regular' size: 13]]]])]
!
resetFonts
	fonts := nil
! !

!TopBar methodsFor: 'statistics'!
noteFrame: costMicros end: endMicros
	"A frame was presented at endMicros: note the frame time (ms since the previous frame; costMicros is the compositor's work for it)."
	| previous |
	previous := count = 0 ifTrue: [endMicros - costMicros] ifFalse: [ends at: index].
	index := index \\ 64 + 1.
	costs at: index put: (endMicros - previous min: 1000000) / 1000.0.
	ends at: index put: endMicros.
	count := count + 1
!
processCount: anInteger
	processCount := anInteger
!
updateAt: nowMicros
	"Refresh the texts at most twice a second; answer whether they changed."
	| n sum fps old recent tag |
	tag := Array with: (self remoteSince: nowMicros // 1000) with: Animation timeScale.
	tag = tagState ifFalse: [tagState := tag. ^true].
	nowMicros - lastUpdate < 500000 ifTrue: [^false].
	lastUpdate := nowMicros.
	old := self statsText.
	n := count min: 32.
	sum := 0.
	0 to: n - 1 do: [:i | sum := sum + (costs at: (index - i - 1) \\ 64 + 1)].
	recent := ends count: [:e | e > 0 and: [nowMicros - e <= 1000000]].
	fps := recent.
	msText := n = 0 ifTrue: ['– ms'] ifFalse: [((sum / n) printShowingDecimalPlaces: 1), ' ms'].
	fpsText := fps printString, ' fps'.
	procText := processCount printString, ' processes'.
	^old ~= self statsText
! !

!TopBar methodsFor: 'drawing'!
drawOn: c
	| w x right y font bold mono monoBold label hintLeft banner |
	w := world extent x.
	c fillRect: (0 @ 0 extent: w @ 26) color: Color white.
	c fillRect: (0 @ 26 extent: w @ 1) color: Color black.
	c image: (UIIcons orbScale: c scale) in: (14 @ 5 extent: 16 @ 16).
	font := self font: #brand.
	y := (26 - font lineHeight / 2) rounded.
	c drawString: 'Samaltak' at: 37 @ y font: font color: Color black.
	c drawString: 'Samaltak' at: 37.5 @ y font: font color: Color black.
	x := 37 + (font widthOf: 'Samaltak') + 14.
	c fillRect: (x @ 7 extent: 1 @ 13) color: Color black.
	x := x + 15.
	font := self font: #regular.
	c drawString: world imageName at: x @ (26 - font lineHeight / 2) rounded font: font color: Color black.
	hintLeft := x + (font widthOf: world imageName) + 14.
	(banner := Smalltalk vm banner) isNil ifFalse: [
		c fillRect: (hintLeft @ 7 extent: 1 @ 13) color: Color black.
		c drawString: banner at: (hintLeft + 15) @ (26 - font lineHeight / 2) rounded font: font color: Color black.
		hintLeft := hintLeft + 15 + (font widthOf: banner) + 14].
	"right to left"
	mono := self font: #mono.
	monoBold := self font: #monoBold.
	y := (26 - mono lineHeight / 2) rounded.
	right := w - 12.
	World helpHandler notNil ifTrue: [
		right := self drawHelpOn: c right: right.
		right := right - 8].
	(self remoteSince: (Time millisecondClockValue)) ifNotNil: [:flash |
		right := self drawRemoteTagOn: c right: right flash: flash.
		right := right - 10].
	Animation timeScale = 1 ifFalse: [
		right := self drawSlowTagOn: c right: right.
		right := right - 10].
	right := right - (mono widthOf: procText).
	c drawString: procText at: right @ y font: mono color: Color black.
	right := right - 8.
	c fillRect: (right @ 7 extent: 1 @ 13) color: Color black.
	right := right - 7 - (mono widthOf: fpsText).
	c drawString: fpsText at: right @ y font: mono color: Color black.
	right := right - 7 - (monoBold widthOf: msText).
	c drawString: msText at: right @ y font: monoBold color: Color black.
	right := right - 7 - 64.
	self drawSparkOn: c in: (right @ 5 extent: 64 @ 16).
	label := Font header.
	right := right - 7 - (label widthOf: 'compositor').
	c drawString: 'compositor' at: right @ (26 - label lineHeight / 2) rounded font: label color: Color black.
	font := self font: #italic.
	c drawString: 'Click the desktop for the World menu'
		in: (hintLeft @ 0 corner: (right - 14) @ 26) font: font color: (Color named: #ink3) align: #center
!
drawSparkOn: c in: r
	| yOf prev n |
	"0 … 33.4 ms (two frame budgets) bottom to top; a frame over 20 ms (a missed vsync) gets a dot"
	yOf := [:v | r top + 15 - (((v max: 0) min: 33.4) / 33.4 * 14)].
	n := count min: 64.
	n < 2 ifTrue: [^self].
	prev := nil.
	n - 1 to: 0 by: -1 do: [:age |
		| v p |
		v := costs at: (index - age - 1) \\ 64 + 1.
		p := (r right - age) @ (yOf value: v).
		prev isNil ifFalse: [c line: prev to: p color: Color ultramarine width: 1].
		v > 20 ifTrue: [c fillRect: (p - (1.5 @ 1.5) extent: 3 @ 3) color: Color ultramarine].
		prev := p]
! !

!TopBar methodsFor: 'remote tag'!
remoteSince: nowMs
	"nil while no remote session acted on the image; else whether its last command is less than 220 ms old (the tag flashes)."
	| last |
	last := RemoteControl lastRequestTime.
	last isNil ifTrue: [^nil].
	^nowMs - last < 220
!
drawRemoteTagOn: c right: right flash: aBoolean
	"The prototype's REMOTE tag: a small ultramarine-framed caps label with a dot; inverted while it flashes."
	| font label w r ink |
	font := Font header.
	label := 'REMOTE'.
	w := 6 + 6 + 5 + (font widthOf: label) + 6.
	r := (right - w) @ 4 extent: w @ 18.
	ink := aBoolean ifTrue: [Color white] ifFalse: [Color ultramarine].
	aBoolean ifTrue: [c fillRect: r color: Color ultramarine].
	c strokeRect: r color: Color ultramarine width: 1.
	c fillRect: ((r left + 6) @ (r top + 6) extent: 6 @ 6) color: ink.
	c drawString: label at: (r left + 17) @ (r top + (18 - font lineHeight / 2) rounded) font: font color: ink.
	^r left
!
drawSlowTagOn: c right: right
	"While animations run slowed down: an ultramarine tag with the factor, e.g. 10× SLOW."
	| font label w r |
	font := Font header.
	label := Animation timeScale printString, '× SLOW'.
	w := 6 + (font widthOf: label) + 6.
	r := (right - w) @ 4 extent: w @ 18.
	c fillRect: r color: Color ultramarine.
	c drawString: label at: (r left + 6) @ (r top + (18 - font lineHeight / 2) rounded) font: font color: Color white.
	^r left
!
drawHelpOn: c right: right
	"The ? button (opens Help, like the World menu's Help…)."
	| r font |
	font := self font: #regular.
	r := (right - 20) @ 3 extent: 20 @ 20.
	c drawString: '?' in: r font: font color: Color black align: #center.
	^r left
!
helpRect
	^(world extent x - 32) @ 3 extent: 20 @ 20
! !

!TopBar methodsFor: 'remote control'!
remoteRole
	^#topbar
!
remoteLabel
	^Smalltalk vm banner ifNil: [world imageName] ifNotNil: [:b | world imageName, ' | ', b]
!
remoteName
	^'top'
!
remoteState
	^Array with: 'compositor="', msText, ' ', fpsText, '"' with: 'processes=', processCount printString
!
remoteBounds
	^0 @ 0 extent: world extent x @ 26
!
remoteChildren
	^#()
! !

!TopBar class methodsFor: 'instance creation'!
world: aWorld
	^self new setWorld: aWorld
! !
