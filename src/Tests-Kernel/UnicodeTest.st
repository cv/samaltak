TestCase subclass: #UnicodeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

UnicodeTest comment: 'Tests Unicode character properties and the Character protocol built on them: general categories, classification and case of several scripts, display widths, extended grapheme clusters (all of GraphemeBreakTest.txt), and that the fast paths for low code points answer what the tables do.'!

!UnicodeTest methodsFor: 'helpers'!
char: anInteger
	^Character value: anInteger
!
string: codePoints
	^String withAll: (codePoints collect: [:each | Character value: each])
! !

!UnicodeTest methodsFor: 'tests'!
testVersion
	self assert: Unicode version equals: '17.0.0'
!
testGeneralCategories
	#(65 #Lu 97 #Ll 170 #Lo 181 #Ll 186 #Lo 215 #Sm 247 #Sm 453 #Lt 688 #Lm 769 #Mn 2307 #Mc 8413 #Me
	  53 #Nd 1635 #Nd 8555 #Nl 189 #No 95 #Pc 45 #Pd 40 #Ps 41 #Pe 171 #Pi 187 #Pf 46 #Po 43 #Sm 36 #Sc 94 #Sk
	  169 #So 128512 #So 32 #Zs 12288 #Zs 8232 #Zl 8233 #Zp 0 #Cc 133 #Cc 173 #Cf 8205 #Cf 55296 #Cs 57344 #Co
	  888 #Cn 1114111 #Cn 26085 #Lo) pairsDo: [:cp :category |
		self assert: (Unicode generalCategoryTagOf: cp) equals: category.
		self assert: (self char: cp) generalCategory equals: category]
!
testDigitValues
	"digitValue answers 0-9 for every decimal digit (Nd), as in Squeak and Pharo: Unicode assigns them in runs of ten; 10-35 only for ASCII letters, -1 for other numbers and letters."
	UnicodeTables decimalDigitZeros do: [:zero |
		0 to: 9 do: [:i |
			self assert: (self char: zero + i) isDigit.
			self assert: (self char: zero + i) digitValue equals: i]].
	self assert: UnicodeTables decimalDigitZeros size * 10 equals: ((0 to: 16r1FFFF) count: [:cp | Unicode isDigitCode: cp]).
	self assert: (self char: 1641) digitValue equals: 9.
	self assert: (self char: 65303) digitValue equals: 7.
	self assert: (self char: 120799) digitValue equals: 7.
	#(8555 189 178 65313 945 32 47 58 64 91 96 123 1631) do: [:cp |
		self assert: (self char: cp) digitValue equals: -1].
	self assert: $z digitValue equals: 35
!
testCodeAndCharacterSelectors
	"The ...Code: selectors take code points (Squeak); isLetter: isDigit: isUppercase: isLowercase: isMathSymbol: toUppercase: toLowercase: take Characters (Pharo)."
	| alpha |
	alpha := self char: 945.
	self assert: (Unicode isLetterCode: 945).
	self assert: (Unicode isLetter: alpha).
	self deny: (Unicode isLetter: $1).
	self assert: (Unicode isDigitCode: 1635).
	self assert: (Unicode isDigit: (self char: 1635)).
	self deny: (Unicode isDigit: $a).
	self assert: (Unicode isLowercaseCode: 945).
	self assert: (Unicode isLowercase: alpha).
	self assert: (Unicode isUppercaseCode: 913).
	self assert: (Unicode isUppercase: (self char: 913)).
	self deny: (Unicode isUppercase: alpha).
	self assert: (Unicode isMathSymbolCode: 215).
	self assert: (Unicode isMathSymbol: (self char: 8800)).
	self deny: (Unicode isMathSymbol: $a).
	self assert: (Unicode isMarkCode: 769).
	self assert: (Unicode isWhiteSpaceCode: 12288).
	self deny: (Unicode isPrintableCode: 0).
	self assert: (Unicode isExtendedPictographicCode: 128512).
	self assert: (Unicode toUppercaseCode: 945) equals: 913.
	self assert: (Unicode toLowercaseCode: 913) equals: 945.
	self assert: (Unicode toTitlecaseCode: 454) equals: 453.
	self assert: (Unicode caseFoldCode: 181) equals: 956.
	self assert: (Unicode toUppercase: alpha) equals: (self char: 913).
	self assert: (Unicode toLowercase: (self char: 913)) equals: alpha.
	self assert: (Unicode toUppercase: $a) equals: $A.
	self assert: (Unicode toLowercase: $1) equals: $1
