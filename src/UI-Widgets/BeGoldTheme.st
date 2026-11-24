Theme subclass: #BeGoldTheme
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Widgets'!

BeGoldTheme comment: 'I am the be-gold theme: Haiku''s look (its R1 defaults, after BeOS) on the Blue Book''s metrics. Documents are white on #D8D8D8 panels, buttons, tabs and scroll bars are shaded bevels (metric #bevel), a selected row is a gray bar, the desk is #336698 and its blue the accent. Windows (Window chromeStyle #tab) have a 5-point bevelled frame under a #FFCB00 tab as wide as the title, holding the close box and a zoom-like collapse box, with the desk showing beside it. The UI face draws in Noto Sans, Haiku''s system face (fonts/NotoSans-*.ttf); code stays in JetBrains Mono.

	Theme use: Theme beGold.
	Theme toggle.		"back to the Blue Book"'!

!BeGoldTheme methodsFor: 'initialization'!
initializeBeGold
	"The Blue Book metrics with Haiku's colors (its R1 defaults): white documents on #D8D8D8 panels, the #336698 desk, whose blue is also the accent, and the #FFCB00 window tab."
	| blue |
	self initializeBlueBook.
	blue := Color hex: 16r336698.
	colors
		at: #ink2 put: (Color hex: 16r333333);
		at: #ink3 put: (Color hex: 16r5C5C5C);
		at: #ink4 put: (Color hex: 16r999999);
		at: #hair put: (Color hex: 16rC0C0C0);
		at: #paper put: Color white;
		at: #panel put: (Color hex: 16rD8D8D8);
		at: #rule put: (Color hex: 16r999999);
		at: #ultramarine put: blue;
		at: #accentSoft put: (blue alpha: 0.15);
		at: #textSelection put: (blue alpha: 0.30);
		at: #busySoft put: (blue alpha: 0.15);
		at: #l1 put: (Color hex: 16r1B528C);
		at: #l2 put: blue;
		at: #l3 put: (Color hex: 16r6698CB);
		at: #l4 put: (Color hex: 16rA9C4E0);
		at: #l5 put: (Color hex: 16rDDE7F1);
		at: #desk put: blue;
		at: #deskDots put: blue;
		at: #shadow put: Color transparent;
		at: #selection put: (Color hex: 16rBEBEBE);
		at: #mark put: (Color hex: 16r1B528C);
		at: #tab put: (Color hex: 16rFFCB00);
		at: #tabLight put: (Color hex: 16rFFEFB4);
		at: #tabEdge put: (Color hex: 16rB38F00);
		at: #tabInactive put: (Color hex: 16rE8E8E8);
		at: #tabInactiveLight put: (Color hex: 16rF8F8F8);
		at: #tabInactiveEdge put: (Color hex: 16rA3A3A3);
		at: #bevelLight put: (Color hex: 16rF7F7F7);
		at: #bevelDark put: (Color hex: 16r909090);
		at: #buttonTop put: (Color hex: 16rEBEBEB);
		at: #buttonBottom put: (Color hex: 16rDBDBDB);
		at: #pressed put: (Color hex: 16rBEBEBE).
	metrics at: #bevel put: 1
!
applyFonts
	"The UI face, Iosevka Etoile, draws in Haiku's Noto Sans (when the image has it); code stays in JetBrains Mono."
	| changed |
	changed := false.
	#(#('IosevkaEtoile-Regular' 'NotoSans-Regular') #('IosevkaEtoile-Bold' 'NotoSans-Bold') #('IosevkaEtoile-Italic' 'NotoSans-Italic')) do: [:pair |
		(Font imageFaceNamed: pair last) ifNotNil: [:face |
			(Font substitutes at: pair first ifAbsent: [nil]) == face ifFalse: [
				Font substituteFace: pair first with: face.
				changed := true]]].
	fonts := IdentityDictionary new.
	syntax := nil.
	changed ifTrue: [self prerasterizeStandardFonts]
!
refresh
	"As Theme's, with my colors."
	self initializeBeGold.
	syntax := nil.
	terminal := nil.
	self publishPalette
! !

!BeGoldTheme methodsFor: 'fonts'!
makeFont: aSymbol
	"Haiku's headings are bold, not capitals: #header is the bold UI face (Noto Sans) at 12."
	aSymbol == #header ifTrue: [^(Font face: (Font faceNamed: 'IosevkaEtoile-Bold') size: 12) lineHeight: 15; yourself].
	^super makeFont: aSymbol
! !
