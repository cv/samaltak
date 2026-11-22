Object subclass: #WeatherLocation
	instanceVariableNames: 'name latitude longitude'
	classVariableNames: ''
	package: 'Weather'!

WeatherLocation comment: 'I am a place to report the weather for: a name and coordinates, as Omarchy keeps them in ~/.local/state/omarchy/settings/weather.json ({"name": ..., "latitude": ..., "longitude": ...}, written by omarchy-weather-location; geo.omarchy.org answers in the same shape). No name and no coordinates mean: detect where this network is (isAuto); a name without coordinates is looked up (Open-Meteo geocoding).'!

!WeatherLocation methodsFor: 'initialization'!
setName: aString latitude: lat longitude: lon
	name := aString.
	latitude := lat.
	longitude := lon
! !

!WeatherLocation methodsFor: 'accessing'!
name
	^name
!
latitude
	^latitude
!
longitude
	^longitude
! !

!WeatherLocation methodsFor: 'testing'!
isAuto
	"Nothing configured: the location is detected."
	^name isEmpty and: [latitude isNil]
!
hasCoordinates
	^latitude notNil and: [longitude notNil]
! !

!WeatherLocation methodsFor: 'comparing'!
= other
	^(other isKindOf: WeatherLocation) and: [name = other name and: [latitude = other latitude and: [longitude = other longitude]]]
!
hash
	^name hash bitXor: latitude hash
! !

!WeatherLocation methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a WeatherLocation('; print: name; nextPutAll: ' '; print: latitude; nextPutAll: ', '; print: longitude; nextPut: $)
! !

!WeatherLocation class methodsFor: 'instance creation'!
name: aString latitude: lat longitude: lon
	^self new setName: aString latitude: lat longitude: lon
!
unset
	^self name: '' latitude: nil longitude: nil
!
fromJSON: aString
	"weather.json's contents; missing, blank or unparseable is unset (detect)."
	| data |
	data := [JSON parse: (aString ifNil: [''])] on: Error do: [:e | e return: nil].
	data isDictionary ifFalse: [^self unset].
	^self fromDictionary: data
!
fromDictionary: aDictionary
	| lat lon nameValue |
	lat := self number: (aDictionary at: 'latitude' ifAbsent: [nil]).
	lon := self number: (aDictionary at: 'longitude' ifAbsent: [nil]).
	(lat isNil or: [lon isNil]) ifTrue: [lat := lon := nil].
	nameValue := aDictionary at: 'name' ifAbsent: [nil].
	^self name: (nameValue isString ifTrue: [nameValue trimBoth] ifFalse: ['']) latitude: lat longitude: lon
!
number: anObject
	"A number, or a string holding one (JavaScript's parseFloat), else nil."
	anObject isNumber ifTrue: [^anObject].
	anObject isString ifTrue: [^Number readFrom: anObject trimBoth ifFail: [nil]].
	^nil
! !