!
testLowCodePointsAgreeWithTables
	"Below 256 the properties come from a direct table, ASCII case mappings from arithmetic, and grapheme cluster boundaries between code points below 768 from a shortcut; they agree with the runs."
	0 to: 255 do: [:cp |
		self assert: (Unicode propertiesOf: cp) equals: (Unicode searchPropertiesOf: cp)].
	0 to: 127 do: [:cp |
		self assert: (Unicode toUppercaseCode: cp) equals: ((Unicode map: cp runs: UnicodeTables uppercaseRuns) ifNil: [cp]).
		self assert: (Unicode toLowercaseCode: cp) equals: ((Unicode map: cp runs: UnicodeTables lowercaseRuns) ifNil: [cp]).
		self assert: (Unicode caseFoldCode: cp) equals: (Unicode toLowercaseCode: cp).
		self assert: (Unicode toTitlecaseCode: cp) equals: (Unicode toUppercaseCode: cp)].
	0 to: 767 do: [:cp |
		self assert: (#(#Other #CR #LF #Control) includes: (Unicode graphemeBreakPropertyOf: cp)).
		self assert: (Unicode indicConjunctBreakOf: cp) equals: #None]
!
testLatin1
	"Latin-1 classification and case: µ is a lowercase letter going up to Greek capital mu, ª º are letters without case, × ÷ math symbols, ÿ goes up to U+0178, ß has no simple uppercase."
	| micro |
	micro := self char: 181.
	self assert: micro isLetter.
	self assert: micro isLowercase.
	self assert: micro asUppercase value equals: 924.
	self assert: micro caseFolded value equals: 956.
	self assert: micro asLowercase == micro.
	#(170 186) do: [:cp |
		self assert: (self char: cp) isLetter.
		self deny: (self char: cp) isUppercase.
		self deny: (self char: cp) isLowercase].
	self deny: $× isLetter.
	self deny: $÷ isLetter.
	self assert: $× isSpecial.
	self assert: $ÿ asUppercase value equals: 376.
	self assert: (self char: 376) asLowercase equals: $ÿ.
	self assert: $ß asUppercase equals: $ß.
	self assert: $ß isLowercase.
	self assert: $Ä asLowercase equals: $ä.
	self assert: $ä asUppercase equals: $Ä.
	self assert: (self char: 160) isSeparator.
	self assert: (self char: 133) isSeparator.
	self deny: (self char: 133) isPrintable.
	self deny: (self char: 173) isPrintable.
	self assert: $é isPrintable
!
testScripts
	"Greek, Cyrillic, Armenian, Georgian (Mkhedruli is lowercase with Mtavruli capitals, titlecase itself), CJK, Hangul."
	#(913 945 1046 1078 1329 1377 7312 4304 66560 66600) pairsDo: [:upper :lower |
		self assert: (self char: upper) isUppercase.
		self assert: (self char: lower) isLowercase.
		self assert: (self char: upper) isLetter.
		self assert: (self char: upper) asLowercase value equals: lower.
		self assert: (self char: lower) asUppercase value equals: upper.
		self assert: (self char: upper) caseFolded value equals: lower].
	self assert: (self char: 4304) asTitlecase value equals: 4304.
	#(26085 26412 12354 44032 1488 1575) do: [:cp |
		self assert: (self char: cp) isLetter.
		self deny: (self char: cp) isUppercase.
		self deny: (self char: cp) isLowercase.
		self assert: (self char: cp) asUppercase value equals: cp].
	self assert: (self char: 1635) isDigit.
	self assert: (self char: 1635) isAlphaNumeric.
	self assert: (self char: 1635) digitValue equals: 3.
	self deny: (self char: 8555) isDigit
!
testNonLetters
	"Emoji, CJK punctuation, ideographic space, marks and format characters are not letters."
	#(128512 128077 12289 12290 12288 769 8205 65279 9731 8364) do: [:cp |
		self deny: (self char: cp) isLetter].
	self assert: (self char: 769) isMark.
	self assert: (self char: 2307) isMark.
	self deny: $a isMark.
	self assert: (self char: 12288) isSeparator.
	self assert: (self char: 8232) isSeparator.
	self deny: (self char: 8203) isSeparator.
	self deny: (self char: 65279) isSeparator.
	self assert: (self char: 128512) isPrintable.
	self assert: (self char: 57344) isPrintable.
	self deny: (self char: 8232) isPrintable.
	self deny: (self char: 55296) isPrintable.
	self deny: (self char: 888) isPrintable.
	self deny: (self char: 65535) isPrintable.
	self assert: (self char: 955) printString equals: '$λ'.
	self assert: (self char: 160) printString equals: '(Character value: 160)'.
	self assert: (self char: 8205) printString equals: '(Character value: 8205)'
