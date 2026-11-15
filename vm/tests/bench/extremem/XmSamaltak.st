"Extremem's GC pauses on Samaltak."!

!AwfyPlatform class methodsFor: 'extremem'!
gcCountAndMicroseconds
	"The GCs so far and the microseconds they took."
	| statistics |
	statistics := Smalltalk vm statistics.
	^Array with: statistics gcCount with: statistics gcMicroseconds
! !
