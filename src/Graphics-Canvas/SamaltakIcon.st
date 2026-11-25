Object subclass: #SamaltakIcon
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Graphics-Canvas'!

SamaltakIcon comment: 'I am Samaltak''s icon, icons/samaltak.svg: an object sends a message, the receiver answers. Stage 2 rasterizes it into the image (side pixels square) as the icon HostWindow gives every window it opens (the Dock''s on macOS, the window manager''s elsewhere); bin/samaltak install names the file in the launcher''s .desktop entries.'!

!SamaltakIcon class methodsFor: 'accessing'!
side
	"Pixels a side: what the Dock shows at 128 points on a Retina display."
	^256
!
path
	"icons/samaltak.svg in the current directory (stage 2 runs in the checkout), else next to the image's build directory."
	(File exists: 'icons/samaltak.svg') ifTrue: [^'icons/samaltak.svg'].
	^(Smalltalk vm imagePath copyUpToLast: $/) , '/../icons/samaltak.svg'
! !

!SamaltakIcon class methodsFor: 'rasterizing'!
form
	^(SVGImage fromFile: self path) formWidth: self side height: self side color: Color white
!
straightPixelsOf: aForm
	"aForm's pixels as RGBA bytes with straight alpha (a Form's are premultiplied), as window icons take them."
	| bytes v a o |
	bytes := ByteArray new: aForm width * aForm height * 4.
	1 to: aForm bits size do: [:i |
		v := aForm bits at: i.
		a := (v bitShift: -24) bitAnd: 255.
		o := i * 4 - 3.
		a = 0 ifFalse: [
			0 to: 2 do: [:c | bytes at: o + c put: (((v bitShift: c * -8) bitAnd: 255) * 255 + (a // 2) // a min: 255)].
			bytes at: o + 3 put: a]].
	^bytes
!
install
	"Stage 2: rasterize me and give me to the windows."
	HostWindow icon: (self straightPixelsOf: self form) width: self side
! !

!SamaltakIcon class methodsFor: 'class initialization'!
initialize
	Smalltalk addStage2Step: [self install] named: 'Icon'
! !