!
testSpecialCaseMappings
	"Titlecase digraphs, final sigma, dotted I, sharp s, Cherokee (folding to uppercase), long s, Kelvin sign."
	self assert: (self char: 454) asUppercase value equals: 452.
	self assert: (self char: 454) asTitlecase value equals: 453.
	self assert: (self char: 452) asTitlecase value equals: 453.
	self assert: (self char: 453) isLetter.
	self deny: (self char: 453) isUppercase.
	self assert: (self char: 962) asUppercase value equals: 931.
	self assert: (self char: 962) caseFolded value equals: 963.
	self assert: (self char: 931) caseFolded value equals: 963.
	self assert: (self char: 304) asLowercase equals: $i.
	self assert: (self char: 304) caseFolded value equals: 304.
	self assert: (self char: 7838) asLowercase equals: $ß.
	self assert: (self char: 7838) caseFolded equals: $ß.
	self assert: (self char: 5024) asLowercase value equals: 43888.
	self assert: (self char: 43888) caseFolded value equals: 5024.
	self assert: (self char: 383) caseFolded equals: $s.
	self assert: (self char: 383) asUppercase equals: $S.
	self assert: (self char: 8490) asLowercase equals: $k.
	self assert: $a asTitlecase equals: $A
!
testDisplayWidth
	#(97 1 233 1 26085 2 12354 2 44032 2 65313 2 12288 2 128512 2 127988 2 9731 1 8987 2
	  769 0 8205 0 8203 0 65039 0 4448 0 4520 0 55216 0 173 1 0 0 9 0 127 0 155 0 1488 1 3585 1) pairsDo: [:cp :width |
		self assert: (Unicode displayWidthOf: cp) equals: width.
		self assert: (self char: cp) displayWidth equals: width]
!
testGraphemeBreakProperties
	#(13 #CR 10 #LF 0 #Control 769 #Extend 8205 #ZWJ 127462 #Regional_Indicator 1536 #Prepend 2307 #SpacingMark
	  4352 #L 4449 #V 4520 #T 44032 #LV 44033 #LVT 97 #Other 128512 #Other) pairsDo: [:cp :property |
		self assert: (Unicode graphemeBreakPropertyOf: cp) equals: property].
	self assert: (Unicode isExtendedPictographicCode: 128512).
	self assert: (Unicode isExtendedPictographicCode: 169).
	self deny: (Unicode isExtendedPictographicCode: 97).
	self assert: (Unicode indicConjunctBreakOf: 2325) equals: #Consonant.
	self assert: (Unicode indicConjunctBreakOf: 2381) equals: #Linker.
	self assert: (Unicode indicConjunctBreakOf: 769) equals: #Extend
!
testGraphemeBreakTestFile
	"Every line of the UCD's GraphemeBreakTest.txt: the clusters, and the boundaries found going forward and backward."
	| failures |
	failures := OrderedCollection new.
	GraphemeBreakTestData cases do: [:clusters |
		| string boundaries ok |
		string := self string: (clusters inject: #() into: [:all :each | all , each]).
		boundaries := OrderedCollection with: 0.
		clusters do: [:each | boundaries add: boundaries last + each size].
		ok := string graphemeClusters = (clusters collect: [:each | self string: each]) asArray
			and: [string graphemeClusterCount = clusters size
			and: [(0 to: string size) allSatisfy: [:p | (string isGraphemeClusterBoundaryAt: p) = (boundaries includes: p)]]].
		ok := ok and: [(1 to: boundaries size - 1) allSatisfy: [:i |
			(string graphemeClusterStartBefore: (boundaries at: i + 1)) = (boundaries at: i)
				and: [(string graphemeClusterEndAfter: (boundaries at: i)) = (boundaries at: i + 1)]]].
		ok ifFalse: [failures add: clusters]].
	self assert: GraphemeBreakTestData cases size > 700.
	self assert: failures isEmpty description: failures size printString , ' failing: ' , (failures first: (failures size min: 5)) printString
!
testGraphemeClusters
	| s flags family |
	s := self string: #(101 769 120).
	self assert: s graphemeClusterCount equals: 2.
	self assert: (s graphemeClusterEndAfter: 0) equals: 2.
	self assert: (s graphemeClusterEndAfter: 1) equals: 2.
	self assert: (s graphemeClusterEndAfter: 2) equals: 3.
	self assert: (s graphemeClusterEndAfter: 3) equals: 3.
	self assert: (s graphemeClusterStartBefore: 3) equals: 2.
	self assert: (s graphemeClusterStartBefore: 2) equals: 0.
	self assert: (s graphemeClusterStartBefore: 1) equals: 0.
	self assert: (s graphemeClusterStartBefore: 0) equals: 0.
	flags := self string: #(127465 127466 127467 127479 127467).
	self assert: flags graphemeClusters equals: {self string: #(127465 127466). self string: #(127467 127479). self string: #(127467)}.
	family := self string: #(128104 8205 128105 8205 128103 8205 128102).
	self assert: family graphemeClusterCount equals: 1.
	self assert: (self string: #(128077 127997)) graphemeClusterCount equals: 1.
	self assert: (self string: #(4352 4449 4520)) graphemeClusterCount equals: 1.
	self assert: (self string: #(13 10 97)) graphemeClusterCount equals: 2.
	self assert: (self string: #(2325 2381 2359)) graphemeClusterCount equals: 1.
	self assert: '' graphemeClusterCount equals: 0.
	self assert: 'abc' graphemeClusters equals: #('a' 'b' 'c')
! !
