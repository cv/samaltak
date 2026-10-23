ArrayedCollection variableWordSubclass: #Bitmap
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Kernel-Collections'!

Bitmap comment: 'I am a fixed-size sequence of unsigned 32-bit integers, used for pixel data (e.g. ARGB words).'!

!Bitmap methodsFor: 'printing'!
printOn: aStream
	self printNameOn: aStream.
	aStream nextPut: $(; print: self size; nextPutAll: ' words)'
! !
