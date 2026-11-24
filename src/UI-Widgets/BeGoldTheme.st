Theme subclass: #BeGoldTheme
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'UI-Widgets'!

BeGoldTheme comment: 'I am the be-gold theme: the Blue Book''s metrics and fonts with BeOS-like colors. Panels are gray, buttons are raised bevels (metric #bevel), windows have a gold tab holding the title and close box (Window chromeStyle #tab), and NVIDIA green (16r76B900) takes ultramarine''s place as accent and desk.

	Theme use: Theme beGold.
	Theme toggle.		"back to the Blue Book"'!

!BeGoldTheme methodsFor: 'initialization'!
initializeBeGold
	"The Blue Book metrics with BeOS-like colors: gray panels, gold tabs and NVIDIA green (16r76B900) where the Blue Book has ultramarine."
	| green deep |
	self initializeBlueBook.
	green := Color hex: 16r76B900.
	deep := Color hex: 16r4A7A00.
	colors
		at: #ink2 put: (Color hex: 16r333333);
		at: #ink3 put: (Color hex: 16r5C5C5C);
		at: #ink4 put: (Color hex: 16r9A9A9A);
		at: #hair put: (Color hex: 16rB9B9B9);
		at: #paper put: (Color hex: 16rDEDEDE);
		at: #ultramarine put: deep;
		at: #accentSoft put: (green alpha: 0.25);
		at: #textSelection put: (green alpha: 0.40);
		at: #busySoft put: (green alpha: 0.20);
		at: #l1 put: deep;
		at: #l2 put: (Color hex: 16r5E9600);
		at: #l3 put: green;
		at: #l4 put: (Color hex: 16rB5DB6E);
		at: #l5 put: (Color hex: 16rE2F0C8);
		at: #desk put: (Color hex: 16r5E9400);
		at: #deskDots put: (Color hex: 16r578A00);
		at: #tab put: (Color hex: 16rFFD75A);
		at: #tabShade put: (Color hex: 16rD9A514);
		at: #bevelLight put: (Color hex: 16rF7F7F7);
		at: #bevelDark put: (Color hex: 16r8E8E8E);
		at: #pressed put: green.
	metrics at: #bevel put: 1
!
refresh
	"As Theme's, with my colors."
	self initializeBeGold.
	syntax := nil.
	terminal := nil.
	self publishPalette
! !
