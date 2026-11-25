TestCase subclass: #SourceUpdateTest
	instanceVariableNames: 'server account store filer base head fixture savedBase savedRestart savedHash'
	classVariableNames: ''
	package: 'Tests-Tools'!

SourceUpdateTest comment: 'I test SourceUpdate (SourceFiler default updateFrom: ''main''): a fake GitHub (GitHubTestServer, Tests-Net) holds two commits, the base (the fixture classes setUp files into the image) and the head: methods added, changed and removed, an instance variable added to a class with a live instance, a new comment, a new class in a new package with a class-side initialize, a removed class, an extension file, a VM source and host files (reported, not applied). Then: conflicts with the image and with the pending change set (kept, or overwritten with takeTheirs), a head that does not compile (nothing applied), a dry run, up to date, the base commit and the update control command.'!

!SourceUpdateTest methodsFor: 'running'!
setUp
	savedBase := SourceFiler baseCommit.
	savedRestart := SourceFiler needsRestart.
	self removeFixtures.
	server := GitHubTestServer token: self token files: self baseFiles.
	account := GitHubAccount new.
	account configure: (Dictionary new
		at: 'repository' put: 'test/repo';
		at: 'apiUrl' put: server url;
		at: 'token' put: self token;
		yourself).
	store := GitHubSourceStore on: account.
	filer := SourceFiler new useGitHub: true; gitHubStore: store; yourself.
	Compiler fileInString: self baseFixture; fileInString: self oldFixture.
	fixture := (self classNamed: 'SourceUpdateFixture') withA: 3.
	base := server refs at: 'main'.
	head := server commit: self headChanges message: 'Next'
!
tearDown
	savedHash isNil ifFalse: [String compile: savedHash first classified: savedHash last].
	self removeFixtures.
	SourceFiler baseCommit: savedBase; needsRestart: savedRestart.
	store close.
	server stop.
	account clear
!
removeFixtures
	#(#SourceUpdateNewFixture #SourceUpdateFixture #SourceUpdateOldFixture) do: [:name |
		(Smalltalk at: name ifAbsent: [nil]) ifNotNil: [:class | class removeFromSystem]].
	Smalltalk removePackageNamed: 'Tests-SourceUpdate'
! !

!SourceUpdateTest methodsFor: 'fixtures'!
token
	^'ghp_UpdateTestToken0123456789' copy
!
classNamed: aString
	^Smalltalk at: aString asSymbol ifAbsent: [nil]
!
fixturePath
	^'src/Tests-Tools/SourceUpdateFixture.st'
!
baseFiles
	^Dictionary new
		at: self fixturePath put: self baseFixture;
		at: 'src/Tests-Tools/SourceUpdateOldFixture.st' put: self oldFixture;
		at: 'src/packages.txt' put: '# packages
Tests-Net 0
Tests-Tools 5
';
		at: 'src/VM-Core/Posix.st' put: '"one"!!
';
		at: 'vm/platform/posix.c' put: 'int one;';
		at: 'Makefile' put: 'all:';
		at: 'docs/github.md' put: '# GitHub';
		yourself
!
headChanges
	^Dictionary new
		at: self fixturePath put: self headFixture;
		at: 'src/Tests-Net/SourceUpdateFixture.extension.st' put: self extensionText;
		at: 'src/Tests-Tools/SourceUpdateOldFixture.st' put: nil;
		at: 'src/Tests-SourceUpdate/SourceUpdateNewFixture.st' put: self newFixture;
		at: 'src/packages.txt' put: '# packages
Tests-Net 0
Tests-Tools 5
Tests-SourceUpdate 5
';
		at: 'src/VM-Core/Posix.st' put: '"two"!!
';
		at: 'vm/platform/posix.c' put: 'int two;';
		at: 'Makefile' put: 'all: vm';
		at: 'docs/github.md' put: '# GitHub, updated';
		yourself
!
update
	^self updateWith: [:u | u]
!
updateWith: aBlock
	^(aBlock value: ((SourceUpdate account: account ref: 'main' base: base) filer: filer; yourself)) run
