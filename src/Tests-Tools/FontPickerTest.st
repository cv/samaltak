TestCase subclass: #FontPickerTest
	instanceVariableNames: 'picker'
	classVariableNames: ''
	package: 'Tests-Tools'!

FontPickerTest comment: 'I test FontPicker without opening its window: faces split into families and typefaces, the collections, and the target that gets the chosen font.'!

!FontPickerTest methodsFor: 'running'!
setUp
	picker := FontPicker new
! !

!FontPickerTest methodsFor: 'tests'!
testCollections
	self assert: ((picker faceNamesIn: 'Fixed Width') includes: 'JetBrainsMono-Regular').
	self deny: ((picker faceNamesIn: 'Fixed Width') includes: 'IosevkaEtoile-Regular').
	self assert: ((picker faceNamesIn: 'Proportional') includes: 'IosevkaEtoile-Regular').
	self assert: (picker faceNamesIn: 'Fallback') = Font fallbackFaceNames asArray
!
testFacesOfFamilyRegularFirst
	self assert: (picker facesOfFamily: 'JetBrainsMono') = #('JetBrainsMono-Regular' 'JetBrainsMono-Italic' 'JetBrainsMono-Bold')
!
testFamilyAndStyle
	self assert: (picker familyOf: 'JetBrainsMono-Bold') = 'JetBrainsMono'.
	self assert: (picker styleOf: 'JetBrainsMono-Bold') = 'Bold'.
	self assert: (picker familyOf: 'Twemoji') = 'Twemoji'.
	self assert: (picker styleOf: 'Twemoji') = 'Regular'
!
testTargetGetsTheChoice
	| editor |
	editor := TextEditor new.
	editor font: (Font faceNamed: 'JetBrainsMono-Italic' size: 14).
	picker target: editor.
	self assert: picker expression = 'Font faceNamed: ''JetBrainsMono-Italic'' size: 14'.
	picker changeSize: 1.
	self assert: editor font size = 18.
	self assert: (picker faceNameOf: editor font) = 'JetBrainsMono-Italic'.
	picker typefaceSelected: 'JetBrainsMono-Bold'.
	self assert: (picker faceNameOf: editor font) = 'JetBrainsMono-Bold'
! !
