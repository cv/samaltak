TestCase subclass: #SamaltakIconTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

SamaltakIconTest comment: 'I check the window icon: stage 2 put icons/samaltak.svg into the image, rasterized with straight alpha: transparent outside the rounded body, the receiver white, the grid blue.'!

!SamaltakIconTest methodsFor: 'tests'!
testInTheImage
	| side |
	side := SamaltakIcon side.
	self assert: HostWindow iconWidth equals: side.
	self assert: HostWindow icon size equals: side * side * 4
!
testFormSide
	"The top bar's size, rasterized once."
	self assert: (SamaltakIcon formSide: 40) width equals: 40.
	self assert: (SamaltakIcon formSide: 40) == (SamaltakIcon formSide: 40)
!
testPixels
	"The corner is outside the body; the receiver (the circle at 704@384 of the 1024 drawing, on the 824 grid) is white; the body between is opaque blue."
	| bytes side at |
	bytes := HostWindow icon.
	side := SamaltakIcon side.
	at := [:x :y | (1 to: 4) collect: [:i | bytes at: (y * side + x) * 4 + i]].
	self assert: (at value: 4 value: 4) equals: #(0 0 0 0).
	self assert: (at value: 167 value: 102) equals: #(255 255 255 255).
	self assert: (at value: 60 value: 200) last equals: 255.
	self assert: (at value: 60 value: 200) third > (at value: 60 value: 200) first
!
testStraightAlpha
	"Premultiplied half-transparent red becomes red at half alpha."
	| form |
	form := Form width: 2 height: 1.
	form bits at: 1 put: 16r80000080; at: 2 put: 0.
	self assert: (SamaltakIcon straightPixelsOf: form) asArray equals: #(255 0 0 128 0 0 0 0)
! !
