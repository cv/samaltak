TestCase subclass: #SourceFilerGitHubTest
	instanceVariableNames: 'server account store filer'
	classVariableNames: ''
	package: 'Tests-Tools'!

SourceFilerGitHubTest comment: 'I test SourceFiler''s stores: its GitHub store against a fake GitHub (GitHubTestServer, Tests-Net) holding a copy of ToolsTestFixture''s source that differs from the image''s. A write changes only its chunk; commits carry new files, removed files (sha null), extension files and two edits to one file; a failed commit keeps the change set; discard; large files; which store is used; and the token never shows. SourceDirectoryStoreTest tests the local store.'!

!SourceFilerGitHubTest methodsFor: 'running'!
setUp
	self serve: self files
!
serve: aDictionary
	server isNil ifFalse: [server stop].
	store isNil ifFalse: [store close].
	server := GitHubTestServer token: self token files: aDictionary.
	account := GitHubAccount new.
	account configure: (Dictionary new
		at: 'repository' put: 'test/repo';
		at: 'apiUrl' put: server url;
		at: 'token' put: self token;
		yourself).
	store := GitHubSourceStore on: account.
	filer := SourceFiler new useGitHub: true; gitHubStore: store; yourself
!
tearDown
	store close.
	server stop.
	account clear
! !

!SourceFilerGitHubTest methodsFor: 'fixtures'!
token
	^'ghp_StoreTestToken0123456789' copy
!
fixturePath
	^'src/Tests-Tools/ToolsTestFixture.st'
!
extensionPath
	^'src/Tests-Net/ToolsTestFixture.extension.st'
