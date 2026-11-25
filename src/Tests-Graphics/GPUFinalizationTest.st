GraphicsTestCase subclass: #GPUFinalizationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Graphics'!

GPUFinalizationTest comment: 'I check that GPU objects dropped without release give their platform handles back once they are garbage collected (WeakRegistry, the finalization process), counted by Smalltalk vm platformHandleCounts.'!

!GPUFinalizationTest methodsFor: 'support'!
count: aSymbol
	^Smalltalk vm platformHandleCounts at: aSymbol
!
assertDropping: aBlock releases: aSymbol
	"aBlock answers a new GPU object with a live handle; dropping it must free that handle. Counted from a settled count: the objects earlier tests dropped are finalized first (on a loaded machine the finalization Process runs late)."
	| before object |
	before := self settledCount: aSymbol.
	object := aBlock value.
	self assert: (self count: aSymbol) equals: before + 1.
	object := nil.
	Smalltalk vm garbageCollect.
	self assert: (self waitFor: [(self count: aSymbol) = before]) description: [aSymbol, ': ', (self count: aSymbol) printString, ' live, ', before printString, ' before']
!
settledCount: aSymbol
	"The count once garbage collections no longer change it (at most 5 s)."
	| n t |
	t := Time millisecondClockValue.
	[Smalltalk vm garbageCollect.
	 n := self count: aSymbol.
	 (Delay forMilliseconds: 20) wait.
	 Smalltalk vm garbageCollect.
	 (Delay forMilliseconds: 20) wait.
	 (self count: aSymbol) ~= n and: [Time millisecondClockValue - t < 5000]] whileTrue.
	^self count: aSymbol
! !

!GPUFinalizationTest methodsFor: 'tests'!
testDroppedTextureReleasesHandle
	self
		assertDropping: [(GPUDevice default textureWidth: 16 height: 16 format: #rgba8 usage: #(#sampler)) handle; yourself]
		releases: #textures
!
testDroppedBufferReleasesHandle
	self
		assertDropping: [(GPUDevice default vertexBufferSize: 256) handle; yourself]
		releases: #buffers
!
testDroppedSamplerReleasesHandle
	self
		assertDropping: [(GPUDevice default samplerLinear: true repeat: false) handle; yourself]
		releases: #samplers
!
testDroppedFenceReleasesHandle
	self
		assertDropping: [GPUDevice default commandBuffer submitWithFence]
		releases: #fences
!
testManyDroppedTextures
	| before |
	before := self count: #textures.
	1 to: 200 do: [:i | (GPUDevice default textureWidth: 8 height: 8 format: #r8 usage: #(#sampler)) handle].
	Smalltalk vm garbageCollect.
	self assert: (self waitFor: [(self count: #textures) = before])
!
testReleasedTextureIsUnregistered
	| tex before |
	tex := GPUDevice default textureWidth: 8 height: 8 format: #r8 usage: #(#sampler).
	tex handle.
	self assert: (WeakRegistry default includes: tex).
	before := self count: #textures.
	tex release.
	self deny: (WeakRegistry default includes: tex).
	self assert: (self count: #textures) equals: before - 1.
	tex handle.
	self assert: (WeakRegistry default includes: tex).
	tex release
! !
