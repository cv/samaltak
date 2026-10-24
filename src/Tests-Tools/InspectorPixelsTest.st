ToolsTestCase subclass: #InspectorPixelsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

InspectorPixelsTest comment: 'I test the Inspector''s pixel view on Forms and glyphs (Font>>glyphFor:): the fitting zoom, the value of the pixel under the (injected) pointer in the status line and the remote state, the magnified cells on screen, wheel zoom, and opening it with inspect from a Workspace.'!

!InspectorPixelsTest methodsFor: 'support'!
rgbAt: aPoint
	| v |
	self settle.
	v := (world compositor sync: [:c | c screenshotScale: 1]) pixelValueAt: aPoint rounded.
	^Array with: (v bitAnd: 255) with: ((v bitShift: -8) bitAnd: 255) with: ((v bitShift: -16) bitAnd: 255)
!
hover: aView pixel: aPoint
	self moveTo: (aView remotePointAt: aPoint x printString, ',', aPoint y printString).
	self assert: (self waitFor: [aView hover = aPoint]) description: 'not hovering ', aPoint printString
!
statusOf: anInspector
	^(anInspector window sync: [anInspector widgetNamed: 'pixel-status']) remoteLabel
! !

!InspectorPixelsTest methodsFor: 'tests'!
testFormPixels
	| form w inspector view fit |
	form := Form width: 4 height: 3.
	form fill: Color white.
	form at: 1 @ 2 put: (Color r: 1 g: 0 b: 0).
	w := self open: [Inspector openOn: form near: nil].
	inspector := w content.
	view := inspector pixelView.
	self assert: view notNil.
	self assert: view remoteName equals: 'pixels'.
	fit := (((view width - 16) / 4) floor min: ((view height - 16) / 3) floor) min: 64.
	self assert: view zoom equals: fit.
	self assert: fit >= 6.
	self assert: (view remoteState includes: 'size=4x3').
	self assert: (view remoteState includes: 'zoom=', fit printString).
	self hover: view pixel: 1 @ 2.
	self assert: (view remoteState includes: 'hover=1,2').
	self assert: (view remoteState includes: 'value=255,0,0,255').
	self assert: ((self statusOf: inspector) includesSubstring: 'x 1  y 2   r 255  g 0  b 0  a 255').
	self assert: (self rgbAt: (view screenPointOfPixel: 1 @ 2)) equals: #(255 0 0).
	self assert: (self rgbAt: (view screenPointOfPixel: 2 @ 2)) equals: #(255 255 255).
	form at: 2 @ 2 put: (Color r: 0 g: 0 b: 1).
	self assert: (self waitFor: [(self rgbAt: (view screenPointOfPixel: 2 @ 2)) = #(0 0 255)] timeout: 3000)
		description: 'a changed pixel was not redrawn'.
	self hover: view pixel: 0 @ 0.
	self assert: (view remoteState includes: 'value=255,255,255,255')
!
testGlyphPixels
	| glyph w inspector view ink blank zoom |
	glyph := Font code glyphFor: $g.
	w := self open: [Inspector openOn: glyph near: nil].
	inspector := w content.
	view := inspector pixelView.
	self assert: (view remoteState includes: 'size=', glyph width printString, 'x', glyph height printString).
	self assert: view zoom >= 10.
	ink := (0 to: glyph height - 1) inject: nil into: [:found :y |
		found ifNil: [(0 to: glyph width - 1) inject: nil into: [:f :x | f ifNil: [(glyph coverageAt: x @ y) = 255 ifTrue: [x @ y]]]]].
	blank := 0 @ 0.
	self assert: ink notNil.
	self assert: (glyph coverageAt: blank) equals: 0.
	self hover: view pixel: ink.
	self assert: (view remoteState includes: 'value=255').
	self assert: ((self statusOf: inspector) includesSubstring: 'coverage 255').
	self assert: (self rgbAt: (view screenPointOfPixel: ink)) equals: #(0 0 0).
	self assert: (self rgbAt: (view screenPointOfPixel: blank)) equals: #(255 255 255).
	self hover: view pixel: blank.
	self assert: (view remoteState includes: 'value=0').
	zoom := view zoom.
	self inject: 4 at: (view screenPointOfPixel: blank) button: 0 count: 0.0 @ 1.0 modifiers: 0.
	self assert: (self waitFor: [view zoom = (zoom + 1)]) description: 'the wheel did not zoom in'.
	self assert: ((w sync: [inspector widgetNamed: 'pixels-header']) remoteState includes: 'right="', glyph width printString, '×', glyph height printString, ' · zoom ', (zoom + 1) printString, '"')
!
testInspectFromAWorkspace
	| ws inspector |
	ws := self openWorkspaceWith: '(Font code glyphFor: $g) inspect'.
	self evaluate: '(Font code glyphFor: $g) inspect' in: ws mode: #do.
	self assert: (self waitFor: [(self windowsOf: Inspector) size = 1]) description: 'no Inspector'.
	inspector := (self windowsOf: Inspector) first content.
	self assert: inspector object character equals: $g.
	self assert: inspector pixelView form == inspector object.
	self assert: (self waitFor: [inspector window title = 'Inspector: a GlyphForm'])
! !
