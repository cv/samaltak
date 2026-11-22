TestCase subclass: #OmarchyThemeTest
	instanceVariableNames: 'dir previousTheme previousWorld world'
	classVariableNames: ''
	package: 'Tests-UI-Omarchy'!

OmarchyThemeTest comment: 'Tests OmarchyTheme on theme files written to a scratch directory: the palette and its fallbacks, surface colors with references, roles and alphas, user overrides, the type scale and spacing, and noticing changed files.'!

!OmarchyThemeTest methodsFor: 'running'!
setUp
	dir := self scratchDirectory / 'current'.
	Directory create: dir.
	Directory create: dir / 'theme'.
	File writeText: 'flexoki-light' to: dir / 'theme.name'.
	File writeText: 'mode = "light"
accent = "#205EA6"
muted = "#B7B5AC"
background = "#FFFCF0"
foreground = "#100F0F"
red = "#D14D41"
' to: dir / 'theme' / 'colors.toml'.
	File writeText: '[hyprland]
active-border = "#205EA6"

[bar]
background = "background"
background-alpha = 0.5

[popups]
background       = "#FFFCF0"
background-alpha = 1.0
text             = "#100F0F"
border           = "hyprland.active-border"
border-alpha     = 1.0

[font]
base-size = 12
title = 15

[spacing]
scale = 1.0
scale-with-font = true
' to: dir / 'theme' / 'shell.toml'
!
theme
	^OmarchyTheme new setDirectory: dir / 'theme' userShell: dir / 'user-shell.toml'
!
darkTheme
	"Tokyo Night's palette, in a theme directory of its own."
	| d |
	d := self scratchDirectory / 'dark'.
	Directory create: d.
	File writeText: 'mode = "dark"
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"
background = "#1a1b26"
dark_background = "#13141c"
foreground = "#a9b1d6"
red = "#f7768e"
green = "#9ece6a"
bright_green = "#b9f27c"
' to: d / 'colors.toml'.
	^OmarchyTheme new setDirectory: d userShell: d / 'none.toml'
!
tearDown
	world isNil ifFalse: [world stop. World current: previousWorld].
	previousTheme isNil ifFalse: [
		OmarchyTheme uninstall.
		Theme current: previousTheme.
		previousTheme publishPalette]
!
use: aTheme
	"Make aTheme current as install does (without its watcher)."
	previousTheme isNil ifTrue: [previousTheme := Theme current].
	Theme current: aTheme.
	aTheme publishPalette; applyFonts
! !

