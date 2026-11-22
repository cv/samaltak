Object subclass: #WeatherDay
	instanceVariableNames: 'date high low code'
	classVariableNames: ''
	package: 'Weather'!

WeatherDay comment: 'I am one day of the forecast: its date (YYYY-MM-DD, the place''s own), the high and low in °C and the WMO weather code (Open-Meteo''s daily weather_code).'!

!WeatherDay methodsFor: 'initialization'!
setDate: aString high: maxC low: minC code: anInteger
	date := aString.
	high := maxC.
	low := minC.
	code := anInteger
! !

!WeatherDay methodsFor: 'accessing'!
date
	^date
!
high
	"°C, or nil."
	^high
!
low
	^low
!
code
	^code
!
dayName
	"Saturday."
	| parts |
	parts := (date copyFrom: 1 to: 10) subStrings: '-'.
	^(Date year: parts first asNumber month: (parts at: 2) asNumber day: (parts at: 3) asNumber) dayOfWeekName
!
icon
	^WeatherIcons forCode: code night: false
! !

!WeatherDay class methodsFor: 'instance creation'!
date: aString high: maxC low: minC code: anInteger
	^self new setDate: aString high: maxC low: minC code: anInteger
! !
