TestCase subclass: #SourceDirectoryStoreTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Tools'!

SourceDirectoryStoreTest comment: 'I test SourceFiler on a local source directory (SourceDirectoryStore) in a scratch directory: a write changes only its chunk, a file left without chunks is removed, and commit is git''s. I need a writable directory, so I am not in the UEFI test boot (SourceFilerGitHubTest is).'!

!SourceDirectoryStoreTest methodsFor: 'fixtures'!
extensionText
	^'!!ToolsTestFixture methodsFor: ''*Tests-Net''!!
fixtureOld
	^1
!! !!
'
! !

!SourceDirectoryStoreTest methodsFor: 'tests'!
testLocalDirectory
	| dir local path |
	dir := self scratchDirectory.
	path := dir, '/Tests-Net/ToolsTestFixture.extension.st'.
	Directory create: dir, '/Tests-Net'.
	File writeText: self extensionText to: path.
	local := SourceFiler new sourceDirectory: dir; useGitHub: false; yourself.
	self assert: (local writeSource: 'fixtureNew
	^2' selector: #fixtureNew class: ToolsTestFixture category: '*Tests-Net') equals: path.
	self assert: ((File readText: path) includesSubstring: 'fixtureNew').
	self assert: local pendingChanges isEmpty.
	self should: [local commit: 'x'] raise: Error.
	local removeMethod: #fixtureNew class: ToolsTestFixture category: '*Tests-Net'.
	self assert: (File readText: path) equals: self extensionText.
	self assert: (local removeMethod: #fixtureOld class: ToolsTestFixture category: '*Tests-Net') equals: path.
	self deny: (File exists: path)
! !
