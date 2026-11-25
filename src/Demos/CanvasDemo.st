Object subclass: #CanvasDemo
	instanceVariableNames: 'extent frame'
	classVariableNames: ''
	package: 'Demos'!

CanvasDemo comment: 'I draw a Blue Book styled mock desktop with the Canvas: halftone desk, top bar, a focused System Browser (striped title bar, lists with tracked-caps headers, inverted selection, code with syntax colors, status bar) and an unfocused Workspace.

	CanvasDemo run                       "a real window, redrawn and presented at <= 60 Hz until closed"
	CanvasDemo writePNG: ''/tmp/demo.png''  "headless: render offscreen, read back, encode"
	CanvasDemo benchmark                 "ms to record a 900x500 window full of text"'!

!CanvasDemo methodsFor: 'initialization'!
setExtent: aPoint
	extent := aPoint.
	frame := 0
! !

!CanvasDemo methodsFor: 'drawing'!
displayList
	"Record one frame."
	| canvas |
	canvas := Canvas extent: extent scale: Font deviceScale.
	self drawOn: canvas.
	frame := frame + 1.
	^canvas displayList
!
drawOn: c
	c fillRect: (0 @ 0 extent: extent) color: Color white.
	c pattern: #halftone in: (0 @ 27 corner: extent).
	self drawTopBarOn: c.
	self drawWorkspaceOn: c in: (40 @ 370 extent: 520 @ 230).
	self drawBrowserOn: c in: (14 @ 40 extent: 640 @ 320).
	self drawTranscriptOn: c in: (600 @ 300 extent: 380 @ 150).
	self drawProcessesOn: c in: (670 @ 40 extent: 310 @ 240)
!
drawTopBarOn: c
	| ink3 x stats |
	ink3 := Color named: #ink3.
	c fillRect: (0 @ 0 extent: extent x @ 26) color: Color white.
	c fillRect: (0 @ 26 extent: extent x @ 1) color: Color black.
	c fillRect: (12 @ 9 extent: 8 @ 8) color: Color ultramarine.
	c drawString: 'Samaltak' at: 28 @ 4 font: Font uiItalic color: Color black.
	c fillRect: (100 @ 7 extent: 1 @ 13) color: Color black.
	c drawString: 'nuuk.image' at: 112 @ 4 font: Font ui color: Color black.
	c drawString: 'Click the desktop for the World menu' in: (200 @ 0 extent: extent x - 620 @ 26) font: Font uiItalic color: ink3 align: #center.
	stats := (frame \\ 3 + 15) printString , '.7 ms  60 fps  ·  11 processes'.
	x := extent x - 12 - (Font ui widthOf: stats).
	c drawString: stats at: x @ 4 font: Font ui color: Color black.
	c fillRect: (x - 68 @ 16 extent: 60 @ 1) color: Color black.
	c drawString: 'compositor' at: x - 76 - (Font header widthOf: 'compositor') @ 6 font: Font header color: Color black
