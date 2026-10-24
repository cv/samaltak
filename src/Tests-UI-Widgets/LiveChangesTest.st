UIWindowsTestCase subclass: #LiveChangesTest
	instanceVariableNames: 'originals'
	classVariableNames: ''
	package: 'Tests-UI-Widgets'!

LiveChangesTest comment: 'Accepting changed drawing code takes effect on the open windows at once (SystemChanges): the Theme''s accent, the Renderer''s shader source (a broken one keeps the old pipeline and toasts), the glyph rasterizer, the desk. Each test edits real methods and puts the originals back.'!

!LiveChangesTest methodsFor: 'running'!
setUp
	super setUp.
	originals := OrderedCollection new
!
tearDown
	originals reverseDo: [:each | (each at: 1) addSelector: (each at: 2) withMethod: (each at: 3)].
	super tearDown
!
timeLimitMilliseconds
	^60000
! !

!LiveChangesTest methodsFor: 'support'!
edit: aBehavior selector: aSelector replacing: oldString with: newString
	"Accept aBehavior>>aSelector with oldString replaced, as the browser does; the original comes back in tearDown."
	| method source |
	method := aBehavior compiledMethodAt: aSelector.
	(originals anySatisfy: [:each | (each at: 1) == aBehavior and: [(each at: 2) == aSelector]])
		ifFalse: [originals add: (Array with: aBehavior with: aSelector with: method)].
	source := method sourceCode asString.
	self assert: (source includesSubstring: oldString).
	Compiler compile: (source copyReplaceAll: oldString with: newString) in: aBehavior classified: method category
!
pixel: aPoint is: aColor
	"Answer whether the screen shows aColor (within 3 levels) at aPoint."
	| actual |
	actual := self rgbAt: aPoint in: self screenshot.
	^(actual with: (Array with: aColor red with: aColor green with: aColor blue) collect: [:a :e | (a - (e * 255) rounded) abs]) allSatisfy: [:d | d <= 3]
!
inkIn: aRectangle
	| form ink |
	form := self screenshot.
	ink := 0.
	aRectangle top to: aRectangle bottom - 1 do: [:y |
		aRectangle left to: aRectangle right - 1 do: [:x | ink := ink + (255 - (self rgbAt: x @ y in: form) first)]].
	^ink
! !

!LiveChangesTest methodsFor: 'tests'!
testThemeAccentChangeRestylesOpenWindows
	| w center red |
	w := self open: (ProgressStripe new fraction: 1.0; yourself) title: 'Accent' at: (100 @ 100 extent: 240 @ 120).
	center := w contentOrigin + (w contentExtent // 2).
	self assert: (self pixel: center is: (Color hex: 16r1B3A8C)).
	self edit: Theme selector: #initializeBlueBook replacing: '16r1B3A8C' with: '16rC8102E'.
	red := Color hex: 16rC8102E.
	self assert: (self waitFor: [self pixel: center is: red]) description: 'the open window was not restyled'.
	self assert: Theme current ultramarine equals: red.
	self assert: Color ultramarine equals: red
!
testShaderChangeRebuildsThePipeline
	| w center version |
	w := self open: (RecordingTestView new color: (Color r: 1 g: 0 b: 0); yourself) title: 'Shader' at: (100 @ 100 extent: 240 @ 120).
	center := w contentOrigin + (w contentExtent // 2).
	self assert: (self pixel: center is: (Color r: 1 g: 0 b: 0)).
	version := world compositor renderer pipelineVersion.
	self edit: Renderer class selector: #shaderSource
		replacing: 'if (m == 0u) return in.color;'
		with: 'if (m == 0u) return in.color.bgra;'.
	self assert: (self waitFor: [self pixel: center is: (Color r: 0 g: 0 b: 1)]) description: 'the cached layer was not rendered with the new shader'.
	self assert: world compositor renderer pipelineVersion equals: version + 1.
	"a shader that does not compile: the old pipeline stays, the error is toasted"
	self edit: Renderer class selector: #shaderSource replacing: 'uint m = in.mode' with: 'uint m = in.noSuchField'.
	self assert: (self waitFor: [world toasts anySatisfy: [:t | t text includesSubstring: 'noSuchField']]).
	self assert: world compositor renderer pipelineVersion equals: version + 1.
	self assert: (self pixel: center is: (Color r: 0 g: 0 b: 1))
!
testRasterizerChangeReRasterizesText
	| w rect atlas before |
	w := self open: (Label text: 'gggg mmmm wwww' font: #code) title: 'Glyphs' at: (100 @ 100 extent: 240 @ 80).
	rect := w contentOrigin extent: w contentExtent.
	before := self inkIn: rect.
	atlas := GlyphAtlas default.
	self edit: GlyphRasterizer selector: #coverage
		replacing: '(v * 255.0 + 0.5) truncated'
		with: '(v > 0.02 ifTrue: [255] ifFalse: [0])'.
	self deny: GlyphAtlas default == atlas.
	self assert: (self waitFor: [(self inkIn: rect) > (before * 1.15)]) description: 'the text was not rasterized again'
!
testDeskIsSmalltalk
	| desk |
	desk := 900 @ 600.
	self deny: (self pixel: desk is: Color ultramarine).
	self edit: World selector: #drawDeskOn: replacing: 'pattern: #halftone in: self bounds color: Color black' with: 'fillRect: self bounds color: Color ultramarine'.
	self assert: (self waitFor: [self pixel: desk is: Color ultramarine])
! !
