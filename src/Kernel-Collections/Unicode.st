Object subclass: #Unicode
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

Unicode comment: 'I answer Unicode character properties, from UnicodeTables (generated from the Unicode Character Database, see Unicode version): the general category (#Lu #Ll ... #Cn) and the classifications built on it, simple case mappings and simple case folding, the display width a terminal or a monospaced editor gives a code point (as wcwidth), and the properties of extended grapheme clusters (UAX #29, String>>isGraphemeClusterBoundaryAt:). Character delegates its classification and case conversion to me.

As in Squeak, the selectors ending in Code: (isLetterCode: toUppercaseCode: ...), generalCategoryTagOf: and the ...Of: accessors take code points (Integers); as in Pharo, isLetter: isDigit: isUppercase: isLowercase: isMathSymbol: toUppercase: and toLowercase: take Characters (and the last two answer Characters).

isUppercaseCode: and isLowercaseCode: are the general categories Lu and Ll (not the Other_Uppercase/Other_Lowercase properties), isDigitCode: is Nd, isWhiteSpaceCode: the White_Space property. isPrintableCode: is everything with a visible rendering or space: not Cc Cf Cs Cn Zl Zp (private use characters count as printable). Code points below 256 are answered from a direct table, case mappings of ASCII by arithmetic.'!

!Unicode class methodsFor: 'accessing'!
version
	"The version of the Unicode Character Database my tables come from."
	^UnicodeTables version
!
propertiesOf: codePoint
	"Answer the property word of codePoint (its bits are described in tools/unicode-tables.py): general category, grapheme cluster break properties, display width, White_Space, Emoji_Presentation."
	codePoint < 256 ifTrue: [^UnicodeTables latin1Properties at: codePoint + 1].
	^self searchPropertiesOf: codePoint
!
generalCategoryTagOf: codePoint
	"Answer the general category, a Symbol: #Lu #Ll #Lt #Lm #Lo #Mn #Mc #Me #Nd #Nl #No #Pc #Pd #Ps #Pe #Pi #Pf #Po #Sm #Sc #Sk #So #Zs #Zl #Zp #Cc #Cf #Cs #Co or #Cn (unassigned)."
	^UnicodeTables categories at: ((self propertiesOf: codePoint) bitAnd: 31)
!
decimalDigitValueOf: codePoint
	"Answer the value 0-9 of a decimal digit (general category Nd), -1 for other code points. Unicode assigns the decimal digits in runs of ten from 0 to 9, so the value is the distance from the last zero at or below codePoint."
	| zeros lo hi mid |
	(self isDigitCode: codePoint) ifFalse: [^-1].
	zeros := UnicodeTables decimalDigitZeros.
	lo := 1.
	hi := zeros size.
	[lo < hi] whileTrue: [
		mid := lo + hi + 1 bitShift: -1.
		(zeros at: mid) <= codePoint ifTrue: [lo := mid] ifFalse: [hi := mid - 1]].
	^codePoint - (zeros at: lo)
!
displayWidthOf: codePoint
	"Answer the columns a terminal or a monospaced editor gives codePoint, as wcwidth: 0 for nonspacing and enclosing marks, format characters (but the soft hyphen), controls and the Hangul medial vowels and final consonants (U+1160-11FF, U+D7B0-D7FF), which join the preceding character; 2 for East Asian Wide and Fullwidth characters (emoji presentation characters among them); 1 for the rest."
	^((self propertiesOf: codePoint) bitShift: -12) bitAnd: 3
! !

!Unicode class methodsFor: 'testing'!
isLetterCode: codePoint
	"General category L*."
	^((self propertiesOf: codePoint) bitAnd: 31) <= 5
!
isUppercaseCode: codePoint
	"General category Lu."
	^((self propertiesOf: codePoint) bitAnd: 31) = 1
!
isLowercaseCode: codePoint
	"General category Ll."
	^((self propertiesOf: codePoint) bitAnd: 31) = 2
!
isMarkCode: codePoint
	"General category M* (combining marks)."
	^((self propertiesOf: codePoint) bitAnd: 31) between: 6 and: 8
!
isDigitCode: codePoint
	"General category Nd (decimal digits of any script)."
	^((self propertiesOf: codePoint) bitAnd: 31) = 9
!
isMathSymbolCode: codePoint
	"General category Sm."
	^((self propertiesOf: codePoint) bitAnd: 31) = 19
!
isWhiteSpaceCode: codePoint
	"The White_Space property: tab, lf, vt, ff, cr, space, U+0085, no-break spaces, the Zs spaces and the line and paragraph separators."
	^((self propertiesOf: codePoint) bitAnd: 16384) ~= 0
!
isPrintableCode: codePoint
	"Not Cc Cf Cs Cn Zl or Zp."
	| category |
	category := (self propertiesOf: codePoint) bitAnd: 31.
	^category < 24 or: [category = 29]
! !

!Unicode class methodsFor: 'characters'!
isLetter: aCharacter
	^self isLetterCode: aCharacter value
!
isDigit: aCharacter
	^self isDigitCode: aCharacter value
