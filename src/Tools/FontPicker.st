ToolPane subclass: #FontPicker
	instanceVariableNames: 'collections families typefaces sizes preview info targetLabel target faceName size fonts'
	classVariableNames: ''
	package: 'Tools'!

FontPicker comment: 'I am the font picker, after the font panel of macOS: Collection, Family, Typeface and Size columns under an editable preview, and the expression that makes the chosen font. Opened from the World menu I take the keyboard focus of the window that was active (any widget that understands font:, e.g. a TextEditor) as my target and set its font as the choice changes; openFor: names the target.

	FontPicker open.
	FontPicker openFor: aTextEditor.

Families and typefaces come from the face names (JetBrainsMono-Bold: family JetBrainsMono, typeface Bold) of the faces in the image (Font imageFaceNames) and of those read since (Font faces).'!

!FontPicker methodsFor: 'faces'!
allFaceNames
	^(Font imageFaceNames asSet addAll: Font faces keys; yourself) asSortedCollection asArray
!
collectionNames
	^#('All Fonts' 'Fixed Width' 'Proportional' 'Fallback')
!
faceNameOf: aFont
	^aFont face name copyReplaceAll: '.ttf' with: ''
!
faceNamesIn: aCollectionName
	aCollectionName = 'Fixed Width' ifTrue: [^self allFaceNames select: [:each | self isFixedWidth: each]].
	aCollectionName = 'Proportional' ifTrue: [^self allFaceNames reject: [:each | self isFixedWidth: each]].
	aCollectionName = 'Fallback' ifTrue: [^Font fallbackFaceNames asArray].
	^self allFaceNames
!
facesOfFamily: aFamily
	"The faces of aFamily in the selected collection, Regular first."
	| faces |
	faces := (self faceNamesIn: (collections selection ifNil: [self collectionNames first])) select: [:each | (self familyOf: each) = aFamily].
	^(faces asSortedCollection: [:a :b | (self styleRank: a) < (self styleRank: b) or: [(self styleRank: a) = (self styleRank: b) and: [a <= b]]]) asArray
!
familyOf: aFaceName
	^(aFaceName includes: $-) ifTrue: [aFaceName copyUpToLast: $-] ifFalse: [aFaceName]
!
fontNamed: aFaceName size: aNumber
	^fonts at: aFaceName, ' ', aNumber printString ifAbsentPut: [Font faceNamed: aFaceName size: aNumber]
!
isFixedWidth: aFaceName
	| font |
	font := self fontNamed: aFaceName size: 13.
	^(font widthOf: 'iiii') = (font widthOf: 'WWWW')
!
styleOf: aFaceName
	^(aFaceName includes: $-) ifTrue: [aFaceName copyAfterLast: $-] ifFalse: ['Regular']
!
styleRank: aFaceName
	^#('Regular' 'Italic' 'Bold') indexOf: (self styleOf: aFaceName) ifAbsent: [0]
! !

!FontPicker methodsFor: 'initialization'!
build
	| toolbar columns |
	collections := ListView new name: 'collections'; title: 'Collection'; yourself.
	collections items: self collectionNames; onSelect: [:name | self collectionSelected: name].
	families := ListView new name: 'families'; title: 'Family'; yourself.
	families
		rightBlock: [:family | | count | count := (self facesOfFamily: family) size. count > 1 ifTrue: [count printString]];
		onSelect: [:family | self familySelected: family].
	typefaces := ListView new name: 'typefaces'; title: 'Typeface'; yourself.
	typefaces labelBlock: [:face | self styleOf: face]; onSelect: [:face | self typefaceSelected: face].
	sizes := ListView new name: 'sizes'; title: 'Size'; yourself.
	sizes items: self standardSizes; labelBlock: [:each | self printSize: each]; onSelect: [:each | self sizeSelected: each].
	preview := TextEditor new name: 'preview'; yourself.
	preview highlighting: false; text: self sampleText.
	info := Label text: '' font: #code.
	info color: #ink3.
	targetLabel := Label text: '' font: #smallItalic.
	targetLabel color: #ink3; align: #right.
	toolbar := Row with: (Array
		with: (info flex: 1; yourself)
		with: (targetLabel fixed: 180; yourself)
		with: ((Button label: '−' action: [self changeSize: -1]) name: 'smaller'; tooltip: 'smaller'; sizeToContent; yourself)
		with: ((Button label: '+' action: [self changeSize: 1]) name: 'larger'; tooltip: 'larger'; sizeToContent; yourself)).
	toolbar spacing: 6; padding: (8 @ 4 corner: 8 @ 4); fixed: 29.
	columns := Row with: (Array
		with: ((self pane: collections title: 'Collection') percent: 20)
		with: ((self pane: families title: 'Family') percent: 32)
		with: ((self pane: typefaces title: 'Typeface') percent: 28)
		with: (self pane: sizes title: 'Size' right: [self printSize: size])).
	columns separators: true.
	self addAll: (Array with: (preview percent: 42; yourself) with: Splitter new with: columns with: toolbar)