!
baseFixture
	"The fixture class as the base commit has it (and the image, after setUp)."
	^'Object subclass: #SourceUpdateFixture
	instanceVariableNames: ''a''
	classVariableNames: ''''
	package: ''Tests-Tools''!!

SourceUpdateFixture comment: ''Old comment.''!!

!!SourceUpdateFixture methodsFor: ''accessing''!!
a
	^a
!!
a: anObject
	a := anObject
!!
changed
	^1
!!
removed
	^#removed
!!
local
	^#base
!! !!

!!SourceUpdateFixture class methodsFor: ''instance creation''!!
withA: anObject
	^self new a: anObject
!! !!
'
!
headFixture
	"The fixture class at the head: an instance variable b, b and sum added, changed and local changed, removed removed, a new comment."
	^'Object subclass: #SourceUpdateFixture
	instanceVariableNames: ''a b''
	classVariableNames: ''''
	package: ''Tests-Tools''!!

SourceUpdateFixture comment: ''New comment.''!!

!!SourceUpdateFixture methodsFor: ''accessing''!!
a
	^a
!!
a: anObject
	a := anObject
!!
b
	^b
!!
changed
	^2
!!
local
	^#theirs
!!
sum
	^a + (b ifNil: [0])
!! !!

!!SourceUpdateFixture class methodsFor: ''instance creation''!!
withA: anObject
	^self new a: anObject
!! !!
'
!
extensionText
	"An extension file the head adds."
	^'!!SourceUpdateFixture methodsFor: ''*Tests-Net''!!
extended
	^#extended
!! !!
'
!
oldFixture
	"A class the head removes."
	^'Object subclass: #SourceUpdateOldFixture
	instanceVariableNames: ''''
	classVariableNames: ''''
	package: ''Tests-Tools''!!

!!SourceUpdateOldFixture methodsFor: ''accessing''!!
old
	^#old
!! !!
'
!
newFixture
	"A class the head adds, in a new package, with a class variable its class-side initialize sets."
	^'SourceUpdateFixture subclass: #SourceUpdateNewFixture
	instanceVariableNames: ''c''
	classVariableNames: ''Initialized''
	package: ''Tests-SourceUpdate''!!

SourceUpdateNewFixture comment: ''I am new.''!!

!!SourceUpdateNewFixture methodsFor: ''accessing''!!
total
	^self sum + 1
!! !!

!!SourceUpdateNewFixture class methodsFor: ''class initialization''!!
initialize
	Initialized := true
!!
initialized
	^Initialized
