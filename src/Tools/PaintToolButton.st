Button subclass: #PaintToolButton
	instanceVariableNames: 'tool'
	classVariableNames: ''
	package: 'Tools'!

PaintToolButton comment: 'I am a toolbox button of Paint: a square tile showing my tool''s 16x16 pixel icon, pressed in while my tool is selected. My label names the tool and is my tooltip.

	PaintToolButton tool: #pencil label: ''Pencil'' action: [...]'!

!PaintToolButton methodsFor: 'drawing'!
drawIconOn: aCanvas at: aPoint
	"One quad per run of a color in a row."
	| ink |
	ink := self isEnabled ifTrue: [Color black] ifFalse: [self theme color: #ink4].
	(self class iconFor: tool) doWithIndex: [:row :y | | x |
		x := 1.
		[x <= row size] whileTrue: [| ch end color |
			ch := row at: x.
			end := x.
			[end < row size and: [(row at: end + 1) = ch]] whileTrue: [end := end + 1].
			(color := self class colorOf: ch ink: ink) isNil ifFalse: [
				aCanvas fillRect: (aPoint + ((x - 1) @ (y - 1)) extent: (end - x + 1) @ 1) color: color].
			x := end + 1]]
!
drawSelfOn: aCanvas
	| t r |
	t := self theme.
	r := self localBounds.
	t isBevelled
		ifTrue: [
			aCanvas fillRect: r color: t panel.
			t drawRaised: r pressed: self isInverted hover: (hover == true and: [self isEnabled]) on: aCanvas]
		ifFalse: [
			aCanvas fillRect: r color: (self isInverted ifTrue: [t color: #wash] ifFalse: [t paper]).
			aCanvas strokeRect: r color: t ink width: (self isInverted ifTrue: [2] ifFalse: [1])].
	self drawIconOn: aCanvas at: r center - (8 @ 8) + (self isInverted ifTrue: [1 @ 1] ifFalse: [0 @ 0])
! !

!PaintToolButton methodsFor: 'layout'!
preferredExtent
	^26 @ 26
! !

!PaintToolButton methodsFor: 'private'!
setTool: aSymbol
	tool := aSymbol
! !

!PaintToolButton methodsFor: 'accessing'!
tool
	^tool
! !

!PaintToolButton class methodsFor: 'icons'!
colorOf: aCharacter ink: inkColor
	"k ink, w white, l light gray, g gray, y yellow, r red, b blue, o brown, p pink; nil for clear."
	aCharacter = $k ifTrue: [^inkColor].
	aCharacter = $w ifTrue: [^Color white].
	aCharacter = $l ifTrue: [^Color r: 0.75 g: 0.75 b: 0.75].
	aCharacter = $g ifTrue: [^Color r: 0.5 g: 0.5 b: 0.5].
	aCharacter = $y ifTrue: [^Color r: 1 g: 0.85 b: 0.2].
	aCharacter = $r ifTrue: [^Color r: 0.85 g: 0.1 b: 0.1].
	aCharacter = $b ifTrue: [^Color r: 0.1 g: 0.35 b: 0.9].
	aCharacter = $o ifTrue: [^Color r: 0.55 g: 0.35 b: 0.15].
	aCharacter = $p ifTrue: [^Color r: 1 g: 0.6 b: 0.7].
	^nil
!
iconFor: aSymbol
	"16 rows of 16 pixels; see colorOf:ink: for the letters."
	aSymbol == #pencil ifTrue: [^#(
		'................' '............kk..' '...........kppk.' '..........kpppk.'
		'.........klkpk..' '........kyylk...' '.......kyyyk....' '......kyyyk.....'
		'.....kyyyk......' '....kyyyk.......' '...kwyyk........' '...kwwk.........'
		'..kkkk..........' '..kk............' '................' '................')].
	aSymbol == #brush ifTrue: [^#(
		'................' '.............kk.' '............kook' '...........kook.'
		'..........kook..' '.........kook...' '........kook....' '.......kllk.....'
		'......kllk......' '.....kbbk.......' '....kbbbk.......' '...kbbbk........'
		'..kbbbk.........' '.kbbk...........' '.kk.............' '................')].
	aSymbol == #spray ifTrue: [^#(
		'................' '.b..b...........' '...b..b.kkk.....' '.b..b..kkgk.....'
		'...b.b..kkk.....' '.b..b...kgk.....' '.......kgggk....' '......kllllgk...'
		'......klwllgk...' '......klwllgk...' '......klwllgk...' '......klwllgk...'
		'......klllllk...' '......klllllk...' '.......kkkkk....' '................')].
	aSymbol == #eraser ifTrue: [^#(
		'................' '................' '................' '........kkkkkk..'
		'.......kwwwwkk..' '......kwwwwklk..' '.....kwwwwkllk..' '....kwwwwkllk...'
		'...kkkkkkllk....' '...kppppklk.....' '...kppppkk......' '...kppppk.......'
		'...kkkkkk.......' '................' '................' '................')].
	aSymbol == #fill ifTrue: [^#(
		'................' '.....kk.........' '....k..k........' '....k.kkk.......'
		'....kkwwkk......' '...kwwwwwkk.....' '..kwwwwwwkbk....' '.kwwwwwwwkbbk...'
		'..kwwwwwkkbbk...' '...kwwwkk.bbk...' '....kwkk..bbk...' '.....kk...bb....'
		'..........b.....' '................' '................' '................')].
	aSymbol == #picker ifTrue: [^#(
		'................' '............kkk.' '...........kkkkk' '..........kkkkkk'
		'.........kkkkkk.' '........kwkkkk..' '.......kwwwk....' '......kwwwk.....'
		'.....kwwwk......' '....kwwwk.......' '...kwwwk........' '..kwwk..........'
		'..kkk...........' '.k..............' 'k...............' '................')].
	aSymbol == #line ifTrue: [^#(
		'................' '................' '............kk..' '...........kk...'
		'..........kk....' '.........kk.....' '........kk......' '.......kk.......'
		'......kk........' '.....kk.........' '....kk..........' '...kk...........'
		'..kk............' '................' '................' '................')].
	aSymbol == #rectangle ifTrue: [^#(
		'................' '................' '................' '..kkkkkkkkkkkk..'
		'..k..........k..' '..k..........k..' '..k..........k..' '..k..........k..'
		'..k..........k..' '..k..........k..' '..k..........k..' '..kkkkkkkkkkkk..'
		'................' '................' '................' '................')].
	aSymbol == #ellipse ifTrue: [^#(
		'................' '................' '................' '.....kkkkkk.....'
		'...kk......kk...' '..k..........k..' '.k............k.' '.k............k.'
		'.k............k.' '..k..........k..' '...kk......kk...' '.....kkkkkk.....'
		'................' '................' '................' '................')].
	^#()
! !

!PaintToolButton class methodsFor: 'instance creation'!
tool: aSymbol label: aString action: aBlock
	^(self label: aString action: aBlock) setTool: aSymbol; tooltip: aString; yourself
! !