!
fixtureText
	"ToolsTestFixture's source as the repository has it: its answer and comment differ from the image's."
	^'Object subclass: #ToolsTestFixture
	instanceVariableNames: ''value''
	classVariableNames: ''''
	package: ''Tests-Tools''!!

ToolsTestFixture comment: ''An older comment.''!!

!!ToolsTestFixture methodsFor: ''accessing''!!
answer
	"An older answer."
	^41
!!
value
	^value
!!
value: anObject
	value := anObject
!! !!
'
!
oldAnswer
	^'answer
	"An older answer."
	^41'
!
extensionText
	^'!!ToolsTestFixture methodsFor: ''*Tests-Net''!!
fixtureOld
	^1
!! !!
'
!
files
	^Dictionary new
		at: self fixturePath put: self fixtureText;
		at: self extensionPath put: self extensionText;
		at: 'src/packages.txt' put: 'Tests-Tools 5';
		at: 'README.md' put: '# test';
		yourself
!
definition
	^'TestCase subclass: #SourceFilerGitHubTest
	instanceVariableNames: ''server account store filer''
	classVariableNames: ''''
	package: ''Tests-Tools'''
! !

!SourceFilerGitHubTest methodsFor: 'tests'!
testEditOneMethodChangesOnlyItsChunk
	| message pr commit pull |
	self assert: (filer writeMethod: ToolsTestFixture >> #answer) equals: self fixturePath.
	self assert: filer pendingChanges equals: (Array with: self fixturePath).
	self assert: (server requestsTo: 'POST') isEmpty.
	message := 'Tests: the fixture''s answer is 42

The browser test keeps it there.'.
	pr := filer commit: message.
	self assert: (server textAt: self fixturePath onBranch: pr branch)
		equals: (self fixtureText copyReplaceAll: self oldAnswer with: (ToolsTestFixture >> #answer) source).
	self assert: (server textAt: self extensionPath onBranch: pr branch) equals: self extensionText.
	self assert: (server textAt: 'README.md' onBranch: pr branch) equals: '# test'.
	self assert: (server textAt: self fixturePath onBranch: 'main') equals: self fixtureText.
	self assert: (pr branch beginsWith: 'agent/').
	self assert: ((pr branch copyFrom: 7 to: 14) allSatisfy: [:c | c isDigit]).
	self assert: (pr branch at: 15) equals: $-.
	self assert: ((pr branch copyFrom: 16 to: 21) allSatisfy: [:c | c isDigit]).
	self assert: (pr branch copyFrom: 22 to: pr branch size) equals: '-tests-the-fixture-s-answer-is-42'.
	commit := server commitAt: pr commitSha.
	self assert: (commit at: 2) asArray equals: (Array with: (server refs at: 'main')).
	self assert: commit last equals: message.
	self assert: (server requestsTo: 'POST git/blobs') size equals: 1.
	self assert: server refs size equals: 2.
	self assert: (server refs at: pr branch) equals: pr commitSha.
	self assert: pr number equals: 1.
	self assert: pr url equals: 'https://github.test/test/repo/pull/1'.
	pull := server pulls first.
	self assert: (pull at: 'title') equals: 'Tests: the fixture''s answer is 42'.
	self assert: (pull at: 'head') equals: pr branch.
	self assert: (pull at: 'base') equals: 'main'.
	self assert: ((pull at: 'body') beginsWith: 'The browser test keeps it there.').
	self assert: ((pull at: 'body') includesSubstring: '- `ToolsTestFixture>>answer`').
	self assert: filer pendingChanges isEmpty.
	self deny: store isStarted
!
testNewClassFile
	| path pr text |
	path := 'src/Tests-Tools/SourceFilerGitHubTest.st'.
	self assert: (filer writeDefinition: self definition of: SourceFilerGitHubTest) equals: path.
	self assert: (filer writeCommentOf: SourceFilerGitHubTest) equals: path.
	self assert: (filer writeMethod: SourceFilerGitHubTest >> #token) equals: path.
	self assert: filer pendingChanges equals: (Array with: path).
	pr := filer commit: 'Tests: a new file' pullRequest: false.
	text := server textAt: path onBranch: pr branch.
	self assert: (text beginsWith: self definition, '!!').
	self assert: (text includesSubstring: 'SourceFilerGitHubTest comment: ''I test SourceFiler').
	self assert: (text includesSubstring: '!!SourceFilerGitHubTest methodsFor: ''fixtures''!!
token
').
	self assert: (server textAt: path onBranch: 'main') isNil.
	self assert: ((server treeOfBranch: pr branch) at: path) first equals: '100644'.
	self assert: pr number isNil.
	self assert: pr url isNil.
	self assert: server pulls isEmpty.
	self assert: (server refs at: pr branch) equals: pr commitSha
!
testRemoveMethod
	| pr |
	self assert: (filer removeMethod: #value: class: ToolsTestFixture category: 'accessing') equals: self fixturePath.
	self assert: (filer removeMethod: #noSuchMethod class: ToolsTestFixture category: 'accessing') isNil.
	pr := filer commit: 'Tests: no value:'.
	self assert: (server textAt: self fixturePath onBranch: pr branch) equals: (self fixtureText copyReplaceAll: '
value: anObject
	value := anObject
!!' with: '').
	self assert: ((server pulls first at: 'body') includesSubstring: 'ToolsTestFixture>>value: (removed)')
!
testExtensionMethods
	| kernelPath pr body |
	kernelPath := 'src/Tests-Kernel/ToolsTestFixture.extension.st'.
	self assert: (filer writeSource: 'fixtureNew
	^2' selector: #fixtureNew class: ToolsTestFixture category: '*Tests-Net') equals: self extensionPath.
	self assert: (filer writeSource: 'fixtureKernel
	^3' selector: #fixtureKernel class: ToolsTestFixture class category: '*Tests-Kernel') equals: kernelPath.
	self assert: filer pendingChanges equals: (Array with: kernelPath with: self extensionPath).
	pr := filer commit: 'Tests: extensions'.
	self assert: (server textAt: self extensionPath onBranch: pr branch) equals: (self extensionText copyReplaceAll: '	^1
!! !!' with: '	^1
!!
fixtureNew
	^2
!! !!').
	self assert: (server textAt: kernelPath onBranch: pr branch) equals: '!!ToolsTestFixture class methodsFor: ''*Tests-Kernel''!!
fixtureKernel
	^3
!! !!
'.
	body := server pulls first at: 'body'.
	self assert: (body includesSubstring: 'ToolsTestFixture>>fixtureNew').
	self assert: (body includesSubstring: 'ToolsTestFixture class>>fixtureKernel')
!
testRemovingTheLastExtensionMethodRemovesTheFile
	| pr entry |
	self assert: (filer removeMethod: #fixtureOld class: ToolsTestFixture category: '*Tests-Net') equals: self extensionPath.
	self assert: filer pendingChanges equals: (Array with: self extensionPath).
	pr := filer commit: 'Tests: no extension left'.
	self assert: (server textAt: self extensionPath onBranch: pr branch) isNil.
	self assert: (server textAt: self fixturePath onBranch: pr branch) equals: self fixtureText.
	self assert: (server textAt: self extensionPath onBranch: 'main') equals: self extensionText.
	entry := ((server requestsTo: 'POST git/trees') first json at: 'tree') first.
	self assert: (entry at: 'path') equals: self extensionPath.
	self assert: (entry includesKey: 'sha').
	self assert: (entry at: 'sha') isNil.
	self assert: (server requestsTo: 'POST git/blobs') isEmpty
!
testRemoveClass
	| pr |
	self assert: (filer removeClass: ToolsTestFixture) equals: self fixturePath.
	self assert: (filer removeClass: SourceFilerGitHubTest) isNil.
	pr := filer commit: 'Tests: no fixture'.
	self assert: (server textAt: self fixturePath onBranch: pr branch) isNil.
	self assert: (server textAt: self extensionPath onBranch: pr branch) equals: self extensionText
!
testTwoEditsToOneFile
	| pr |
	filer writeMethod: ToolsTestFixture >> #answer.
	filer writeSource: 'value
	"The value."
	^value' selector: #value class: ToolsTestFixture category: 'accessing'.
	self assert: filer pendingChanges equals: (Array with: self fixturePath).
	pr := filer commit: 'Tests: two edits'.
	self assert: (server textAt: self fixturePath onBranch: pr branch) equals: ((self fixtureText
		copyReplaceAll: self oldAnswer with: (ToolsTestFixture >> #answer) source)
		copyReplaceAll: 'value
	^value' with: 'value
	"The value."
	^value').
	self assert: (server requestsTo: 'POST git/blobs') size equals: 1.
	self assert: ((server pulls first at: 'body') includesSubstring: 'ToolsTestFixture>>value')
!
testWritingTheBaseTextBackIsNoChange
	filer writeSource: self oldAnswer selector: #answer class: ToolsTestFixture category: 'accessing'.
	self assert: filer pendingChanges isEmpty.
	filer writeMethod: ToolsTestFixture >> #answer.
	filer writeSource: self oldAnswer selector: #answer class: ToolsTestFixture category: 'accessing'.
	self assert: filer pendingChanges isEmpty.
	self should: [filer commit: 'Tests: nothing'] raise: GitHubError.
	self assert: (server requestsTo: 'POST') isEmpty
!
testDiscardChanges
	filer writeMethod: ToolsTestFixture >> #answer.
	self assert: filer pendingChanges notEmpty.
	filer discardChanges.
	self assert: filer pendingChanges isEmpty.
	self deny: store isStarted.
	self assert: (server requestsTo: 'POST') isEmpty.
	"the next change set starts again at the base branch's head"
	filer writeMethod: ToolsTestFixture >> #answer.
	self assert: (server requestsTo: 'GET git/ref/heads/main') size equals: 2.
	self assert: filer pendingChanges equals: (Array with: self fixturePath)
!
testFailedCommitKeepsTheChanges
	| error pr |
	filer writeMethod: ToolsTestFixture >> #answer.
	server fail: 'POST git/commits' status: 422 message: 'Tree SHA does not exist'.
	error := [filer commit: 'Tests: fails once'. nil] on: GitHubError do: [:e | e return: e].
	self assert: error notNil.
	self assert: error status equals: 422.
	self assert: (error messageText includesSubstring: 'Tree SHA does not exist').
	self assert: filer pendingChanges equals: (Array with: self fixturePath).
	self assert: server refs size equals: 1.
	pr := filer commit: 'Tests: fails once'.
	self assert: (server textAt: self fixturePath onBranch: pr branch)
		equals: (self fixtureText copyReplaceAll: self oldAnswer with: (ToolsTestFixture >> #answer) source).
	self assert: filer pendingChanges isEmpty
!
testLargeFile
	| big pr |
	big := String new: 3000000 streamContents: [:s |
		s nextPutAll: self fixtureText; nextPutAll: '
!!ToolsTestFixture methodsFor: ''filler''!!'.
		1 to: 40000 do: [:i |
			s nextPutAll: '
filler'; print: i; nextPutAll: '
	"'; nextPutAll: (String new: 40 withAll: $x); nextPutAll: ' é"
	^'; print: i; nextPutAll: '
!!'].
		s nextPutAll: ' !!
'].
	self assert: big size > 2500000.
	self serve: (Dictionary new at: self fixturePath put: big; yourself).
	self assert: (filer writeMethod: ToolsTestFixture >> #answer) equals: self fixturePath.
	pr := filer commit: 'Tests: a large file'.
	self assert: (server textAt: self fixturePath onBranch: pr branch)
		equals: (big copyReplaceAll: self oldAnswer with: (ToolsTestFixture >> #answer) source)
!
testWhichStore
	| other |
	other := SourceFiler new sourceDirectory: nil; gitHubStore: (GitHubSourceStore on: GitHubAccount new); yourself.
	self deny: other isEnabled.
	self assert: other pendingChanges isEmpty.
	self assert: (other writeMethod: ToolsTestFixture >> #answer) isNil.
	other gitHubStore: store.
	self assert: other usesGitHub.
	self assert: other isEnabled.
	self assert: (other pathForClass: ToolsTestFixture) equals: self fixturePath.
	other useGitHub: false.
	self deny: other isEnabled.
	other sourceDirectory: '/samaltak-test/src'; useGitHub: nil.
	(File mountTableFor: '/samaltak-test/src') isNil ifTrue: [
		self deny: other usesGitHub.
		self assert: (other pathForClass: ToolsTestFixture) equals: '/samaltak-test/src/Tests-Tools/ToolsTestFixture.st'].
	other useGitHub: true.
	self assert: other usesGitHub.
	self assert: other store == store
!
testTokenIsNeverPrinted
	| texts pr bad badStore error |
	filer writeMethod: ToolsTestFixture >> #answer.
	texts := OrderedCollection new.
	texts add: filer printString; add: store printString; add: store client printString; add: account printString.
	pr := filer commit: 'Tests: print'.
	texts add: pr printString.
	bad := GitHubAccount new.
	bad configure: (Dictionary new at: 'repository' put: 'test/repo'; at: 'apiUrl' put: server url; at: 'token' put: 'ghp_WrongStoreToken' copy; yourself).
	badStore := GitHubSourceStore on: bad.
	error := [(SourceFiler new useGitHub: true; gitHubStore: badStore; yourself) writeMethod: ToolsTestFixture >> #answer. nil]
		on: GitHubError do: [:e | e return: e].
	badStore close.
	self assert: error status equals: 401.
	texts add: error messageText; add: error description; add: badStore printString.
	texts do: [:each |
		self deny: (each includesSubstring: self token).
		self deny: (each includesSubstring: 'ghp_WrongStoreToken')]
!
testDocs
	self serve: (self files
		at: 'docs/guide.md' put: '# guide';
		at: 'docs/images/a.png' put: 'png';
		yourself).
	self assert: filer docs equals: #('guide.md').
	self assert: (filer doc: 'guide') equals: '# guide'.
	self assert: (filer doc: 'guide.md') equals: '# guide'.
	self assert: (filer doc: 'missing') isNil
!
testBinaryFile
	| bytes pr |
	bytes := #[0 1 128 255 10 13 192 193].
	self assert: (filer writeFile: 'fonts/Test-Regular.ttf' bytes: bytes) equals: 'fonts/Test-Regular.ttf'.
	self assert: filer pendingChanges equals: #('fonts/Test-Regular.ttf').
	pr := filer commit: 'Fonts: a test face' pullRequest: false.
	self assert: (server bytesAt: 'fonts/Test-Regular.ttf' onBranch: pr branch) asByteArray equals: bytes.
	self assert: (server bytesAt: 'fonts/Test-Regular.ttf' onBranch: 'main') isNil
!
testBinaryFileWhenWritingIsOff
	filer enabled: false.
	self assert: (filer writeFile: 'fonts/Test-Regular.ttf' bytes: #[0 255]) isNil.
	self assert: filer pendingChanges isEmpty
! !
