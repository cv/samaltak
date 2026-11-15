Object subclass: #ColorEmoji
	instanceVariableNames: 'face ligatures variationSelector clusters layers'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

ColorEmoji comment: 'I decide which grapheme clusters are drawn as color emoji, and with which color glyphs of my face (Twemoji: COLR layers in CPAL colors, GSUB ligatures for sequences). Font asks me (Font class>>emoji); I cache the answer per cluster and the layers per glyph.

A cluster with U+FE0E is text. Otherwise its code points but U+FE0F go through my cmap and my ligatures (longest first, left to right; U+FE0F in their components is ignored too), and the empty glyphs left (joiners, tags) are dropped. The cluster is color if glyphs remain and all are color glyphs, and it has U+FE0F, U+20E3, ZWJ, an emoji modifier, two regional indicators or tags, or is one Emoji_Presentation code point. So a bare digit, # or © stays text, 1 U+FE0F U+20E3 is a keycap, and a ZWJ sequence I lack a ligature for shows its parts.'!

!ColorEmoji methodsFor: 'initialization'!
setFace: aTrueTypeFont
	face := aTrueTypeFont.
	variationSelector := face glyphIndexFor: 16rFE0F.
	ligatures := Dictionary new.
	face ligatures keysAndValuesDo: [:first :list |
		ligatures at: first put: ((list collect: [:each | Array with: (each first copyWithout: variationSelector) with: each last])
			asSortedCollection: [:a :b | a first size >= b first size]) asArray].
	clusters := Dictionary new.
	layers := Dictionary new
! !

!ColorEmoji methodsFor: 'accessing'!
face
	^face
!
glyphsOf: aString from: start to: stop
	"Answer the color glyph indices of the grapheme cluster start .. stop of aString, or nil if it is text."
	| key glyphs |
	key := aString copyFrom: start to: stop.
	glyphs := clusters at: key ifAbsent: [
		glyphs := (self computeGlyphsOf: key) ifNil: [false].
		Font rasterizing: [clusters at: key put: glyphs]].
	^glyphs == false ifTrue: [nil] ifFalse: [glyphs]
!
layersOf: glyph
	"Answer the layers of a color glyph, bottom first, as a flat Array: layer glyph index, Color (nil: the text color), ..."
	^layers at: glyph ifAbsent: [
		| list |
		list := self computeLayersOf: glyph.
		Font rasterizing: [layers at: glyph put: list]]
! !

!ColorEmoji methodsFor: 'private'!
computeGlyphsOf: aString
	| cps glyphs result i match |
	cps := (1 to: aString size) collect: [:k | (aString at: k) value].
	((cps includes: 16rFE0E) or: [(self asksForEmoji: cps) not]) ifTrue: [^nil].
	glyphs := (cps reject: [:cp | cp = 16rFE0F]) collect: [:cp | face glyphIndexFor: cp].
	result := OrderedCollection new.
	i := 1.
	[i <= glyphs size] whileTrue: [
		match := (ligatures at: (glyphs at: i) ifAbsent: [#()]) detect: [:each | self components: each first match: glyphs at: i + 1] ifNone: [nil].
		match isNil
			ifTrue: [result add: (glyphs at: i). i := i + 1]
			ifFalse: [result add: match last. i := i + 1 + match first size]].
	result := result reject: [:g | (face colorLayersOf: g) isNil and: [(face boundsOf: g) isNil]].
	(result notEmpty and: [result allSatisfy: [:g | (face colorLayersOf: g) notNil]]) ifFalse: [^nil].
	^result asArray
!
asksForEmoji: codePoints
	"U+FE0F, a keycap, ZWJ, an emoji modifier, tags or two regional indicators; or one Emoji_Presentation code point."
	codePoints size = 1 ifTrue: [^Unicode isEmojiPresentationCode: codePoints first].
	^(codePoints anySatisfy: [:cp | cp = 16rFE0F or: [cp = 16r20E3 or: [cp = 16r200D
		or: [(cp between: 16r1F3FB and: 16r1F3FF) or: [cp between: 16rE0020 and: 16rE007F]]]]])
		or: [(codePoints count: [:cp | cp between: 16r1F1E6 and: 16r1F1FF]) >= 2]
!
components: anArray match: glyphs at: start
	anArray size > (glyphs size - start + 1) ifTrue: [^false].
	1 to: anArray size do: [:k | (anArray at: k) = (glyphs at: start + k - 1) ifFalse: [^false]].
	^true
!
computeLayersOf: glyph
	| list palette |
	list := (face colorLayersOf: glyph) copy.
	palette := face palette.
	2 to: list size by: 2 do: [:i |
		list at: i put: ((list at: i) = 16rFFFF ifFalse: [palette at: (list at: i) + 1])].
	^list
! !

!ColorEmoji class methodsFor: 'instance creation'!
face: aTrueTypeFont
	^self new setFace: aTrueTypeFont
! !
