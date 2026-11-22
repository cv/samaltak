Object subclass: #WeatherIcons
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Weather'!

WeatherIcons comment: 'I map WMO weather codes (Open-Meteo''s weather_code) to the Nerd Font weather glyphs the Omarchy shell''s weather panel shows (its Model.js: iconForOpenMeteoCode via wttr.in''s codes), by day or by night.'!

!WeatherIcons class methodsFor: 'icons'!
forCode: aCode night: aBoolean
	"The glyph for a WMO code (nil: overcast)."
	| c |
	c := aCode isNil ifTrue: [-1] ifFalse: [aCode].
	c = 0 ifTrue: [^self wttr: 113 night: aBoolean].
	(c = 1 or: [c = 2]) ifTrue: [^self wttr: 116 night: aBoolean].
	c = 3 ifTrue: [^self wttr: 119 night: aBoolean].
	(#(45 48) includes: c) ifTrue: [^self wttr: 143 night: aBoolean].
	(#(51 53 55 56 57 61) includes: c) ifTrue: [^self wttr: 266 night: aBoolean].
	(#(63 65 66 67 80 81 82) includes: c) ifTrue: [^self wttr: 308 night: aBoolean].
	(#(71 73 75 77 85 86) includes: c) ifTrue: [^self wttr: 338 night: aBoolean].
	(#(95 96 99) includes: c) ifTrue: [^self wttr: 389 night: aBoolean].
	^self wttr: 119 night: aBoolean
!
wttr: code night: aBoolean
	"wttr.in's condition codes, as the shell's iconForCode."
	(code = 113) ifTrue: [^self glyph: (aBoolean ifTrue: [16rE32B] ifFalse: [16rE30D])].
	(code = 116) ifTrue: [^self glyph: (aBoolean ifTrue: [16rE32E] ifFalse: [16rE302])].
	(#(119 122) includes: code) ifTrue: [^self glyph: 16rE33D].
	(#(143 248 260) includes: code) ifTrue: [^self glyph: (aBoolean ifTrue: [16rE346] ifFalse: [16rE313])].
	(#(176 263 353) includes: code) ifTrue: [^self glyph: (aBoolean ifTrue: [16rE333] ifFalse: [16rE308])].
	(#(179 227 230 323 326 368) includes: code) ifTrue: [^self glyph: (aBoolean ifTrue: [16rE327] ifFalse: [16rE30A])].
	(#(182 185 281 284 311 314 317 320 350 362 365 374 377) includes: code) ifTrue: [^self glyph: 16rE3AD].
	(#(200 386 389 392 395) includes: code) ifTrue: [^self glyph: 16rE31D].
	(#(266 293 296 299 302 305 308 356 359) includes: code) ifTrue: [^self glyph: 16rE318].
	(#(329 332 335 338 371) includes: code) ifTrue: [^self glyph: 16rE31A].
	^self glyph: 16rE33D
!
mapMarker
	"nf-fa-map_marker"
	^self glyph: 16rF041
!
glyph: aCodePoint
	^String with: (Character value: aCodePoint)
! !
