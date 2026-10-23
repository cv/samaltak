Behavior subclass: #ClassDescription
	instanceVariableNames: 'instanceVariables organization'
	classVariableNames: ''
	package: 'Kernel-Classes'!

ClassDescription comment: 'I add what tools need to Behavior: instance variable names and the organization of methods into categories (protocols). Each CompiledMethod knows its category; organization is a cache, a Dictionary from category to sorted selectors, rebuilt on demand.'!

!ClassDescription methodsFor: 'instance variables'!
instVarNames
	"Answer the names of the instance variables I define, as Strings."
	instanceVariables isNil ifTrue: [^#()].
	^instanceVariables collect: [:each | each asString]
!
instanceVariableNames
	^self instVarNames
!
setInstanceVariables: anArray
	instanceVariables := anArray
!
instanceVariableNames: aString
	"Change the instance variables I define (class-side variables when I am a metaclass)."
	^ClassBuilder new reshape: self instanceVariableNames: aString
! !

!ClassDescription methodsFor: 'accessing'!
theNonMetaClass
	^self subclassResponsibility
!
theMetaClass
	^self theNonMetaClass class
!
instanceSide
	^self theNonMetaClass
!
classSide
	^self theMetaClass
!
package
	^self theNonMetaClass package
!
category
	^self theNonMetaClass category
!
comment
	^self theNonMetaClass comment
! !

!ClassDescription methodsFor: 'organization'!
organization
	"Answer a Dictionary from category name to the sorted Array of its selectors."
	organization isNil ifTrue: [organization := self computeOrganization].
	^organization
!
computeOrganization
	| dict |
	dict := Dictionary new.
	methodDict keysAndValuesDo: [:sel :method |
		(dict at: (method category ifNil: ['as yet unclassified']) ifAbsentPut: [OrderedCollection new]) add: sel].
	dict keysAndValuesDo: [:cat :sels | dict at: cat put: sels asSortedCollection asArray].
	^dict
!
organizationChanged
	organization := nil
!
categories
	"Answer my method categories, sorted."
	^self organization keys asSortedCollection asArray
!
protocols
	^self categories
!
selectorsInCategory: aCategory
	^self organization at: aCategory ifAbsent: [#()]
!
selectorsInProtocol: aCategory
	^self selectorsInCategory: aCategory
!
categoryOfSelector: aSelector
	| m |
	m := self compiledMethodAt: aSelector ifAbsent: [^nil].
	^m category
!
whichCategoryIncludesSelector: aSelector
	^self categoryOfSelector: aSelector
!
protocolOfSelector: aSelector
	^self categoryOfSelector: aSelector
!
classify: aSelector under: aCategory
	"Move the method for aSelector into aCategory."
	(self compiledMethodAt: aSelector) category: aCategory asString.
	self organizationChanged
!
renameCategory: oldName to: newName
	(self selectorsInCategory: oldName) do: [:sel | self classify: sel under: newName]
!
removeCategory: aCategory
	"Remove all methods in aCategory."
	(self selectorsInCategory: aCategory) do: [:sel | self removeSelector: sel]
! !

!ClassDescription methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: self name
! !
