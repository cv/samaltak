Object subclass: #Color
	instanceVariableNames: 'red green blue alpha packed'
	classVariableNames: 'Named'
	package: 'Graphics-Canvas'!

Color comment: 'I am an immutable sRGB color with straight alpha, components Floats in [0, 1]. For the GPU I pack myself into premultiplied RGBA8 (red in the low byte), cached. Create me with Color r:g:b:a:, Color hex: 16r1b3a8c, or by name (Color black, Color ultramarine, Color named: #ink3).'!

!Color methodsFor: 'private'!
setR: r g: g b: b a: a
	red := (r max: 0.0) min: 1.0.
	green := (g max: 0.0) min: 1.0.
	blue := (b max: 0.0) min: 1.0.
	alpha := (a max: 0.0) min: 1.0
! !

!Color methodsFor: 'accessing'!
red
	^red
!
green
	^green
!
blue
	^blue
!
alpha
	^alpha
!
isTransparent
	^alpha = 0
!
isOpaque
	^alpha = 1
! !

!Color methodsFor: 'converting'!
premultipliedRGBA8
	"Answer the premultiplied color packed as a 32-bit integer: red in bits 0-7, then green, blue, alpha (the byte order of an RGBA8 texel)."
	^packed ifNil: [packed := self premultipliedRGBA8Times: 1.0]
!
premultipliedRGBA8Times: opacity
	"Pack with the alpha multiplied by opacity."
	| a |
	a := alpha * opacity.
	^(red * a * 255.0 + 0.5) truncated
		+ ((green * a * 255.0 + 0.5) truncated bitShift: 8)
		+ ((blue * a * 255.0 + 0.5) truncated bitShift: 16)
		+ ((a * 255.0 + 0.5) truncated bitShift: 24)
!
asArray
	"{r. g. b. a}, premultiplied, as GPU clear colors are given."
	^Array with: red * alpha with: green * alpha with: blue * alpha with: alpha
!
hex
	"Answer the 24-bit RGB value."
	^((red * 255.0 + 0.5) truncated bitShift: 16) + ((green * 255.0 + 0.5) truncated bitShift: 8) + (blue * 255.0 + 0.5) truncated
! !

!Color methodsFor: 'deriving'!
alpha: aNumber
	^Color r: red g: green b: blue a: aNumber
!
mixed: proportion with: aColor
	"Answer the color proportion of the way from me (0) to aColor (1)."
	| q |
	q := 1.0 - proportion.
	^Color
		r: red * q + (aColor red * proportion)
		g: green * q + (aColor green * proportion)
		b: blue * q + (aColor blue * proportion)
		a: alpha * q + (aColor alpha * proportion)
!
negated
	^Color r: 1.0 - red g: 1.0 - green b: 1.0 - blue a: alpha
! !

!Color methodsFor: 'comparing'!
= aColor
	^aColor class == self class and: [
		red = aColor red and: [green = aColor green and: [blue = aColor blue and: [alpha = aColor alpha]]]]
!
hash
	^self premultipliedRGBA8 hash
! !

!Color methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: '(Color hex: 16r'; nextPutAll: ((self hex printStringBase: 16) padLeftTo: 6 with: $0).
	alpha < 1 ifTrue: [aStream nextPutAll: ' alpha: '; print: alpha].
	aStream nextPut: $)
! !

!Color class methodsFor: 'instance creation'!
r: r g: g b: b
	^self r: r g: g b: b a: 1.0
!
r: r g: g b: b a: a
	^self basicNew setR: r asFloat g: g asFloat b: b asFloat a: a asFloat
!
hex: anInteger
	"Color hex: 16r1b3a8c"
	^self
		r: ((anInteger bitShift: -16) bitAnd: 255) / 255.0
		g: ((anInteger bitShift: -8) bitAnd: 255) / 255.0
		b: (anInteger bitAnd: 255) / 255.0
!
hex: anInteger alpha: a
	^(self hex: anInteger) alpha: a
!
gray: brightness
	^self r: brightness g: brightness b: brightness
!
named: aSymbol
	^self namedColors at: aSymbol
!
named: aSymbol put: aColor
	"Redefine a named color (a theme publishes its palette this way; drawing code that asks by name follows)."
	self namedColors at: aSymbol put: aColor
!
namedColors
	"The palette of the Blue Book theme (docs/ui.md, themes/blue-book.css). Besides the colors by name, the roles the window system draws with, which the current Theme publishes (Theme>>publishPalette): ink (text, rules, frames, inverted selection) on paper, the accent (ultramarine), the hard shadow, the desk and its halftone dots."
	^Named ifNil: [
		Named := IdentityDictionary new.
		Named
			at: #black put: (self hex: 16r000000);
			at: #white put: (self hex: 16rFFFFFF);
			at: #ink put: (self hex: 16r000000);
			at: #paper put: (self hex: 16rFFFFFF);
			at: #shadow put: (self hex: 16r000000);
			at: #desk put: (self hex: 16rFFFFFF);
			at: #deskDots put: (self hex: 16r000000);
			at: #transparent put: (self r: 0 g: 0 b: 0 a: 0);
			at: #ultramarine put: (self hex: 16r1B3A8C);
			at: #hair put: (self hex: 16rC9C9C9);
			at: #ink2 put: (self hex: 16r3A3A3A);
			at: #ink3 put: (self hex: 16r6B6B6B);
			at: #ink4 put: (self hex: 16rA6A6A6);
			at: #comment put: (self hex: 16r5E5E5E);
			at: #red put: (self r: 1 g: 0 b: 0);
			at: #green put: (self r: 0 g: 1 b: 0);
			at: #blue put: (self r: 0 g: 0 b: 1);
			at: #gray put: (self gray: 0.5);
			yourself]
! !

!Color class methodsFor: 'class initialization'!
initialize
	SystemChanges subscribe: #Color do: [:change |
		(change affects: Color) ifTrue: [Named := nil]]
! !

!Color class methodsFor: 'named colors'!
black
	^self named: #black
!
white
	^self named: #white
!
transparent
	^self named: #transparent
!
ultramarine
	"The accent: the Blue Book's ultramarine, or the current theme's accent."
	^self named: #ultramarine
!
ink
	"Text, rules, frames and inverted selection: black, or the current theme's foreground."
	^self named: #ink
!
paper
	"What ink is drawn on: white, or the current theme's background."
	^self named: #paper
!
shadow
	"The windows' hard shadow."
	^self named: #shadow
!
desk
	"The desk behind the windows; deskDots its halftone."
	^self named: #desk
!
deskDots
	^self named: #deskDots
!
red
	^self named: #red
!
green
	^self named: #green
!
blue
	^self named: #blue
!
gray
	^self named: #gray
! !
