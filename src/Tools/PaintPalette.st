Widget subclass: #PaintPalette
	instanceVariableNames: 'colors foreground background onChange'
	classVariableNames: ''
	package: 'Tools'!

PaintPalette comment: 'I am Paint''s color box: the current foreground over the background, then the 28 colors of Windows 95 Paint. A left click takes the foreground, a right click the background; onChange: [:palette] follows.'!

!PaintPalette methodsFor: 'accessing'!
background
	^background
!
background: aColor
	background := aColor.
	self invalidate
!
colors
	"The Windows 95 palette: two rows of 14."
	^colors
!
foreground
	^foreground
!
foreground: aColor
	foreground := aColor.
	self invalidate
!
onChange: aBlock
	"[:palette] after a click changed a color."
	onChange := aBlock
! !

!PaintPalette methodsFor: 'drawing'!
cell
	^17
!
drawSelfOn: aCanvas
	"The current colors (foreground over background) at the left, then the swatches."
	| ink |
	ink := self theme ink.
	aCanvas fillRect: (4 @ 4 extent: 34 @ 32) color: self theme paper.
	aCanvas strokeRect: (4 @ 4 extent: 34 @ 32) color: ink width: 1.
	aCanvas fillRect: (17 @ 15 extent: 16 @ 16) color: background.
	aCanvas strokeRect: (17 @ 15 extent: 16 @ 16) color: ink width: 1.
	aCanvas fillRect: (9 @ 9 extent: 16 @ 16) color: foreground.
	aCanvas strokeRect: (9 @ 9 extent: 16 @ 16) color: ink width: 1.
	colors doWithIndex: [:each :i | | r |
		r := self swatchRectAt: i.
		aCanvas fillRect: r color: each.
		aCanvas strokeRect: r color: ink width: 1]
!
preferredExtent
	^(48 + (14 * self cell) + 4) @ (8 + (2 * self cell))
!
swatchRectAt: anIndex
	| col row |
	col := anIndex - 1 \\ 14.
	row := anIndex - 1 // 14.
	^(48 + (col * self cell)) @ (4 + (row * self cell)) extent: (self cell - 2) @ (self cell - 2)
! !

!PaintPalette methodsFor: 'events'!
changedColors
	self invalidate.
	onChange isNil ifFalse: [onChange value: self]
!
colorAt: aPoint
	1 to: colors size do: [:i | ((self swatchRectAt: i) containsPoint: aPoint) ifTrue: [^colors at: i]].
	^nil
!
mouseDown: anEvent
	"Left takes the foreground, right (rightMouseDown:) the background."
	(self colorAt: (self localEventPosition: anEvent)) ifNotNil: [:c | foreground := c. self changedColors].
	^true
!
rightMouseDown: anEvent
	(self colorAt: (self localEventPosition: anEvent)) ifNotNil: [:c | background := c. self changedColors].
	^true
! !

!PaintPalette methodsFor: 'initialize-release'!
initialize
	super initialize.
	colors := (#(16r000000 16r808080 16r800000 16r808000 16r008000 16r008080 16r000080 16r800080 16r808040 16r004040 16r0080FF 16r004080 16r8000FF 16r804000
		16rFFFFFF 16rC0C0C0 16rFF0000 16rFFFF00 16r00FF00 16r00FFFF 16r0000FF 16rFF00FF 16rFFFF80 16r00FF80 16r80FFFF 16r8080FF 16rFF0080 16rFF8040)
			collect: [:each | Color hex: each]).
	foreground := colors first.
	background := colors at: 15
! !

!PaintPalette methodsFor: 'remote control'!
remoteLabel
	^'colors'
! !
