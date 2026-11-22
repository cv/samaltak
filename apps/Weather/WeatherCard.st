Widget subclass: #WeatherCard
	instanceVariableNames: 'report location error imperial onActivate onRefresh'
	classVariableNames: ''
	package: 'Weather'!

WeatherCard comment: 'I show the weather as the Omarchy desktop card and the bar''s weather panel do: the current conditions (the weather''s glyph, the temperature large, the place and FEELS, WIND, HUMID) above a hairline and the next three days (glyph, day, high and low), on the theme''s popup surface in its typeface and type scale (OmarchyTheme; other themes give me their paper, ink and code font). Until the first report I say what is going on.

A click runs onActivate (the app opens the bar''s weather panel), a middle click onRefresh.'!

!WeatherCard methodsFor: 'initialization'!
initialize
	super initialize.
	error := ''.
	imperial := false
! !

!WeatherCard methodsFor: 'accessing'!
report: aReport location: aLocation error: aString
	"Show what the service has now (any Process: my window's do: runs me)."
	report := aReport.
	location := aLocation.
	error := aString ifNil: [''].
	self invalidate
!
report
	^report
!
imperial: aBoolean
	imperial := aBoolean.
	self invalidate
!
onActivate: aBlock
	onActivate := aBlock
!
onRefresh: aBlock
	onRefresh := aBlock
!
statusText
	"What I show without a report."
	^error isEmpty ifTrue: ['Fetching weather…'] ifFalse: [error]
! !