!
drawWindowFrame: title on: c in: r focused: focused
	"Frame, shadow and title bar; answer the content rectangle."
	| bar titleWidth tab boxY |
	c fillRect: (r translateBy: (focused ifTrue: [2] ifFalse: [1]) @ (focused ifTrue: [2] ifFalse: [1])) color: Color black.
	c fillRect: r color: Color white.
	c strokeRect: r color: Color black width: 1.
	bar := r left + 1 @ (r top + 1) extent: r width - 2 @ 21.
	c fillRect: (bar left @ bar bottom extent: bar width @ 1) color: Color black.
	titleWidth := (Font title widthOf: title) + 16.
	tab := (bar center x - (titleWidth / 2)) rounded @ (bar top + 3) extent: titleWidth rounded @ 16.
	focused ifTrue: [
		c pattern: #stripes in: (bar left + 6 @ (bar top + 5) corner: tab left - 4 @ (bar top + 16)).
		c pattern: #stripes in: (tab right + 4 @ (bar top + 5) corner: bar right - 6 @ (bar top + 16)).
		c fillRect: tab color: Color black].
	boxY := bar top + 5.
	{bar left + 6. bar right - 17} do: [:bx |
		c fillRect: (bx - 2 @ (boxY - 2) extent: 15 @ 15) color: Color white.
		c strokeRect: (bx @ boxY extent: 11 @ 11) color: (focused ifTrue: [Color black] ifFalse: [Color named: #ink4]) width: 1].
	c drawString: title in: tab font: Font title color: (focused ifTrue: [Color white] ifFalse: [Color named: #ink3]) align: #center.
	^r left + 1 @ (bar bottom + 1) corner: r right - 1 @ (r bottom - 1)
!
drawPane: header right: rightText on: c in: r
	"A pane header (tracked caps) over a 1-point rule; answer the body rectangle."
	c drawString: header at: r left + 8 @ (r top + 3) font: Font header color: Color black.
	rightText isNil ifFalse: [
		c drawString: rightText in: (r left @ r top extent: r width - 8 @ 19) font: Font smallItalic color: (Color named: #ink3) align: #right].
	c fillRect: (r left @ (r top + 19) extent: r width @ 1) color: Color black.
	^r left @ (r top + 20) corner: r bottomRight
!
drawList: items selected: index muted: mutedItems on: c in: r focused: focused
	| y row |
	c clip: r during: [
		y := r top + 1.
		items doWithIndex: [:item :i |
			row := r left @ y extent: r width @ 19.
			i = index
				ifTrue: [
					focused
						ifTrue: [c fillRect: row color: Color black]
						ifFalse: [c strokeRect: row color: Color black width: 1]].
			c drawString: item at: r left + 8 @ (y + 0.5) font: Font ui color: ((i = index and: [focused]) ifTrue: [Color white] ifFalse: [Color black]).
			(mutedItems notNil and: [i <= mutedItems size]) ifTrue: [
				c drawString: (mutedItems at: i) in: (row insetBy: 8 @ 0) font: Font smallItalic
					color: ((i = index and: [focused]) ifTrue: [Color white alpha: 0.7] ifFalse: [Color named: #ink3]) align: #right].
			y := y + 19]]
!
drawBrowserOn: c in: r
	| content top columns colWidth x lists code y |
	content := self drawWindowFrame: 'System Browser: Window' on: c in: r focused: true.
	top := content top @ content top extent: content width @ 170.
	columns := #('packages' 'classes' 'protocols' 'methods').
	colWidth := content width / 4.
	lists := {
		#('Tools' 'UI-Widgets' 'UI-Windows' 'Graphics-Canvas' 'Graphics-GPU' 'Kernel-Objects' 'Kernel-Numbers').
		#('Compositor' 'Window' 'World' 'Layer').
		#('-- all --' 'opening' 'event loop' 'drawing').
		#('open' 'close' 'drawOn:')}.
	1 to: 4 do: [:i |
		| col body |
		x := (content left + (i - 1 * colWidth)) rounded.
		col := x @ top top corner: (content left + (i * colWidth)) rounded @ top bottom.
		i > 1 ifTrue: [c fillRect: (x @ top top extent: 1 @ top height) color: Color black].
		body := self drawPane: (columns at: i) right: (i = 1 ifTrue: ['by layer'] ifFalse: [nil]) on: c in: col.
		self drawList: (lists at: i) selected: (#(3 2 2 1) at: i)
			muted: (i = 1 ifTrue: [#('Tools' 'Widgets' 'Windows' '2D' '3D')] ifFalse: [nil])
			on: c in: body focused: i = 4].
	c fillRect: (content left @ top bottom extent: content width @ 1) color: Color black.
	code := #(
		#(#(#codeBold 'open'))
		#(#(#code '    process := [') #(#codeItalic 'self') #(#code ' eventLoop] ') #(#codeBold 'forkNamed:') #(#code ' title.'))
		#(#(#ultramarine '    Compositor') #(#code ' default ') #(#codeBold 'addLayer:') #(#code ' layer.'))
		#(#(#comment '    "Answer the receiver; the window runs in its own Process."'))
		#(#(#code '    ^') #(#codeItalic 'self')) ).
	y := top bottom + 8.
	code do: [:line |
		| pen |
		pen := content left + 12.
		line do: [:span |
			| font color |
			font := Font code.
			color := Color black.
			span first == #codeBold ifTrue: [font := Font codeBold].
			span first == #codeItalic ifTrue: [font := Font codeItalic].
			span first == #ultramarine ifTrue: [color := Color ultramarine].
			span first == #comment ifTrue: [font := Font codeItalic. color := Color named: #comment].
			c drawString: span last at: pen @ y font: font color: color.
			pen := pen + (font widthOf: span last)].
		y := y + 20].
	c fillRect: (content left @ (content bottom - 20) extent: content width @ 1) color: Color black.
	c drawString: 'Window>>open  ·  Windows · UI-Windows · opening' at: content left + 8 @ (content bottom - 19) font: Font smallItalic color: (Color named: #ink2)
!
drawWorkspaceOn: c in: r
	| content lines y |
	content := self drawWindowFrame: 'Workspace' on: c in: r focused: false.
	lines := #('"Put the cursor on a line or select an expression, then"' '⌘D do it · ⌘P print it · ⌘I inspect it."' '' '100 factorial' '(1 to: 20) select: [:i | i isPrime]' '3/4 + (1/4)' 'Transcript show: ''hello, Samaltak''; cr' '#(3 1 4 1 5 9 2 6) asSortedCollection' '{3/4. 3@4. ''text''. #sym. $c. 2 raisedTo: 100}').
	y := content top + 8.
	c clip: content during: [
		lines doWithIndex: [:line :i |
			c drawString: line at: content left + 12 @ y font: (i <= 2 ifTrue: [Font codeItalic] ifFalse: [Font code])
				color: (i <= 2 ifTrue: [Color named: #comment] ifFalse: [Color black]).
			y := y + 20]]
!
drawTranscriptOn: c in: r
	| content |
	content := self drawWindowFrame: 'Transcript' on: c in: r focused: false.
	#('Samaltak 0.1 · Smalltalk' 'samaltak.image · 9 packages · 180 classes' 'green threads, preempted at safepoints' '→ fonts: Iosevka Etoile, JetBrains Mono ✓') doWithIndex: [:line :i |
		c drawString: line at: content left + 12 @ (content top + 6 + (i - 1 * 20)) font: Font code color: Color black]
!
drawProcessesOn: c in: r
	| content body rows y |
	content := self drawWindowFrame: 'Process Browser' on: c in: r focused: false.
	body := self drawPane: 'pri  process' right: 'state' on: c in: content.
	rows := #(#('80' 'timer interrupt watcher' 'waiting') #('70' 'compositor (vsync)' 'waiting') #('60' 'input dispatcher' 'waiting') #('40' 'Workspace' 'waiting') #('40' 'Process Browser' 'running') #('40' 'Mandelbrot' 'waiting') #('40' 'System Browser' 'waiting')).
	y := body top + 2.
	rows doWithIndex: [:row :i |
		c strokeRect: (body left + 10 @ (y + 7) extent: 6 @ 6) color: Color black width: 1.
		i = 5 ifTrue: [c fillRect: (body left + 10 @ (y + 7) extent: 6 @ 6) color: Color black].
		c drawString: row first at: body left + 26 @ y font: Font ui color: Color black.
		c drawString: (row at: 2) at: body left + 52 @ y font: Font ui color: Color black.
		c drawString: row last in: (body left @ y extent: body width - 10 @ 19) font: (i = 5 ifTrue: [Font uiBold] ifFalse: [Font smallItalic]) color: (i = 5 ifTrue: [Color black] ifFalse: [Color named: #ink3]) align: #right.
		y := y + 19]
! !

!CanvasDemo methodsFor: 'benchmark'!
textDisplayList: aPoint
	"A window full of text: 25 lines of about 115 glyphs (code and UI font) in 900x500 points."
	| canvas line y fonts |
	canvas := Canvas extent: aPoint scale: Font deviceScale.
	canvas fillRect: (0 @ 0 extent: aPoint) color: Color white.
	fonts := {Font code. Font ui}.
	line := 'printOn:aStream|stream|aStream nextPutAll:self class name;nextPut:$(;print:x;nextPut:$@;print:y;nextPut:$);yourself.^self printString'.
	y := 0.
	[y + 20 <= aPoint y] whileTrue: [
		canvas drawString: line at: 8 @ y font: (fonts at: y // 20 \\ 2 + 1) color: Color black.
		y := y + 20].
	^canvas displayList
! !

!CanvasDemo class methodsFor: 'instance creation'!
extent: aPoint
	^self new setExtent: aPoint
! !

!CanvasDemo class methodsFor: 'running'!
run
	"Open a window and redraw the scene every frame (at most 60 Hz) until it is closed or 30 s passed."
	^self runFor: 30000
!
runFor: milliseconds
	| demo window event start frames recordUs renderUs t0 t1 next quit |
	demo := self extent: 1000 @ 620.
	window := DisplayWindow width: 1000 height: 620 title: 'Samaltak Canvas demo'.
	event := Array new: 8.
	start := Time millisecondClockValue.
	frames := 0.
	recordUs := 0.
	renderUs := 0.
	quit := false.
	next := start.
	[quit or: [Time millisecondClockValue - start > milliseconds]] whileFalse: [
		[(DisplayWindow nextEventInto: event) notNil] whileTrue: [
			((event at: 1) = 9 or: [(event at: 1) = 10]) ifTrue: [quit := true]].
		t0 := Time microsecondClockValue.
		demo setExtent: window extent.
		t1 := Time microsecondClockValue.
		window show: demo displayList clear: Color white.
		renderUs := renderUs + (Time microsecondClockValue - t1).
		frames := frames + 1.
		next := next + 16.
		(next - Time millisecondClockValue) > 0 ifTrue: [(Delay forMilliseconds: next - Time millisecondClockValue) wait].
		next := next max: Time millisecondClockValue].
	window close.
	Transcript show: 'CanvasDemo: '; show: frames printString; show: ' frames, '; show: (renderUs // (frames max: 1)) printString; show: ' us per frame (record + render + present)'; cr.
	^frames
!
writePNG: aPath
	"Render the scene headless at the device scale and write it as a PNG."
	| demo surface |
	demo := self extent: 1000 @ 620.
	surface := Surface extent: 1000 @ 620 scale: Font deviceScale.
	surface render: demo displayList clear: Color white.
	PNGWriter write: surface to: aPath.
	surface release.
	^aPath
!
writePNG
	^self writePNG: '.context/canvas-demo.png'
!
benchmark
	"Answer {glyphs. microseconds per DisplayList} for a 900x500 window of text."
	| demo list start n |
	demo := self extent: 900 @ 500.
	list := demo textDisplayList: 900 @ 500.
	n := 20.
	start := Time microsecondClockValue.
	n timesRepeat: [list := demo textDisplayList: 900 @ 500].
	^Array with: list quadCount - 1 with: (Time microsecondClockValue - start) // n
! !
