"Extremem's GC pauses on Pharo."!

!AwfyPlatform class methodsFor: 'extremem'!
gcCountAndMicroseconds
	"The GCs so far and the microseconds they took: full GCs and scavenges; the VM counts whole milliseconds."
	| vm |
	vm := Smalltalk vm.
	^Array
		with: (vm parameterAt: 7) + (vm parameterAt: 9)
		with: (vm parameterAt: 8) + (vm parameterAt: 10) * 1000
! !
