Object subclass: #DamageProbe
	instanceVariableNames: 'compositor previousKeys listKeys scenarios current lastDamage'
	classVariableNames: ''
	package: 'UI-Windows'!

DamageProbe comment: 'I measure how much of each frame the compositor presents actually changes, for damage-limited composition (docs/graphics-damage.md). Off by default; while I run (DamageProbe start, on the current World''s compositor) the compositor hands me each presented frame, and StageTimes counts the stages below it.

Damage is what changed between two presented frames, found from the display lists, not the pixels: every quad has a key (its position and what its clip leaves of it, mode, color, the texels of glyphs, images and lines, the texture of glyphs and images: solid and pattern quads leave their texels unwritten and join any batch); a quad whose key is new or gone damages its bounds (within its clip). I compare the whole screen''s composite list with the previous frame''s (windows moved, raised, fading, the top bar, toasts, the pointer), and for each layer rendered again its old content and chrome lists with the new ones, placed where the layer is on screen (what changed inside a window; windows above it are not subtracted). The damaged area is counted in 16 × 16 pixel tiles (QEMU''s VNC server compares 16 pixels wide).

Per frame I keep {start µs. damaged px (tiles). bounding box px. rectangles. layers rendered. layer px. screen px. draw µs. layers µs. show µs. StageTimes of the frame. my own µs. its FrameRecord}, under the scenario marked last (mark:). summary answers a line per scenario; csv: aName the frames.

	DamageProbe start.
	DamageProbe current mark: ''typing''.
	DamageProbe current summary.
	DamageProbe stop'!

!DamageProbe methodsFor: 'initialization'!
setCompositor: aCompositor
	compositor := aCompositor.
	previousKeys := Dictionary new.
	listKeys := IdentityDictionary new.
	scenarios := OrderedCollection new.
	self mark: 'start'
! !

!DamageProbe methodsFor: 'accessing'!
compositor
	^compositor
!
lastDamage
	"The rectangles (device pixels) the last frame damaged."
	^lastDamage
!
scenarios
	"{name. frames. start µs. start tick. end µs. end tick} each."
	^scenarios
! !

!DamageProbe methodsFor: 'scenarios'!
mark: aString
	"Count the frames from now on under aString."
	| now next |
	now := Time microsecondClockValue.
	self finish.
	next := Array new: 6.
	next at: 1 put: aString; at: 2 put: OrderedCollection new; at: 3 put: now; at: 4 put: compositor tickCount.
	scenarios add: next.
	current := next
!
finish
	current isNil ifFalse: [
		current at: 5 put: Time microsecondClockValue; at: 6 put: compositor tickCount.
		current := nil]
! !

!DamageProbe methodsFor: 'frames'!
beforeRender: windows
	"What the layers of windows showed before this frame renders them again: {window. content. chrome. rendered} each."
	^windows collect: [:w | Array with: w with: w layer renderedContent with: w layer renderedChrome with: w layer isRendered]
!
frame: aDisplayList rendered: before start: t0 draw: drawUs layers: layerUs show: showUs record: aFrameRecord
	"The compositor presented aDisplayList (the whole screen) after rendering the layers of before (beforeRender:)."
	| t screen damage keys scale layerPx bbox stages |
	current isNil ifTrue: [^self].
	t := Time microsecondClockValue.
	screen := 0 @ 0 extent: aDisplayList pixelExtent.
	scale := compositor world displayScale.
	damage := OrderedCollection new.
	keys := self keysOf: aDisplayList.
	self diff: previousKeys with: keys into: damage clip: screen offset: 0 @ 0.
	previousKeys := keys.
	layerPx := 0.
	before do: [:each | | w layer origin clip |
		w := each first.
		layer := w layer.
		layer pixelExtent isNil ifFalse: [
			layerPx := layerPx + (layer pixelExtent x * layer pixelExtent y).
			origin := ((w bounds origin + layer offset) * scale) rounded.
			clip := (origin extent: layer pixelExtent) intersect: screen.
			(each at: 4)
				ifTrue: [
					self diff: (self keysOfLayerList: (each at: 2)) with: (self keysOfLayerList: layer renderedContent) into: damage clip: clip offset: origin.
					self diff: (self keysOfLayerList: (each at: 3)) with: (self keysOfLayerList: layer renderedChrome) into: damage clip: clip offset: origin]
				ifFalse: [(clip width > 0 and: [clip height > 0]) ifTrue: [damage add: clip]]]].
	self pruneLists.
	lastDamage := damage.
	bbox := 0.
	damage isEmpty ifFalse: [| l tp r b |
		l := tp := 1000000.
		r := b := -1000000.
		damage do: [:each |
			l := l min: each left. tp := tp min: each top.
			r := r max: each right. b := b max: each bottom].
		bbox := (r - l) * (b - tp)].
	stages := StageTimes current isNil ifTrue: [Dictionary new] ifFalse: [StageTimes current takeFrame].
	(current at: 2) add: {t0. self tileAreaOf: damage in: screen. bbox. damage size. before size. layerPx. screen width * screen height.
		drawUs. layerUs. showUs. stages. Time microsecondClockValue - t. aFrameRecord}
