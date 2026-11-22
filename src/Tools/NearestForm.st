Form subclass: #NearestForm
	instanceVariableNames: 'source'
	classVariableNames: ''
	package: 'Tools'!

NearestForm comment: 'I am another Form''s pixels (the same Bitmap) sampled without filtering, so a PixelView can magnify them into crisp cells. I upload again whenever the source''s version changes.'!

!NearestForm methodsFor: 'accessing'!
source
	^source
!
setSource: aForm
	source := aForm.
	self setWidth: aForm width height: aForm height bits: aForm bits
! !

!NearestForm methodsFor: 'rendering'!
textureOn: aDevice
	version := source version.
	^super textureOn: aDevice
!
contentVersion
	^source version
!
isLinearFiltered
	^false
! !

!NearestForm class methodsFor: 'instance creation'!
on: aForm
	^self new setSource: aForm
! !
