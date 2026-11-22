TestCase subclass: #OmarchyThemeTest
	instanceVariableNames: 'dir'
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
