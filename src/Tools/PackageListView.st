ListView subclass: #PackageListView
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tools'!

PackageListView comment: 'I am the System Browser''s package list, grouped by layer (Tools 5 at the top, Kernel 0 at the bottom): the first package of each layer shows the layer chip and the layer''s name on the right, and a hairline separates the groups. Items are Packages; test packages are muted.'!

!PackageListView methodsFor: 'initialization'!
initialize
	super initialize.
	self
		labelBlock: [:p | p name];
		rightBlock: [:p | (self startsGroup: p) ifTrue: [SystemBrowser layerName: p layer] ifFalse: [nil]];
		cellBlock: (ListView layerChipCell: [:p | (self startsGroup: p) ifTrue: [p layer ifNil: [0]] ifFalse: [nil]]);
		styleBlock: [:p | ((p name beginsWith: 'Tests-') or: [p name = 'Demos']) ifTrue: [#muted] ifFalse: [nil]];
		remoteNameBlock: [:p | p name]
! !

!PackageListView methodsFor: 'grouping'!
startsGroup: aPackage
	| i |
	i := items indexOf: aPackage.
	i <= 1 ifTrue: [^true].
	^(items at: i - 1) layer ~= aPackage layer
! !

!PackageListView methodsFor: 'drawing'!
drawItem: anItem in: r on: aCanvas inverted: inverted
	((self startsGroup: anItem) and: [(items indexOf: anItem) > 1]) ifTrue: [
		aCanvas fillRect: (r left @ r top corner: r right @ (r top + 1)) color: (self theme color: #hair)].
	super drawItem: anItem in: r on: aCanvas inverted: inverted
! !
