TestCase subclass: #WeatherTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Weather'!

WeatherTest comment: 'Tests the weather app without the network: Omarchy''s weather.json, Open-Meteo''s forecast, units and rounding as the shell does them, the glyphs, the service reading its settings, and the card drawing a report.

	bin/samaltak test apps/Weather'!

!WeatherTest methodsFor: 'fixtures'!
forecastJSON
	^JSON parse: '{"current": {"time": "2026-11-21T18:30", "temperature_2m": 11.5, "apparent_temperature": 10.1,
		"relative_humidity_2m": 86, "wind_speed_10m": 5.2, "weather_code": 0, "is_day": 0},
	 "daily": {"time": ["2026-11-21", "2026-11-22", "2026-11-23", "2026-11-24"],
		"weather_code": [51, 3, 61, 95], "temperature_2m_max": [14.2, 15.5, 13.0, 12.4], "temperature_2m_min": [9.0, 8.4, -2.5, 7.1]}}'
! !

!WeatherTest methodsFor: 'tests'!
testLocationFile
	| loc |
	loc := WeatherLocation fromJSON: '{"name": " San Francisco ", "latitude": 37.77493, "longitude": "-122.41942"}'.
	self assert: loc name equals: 'San Francisco'.
	self assert: loc latitude equals: 37.77493.
	self assert: loc longitude equals: -122.41942.
	self assert: loc hasCoordinates.
	self deny: loc isAuto.
	self assert: (WeatherLocation fromJSON: '') isAuto.
	self assert: (WeatherLocation fromJSON: 'not json') isAuto.
	self assert: (WeatherLocation fromJSON: nil) isAuto.
	loc := WeatherLocation fromJSON: '{"name": "Vienna", "latitude": null}'.
	self deny: loc isAuto.
	self deny: loc hasCoordinates
!
testReport
	| report |
	report := WeatherReport fromJSON: self forecastJSON.
	self assert: report today equals: '2026-11-21'.
	self assert: report temperature equals: 11.5.
	self deny: report isDay.
	self assert: report icon equals: (WeatherIcons forCode: 0 night: true).
	self assert: (report days collect: [:d | d date]) equals: #('2026-11-22' '2026-11-23' '2026-11-24').
	self assert: (report days collect: [:d | d dayName]) equals: #('Sunday' 'Monday' 'Tuesday').
	self assert: report days first code equals: 3.
	self assert: (WeatherReport fromJSON: (JSON parse: '{"current": {}}')) isNil.
	self assert: (WeatherReport fromJSON: nil) isNil
!
testUnitsRoundLikeTheShell
	self assert: (WeatherReport temperature: 11.5 imperial: false) equals: '12'.
	self assert: (WeatherReport temperature: -2.5 imperial: false) equals: '-2'.
	self assert: (WeatherReport temperature: 11.5 imperial: true) equals: '53'.
	self assert: (WeatherReport temperature: nil imperial: true) equals: ''.
	self assert: (WeatherReport wind: 5.2 imperial: false) equals: '5 km/h'.
	self assert: (WeatherReport wind: 5.2 imperial: true) equals: '3 mph'.
	self assert: (WeatherReport localeUsesImperial: 'en_US.UTF-8').
	self assert: (WeatherReport localeUsesImperial: 'en-US').
	self deny: (WeatherReport localeUsesImperial: 'en_USX').
	self deny: (WeatherReport localeUsesImperial: 'de_AT.UTF-8').
	self deny: (WeatherReport localeUsesImperial: nil)
!
testIcons
	self assert: (WeatherIcons forCode: 0 night: false) first value equals: 16rE30D.
	self assert: (WeatherIcons forCode: 0 night: true) first value equals: 16rE32B.
	self assert: (WeatherIcons forCode: 2 night: false) first value equals: 16rE302.
	self assert: (WeatherIcons forCode: 45 night: true) first value equals: 16rE346.
	self assert: (WeatherIcons forCode: 61 night: false) first value equals: 16rE318.
	self assert: (WeatherIcons forCode: 80 night: true) first value equals: 16rE318.
	self assert: (WeatherIcons forCode: 75 night: false) first value equals: 16rE31A.
	self assert: (WeatherIcons forCode: 99 night: false) first value equals: 16rE31D.
	self assert: (WeatherIcons forCode: nil night: false) first value equals: 16rE33D
!
testServiceReadsItsSettings
	| path service |
	path := self scratchDirectory / 'weather.json'.
	File writeText: '{"name": "Here", "latitude": 1.5, "longitude": 2.5}' to: path.
	service := WeatherService new locationPath: path; yourself.
	service readSettings.
	self assert: service configured equals: (WeatherLocation name: 'Here' latitude: 1.5 longitude: 2.5).
	self assert: service resolve == service configured.
	File writeText: '{}' to: path.
	service readSettings.
	self assert: service configured isAuto.
	self assert: (service forecastURLFor: (WeatherLocation name: 'x' latitude: 1.5 longitude: -2.5))
		equals: 'https://api.open-meteo.com/v1/forecast?latitude=1.5&longitude=-2.5&daily=weather_code,temperature_2m_max,temperature_2m_min&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day&forecast_days=4&timezone=auto'
!
testCardDrawsAReport
	| card canvas |
	card := WeatherCard new.
	card bounds: (0 @ 0 extent: card preferredExtent).
	self assert: card preferredExtent x > 400.
	self assert: card preferredExtent y > 100.
	canvas := Canvas extent: card preferredExtent scale: 1.
	card drawOn: canvas.
	card report: (WeatherReport fromJSON: self forecastJSON) location: (WeatherLocation name: 'San Francisco' latitude: 1 longitude: 2) error: ''.
	canvas := Canvas extent: card preferredExtent scale: 1.
	card drawOn: canvas.
	self assert: card remoteLabel equals: '12°C'.
	self assert: (card remoteState includes: 'place=San Francisco')
! !