!WeatherCard methodsFor: 'theme'!
omarchy
	"The current theme if it is Omarchy's, else nil."
	^(self theme respondsTo: #fontOfSize:bold:letterSpacing:) ifTrue: [self theme] ifFalse: [nil]
!
fontOfSize: pixels bold: aBoolean
	^self fontOfSize: pixels bold: aBoolean tracking: 0
!
fontOfSize: pixels bold: aBoolean tracking: points
	| font |
	self omarchy ifNotNil: [:t | ^t fontOfSize: pixels bold: aBoolean letterSpacing: points].
	font := Font faceNamed: (aBoolean ifTrue: ['JetBrainsMono-Bold'] ifFalse: ['JetBrainsMono-Regular']) size: pixels.
	points = 0 ifFalse: [font letterSpacing: points].
	^font
!
pixelsOf: aToken
	"The shell's type scale (OmarchyTheme), or its defaults at base size 12."
	self omarchy ifNotNil: [:t | ^t pixelsOf: aToken].
	^(12 * (OmarchyTheme tokenFactors at: aToken)) rounded
!
space: points
	self omarchy ifNotNil: [:t | ^t space: points].
	^points
!
cardPadding
	"The desktop card's padding (Style.spacing.panelPadding, 18) less its 2-point border, which the window manager's border replaces: Hyprland draws its border outside the window, the card inside its padding."
	^(self omarchy ifNil: [18] ifNotNil: [:t | t metric: #panelPadding]) - (self space: 2)
!
background
	self omarchy ifNotNil: [:t | ^t color: #popupBackground].
	^self theme paper
!
foreground
	self omarchy ifNotNil: [:t | ^t color: #popupText].
	^self theme ink
!
dim
	"Qt.darker(text, 1.4), as the card dims its labels."
	^self darker: self foreground by: 1.4
!
dimmer
	^self darker: self foreground by: 1.5
!
darker: aColor by: factor
	^Color r: aColor red / factor g: aColor green / factor b: aColor blue / factor a: aColor alpha
! !

!WeatherCard methodsFor: 'fonts'!
iconFont
	^self fontOfSize: 64 bold: false
!
temperatureFont
	^self fontOfSize: 56 bold: true
!
unitFont
	^self fontOfSize: (self pixelsOf: #display) bold: false
!
placeFont
	^self fontOfSize: (self pixelsOf: #body) bold: false tracking: 1
!
markerFont
	^self fontOfSize: (self pixelsOf: #body) bold: false
!
statLabelFont
	^self fontOfSize: (self pixelsOf: #bodySmall) bold: false tracking: 1
!
statValueFont
	^self fontOfSize: (self pixelsOf: #title) bold: false
!
dayIconFont
	^self fontOfSize: (self pixelsOf: #display) bold: false
!
dayNameFont
	^self fontOfSize: (self pixelsOf: #caption) bold: false tracking: 1
!
dayTemperatureFont
	^self fontOfSize: (self pixelsOf: #body) bold: false
!
statusFont
	^self fontOfSize: (self pixelsOf: #bodySmall) bold: false
! !

!WeatherCard methodsFor: 'layout'!
contentWidth
	"The card's width without its padding: a column of desktop-cards on a 1512-point screen less the card's padding. desktop-cards (Layout.js) makes a column floor((1512 - 2 gaps - 2 gaps) / 3) wide, the gap 10 points: 490."
	^490 - (2 * (self space: 18))
!
widthOf: aString in: aFont
	"The width a Qt Text gives aString: its natural width (ink past the last advance included), in whole points."
	^(aFont naturalWidthOf: aString) ceiling
!
heroHeight
	^self heroLeftHeight max: self heroRightHeight
!
heroLeftHeight
	^self iconFont lineHeight max: self temperatureFont lineHeight
!
heroRightHeight
	^self placeFont lineHeight + (self space: 12) + self statHeight
!
statHeight
	^self statLabelFont lineHeight + (self space: 5) + self statValueFont lineHeight
!
forecastHeight
	^self dayIconFont lineHeight max: self dayNameFont lineHeight + (self space: 2) + self dayTemperatureFont lineHeight
!
contentHeight
	^self heroHeight + (self space: 14) + (self space: 1) + (self space: 14) + self forecastHeight
!
preferredExtent
	^(self contentWidth + (2 * self cardPadding)) ceiling @ (self contentHeight + (2 * self cardPadding)) ceiling
! !

!WeatherCard methodsFor: 'drawing'!
drawSelfOn: aCanvas
	| pad |
	aCanvas fillRect: self localBounds color: self background.
	pad := self cardPadding.
	report isNil ifTrue: [
		^aCanvas drawString: self statusText at: pad @ pad font: self statusFont color: self dimmer].
	aCanvas translateBy: pad @ pad during: [
		self drawHeroOn: aCanvas.
		aCanvas fillRect: (0 @ (self heroHeight + (self space: 14)) extent: (self width - (2 * pad)) @ (self space: 1))
			color: (self foreground alpha: 0.12).
		aCanvas translateBy: 0 @ (self heroHeight + (2 * (self space: 14)) + (self space: 1)) during: [
			self drawForecastOn: aCanvas width: self width - (2 * pad)]]
!
drawHeroOn: c
	"Left: the glyph and the temperature, vertically centered; right: the place above the stats."
	| h x iconFont tempFont unitFont temp tempY rightX y stats w |
	h := self heroHeight.
	iconFont := self iconFont.
	tempFont := self temperatureFont.
	unitFont := self unitFont.
	x := self space: 16.
	c drawString: report icon at: x @ ((h - iconFont lineHeight) / 2 + 5) font: iconFont color: self foreground.
	x := x + (self widthOf: report icon in: iconFont) + (self space: 16).
	temp := WeatherReport temperature: report temperature imperial: imperial.
	tempY := (h - tempFont lineHeight) / 2.
	c drawString: temp at: x @ tempY font: tempFont color: self foreground.
	x := x + (self widthOf: temp in: tempFont) + (self space: 2).
	c drawString: self unitText at: x @ (tempY + (self space: 10)) font: unitFont color: self foreground.
	stats := self stats.
	w := self statsWidth: stats.
	rightX := self width - (2 * self cardPadding) - (self space: 20) - w.
	y := (h - self heroRightHeight) / 2.
	self drawPlaceOn: c at: rightX @ y width: w.
	y := y + self placeFont lineHeight + (self space: 12).
	stats do: [:pair |
		c drawString: pair first at: rightX @ y font: self statLabelFont color: self dimmer.
		c drawString: pair last at: rightX @ (y + self statLabelFont lineHeight + (self space: 5)) font: self statValueFont color: self foreground.
		rightX := rightX + (self statWidth: pair) + (self space: 36)]
!
drawPlaceOn: c at: aPoint width: w
	| marker name font x |
	location isNil ifTrue: [^self].
	location name isEmpty ifTrue: [^self].
	marker := WeatherIcons mapMarker.
	font := self placeFont.
	c drawString: marker at: aPoint font: self markerFont color: self dim.
	x := aPoint x + (self widthOf: marker in: self markerFont) + (self space: 6).
	name := self class truncate: location name asUppercase to: w - (x - aPoint x) font: font.
	c drawString: name at: x @ aPoint y font: font color: self dim
!
drawForecastOn: c width: width
	"Each day: its glyph beside its name and its high and low; the days centered."
	| days cells x |
	days := report days.
	days isEmpty ifTrue: [^self].
	cells := days collect: [:day | self cellWidthOf: day].
	x := (width - ((cells inject: 0 into: [:a :b | a + b]) + ((days size - 1) * (self space: 44)))) / 2.
	days with: cells do: [:day :cellWidth |
		self drawDay: day on: c at: x.
		x := x + cellWidth + (self space: 44)]
!
drawDay: aDay on: c at: left
	| h iconFont nameFont tempFont x y high low |
	h := self forecastHeight.
	iconFont := self dayIconFont.
	nameFont := self dayNameFont.
	tempFont := self dayTemperatureFont.
	c drawString: aDay icon at: left @ ((h - iconFont lineHeight) / 2) font: iconFont color: self foreground.
	x := left + (self widthOf: aDay icon in: iconFont) + (self space: 10).
	y := (h - (nameFont lineHeight + (self space: 2) + tempFont lineHeight)) / 2.
	c drawString: aDay dayName asUppercase at: x @ y font: nameFont color: self dim.
	y := y + nameFont lineHeight + (self space: 2).
	high := self degrees: aDay high.
	low := self degrees: aDay low.
	c drawString: high at: x @ y font: tempFont color: self foreground.
	c drawString: low at: (x + (self widthOf: high in: tempFont) + (self space: 6)) @ y font: tempFont color: self dimmer
!
cellWidthOf: aDay
	| tempFont temps |
	tempFont := self dayTemperatureFont.
	temps := (self widthOf: (self degrees: aDay high) in: tempFont) + (self space: 6) + (self widthOf: (self degrees: aDay low) in: tempFont).
	^(self widthOf: aDay icon in: self dayIconFont) + (self space: 10) + ((self widthOf: aDay dayName asUppercase in: self dayNameFont) max: temps)
!
stats
	"{label. value} for FEELS, WIND and HUMID."
	^Array
		with: (Array with: 'FEELS' with: (self degrees: report feelsLike), (imperial ifTrue: ['F'] ifFalse: ['C']))
		with: (Array with: 'WIND' with: (WeatherReport wind: report wind imperial: imperial))
		with: (Array with: 'HUMID' with: (report humidity isNil ifTrue: [''] ifFalse: [(WeatherReport round: report humidity) printString, '%']))
!
statWidth: aPair
	^(self widthOf: aPair first in: self statLabelFont) max: (self widthOf: aPair last in: self statValueFont)
!
statsWidth: stats
	^(stats inject: 0 into: [:sum :each | sum + (self statWidth: each)]) + ((stats size - 1) * (self space: 36))
!
degrees: celsius
	| n |
	n := WeatherReport temperature: celsius imperial: imperial.
	^n isEmpty ifTrue: [''] ifFalse: [n, '°']
!
unitText
	^'°', (imperial ifTrue: ['F'] ifFalse: ['C'])
! !

!WeatherCard methodsFor: 'events'!
mouseDown: anEvent
	anEvent button = 1 ifTrue: [onActivate isNil ifFalse: [onActivate value]. ^true].
	anEvent button = 3 ifTrue: [onRefresh isNil ifFalse: [onRefresh value]. ^true].
	^false
!
cursorAt: aPoint
	^#hand
! !

!WeatherCard methodsFor: 'remote control'!
remoteRole
	^#card
!
remoteLabel
	report isNil ifTrue: [^self statusText].
	^(WeatherReport temperature: report temperature imperial: imperial), self unitText
!
remoteState
	report isNil ifTrue: [^#('fetching')].
	^Array
		with: 'place=', (location isNil ifTrue: [''] ifFalse: [location name])
		with: 'days=', (report days collect: [:d | d dayName]) printString
! !

!WeatherCard class methodsFor: 'text'!
truncate: aString to: width font: aFont
	"aString, cut with an ellipsis to fit width points."
	| s |
	(aFont naturalWidthOf: aString) <= width ifTrue: [^aString].
	s := aString.
	[s notEmpty and: [(aFont naturalWidthOf: s, '…') > width]] whileTrue: [s := s allButLast].
	^s, '…'
! !