!! !!
'
!
filesAt99cfe6d: aBoolean
	"String>>hash and ObjectMemory>>stringHash: (src/VM-Core) as 99cfe6d (true) and its parent (false) have them: the image's hash, its primitive's C and the image header's hash flag changed together (an image at the parent runs a VM that hashes as FNV-1a)."
	^aBoolean
		ifTrue: [Dictionary new
		at: 'src/Kernel-Collections/String.st' put: '!!String methodsFor: ''comparing''!!
hash
	"The same for equal Strings and Symbols. Of more than 8 code points all below 256: them as bytes in 64-bit little-endian words, the last zero-padded; from h := the size, h := (h bitXor: word) * 16r5851F42D4C957F2D for each word, then h := h bitXor: h >> 32, h := h * 16r2545F4914F6CDD1D, h := h bitXor: h >> 29 (modulo 2^64), the low 30 bits. Else (up to 8, or code points above 255) FNV-1a over the code points, the low 30 bits."
	<primitive: ''stringHash''>
	| m h w k |
	(self size <= 8 or: [self anySatisfy: [:c | c value > 255]]) ifTrue: [
		h := 2166136261.
		self do: [:c | h := ((h bitXor: c value) * 16777619) bitAnd: 16rFFFFFFFF].
		^h bitAnd: 16r3FFFFFFF].
	m := 16rFFFFFFFFFFFFFFFF.
	h := self size.
	w := 0.
	k := 0.
	self do: [:c |
		w := w bitOr: (c value bitShift: 8 * k).
		k := k + 1.
		k = 8 ifTrue: [
			h := ((h bitXor: w) * 16r5851F42D4C957F2D) bitAnd: m.
			w := 0.
			k := 0]].
	k > 0 ifTrue: [h := ((h bitXor: w) * 16r5851F42D4C957F2D) bitAnd: m].
	h := h bitXor: (h bitShift: -32).
	h := (h * 16r2545F4914F6CDD1D) bitAnd: m.
	h := h bitXor: (h bitShift: -29).
	^h bitAnd: 16r3FFFFFFF
!! !!
';
		at: 'src/VM-Core/ObjectMemory.st' put: '!!ObjectMemory methodsFor: ''strings''!!
stringHash: s
	"String>>hash, the same for equal Strings and Symbols. Of more than 8 code points all below 256 (bytes, or 32-bit units that hold none above): them as bytes in 64-bit little-endian words, the last zero-padded; from h := their count, h := (h bitXor: word) * 16r5851F42D4C957F2D for each word, then h := h bitXor: h >> 32, h := h * 16r2545F4914F6CDD1D, h := h bitXor: h >> 29 (modulo 2^64), the low 30 bits. Else (up to 8, one word: a byte at a time keeps keys that differ in their last code point''s low bits apart in small tables; code points above 255, which no byte string has; an image saved before this hash, wordHash false) FNV-1a over them, the low 30 bits. The optimizing tier''s string hash stub does the same for bytes, String>>hash''s fallback and ImageBuilder>>stringHash: in Smalltalk."
	<function>
	<returns: ''uint32_t''>
	<var: #n type: ''uint64_t''>
	<var: #i type: ''uint64_t''>
	<var: #h type: ''uint64_t''>
	<var: #w type: ''uint64_t''>
	| n i h w |
	n := self stringSize: s.
	(wordHash not or: [n <= 8]) ifTrue: [^self fnvHash: s].
	i := 0.
	h := n.
	(self formatOf: s) >= F_BYTES
		ifTrue: [
			[i + 8 <= n] whileTrue: [
				h := ((h bitXor: (self uint64At: s + 16 + i)) * 16r5851F42D4C957F2D) asUInt64.
				i := i + 8]]
		ifFalse: [
			0 to: n asInt64 - 1 do: [:j |
				(self stringCharAt: s index: j asUInt64) > 255 ifTrue: [^self fnvHash: s]]].
	"what is left (bytes after the whole words, or 32-bit units below 256): up to 8 a word"
	w := 0.
	[i < n] whileTrue: [
		w := w bitOr: ((self stringCharAt: s index: i) asUInt64 << (8 * (i bitAnd: 7))).
		i := i + 1.
		((i bitAnd: 7) = 0 or: [i = n]) ifTrue: [
			h := ((h bitXor: w) * 16r5851F42D4C957F2D) asUInt64.
			w := 0]].
	h := h bitXor: h >> 32.
	h := (h * 16r2545F4914F6CDD1D) asUInt64.
	h := h bitXor: h >> 29.
	^(h bitAnd: 16r3FFFFFFF) asUInt32
!! !!
';
		yourself]
		ifFalse: [Dictionary new
		at: 'src/Kernel-Collections/String.st' put: '!!String methodsFor: ''comparing''!!
hash
	"FNV-1a over the code points, the same function as Symbol>>hash."
	<primitive: ''stringHash''>
	| h |
	h := 2166136261.
	self do: [:c | h := ((h bitXor: c value) * 16777619) bitAnd: 16rFFFFFFFF].
	^h bitAnd: 16r3FFFFFFF
!! !!
';
		at: 'src/VM-Core/ObjectMemory.st' put: '!!ObjectMemory methodsFor: ''strings''!!
stringHash: s
	<function>
	<returns: ''uint32_t''>
	| h n |
	h := 2166136261 asUInt32.
	n := self stringSize: s.
	0 to: n asInt64 - 1 do: [:i | h := ((h bitXor: (self stringCharAt: s index: i asUInt64)) * 16777619) asUInt32].
	^h bitAnd: 16r3FFFFFFF
!! !!
';
		yourself]
