TestCase subclass: #ChunkFileTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

ChunkFileTest comment: 'I test ChunkFile, the chunk-format editing behind the browser''s accept: replacing, adding and moving one method keeps every other byte of the file.'!

!ChunkFileTest methodsFor: 'fixtures'!
sample
	^'Object subclass: #Foo
	instanceVariableNames: ''a''
	classVariableNames: ''''
	package: ''Demo''!!

Foo comment: ''I am a demo.''!!

!!Foo methodsFor: ''accessing''!!
a
	^a
!!
a: x
	"Set a (say hi!!!!)."
	a := x
!! !!

!!Foo class methodsFor: ''instance creation''!!
new
	^super new a: 1; yourself
!! !!
'
! !

!ChunkFileTest methodsFor: 'tests'!
testParse
	| f |
	f := ChunkFile on: self sample.
	self assert: (f sourceOf: #a className: 'Foo' meta: false) equals: 'a
	^a'.
	self assert: ((f sourceOf: #a: className: 'Foo' meta: false) includesSubstring: 'say hi!!').
	self assert: (f sourceOf: #new className: 'Foo' meta: true) notNil.
	self assert: (f sourceOf: #new className: 'Foo' meta: false) isNil.
	self assert: (f definitionChunkFor: 'Foo') notNil.
	self assert: (f commentChunkFor: 'Foo') notNil
!
testUnchangedMethodKeepsTheFile
	| f |
	f := ChunkFile on: self sample.
	self deny: (f putMethod: 'a
	^a' selector: #a className: 'Foo' meta: false category: 'accessing').
	self assert: f text equals: self sample
!
testReplaceOneMethod
	| f expected |
	f := ChunkFile on: self sample.
	self assert: (f putMethod: 'a
	^a + 1' selector: #a className: 'Foo' meta: false category: 'accessing').
	expected := self sample copyReplaceAll: '	^a
!!' with: '	^a + 1
!!'.
	self assert: f text equals: expected.
	self assert: (f putMethod: 'a
	^a' selector: #a className: 'Foo' meta: false category: 'accessing').
	self assert: f text equals: self sample
!
testBangsAreDoubled
	| f |
	f := ChunkFile on: self sample.
	f putMethod: 'b
	^''!!''' selector: #b className: 'Foo' meta: false category: 'accessing'.
	self assert: (f text includesSubstring: '^''!!!!''').
	self assert: (f sourceOf: #b className: 'Foo' meta: false) equals: 'b
	^''!!'''
!
testNewMethodGoesIntoItsSection
	| f |
	f := ChunkFile on: self sample.
	f putMethod: 'b
	^2' selector: #b className: 'Foo' meta: false category: 'accessing'.
	self assert: (f text includesSubstring: '	a := x
!!
b
	^2
!! !!').
	self assert: (f sourceOf: #b className: 'Foo' meta: false) equals: 'b
	^2'
!
testNewCategoryAppendsASection
	| f |
	f := ChunkFile on: self sample.
	f putMethod: 'c
	^3' selector: #c className: 'Foo' meta: false category: 'demo'.
	self assert: (f text endsWith: '
!!Foo methodsFor: ''demo''!!
c
	^3
!! !!
').
	self assert: (f text beginsWith: self sample)
!
testRecategorizeMovesTheMethod
	| f |
	f := ChunkFile on: self sample.
	f putMethod: 'a
	^a' selector: #a className: 'Foo' meta: false category: 'other'.
	self assert: (f sourceOf: #a className: 'Foo' meta: false) equals: 'a
	^a'.
	self assert: (f sourceOf: #a: className: 'Foo' meta: false) notNil.
	self assert: ((f text indexOfSubCollection: '''other''') > (f text indexOfSubCollection: '''accessing'''))
!
testRemovingTheLastMethodRemovesItsSection
	| f |
	f := ChunkFile on: self sample.
	f removeMethodEntry: (f methodEntryFor: #new className: 'Foo' meta: true).
	self deny: (f text includesSubstring: 'Foo class methodsFor:').
	self assert: (f sourceOf: #a className: 'Foo' meta: false) notNil
!
testComment
	| f |
	f := ChunkFile on: self sample.
	self deny: (f putComment: 'I am a demo.' className: 'Foo').
	self assert: (f putComment: 'I am Foo''s comment.' className: 'Foo').
	self assert: (f text includesSubstring: 'Foo comment: ''I am Foo''''s comment.''!!').
	self assert: (f sourceOf: #a className: 'Foo' meta: false) notNil
!
testSelectorOf
	self assert: (ChunkFile selectorOf: 'foo
	^1') equals: #foo.
	self assert: (ChunkFile selectorOf: 'at: i put: v
	^v') equals: #at:put:.
	self assert: (ChunkFile selectorOf: '+ aNumber ^0') equals: #+.
	self assert: (ChunkFile selectorOf: 'gcd: anInteger
	| a b |') equals: #gcd:.
	self assert: (ChunkFile selectorOf: '  value: x') equals: #value:
! !