!
initialize
	super initialize.
	size := 24.
	fonts := Dictionary new.
	self build.
	collections selectIndex: 1
!
minimumWindowExtent
	^480 @ 320
! !

!FontPicker methodsFor: 'selecting'!
changeSize: aNumber
	"One step through the standard sizes (aNumber -1 or 1), from the current size."
	| larger smaller |
	larger := self standardSizes detect: [:each | each > size] ifNone: [size].
	smaller := self standardSizes reverse detect: [:each | each < size] ifNone: [size].
	size := aNumber > 0 ifTrue: [larger] ifFalse: [smaller].
	sizes selection: size.
	self fontChanged
!
collectionSelected: aCollectionName
	| names current |
	aCollectionName isNil ifTrue: [^self].
	names := ((self faceNamesIn: aCollectionName) collect: [:each | self familyOf: each]) asSet asSortedCollection asArray.
	current := faceName isNil ifFalse: [self familyOf: faceName].
	families items: names selected: ((names includes: current) ifTrue: [current] ifFalse: [names isEmpty ifFalse: [names first]]).
	self familySelected: families selection
!
familySelected: aFamily
	| faces style |
	aFamily isNil ifTrue: [^self].
	faces := self facesOfFamily: aFamily.
	style := faceName isNil ifFalse: [self styleOf: faceName].
	typefaces items: faces selected: (faces detect: [:each | (self styleOf: each) = style] ifNone: [faces isEmpty ifFalse: [faces first]]).
	self typefaceSelected: typefaces selection
!
fontChanged
	"Show the chosen font and give it to the target."
	| font |
	font := self selectedFont.
	font isNil ifTrue: [^self].
	preview font: font.
	info text: self expression.
	target isNil ifFalse: [target font: font].
	self invalidate
!
selectFont: aFont
	"Show aFont: its face in All Fonts and its size."
	| name |
	name := self faceNameOf: aFont.
	(self allFaceNames includes: name) ifFalse: [^self].
	size := aFont size.
	faceName := name.
	sizes selection: size.
	collections selectionIndex: 1.
	self collectionSelected: collections selection
!
sizeSelected: aNumber
	aNumber isNil ifTrue: [^self].
	size := aNumber.
	self fontChanged
!
typefaceSelected: aFaceName
	aFaceName isNil ifTrue: [^self].
	faceName := aFaceName.
	self fontChanged
! !

!FontPicker methodsFor: 'accessing'!
expression
	faceName isNil ifTrue: [^''].
	^'Font faceNamed: ', faceName printString, ' size: ', (self printSize: size)
!
sampleText
	^'The quick brown fox jumps over the lazy dog.
0123456789 (){}[] => !!= <= ≠ λ ∑
Ångström · Ελληνικά · Кириллица · 日本語 · 한국어 · 🦊'
!
selectedFont
	faceName isNil ifTrue: [^nil].
	^self fontNamed: faceName size: size
!
target
	^target
!
target: aWidget
	"Set aWidget's font as the choice changes, starting from its font."
	target := aWidget.
	targetLabel text: (target isNil ifTrue: [''] ifFalse: ['→ ', target class name]).
	(target notNil and: [target font isKindOf: Font]) ifTrue: [self selectFont: target font]
! !

!FontPicker methodsFor: 'sizes'!
printSize: aNumber
	^aNumber isInteger ifTrue: [aNumber printString] ifFalse: [aNumber printString: 10]
!
standardSizes
	^#(9 10 11 12 13 14 18 24 36 48 64 72 96 144)
! !

!FontPicker class methodsFor: 'opening'!
open
	^self openAt: nil
!
openAt: aPoint
	"Open (or focus) the picker; the keyboard focus of the active window, when it takes a font, becomes its target."
	| window focus |
	window := Tools world isNil ifTrue: [nil] ifFalse: [Tools world activeWindow].
	focus := window ifNotNil: [window keyboardFocus].
	(focus notNil and: [(focus respondsTo: #font:) and: [(window content isKindOf: self) not]]) ifFalse: [focus := nil].
	^self openAt: aPoint for: focus
!
openAt: aPoint for: aWidget
	| existing picker window |
	existing := Tools windowOf: self.
	existing isNil ifFalse: [
		aWidget isNil ifFalse: [existing do: [existing content target: aWidget]].
		existing focus.
		^existing].
	picker := self new.
	window := picker openIn: (Tools placeAt: aPoint extent: 640 @ 460) title: 'Fonts'.
	aWidget isNil ifFalse: [window do: [picker target: aWidget]].
	^window
!
openFor: aWidget
	^self openAt: nil for: aWidget
! !

!FontPicker class methodsFor: 'class initialization'!
initialize
	ToolsMenu register: 'Fonts' description: 'family · typeface · size' order: 47 action: [:point | self openAt: point].
	ToolsMenu register: 'Theme' description: 'Blue Book or be-gold (Haiku)' order: 48 action: [:point | Theme toggle]
! !