!
isUppercase: aCharacter
	^self isUppercaseCode: aCharacter value
!
isLowercase: aCharacter
	^self isLowercaseCode: aCharacter value
!
isMathSymbol: aCharacter
	^self isMathSymbolCode: aCharacter value
!
toUppercase: aCharacter
	"Answer the Character of aCharacter's simple uppercase mapping."
	^Character value: (self toUppercaseCode: aCharacter value)
!
toLowercase: aCharacter
	"Answer the Character of aCharacter's simple lowercase mapping."
	^Character value: (self toLowercaseCode: aCharacter value)
! !

!Unicode class methodsFor: 'case'!
toUppercaseCode: codePoint
	"Answer the simple uppercase mapping of codePoint (itself if it has none)."
	| mapped |
	codePoint < 128 ifTrue: [^(codePoint between: 97 and: 122) ifTrue: [codePoint - 32] ifFalse: [codePoint]].
	mapped := self map: codePoint runs: UnicodeTables uppercaseRuns.
	^mapped isNil ifTrue: [codePoint] ifFalse: [mapped]
!
toLowercaseCode: codePoint
	"Answer the simple lowercase mapping of codePoint (itself if it has none)."
	| mapped |
	codePoint < 128 ifTrue: [^(codePoint between: 65 and: 90) ifTrue: [codePoint + 32] ifFalse: [codePoint]].
	mapped := self map: codePoint runs: UnicodeTables lowercaseRuns.
	^mapped isNil ifTrue: [codePoint] ifFalse: [mapped]
!
toTitlecaseCode: codePoint
	"Answer the simple titlecase mapping of codePoint (itself if it has none)."
	| mapped |
	codePoint < 128 ifTrue: [^self toUppercaseCode: codePoint].
	mapped := self map: codePoint runs: UnicodeTables titlecaseExceptions.
	^mapped isNil ifTrue: [self toUppercaseCode: codePoint] ifFalse: [mapped]
!
caseFoldCode: codePoint
	"Answer the simple case folding of codePoint (CaseFolding.txt, status C and S), for caseless comparison: mostly the lowercase mapping, but e.g. U+00B5 (micro sign) and U+03C2 (final sigma) fold to U+03BC and U+03C3, Cherokee lowercase letters to uppercase."
	| mapped |
	codePoint < 128 ifTrue: [^self toLowercaseCode: codePoint].
	mapped := self map: codePoint runs: UnicodeTables caseFoldExceptions.
	^mapped isNil ifTrue: [self toLowercaseCode: codePoint] ifFalse: [mapped]
! !

!Unicode class methodsFor: 'grapheme clusters'!
graphemeBreakPropertyOf: codePoint
	"Answer the Grapheme_Cluster_Break property (UAX #29): #Other #CR #LF #Control #Extend #ZWJ #Regional_Indicator #Prepend #SpacingMark #L #V #T #LV or #LVT."
	^UnicodeTables graphemeBreakProperties at: (((self propertiesOf: codePoint) bitShift: -5) bitAnd: 15) + 1
!
isExtendedPictographicCode: codePoint
	"The Extended_Pictographic property (emoji and pictographs, assigned or reserved)."
	^((self propertiesOf: codePoint) bitAnd: 512) ~= 0
!
isEmojiPresentationCode: codePoint
	"The Emoji_Presentation property: shown as an emoji without a variation selector."
	^((self propertiesOf: codePoint) bitAnd: 32768) ~= 0
!
indicConjunctBreakOf: codePoint
	"Answer the Indic_Conjunct_Break property: #None #Consonant #Linker or #Extend."
	^#(#None #Consonant #Linker #Extend) at: (((self propertiesOf: codePoint) bitShift: -10) bitAnd: 3) + 1
! !

!Unicode class methodsFor: 'private'!
searchPropertiesOf: codePoint
	"Binary search of the runs."
	| starts lo hi mid |
	starts := UnicodeTables propertyStarts.
	lo := 1.
	hi := starts size.
	[lo < hi] whileTrue: [
		mid := lo + hi + 1 bitShift: -1.
		(starts at: mid) <= codePoint ifTrue: [lo := mid] ifFalse: [hi := mid - 1]].
	^UnicodeTables propertyWords at: (UnicodeTables propertyIndices at: lo)
!
map: codePoint runs: runs
	"Answer what codePoint maps to in runs ({start. stop. stride. delta}, sorted), nil if it is not in one."
	| lo hi mid i |
	(runs isEmpty or: [codePoint < runs first]) ifTrue: [^nil].
	lo := 0.
	hi := runs size // 4 - 1.
	[lo < hi] whileTrue: [
		mid := lo + hi + 1 bitShift: -1.
		(runs at: mid * 4 + 1) <= codePoint ifTrue: [lo := mid] ifFalse: [hi := mid - 1]].
	i := lo * 4 + 1.
	(codePoint <= (runs at: i + 1) and: [(codePoint - (runs at: i)) \\ (runs at: i + 2) = 0]) ifFalse: [^nil].
	^codePoint + (runs at: i + 3)
! !
