Object subclass: #WeatherReport
	instanceVariableNames: 'time temperature feelsLike humidity wind code isDay days'
	classVariableNames: ''
	package: 'Weather'!

WeatherReport comment: 'I am what Open-Meteo''s forecast answered (api.open-meteo.com/v1/forecast with current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day and daily=weather_code,temperature_2m_max,temperature_2m_min, timezone=auto): the current conditions, metric (°C, km/h, %), and the next three days after the place''s today. WeatherReport units: converts for display.

	WeatherReport fromJSON: (JSON parse: aString)     "nil without current conditions"'!

!WeatherReport methodsFor: 'initialization'!
setCurrent: aDictionary days: anArray
	time := aDictionary at: 'time' ifAbsent: [''].
	temperature := aDictionary at: 'temperature_2m' ifAbsent: [nil].
	feelsLike := aDictionary at: 'apparent_temperature' ifAbsent: [nil].
	humidity := aDictionary at: 'relative_humidity_2m' ifAbsent: [nil].
	wind := aDictionary at: 'wind_speed_10m' ifAbsent: [nil].
	code := aDictionary at: 'weather_code' ifAbsent: [nil].
	isDay := (aDictionary at: 'is_day' ifAbsent: [1]) ~= 0.
	days := anArray
! !

!WeatherReport methodsFor: 'accessing'!
today
	"The place's date (YYYY-MM-DD)."
	^time size >= 10 ifTrue: [time copyFrom: 1 to: 10] ifFalse: ['']
!
temperature
	"°C"
	^temperature
!
feelsLike
	^feelsLike
!
humidity
	"%"
	^humidity
!
wind
	"km/h"
	^wind
!
code
	^code
!
isDay
	^isDay
!
days
	"The next three days, WeatherDays."
	^days
!
icon
	^WeatherIcons forCode: code night: isDay not
! !

!WeatherReport class methodsFor: 'instance creation'!
fromJSON: aDictionary
	"The report in Open-Meteo's answer, or nil if it has no current temperature."
	| current today |
	aDictionary isDictionary ifFalse: [^nil].
	current := aDictionary at: 'current' ifAbsent: [nil].
	(current isDictionary and: [(current at: 'temperature_2m' ifAbsent: [nil]) isNumber]) ifFalse: [^nil].
	today := (current at: 'time' ifAbsent: ['']) asString.
	today := today size >= 10 ifTrue: [today copyFrom: 1 to: 10] ifFalse: [''].
	^self new setCurrent: current days: (self daysIn: (aDictionary at: 'daily' ifAbsent: [nil]) after: today)
!
daysIn: daily after: today
	"Up to three days of the daily forecast later than today."
	| dates result |
	daily isDictionary ifFalse: [^#()].
	dates := daily at: 'time' ifAbsent: [#()].
	result := OrderedCollection new.
	dates doWithIndex: [:date :i |
		(result size < 3 and: [date isString and: [(date copyFrom: 1 to: (10 min: date size)) > today]]) ifTrue: [
			result add: (WeatherDay
				date: date
				high: (self at: i in: (daily at: 'temperature_2m_max' ifAbsent: [nil]))
				low: (self at: i in: (daily at: 'temperature_2m_min' ifAbsent: [nil]))
				code: (self at: i in: (daily at: 'weather_code' ifAbsent: [nil])))]].
	^result asArray
!
at: i in: anArrayOrNil
	(anArrayOrNil isArray and: [i <= anArrayOrNil size]) ifFalse: [^nil].
	^anArrayOrNil at: i
! !

!WeatherReport class methodsFor: 'units'!
round: aNumber
	"JavaScript's Math.round (halves up), as the Omarchy shell rounds: -2.5 is -2."
	^(aNumber + (1 / 2)) floor
!
fahrenheit: celsius
	^celsius * 9 / 5 + 32
!
temperature: celsius imperial: aBoolean
	"The rounded number shown for celsius, or '' for none."
	celsius isNil ifTrue: [^''].
	^(self round: (aBoolean ifTrue: [self fahrenheit: celsius] ifFalse: [celsius])) printString
!
wind: kmh imperial: aBoolean
	kmh isNil ifTrue: [^''].
	^aBoolean
		ifTrue: [(self round: kmh * 0.621371) printString, ' mph']
		ifFalse: [(self round: kmh) printString, ' km/h']
!
localeUsesImperial: aLocaleName
	"en_US, en_LR and my measure in imperial units."
	| n |
	n := (aLocaleName ifNil: ['']) copyReplaceAll: '-' with: '_'.
	^#('en_US' 'en_LR' 'my') anySatisfy: [:prefix |
		(n beginsWith: prefix) and: [n size = prefix size or: ['_.@' includes: (n at: prefix size + 1)]]]
!
environmentUsesImperial
	"The locale's measurement system: LC_ALL, else LC_MEASUREMENT, else LANG (as glibc picks it)."
	| locale |
	locale := #('LC_ALL' 'LC_MEASUREMENT' 'LANG')
		inject: nil into: [:found :each | found ifNil: [(Smalltalk vm getenv: each) ifNotNil: [:v | v isEmpty ifTrue: [nil] ifFalse: [v]]]].
	^self localeUsesImperial: locale
! !
