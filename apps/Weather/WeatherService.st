Object subclass: #WeatherService
	instanceVariableNames: 'locationPath refreshSeconds process wakeup onChange configured resolved report error locationStamp nextFetch'
	classVariableNames: ''
	package: 'Weather'!

WeatherService comment: 'I keep a WeatherReport current for the place Omarchy''s weather settings name, in a Process of my own: I read ~/.local/state/omarchy/settings/weather.json (again whenever it changes), detect the place through geo.omarchy.org when it names none or look up a bare name with Open-Meteo''s geocoding, and fetch Open-Meteo''s forecast every refreshSeconds (15 minutes), a minute after a failure. My Process looks at the wall clock every two seconds instead of sleeping until the next fetch, so a fetch due while the machine was suspended happens as it wakes. After every attempt onChange runs (in my Process).

	service := WeatherService new onChange: [:s | ...]; start.
	service report. service location. service error.
	service refreshNow. service stop'!

!WeatherService methodsFor: 'initialization'!
initialize
	locationPath := XDG state: 'omarchy/settings/weather.json'.
	refreshSeconds := 15 * 60.
	wakeup := Semaphore new.
	error := ''
! !

!WeatherService methodsFor: 'accessing'!
locationPath: aPath
	locationPath := aPath
!
refreshSeconds: anInteger
	refreshSeconds := anInteger
!
onChange: aBlock
	"[:service | ...] after each attempt to fetch, in my Process."
	onChange := aBlock
!
report
	"The latest WeatherReport, or nil before the first."
	^report
!
configured
	"The WeatherLocation the settings name."
	^configured
!
location
	"The WeatherLocation the report is for (with the name to show), or nil."
	^resolved
!
error
	"Why the latest attempt failed ('' if it did not)."
	^error
! !

!WeatherService methodsFor: 'running'!
start
	(process notNil and: [process isTerminated not]) ifTrue: [^self].
	nextFetch := 0.
	locationStamp := #none.
	process := [[self step. wakeup waitTimeoutMSecs: 2000] repeat] newProcess.
	process priority: Processor userBackgroundPriority; name: 'Weather service'.
	process resume
!
stop
	process isNil ifFalse: [process terminate. process := nil]
!
refreshNow
	"Fetch at once (a middle click)."
	nextFetch := 0.
	wakeup signal
!
step
	"Read the settings again if they changed; fetch if due."
	| stamp |
	stamp := [File modificationTime: locationPath] on: Error do: [:e | e return: nil].
	stamp = locationStamp ifFalse: [
		locationStamp := stamp.
		self readSettings.
		nextFetch := 0].
	self now >= nextFetch ifTrue: [self fetch]
!
readSettings
	"The place weather.json names (unset if there is none)."
	configured := WeatherLocation fromJSON: ([File readText: locationPath] on: Error do: [:e | e return: nil]).
	resolved := nil
!
fetch
	"Resolve the place and fetch its forecast; on failure keep the last report and try again in a minute."
	[| place answer |
	 place := self resolve.
	 answer := WeatherReport fromJSON: (self getJSON: (self forecastURLFor: place)).
	 answer isNil ifTrue: [^self failed: 'Weather unavailable'].
	 report := answer.
	 error := ''.
	 nextFetch := self now + refreshSeconds]
		on: Error do: [:e | ^self failed: (resolved isNil ifTrue: ['Location unavailable'] ifFalse: ['Weather unavailable'])].
	self changed
!
failed: aString
	error := aString.
	nextFetch := self now + 60.
	self changed
!
changed
	onChange isNil ifFalse: [[onChange cull: self] on: Error do: [:e | e return: nil]]
!
now
	"Wall-clock seconds."
	^Time utcMicroseconds // 1000000
! !

!WeatherService methodsFor: 'location'!
resolve
	"The place to fetch for, with coordinates: the configured one, else detected (no name) or looked up (a name)."
	| found |
	configured hasCoordinates ifTrue: [^resolved := configured].
	resolved notNil ifTrue: [^resolved].
	configured isAuto
		ifTrue: [found := WeatherLocation fromDictionary: (self getJSON: 'https://geo.omarchy.org/')]
		ifFalse: [found := self geocode: configured name].
	found hasCoordinates ifFalse: [^self error: 'no location'].
	^resolved := found
!
geocode: aName
	| results first |
	results := (self getJSON: 'https://geocoding-api.open-meteo.com/v1/search?name=', (HTTPClient percentEncode: aName), '&count=1&language=en&format=json')
		at: 'results' ifAbsent: [#()].
	results isEmpty ifTrue: [^WeatherLocation unset].
	first := results first.
	^WeatherLocation name: aName latitude: (first at: 'latitude' ifAbsent: [nil]) longitude: (first at: 'longitude' ifAbsent: [nil])
!
forecastURLFor: aLocation
	^'https://api.open-meteo.com/v1/forecast?latitude=', aLocation latitude printString,
		'&longitude=', aLocation longitude printString,
		'&daily=weather_code,temperature_2m_max,temperature_2m_min',
		'&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day',
		'&forecast_days=4&timezone=auto'
! !

!WeatherService methodsFor: 'http'!
getJSON: aURL
	"GET aURL and answer its JSON; an Error if it fails, is not 200 or takes longer than 10 s."
	| client done response failure worker |
	client := HTTPClient new.
	done := Semaphore new.
	worker := [[response := client get: aURL headers: (Dictionary new at: 'User-Agent' put: 'samaltak-weather'; yourself)]
		on: Error do: [:e | failure := e messageText. e return: nil].
		done signal] fork.
	(done waitTimeoutMSecs: 10000) ifTrue: [
		client close.
		worker terminate.
		^self error: aURL, ': timed out'].
	client close.
	failure isNil ifFalse: [^self error: failure asString].
	response status = 200 ifFalse: [^self error: aURL, ': ', response status printString].
	^response json
! !