!OmarchyThemeTest methodsFor: 'tests'!
testPalette
	| theme |
	theme := self theme.
	self assert: theme name equals: 'flexoki-light'.
	self deny: theme isDark.
	self assert: theme foreground hex equals: (Color hex: 16r100F0F) hex.
	self assert: theme background hex equals: (Color hex: 16rFFFCF0) hex.
	self assert: theme accent hex equals: (Color hex: 16r205EA6) hex.
	self assert: theme urgent hex equals: (Color hex: 16rD14D41) hex.
	self assert: (theme color: #ink) hex equals: theme foreground hex.
	self assert: (theme color: #paper) hex equals: theme background hex.
	self assert: (theme color: #ultramarine) hex equals: theme accent hex
!
testSurfaces
	| theme |
	theme := self theme.
	self assert: (theme color: #popupBorder) hex equals: (Color hex: 16r205EA6) hex.
	self assert: (theme color: #popupBackground) hex equals: (Color hex: 16rFFFCF0) hex.
	self assert: (theme shellColor: 'bar.background') hex equals: theme background hex.
	self assert: (theme shellColor: 'bar.background') alpha equals: 0.5.
	self assert: (theme flatColor: 'rgba(33ccffee) rgba(00ff99ee) 45deg' default: nil) hex equals: 16r33CCFF.
	self assert: (theme flatColor: 'nonsense' default: Color black) == Color black
!
testUserOverrides
	File writeText: '[popups]
border = "accent"
border-alpha = 0.25
' to: dir / 'user-shell.toml'.
	self assert: (self theme color: #popupBorder) hex equals: (Color hex: 16r205EA6) hex.
	self assert: (self theme color: #popupBorder) alpha equals: 0.25.
	self assert: (self theme shellValue: 'popups.text') equals: '#100F0F'
!
testTypeScaleAndSpacing
	| theme |
	theme := self theme.
	self assert: (theme pixelsOf: #caption) equals: 10.
	self assert: (theme pixelsOf: #body) equals: 12.
	self assert: (theme pixelsOf: #title) equals: 15.
	self assert: (theme pixelsOf: #display) equals: 24.
	self assert: (theme font: #display) size equals: 24.
	self assert: (theme font: #titleBold) size equals: 15.
	self assert: (theme space: 16) equals: 16.
	self assert: (theme metric: #panelPadding) equals: 18.
	self assert: ((theme fontOfSize: 56 bold: true) size) equals: 56
!
testChromeRolesLight
	| theme |
	theme := self theme.
	self assert: (theme color: #shadow) hex equals: theme foreground hex.
	self assert: (theme color: #desk) hex equals: theme background hex.
	self assert: (theme color: #deskDots) hex equals: theme muted hex.
	self assert: (theme color: #l1) hex equals: theme accent hex
!
testChromeRolesDark
	| theme |
	theme := self darkTheme.
	self assert: theme isDark.
	self assert: (theme color: #shadow) hex equals: Color black hex.
	self assert: (theme color: #desk) hex equals: 16r13141C.
	self assert: (theme color: #deskDots) hex equals: 16r414868.
	self assert: (theme color: #textSelection) hex equals: 16r292E42
!
testTerminalPalette
	| ansi |
	ansi := self darkTheme ansiColors.
	self assert: ansi size equals: 16.
	self assert: (ansi at: 1) hex equals: 16r1A1B26.
	self assert: (ansi at: 2) hex equals: 16rF7768E.
	self assert: (ansi at: 8) hex equals: 16rA9B1D6.
	self assert: (ansi at: 9) hex equals: 16r414868.
	self assert: (ansi at: 10) hex equals: 16rF7768E.
	self assert: (ansi at: 11) hex equals: 16rB9F27C
!
testInstallingPublishesTheRolesAndUninstallingRestoresTheBlueBook
	| theme |
	theme := self darkTheme.
	self use: theme.
	self assert: Color ink hex equals: 16rA9B1D6.
	self assert: Color paper hex equals: 16r1A1B26.
	self assert: Color ultramarine hex equals: 16r7AA2F7.
	self assert: Color desk hex equals: 16r13141C.
	self assert: (Font faceNamed: 'JetBrainsMono-Regular') == theme regularFace.
	OmarchyTheme uninstall.
	self assert: (Theme current isKindOf: OmarchyTheme) not.
	self assert: Color ink hex equals: 16r000000.
	self assert: Color paper hex equals: 16rFFFFFF.
	self assert: Color ultramarine hex equals: 16r1B3A8C.
	self deny: (Font substitutes includesKey: 'JetBrainsMono-Regular')
!
testTheWorldIsDrawnInTheTheme
	| form |
	self use: self darkTheme.
	previousWorld := World current.
	world := World openHidden: 400 @ 300.
	self assert: (world waitUntilSettled: 5000).
	form := world compositor sync: [:c | c screenshotScale: 1].
	"the top bar's paper, the desk's background and dots"
	self assert: ((form pixelValueAt: 200 @ 2) bitAnd: 16rFFFFFF) equals: 16r261B1A.
	self assert: ((#(0 1) inject: Set new into: [:all :dx | all addAll: (#(0 1) collect: [:dy | (form pixelValueAt: (100 + dx) @ (200 + dy)) bitAnd: 16rFFFFFF]); yourself]) asArray asSortedCollection asArray)
		equals: #(16r1C1413 16r684841)
!
testNotFollowedWhileTesting
	self deny: OmarchyTheme wanted
!
testParseColor
	self assert: (OmarchyTheme parseColor: '#fff') hex equals: Color white hex.
	self assert: (OmarchyTheme parseColor: 'rgb(205EA6)') hex equals: (Color hex: 16r205EA6) hex.
	self assert: (OmarchyTheme parseColor: '#205EA680') alpha * 255 rounded equals: 128.
	self assert: (OmarchyTheme parseColor: 'accent') isNil.
	self assert: (OmarchyTheme parseColor: nil) isNil
!
testNoticesChangedFiles
	| theme |
	theme := self theme.
	self deny: theme isStale.
	(Delay forMilliseconds: 20) wait.
	File writeText: (File readText: dir / 'theme' / 'colors.toml'), 'accent = "#CE5D97"
' to: dir / 'theme' / 'colors.toml'.
	self assert: theme isStale.
	theme refresh.
	self deny: theme isStale.
	self assert: theme accent hex equals: (Color hex: 16rCE5D97) hex
! !