!
useImageAt99cfe6dParent
	"A fake GitHub whose main is 99cfe6d's parent, then 99cfe6d; String>>hash as the parent has it (the same primitive: Strings hash as before) until the test ends."
	| method text |
	server stop.
	server := GitHubTestServer token: self token files: (self filesAt99cfe6d: false).
	account configure: (Dictionary new at: 'apiUrl' put: server url; yourself).
	base := server refs at: 'main'.
	head := server commit: (self filesAt99cfe6d: true) message: 'VM: String hash 8 bytes a multiply past 8 bytes; images say which hash'.
	method := String >> #hash.
	text := method sourceCode.
	savedHash := Array with: text with: method category.
	String
		compile: ((ChunkFile on: ((self filesAt99cfe6d: false) at: 'src/Kernel-Collections/String.st')) sourceOf: #hash className: 'String' meta: false)
		classified: method category
! !

!SourceUpdateTest methodsFor: 'tests'!
testUpdateAppliesTheChanges
	| update class newClass |
	update := self update.
	self assert: update state equals: #applied.
	self assert: update failures isEmpty.
	self assert: update conflicts isEmpty.
	self assert: update head equals: head.
	class := self classNamed: 'SourceUpdateFixture'.
	self assert: class instVarNames asArray equals: #('a' 'b').
	self assert: fixture class == class.
	self assert: fixture a equals: 3.
	self assert: fixture b isNil.
	self assert: (update notes anySatisfy: [:n | n beginsWith: 'SourceUpdateFixture: b nil in its']).
	self assert: fixture sum equals: 3.
	self assert: fixture changed equals: 2.
	self assert: fixture local equals: #theirs.
	self deny: (class includesSelector: #removed).
	self assert: fixture extended equals: #extended.
	self assert: (class >> #extended) category equals: '*Tests-Net'.
	self assert: (class >> #sum) category equals: 'accessing'.
	self assert: class comment equals: 'New comment.'.
	self assert: (class withA: 4) sum equals: 4.
	self assert: (self classNamed: 'SourceUpdateOldFixture') isNil.
	newClass := self classNamed: 'SourceUpdateNewFixture'.
	self assert: newClass superclass == class.
	self assert: newClass packageName equals: 'Tests-SourceUpdate'.
	self assert: newClass comment equals: 'I am new.'.
	self assert: newClass initialized equals: true.
	self assert: ((newClass withA: 1) total) equals: 2.
	self assert: (Smalltalk packages anySatisfy: [:p | p name = 'Tests-SourceUpdate' and: [p layer = 5]]).
	self assert: update needsRestart equals: #('src/VM-Core/Posix.st' 'vm/platform/posix.c').
	self assert: update hostSide equals: #('Makefile' 'docs/github.md').
	self assert: (update summary beginsWith: 'applied 9 methods in 3 classes, 1 new class, 1 class definition changed, 1 class removed, 2 comments, 1 new package (Tests-SourceUpdate)').
	self assert: (update summary includesSubstring: '1 commit)').
	self assert: (update summary includesSubstring: 'needs restart for: src/VM-Core/Posix.st, vm/platform/posix.c').
	self assert: (update summary includesSubstring: 'host side, not in the image: Makefile, docs/github.md')
!
testConflictKeepsTheImagesMethod
	| update class |
	class := self classNamed: 'SourceUpdateFixture'.
	class compile: 'local
	^#mine' classified: 'accessing'.
	update := self update.
	self assert: update state equals: #applied.
	self assert: (update conflicts collect: [:c | c label]) asArray equals: #('SourceUpdateFixture>>local').
	self assert: update conflicts first reason equals: 'changed in this image'.
	self assert: fixture local equals: #mine.
	self assert: fixture changed equals: 2.
	self assert: fixture sum equals: 3.
	self assert: (update summary includesSubstring: 'conflicts, kept as this image has them (takeTheirs: true overwrites): SourceUpdateFixture>>local (changed in this image)')
!
testTakeTheirs
	| update class |
	class := self classNamed: 'SourceUpdateFixture'.
	class compile: 'local
	^#mine' classified: 'accessing'.
	update := self updateWith: [:u | u takeTheirs: true].
	self assert: update state equals: #applied.
	self assert: update conflicts isEmpty.
	self assert: fixture local equals: #theirs
!
testPendingChangeConflicts
	| update class |
	class := self classNamed: 'SourceUpdateFixture'.
	filer writeSource: 'removed
	^#pending' selector: #removed class: class category: 'accessing'.
	self assert: filer pendingChanges equals: (Array with: self fixturePath).
	update := self update.
	self assert: update state equals: #applied.
	self assert: (update conflicts collect: [:c | c label]) asArray equals: #('SourceUpdateFixture>>removed').
	self assert: update conflicts first reason equals: 'changed in the pending change set'.
	self assert: fixture removed equals: #removed.
	self assert: fixture changed equals: 2
!
testAlreadyAppliedIsNoConflict
	| update class |
	class := self classNamed: 'SourceUpdateFixture'.
	class compile: 'local
	^#theirs' classified: 'accessing'.
	update := self update.
	self assert: update conflicts isEmpty.
	self assert: ((update already collect: [:c | c label]) includes: 'SourceUpdateFixture>>local').
	self assert: (update summary includesSubstring: '1 change already in the image')
!
testCompileFailureAppliesNothing
	| update class |
	server commit: (Dictionary new
		at: self fixturePath put: ((self headFixture
			copyReplaceAll: '^a + (b ifNil: [0])' with: '^a + zork')
			copyReplaceAll: '^2' with: '^2 +');
		yourself) message: 'Broken'.
	update := self update.
	self assert: update state equals: #failed.
	self assert: update failures size equals: 2.
	self assert: (update failures anySatisfy: [:f | (f beginsWith: 'SourceUpdateFixture>>sum: ') and: [f includesSubstring: 'zork']]).
	self assert: (update failures anySatisfy: [:f | f beginsWith: 'SourceUpdateFixture>>changed: ']).
	self assert: (update summary beginsWith: 'nothing applied: ').
	class := self classNamed: 'SourceUpdateFixture'.
	self assert: class instVarNames asArray equals: #('a').
	self assert: fixture changed equals: 1.
	self assert: fixture removed equals: #removed.
	self assert: class comment equals: 'Old comment.'.
	self assert: (self classNamed: 'SourceUpdateNewFixture') isNil.
	self assert: (self classNamed: 'SourceUpdateOldFixture') notNil.
	self deny: (Smalltalk packages anySatisfy: [:p | p name = 'Tests-SourceUpdate'])
!
testKeptMethodsMustCompileOnTheNewShape
	| update |
	"The head drops the instance variable a, but a: (unchanged) still assigns it."
	server commit: (Dictionary new
		at: self fixturePath put: ((self headFixture
			copyReplaceAll: 'instanceVariableNames: ''a b''' with: 'instanceVariableNames: ''b''')
			copyReplaceAll: '^a + (b ifNil: [0])' with: '^b');
		yourself) message: 'No a'.
	update := self update.
	self assert: update state equals: #failed.
	self assert: (update failures anySatisfy: [:f | f beginsWith: 'SourceUpdateFixture>>a']).
	self assert: (self classNamed: 'SourceUpdateFixture') instVarNames asArray equals: #('a').
	self assert: fixture a equals: 3
!
testDryRunChangesNothing
	| update class |
	update := self updateWith: [:u | u dryRun: true].
	self assert: update state equals: #preview.
	self assert: (update summary beginsWith: 'would apply 9 methods').
	self assert: update applied notEmpty.
	class := self classNamed: 'SourceUpdateFixture'.
	self assert: class instVarNames asArray equals: #('a').
	self assert: fixture changed equals: 1.
	self assert: (self classNamed: 'SourceUpdateNewFixture') isNil.
	self assert: (self classNamed: 'SourceUpdateOldFixture') notNil
!
testUpToDate
	| update |
	base := head.
	update := self update.
	self assert: update state equals: #upToDate.
	self assert: (update summary beginsWith: 'up to date at ', head).
	self assert: fixture changed equals: 1
!
testUnknownBaseCommit
	| update |
	base := nil.
	update := self update.
	self assert: update state equals: #failed.
	self assert: (update summary includesSubstring: 'SourceFiler baseCommit is nil')
!
testSourceFilerMovesItsBaseCommit
	| update |
	SourceFiler baseCommit: base; needsRestart: #().
	update := filer updateFrom: 'main'.
	self assert: update state equals: #applied.
	self assert: SourceFiler baseCommit equals: head.
	self assert: SourceFiler needsRestart equals: #('src/VM-Core/Posix.st' 'vm/platform/posix.c').
	self assert: SourceFiler lastUpdate == update.
	update := filer updateFrom: 'main'.
	self assert: update state equals: #upToDate.
	self assert: (update summary includesSubstring: 'needs restart for: src/VM-Core/Posix.st')
!
testUpdateCommand
	| saved response |
	saved := SourceFiler default.
	SourceFiler baseCommit: base.
	SourceFiler default: filer.
	[response := RemoteControl dispatch: (RemoteRequest on: (Dictionary new
		at: 'cmd' put: 'update';
		at: 'ref' put: 'main';
		at: 'dryRun' put: true;
		yourself))] ensure: [SourceFiler default: saved].
	self assert: (response at: 'state') equals: 'preview'.
	self assert: ((response at: 'summary') beginsWith: 'would apply').
	self assert: (response at: 'head') equals: head.
	self assert: (response at: 'needsRestart') asArray equals: #('src/VM-Core/Posix.st' 'vm/platform/posix.c').
	self assert: SourceFiler baseCommit equals: base
!
testAddedInstanceVariablesSetAsInitializeSets
	"The head gives SourceUpdateFixture an initialize that sets b and lets a live update use it (initializesAddedInstanceVariables): the instances the image has get b as a new one does, each its own; a stays."
	| other update |
	other := (self classNamed: 'SourceUpdateFixture') withA: 5.
	server commit: (Dictionary new
		at: self fixturePath put: (self headFixture
			copyReplaceAll: '!!SourceUpdateFixture class methodsFor: ''instance creation''!!'
			with: '!!SourceUpdateFixture methodsFor: ''initialization''!!
initialize
	b := OrderedCollection new
!! !!

!!SourceUpdateFixture class methodsFor: ''live update''!!
initializesAddedInstanceVariables
	^true
!! !!

!!SourceUpdateFixture class methodsFor: ''instance creation''!!');
		yourself) message: 'b initialized'.
	update := self update.
	self assert: update state equals: #applied.
	self assert: fixture a equals: 3.
	self assert: fixture b class equals: OrderedCollection.
	self assert: fixture b isEmpty.
	self assert: other b class equals: OrderedCollection.
	self deny: fixture b == other b.
	self assert: (update notes anySatisfy: [:n | n beginsWith: 'SourceUpdateFixture: b set in its'])
!
testVMDependentChangeRefused
	"An image at 99cfe6d's parent updated across it: String>>hash's new definition goes with the VM's new stringHash, which this image's VM does not have; nothing is applied unless forced."
	| update |
	self useImageAt99cfe6dParent.
	update := self update.
	self assert: update state equals: #failed.
	self assert: update vmDependent size equals: 1.
	self assert: (update vmDependent first beginsWith: 'String>>hash (named by ObjectMemory>>stringHash: in src/VM-Core/ObjectMemory.st').
	self assert: (update summary beginsWith: 'nothing applied: image changes that depend on VM changes in the same range').
	self assert: (update summary includesSubstring: 'samaltak-ctl update --force').
	self assert: update needsRestart equals: #('src/VM-Core/ObjectMemory.st').
	self assert: (String >> #hash) sourceCode equals: ((ChunkFile on: ((self filesAt99cfe6d: false) at: 'src/Kernel-Collections/String.st')) sourceOf: #hash className: 'String' meta: false)
!
testVMDependentChangeForced
	| update |
	self useImageAt99cfe6dParent.
	update := self updateWith: [:u | u force: true].
	self assert: update state equals: #applied.
	self assert: (update applied collect: [:c | c label]) asArray equals: #('String>>hash').
	self assert: (update notes anySatisfy: [:n | n beginsWith: 'forced past the VM changes these depend on: String>>hash']).
	self assert: (String >> #hash) sourceCode equals: ((ChunkFile on: ((self filesAt99cfe6d: true) at: 'src/Kernel-Collections/String.st')) sourceOf: #hash className: 'String' meta: false).
	self assert: 'abcdefghijklmnop' hash equals: 'abcdefghijklmnop' copy hash
!
testVMRelations
	"What SourceUpdate reads in VM and image methods: primitive names and numbers, methods named as Class>>selector, the VM's C sources."
	self assert: (SourceUpdate primitivesIn: '	<vmPrimitive: 102 name: ''stringHash''>') asArray equals: #('102' 'stringHash').
	self assert: (SourceUpdate primitivesIn: 'hash
	<primitive: ''stringHash''>
	^0') asArray equals: #('stringHash').
	self assert: (SourceUpdate primitivesIn: '<primitive: 60>') asArray equals: #('60').
	self assert: (SourceUpdate methodsNamedIn: '"String>>hash, and Foo class>>bar: baz; x >> 2"') asArray equals: #('String>>hash' 'Foo class>>bar:' 'Foo class>>bar').
	self assert: (SourceUpdate isVMSource: 'vm/platform/posix.c').
	self deny: (SourceUpdate isVMSource: 'vm/gen/object_memory.c').
	self deny: (SourceUpdate isVMSource: 'src/VM-Core/Posix.st')
!
testTheImageKnowsItsCommit
	"make image passes git rev-parse HEAD to stage 2."
	self assert: (SourceUpdate isSha: savedBase)
! !