! !

!DamageProbe methodsFor: 'damage'!
keysOf: aDisplayList
	"Each quad's key (position, texture, clip, mode, color, texels) -> {count. its device-pixel bounds within its clip}."
	| keys v |
	keys := Dictionary new.
	aDisplayList isNil ifTrue: [^keys].
	v := aDisplayList vertices.
	aDisplayList batches do: [:b | | base textured clip |
		"Solid and pattern quads join whatever batch is open: only glyph and image quads depend on its texture."
		"The clip counts by what it leaves of a quad (keyed below), not as such: a replayed view's batch may carry another scissor that cuts nothing."
		base := 7.
		clip := b scissor.
		clip isNil ifFalse: [clip := (clip at: 1) @ (clip at: 2) extent: (clip at: 3) @ (clip at: 4)].
		textured := self mix: base with: (b texture isNil ifTrue: [0] ifFalse: [b texture identityHash]).
		b first to: b first + b count - 1 by: 6 do: [:i | | p mode k x0 y0 x1 y1 r e |
			p := i * 40 + 1.
			mode := v uint32At: p + 28.
			k := self mix: (self mix: (((mode bitAnd: 255) between: 1 and: 2) ifTrue: [textured] ifFalse: [base]) with: mode) with: (v uint32At: p + 24).
			"Solid and pattern quads leave their texels unwritten (a reused buffer's old bytes)."
			(#(1 2 5) includes: (mode bitAnd: 255)) ifTrue: [k := self mix: (self mix: k with: (v uint32At: p + 16)) with: (v uint32At: p + 20)].
			(mode bitAnd: 16r80000000) = 0
				ifTrue: [| ox oy |
					ox := (v float32At: p + 32) + b dx.
					oy := (v float32At: p + 36) + b dy.
					x0 := (v float32At: p) + ox.
					y0 := (v float32At: p + 4) + oy.
					x1 := (v float32At: p + 8) + ox.
					y1 := (v float32At: p + 12) + oy.
					k := self mix: (self mix: (self mix: (self mix: k with: (x0 * 64) rounded) with: (y0 * 64) rounded) with: (x1 * 64) rounded) with: (y1 * 64) rounded]
				ifFalse: [
					x0 := 1.0e30. y0 := 1.0e30. x1 := -1.0e30. y1 := -1.0e30.
					0 to: 5 do: [:j | | q x y |
						q := p + (j * 40).
						x := (v float32At: q) + (v float32At: q + 32) + b dx.
						y := (v float32At: q + 4) + (v float32At: q + 36) + b dy.
						k := self mix: (self mix: k with: (x * 64) rounded) with: (y * 64) rounded.
						x0 := x0 min: x. y0 := y0 min: y. x1 := x1 max: x. y1 := y1 max: y].
					x0 := x0 - 1. y0 := y0 - 1. x1 := x1 + 1. y1 := y1 + 1].
			r := (x0 floor @ y0 floor) corner: (x1 ceiling @ y1 ceiling).
			clip isNil ifFalse: [r := r intersect: clip].
			(r width > 0 and: [r height > 0]) ifTrue: [
				k := self mix: (self mix: (self mix: (self mix: k with: r left) with: r top) with: r right) with: r bottom.
				e := keys at: k ifAbsent: [nil].
				e isNil
					ifTrue: [keys at: k put: (Array with: 1 with: r)]
					ifFalse: [e at: 1 put: e first + 1]]]].
	^keys
!
keysOfLayerList: aDisplayListOrNil
	aDisplayListOrNil isNil ifTrue: [^Dictionary new].
	^listKeys at: aDisplayListOrNil ifAbsent: [listKeys at: aDisplayListOrNil put: (self keysOf: aDisplayListOrNil)]
!
pruneLists
	"Keep the keys of the lists the layers show now only."
	| live world |
	live := IdentitySet new.
	world := compositor world.
	(world windows, world overlays, world closingWindows) do: [:w |
		w layer renderedContent isNil ifFalse: [live add: w layer renderedContent].
		w layer renderedChrome isNil ifFalse: [live add: w layer renderedChrome]].
	listKeys keys do: [:each | (live includes: each) ifFalse: [listKeys removeKey: each]]
!
mix: h with: n
	^((h bitAnd: 16rFFFFFFFF) * 16777619) + (n bitAnd: 16rFFFFFFFF)
!
diff: oldKeys with: newKeys into: damage clip: aRectangle offset: aPoint
	"The bounds of the quads drawn in one and not the other, moved by aPoint and clipped to aRectangle, into damage."
	newKeys keysAndValuesDo: [:k :e | | o |
		o := oldKeys at: k ifAbsent: [nil].
		(o isNil or: [o first ~= e first]) ifTrue: [self add: e last to: damage clip: aRectangle offset: aPoint]].
	oldKeys keysAndValuesDo: [:k :e |
		(newKeys includesKey: k) ifFalse: [self add: e last to: damage clip: aRectangle offset: aPoint]]
!
add: aRectangle to: damage clip: clipRectangle offset: aPoint
	| r |
	r := (aRectangle translateBy: aPoint) intersect: clipRectangle.
	(r width > 0 and: [r height > 0]) ifTrue: [damage add: r]
!
tileAreaOf: rectangles in: screen
	"The pixels of the 16 x 16 tiles rectangles touch."
	| cols rows tiles n |
	rectangles isEmpty ifTrue: [^0].
	cols := screen width + 15 // 16.
	rows := screen height + 15 // 16.
	tiles := ByteArray new: cols * rows.
	rectangles do: [:r |
		(r top // 16 max: 0) to: (r bottom - 1 // 16 min: rows - 1) do: [:y |
			(r left // 16 max: 0) to: (r right - 1 // 16 min: cols - 1) do: [:x | tiles at: y * cols + x + 1 put: 1]]].
	n := 0.
	tiles do: [:each | n := n + each].
	^n * 256 min: screen width * screen height
! !

!DamageProbe methodsFor: 'reporting'!
summary
	"A line per scenario: frames presented and ticks; the share of frames by damaged fraction of the screen (none, < 1 %, < 10 %, < 50 %, more); damaged px a frame (mean, median, 90th percentile) and the damaged share of what was composited; layers rendered; µs a frame (mean/median) of the compositor's stages and StageTimes'."
	| s |
	s := WriteStream on: String new.
	scenarios do: [:each | self summarize: each on: s. s nextPut: Character lf].
	^s contents
!
summarize: aScenario on: s
	| frames n secs ticks screen dmg buckets stages gpu keys quiet |
	frames := aScenario at: 2.
	n := frames size.
	secs := ((aScenario at: 5) ifNil: [Time microsecondClockValue]) - (aScenario at: 3) / 1000000.0.
	ticks := ((aScenario at: 6) ifNil: [compositor tickCount]) - (aScenario at: 4).
	s nextPutAll: (aScenario at: 1); nextPutAll: ': '; print: n; nextPutAll: ' frames, '; print: ticks; nextPutAll: ' ticks in '; nextPutAll: (secs printShowingDecimalPlaces: 1); nextPutAll: ' s'.
	n = 0 ifTrue: [^self].
	screen := (frames first at: 7) asFloat.
	dmg := frames collect: [:f | f at: 2].
	buckets := Array new: 5 withAll: 0.
	dmg do: [:d | | share i |
		share := d / screen.
		i := d = 0 ifTrue: [1] ifFalse: [share < 0.01 ifTrue: [2] ifFalse: [share < 0.1 ifTrue: [3] ifFalse: [share < 0.5 ifTrue: [4] ifFalse: [5]]]].
		buckets at: i put: (buckets at: i) + 1].
	s nextPutAll: '; damage none/<1%/<10%/<50%/more: '.
	buckets do: [:b | s print: (b * 100 / n) rounded] separatedBy: [s nextPut: $/].
	s nextPutAll: ' % of frames; px/frame mean '; print: (self mean: dmg) rounded;
		nextPutAll: ' p50 '; print: (self percentile: 50 of: dmg);
		nextPutAll: ' p90 '; print: (self percentile: 90 of: dmg);
		nextPutAll: ' max '; print: (dmg inject: 0 into: [:a :b | a max: b]);
		nextPutAll: ' = '; nextPutAll: ((self sum: dmg) * 100.0 / (screen * n) printShowingDecimalPlaces: 2); nextPutAll: ' % of composited px'.
	s nextPutAll: ' (bbox '; nextPutAll: ((self sum: (frames collect: [:f | f at: 3])) * 100.0 / (screen * n) printShowingDecimalPlaces: 2); nextPutAll: ' %)'.
	s nextPutAll: '; layers rendered '; print: (self sum: (frames collect: [:f | f at: 5]));
		nextPutAll: ' ('; print: ((self sum: (frames collect: [:f | f at: 6])) / n) rounded; nextPutAll: ' px/frame)'.
	quiet := frames select: [:f | (f at: 5) = 0].
	s nextPutAll: '; frames rendering no layer '; print: quiet size;
		nextPutAll: ' (damage px mean '; print: (self mean: (quiet collect: [:f | f at: 2])) rounded; nextPutAll: ')'.
	s nextPutAll: '; us mean/p50: draw '. self times: (frames collect: [:f | f at: 8]) on: s.
	s nextPutAll: ' layers '. self times: (frames collect: [:f | f at: 9]) on: s.
	s nextPutAll: ' show '. self times: (frames collect: [:f | f at: 10]) on: s.
	gpu := (frames collect: [:f | (f at: 13) isNil ifTrue: [0] ifFalse: [(f at: 13) gpu]]) reject: [:g | g = 0].
	gpu isEmpty ifFalse: [s nextPutAll: ' gpu '. self times: gpu on: s].
	s nextPutAll: ' probe '. self times: (frames collect: [:f | f at: 12]) on: s.
	stages := Dictionary new.
	frames do: [:f | (f at: 11) keysAndValuesDo: [:k :e | | t |
		t := stages at: k ifAbsent: [stages at: k put: (Array new: 3 withAll: 0)].
		1 to: 3 do: [:i | t at: i put: (t at: i) + (e at: i)]]].
	keys := stages keys asSortedCollection: [:a :b | a <= b].
	keys do: [:k | | e |
		e := stages at: k.
		s nextPutAll: '; '; nextPutAll: k; nextPutAll: ' x'; print: (e at: 1);
			nextPutAll: ' '; print: ((e at: 2) / n) rounded; nextPutAll: ' us/frame '; print: ((e at: 3) / n / 1024) rounded; nextPutAll: ' KB/frame']
!
csv: aString
	"The frames of the scenario named aString: ms since its start, damaged px, bbox px, rectangles, layers, layer px, draw, layers, show, gpu, probe µs."
	| scenario s |
	scenario := scenarios detect: [:each | (each at: 1) = aString] ifNone: [^''].
	s := WriteStream on: String new.
	(scenario at: 2) do: [:f |
		s print: (f at: 1) - (scenario at: 3) // 1000.
		#(2 3 4 5 6 8 9 10) do: [:i | s nextPut: $,; print: (f at: i)].
		s nextPut: $,; print: ((f at: 13) isNil ifTrue: [0] ifFalse: [(f at: 13) gpu]).
		s nextPut: $,; print: (f at: 12).
		s nextPut: Character lf].
	^s contents
!
times: aCollection on: s
	s print: (self mean: aCollection) rounded; nextPut: $/; print: (self percentile: 50 of: aCollection)
!
mean: aCollection
	aCollection isEmpty ifTrue: [^0].
	^(self sum: aCollection) / aCollection size
!
sum: aCollection
	^aCollection inject: 0 into: [:a :b | a + b]
!
percentile: p of: aCollection
	| sorted |
	aCollection isEmpty ifTrue: [^0].
	sorted := aCollection asSortedCollection asArray.
	^sorted at: ((sorted size * p / 100) ceiling max: 1)
! !

!DamageProbe class methodsFor: 'measuring'!
start
	"Measure the current World's compositor's frames (and StageTimes) from now on; answer the probe."
	| probe |
	probe := self new setCompositor: World current compositor.
	StageTimes start.
	Compositor probe: probe.
	^probe
!
current
	^Compositor probe
!
stop
	"Stop measuring; answer the probe."
	| probe |
	probe := Compositor probe.
	Compositor probe: nil.
	StageTimes stop.
	probe isNil ifFalse: [probe finish].
	^probe
! !
