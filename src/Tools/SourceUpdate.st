Object subclass: #SourceUpdate
	instanceVariableNames: 'filer account client ref base head dryRun takeTheirs comparison baseFiles headFiles paths oldTexts newTexts pendingPaths newPackages changes definitionBodies classes shadows bindings reshaped newClasses removedClasses applied already conflicts failures needsRestart hostSide notApplied notes previousRestart state step'
	classVariableNames: ''
	package: 'Tools'!

SourceUpdate comment: 'I bring the running image from the commit its sources are at (base) to a branch''s head on GitHub (GitHubAccount''s repository), without a restart: SourceFiler default updateFrom: ''main'' makes and runs me.

1. Fetch: the head''s sha (git/ref/heads/<ref>, or ref itself when it is a sha), compare/<base>...<head> (status, commits), both commits'' trees (git/trees/<tree>?recursive=1): the paths whose blobs differ.
2. Sort the paths: src/<Package>/*.st of a package in this image (or one packages.txt adds) are applied; src/packages.txt adds new packages; src/VM-* and vm/ are the VM itself (needsRestart); everything outside src/ is host side (hostSide: Makefile, tools/, docs/, ...); anything else in src/ is notApplied.
3. Diff: each changed file''s old and new text (git/blobs), cut into chunks (ChunkFile): class definitions, class-side instance variables, comments and methods, matched by class and selector across files (a method moving to an extension file is a category change). Each difference is a SourceChange.
4. Conflicts: a change applies when the image has the old version; it is already done when the image has the new one; otherwise the image (or the SourceFiler''s pending change set) changed it too: a conflict, reported and left as the image has it unless takeTheirs. A conflicting class definition holds back every change of its class.
5. Check: every new or changed method compiles (nothing installed yet) against shadow classes (unregistered copies with the new definitions); for a class whose instance variables or superclass change, its other methods and its subclasses'' methods compile against the new shape too; a removed class must have no subclass left. One failure and nothing is applied: failures says what.
6. Install (unless dryRun), at userInterruptPriority so no other Process runs half-updated code: new packages (packages.txt order), the methods a reshaped class loses or changes removed first, class definitions (superclass first; ClassBuilder reshapes and migrates instances as the browser does), class-side instance variables, comments, methods added and changed, methods removed, removed classes (subclasses first); then each new class''s class-side initialize (a changed initialize is not run: notes says so).

summary says it in a sentence: "applied 37 methods in 9 classes ...; needs restart for: src/VM-Core/Posix.st". state: #upToDate, #preview (dryRun), #applied, #failed (nothing installed), #partial (installing stopped at failures last; what was installed stays).'!

!SourceUpdate methodsFor: 'initialization'!
setAccount: aGitHubAccount ref: aString base: aShaOrNil
	account := aGitHubAccount.
	ref := aString.
	base := aShaOrNil.
	dryRun := false.
	takeTheirs := false.
	previousRestart := #().
	applied := OrderedCollection new.
	already := OrderedCollection new.
	conflicts := OrderedCollection new.
	failures := OrderedCollection new.
	needsRestart := OrderedCollection new.
	hostSide := OrderedCollection new.
	notApplied := OrderedCollection new.
	notes := OrderedCollection new.
	newPackages := OrderedCollection new.
	changes := OrderedCollection new.
	definitionBodies := Dictionary new.
	newClasses := OrderedCollection new.
	removedClasses := OrderedCollection new.
	reshaped := OrderedCollection new.
	paths := #()
!
filer: aSourceFilerOrNil
	"The SourceFiler whose pending change set counts as local work (conflicts)."
	filer := aSourceFilerOrNil
!
dryRun: aBoolean
	dryRun := aBoolean
!
takeTheirs: aBoolean
	"Apply a change even where the image changed it too."
	takeTheirs := aBoolean
!
previousRestart: aCollection
	"Paths an earlier update left for a restart; the summary repeats them."
	previousRestart := aCollection asArray
! !

!SourceUpdate methodsFor: 'accessing'!
ref
	^ref
!
base
	^base
!
head
	^head
!
state
	^state
!
changes
	^changes
!
applied
	"The SourceChanges installed (or, for a dry run, that would be)."
	^applied asArray
!
already
	^already asArray
!
conflicts
	^conflicts asArray
!
failures
	"Strings: what failed to compile or install, or why nothing could be fetched."
	^failures asArray
!
needsRestart
	"Paths of the VM itself that changed (src/VM-*, vm/): they take effect in an image built and started anew."
	^needsRestart asArray
!
hostSide
	"Paths outside src/ that changed: Makefile, tools/, docs/ ... (the host's checkout, not the image)."
	^hostSide asArray
!
notApplied
	"Other changes I do not apply, with why."
	^notApplied asArray
!
notes
	^notes asArray
!
newPackages
	^newPackages asArray
!
commitCount
	^comparison isNil ifTrue: [0] ifFalse: [comparison at: 'total_commits' ifAbsent: [comparison at: 'ahead_by' ifAbsent: [0]]]
!
succeeded
	^#(#upToDate #preview #applied) includes: state
! !

!SourceUpdate methodsFor: 'running'!
run
	"Fetch, diff, check and, unless dryRun, install (see my comment). Answer self."
	[self fetch.
	 state isNil ifTrue: [
		self sortPaths; readFiles; diff; decide; check.
		failures isEmpty
			ifFalse: [state := #failed]
			ifTrue: [dryRun
				ifTrue: [
					applied addAll: (changes select: [:c | c applies and: [(c isMethod and: [c isRemoved and: [removedClasses includes: c className]]) not]]).
					state := #preview]
				ifFalse: [self install]]]]
		on: GitHubError do: [:e |
			failures add: (self explain: e).
			state := #failed.
			e return: nil].
	shadows := bindings := nil.
	client isNil ifFalse: [client close].
	^self
!
explain: aGitHubError
	(aGitHubError status = 404 and: [head notNil]) ifTrue: [
		^aGitHubError messageText, ': GitHub does not know the image''s commit ', base, ' (built from a commit not pushed?) or ', head].
	^aGitHubError messageText
! !

!SourceUpdate methodsFor: 'fetching'!
client
	^client ifNil: [client := GitHubClient on: account]
!
get: aString
	^self client get: (self client repositoryPath: aString)
!
fetch
	base isNil ifTrue: [
		failures add: 'The image does not know the commit its sources are at (SourceFiler baseCommit is nil): set it with SourceFiler baseCommit: ''<sha>'''.
		^state := #failed].
	account repository isNil ifTrue: [
		failures add: 'No GitHub repository: on the host, run samaltak-ctl github-config --from-gh'.
		^state := #failed].
	head := (self class isSha: ref)
		ifTrue: [ref]
		ifFalse: [((self get: 'git/ref/heads/', ref) at: 'object') at: 'sha'].
	head = base ifTrue: [^state := #upToDate].
	comparison := self get: 'compare/', base, '...', head.
	(comparison at: 'status' ifAbsent: ['ahead']) = 'ahead' ifFalse: [
		notes add: 'the image''s commit ', (self class short: base), ' is not an ancestor of ', ref, ' (', (comparison at: 'status' ifAbsent: ['?']), '): updating to its tree anyway, which undoes what only the image''s commit has'].
	baseFiles := self filesAt: base.
	headFiles := self filesAt: head.
	paths := ((baseFiles keys asSet addAll: headFiles keys; yourself)
		select: [:p | (baseFiles at: p ifAbsent: [nil]) ~= (headFiles at: p ifAbsent: [nil])]) asSortedCollection asArray.
	paths isEmpty ifTrue: [state := #upToDate]
!
filesAt: aCommitSha
	"path -> blob sha of the commit's tree."
	| commit listing files |
	commit := self get: 'git/commits/', aCommitSha.
	listing := self get: 'git/trees/', ((commit at: 'tree') at: 'sha'), '?recursive=1'.
	(listing at: 'truncated' ifAbsent: [false]) == true ifTrue: [
		^GitHubError refuse: 'The tree of ', aCommitSha, ' is too large to list in one request'].
	files := Dictionary new.
	(listing at: 'tree') do: [:e | (e at: 'type') = 'blob' ifTrue: [files at: (e at: 'path') put: (e at: 'sha')]].
	^files
!
textOfBlob: aShaOrNil
	| blob content |
	aShaOrNil isNil ifTrue: [^nil].
	blob := self get: 'git/blobs/', aShaOrNil.
	content := blob at: 'content'.
	^(blob at: 'encoding' ifAbsent: ['base64']) = 'base64'
		ifTrue: [(Base64 decode: content) utf8Decoded]
		ifFalse: [content]
! !

!SourceUpdate methodsFor: 'sorting'!
kindOf: aPath
	"#restart (the VM), #host (outside src/), #packages, #source (src/<Package>/<file>.st), #other (elsewhere in src/)."
	| rest |
	(aPath beginsWith: 'vm/') ifTrue: [^#restart].
	(aPath beginsWith: 'src/') ifFalse: [^#host].
	rest := aPath copyFrom: 5 to: aPath size.
	(rest includes: $/) ifFalse: [^rest = 'packages.txt' ifTrue: [#packages] ifFalse: [#other]].
	(rest beginsWith: 'VM-') ifTrue: [^#restart].
	((aPath endsWith: '.st') and: [(rest occurrencesOf: $/) = 1]) ifFalse: [^#other].
	^#source
!
packageOf: aPath
	^(aPath copyFrom: 5 to: aPath size) copyUpTo: $/
!
sortPaths
	oldTexts := Dictionary new.
	newTexts := Dictionary new.
	paths do: [:p |
		| kind |
		kind := self kindOf: p.
		kind == #restart ifTrue: [needsRestart add: p].
		kind == #host ifTrue: [hostSide add: p].
		kind == #other ifTrue: [notApplied add: p, ' (not used by this image)'].
		kind == #packages ifTrue: [self readPackages].
		kind == #source ifTrue: [oldTexts at: p put: nil]]
!
readPackages
	"New packages from packages.txt, in its order (src/VM-* ones need a restart)."
	| old new known |
	old := self packageLinesOf: (self textOfBlob: (baseFiles at: 'src/packages.txt' ifAbsent: [nil])).
	new := self packageLinesOf: (self textOfBlob: (headFiles at: 'src/packages.txt' ifAbsent: [nil])).
	known := Smalltalk packages collect: [:p | p name].
	new do: [:line |
		((known includes: line first) or: [line first beginsWith: 'VM-']) ifFalse: [newPackages add: line]].
	old do: [:line |
		(new noneSatisfy: [:each | each first = line first]) ifTrue: [
			notApplied add: 'src/packages.txt: ', line first, ' removed (its classes stay in this image)']]
!
packageLinesOf: aStringOrNil
	"{name. layer} of each package line of a packages.txt."
	| lines |
	lines := OrderedCollection new.
	aStringOrNil isNil ifTrue: [^lines].
	aStringOrNil lines do: [:line |
		| words |
		words := line substrings.
		(words notEmpty and: [(words first beginsWith: '#') not]) ifTrue: [
			lines add: {words first. words size > 1 ifTrue: [(words at: 2) asNumber] ifFalse: [nil]}]].
	^lines
!
hasPackage: aString
	^(Smalltalk packages anySatisfy: [:p | p name = aString]) or: [newPackages anySatisfy: [:line | line first = aString]]
!
readFiles
	"The old and new texts of the source files of packages in this image; the rest is notApplied."
	oldTexts keys asSortedCollection do: [:p |
		(self hasPackage: (self packageOf: p))
			ifTrue: [
				oldTexts at: p put: (self textOfBlob: (baseFiles at: p ifAbsent: [nil])).
				newTexts at: p put: (self textOfBlob: (headFiles at: p ifAbsent: [nil]))]
			ifFalse: [
				oldTexts removeKey: p.
				notApplied add: p, ' (package ', (self packageOf: p), ' is not in this image)']].
	pendingPaths := (filer notNil and: [filer gitHubStore isStarted])
		ifTrue: [filer gitHubStore pendingChanges select: [:p | oldTexts includesKey: p]]
		ifFalse: [#()]
! !

!SourceUpdate methodsFor: 'diffing'!
entitiesOf: aDictionary
	"key -> {kind. className. isMeta. selector. value. category. path. chunk}: the methods, definitions (value: a spec), comments and class-side instance variables of the texts (path -> text or nil)."
	| entities |
	entities := Dictionary new.
	aDictionary keysAndValuesDo: [:path :text |
		text isNil ifFalse: [
			| file |
			file := ChunkFile on: text.
			file methodsDo: [:m |
				entities at: (m first, ((m at: 2) ifTrue: [' class'] ifFalse: ['']), '>>', (m at: 3))
					put: {#method. m first. m at: 2. m at: 3. m at: 5. m at: 4. path. nil}].
			file topLevelChunksDo: [:body |
				| entity |
				entity := self topLevelEntityOf: body.
				entity first == #other
					ifTrue: [entities at: 'other ', body put: {#other. nil. false. nil. body. nil. path. body}]
					ifFalse: [entities at: entity first asString, ' ', (entity at: 2) put: {entity first. entity at: 2. entity first == #classSide. nil. entity last. nil. path. body}]]]].
	^entities
!
topLevelEntityOf: aChunk
	"{#definition. className. spec}, {#comment. className. text}, {#classSide. className. names} or {#other. nil. chunk}."
	| node statement spec |
	spec := self class specOf: aChunk.
	spec isNil ifFalse: [^{#definition. spec at: 3. spec}].
	node := [Parser new parseExpression: aChunk] on: Error do: [:e | e return: nil].
	(node notNil and: [node body statements size = 1]) ifTrue: [
		statement := node body statements first.
		(statement isMessage and: [statement arguments size = 1 and: [statement arguments first isLiteral and: [statement arguments first value isString]]]) ifTrue: [
			(statement selector = #comment: and: [statement receiver isVariable]) ifTrue: [
				^{#comment. statement receiver name asString. statement arguments first value}].
			(statement selector = #instanceVariableNames: and: [statement receiver isMessage
				and: [statement receiver selector = #class and: [statement receiver receiver isVariable]]]) ifTrue: [
					^{#classSide. statement receiver receiver name asString. statement arguments first value substrings asArray}]]].
	^{#other. nil. aChunk}
!
diff
	| old new keys |
	old := self entitiesOf: oldTexts.
	new := self entitiesOf: newTexts.
	keys := (old keys asSet addAll: new keys; yourself) asSortedCollection.
	keys do: [:key |
		| o n e change |
		o := old at: key ifAbsent: [nil].
		n := new at: key ifAbsent: [nil].
		e := n ifNil: [o].
		(self entity: o equals: n) ifFalse: [
			e first == #other
				ifTrue: [n isNil ifFalse: [notApplied add: (e at: 7), ': a top-level chunk (', ((e at: 5) copyFrom: 1 to: ((e at: 5) size min: 50)), ')']]
				ifFalse: [
					change := SourceChange new setKind: e first className: (e at: 2) isMeta: (e at: 3) selector: (e at: 4).
					change old: (o ifNotNil: [o at: 5]); new: (n ifNotNil: [n at: 5]); path: (e at: 7).
					e first == #method ifTrue: [
						change oldCategory: (o ifNotNil: [o at: 6]); newCategory: (n ifNotNil: [n at: 6])].
					changes add: change]]].
	new do: [:e | e first == #definition ifTrue: [definitionBodies at: (e at: 2) put: (e at: 8)]]
!
entity: o equals: n
	(o isNil or: [n isNil]) ifTrue: [^o == n].
	o first == #definition ifTrue: [^self class spec: (o at: 5) sameAs: (n at: 5)].
	^(o at: 5) = (n at: 5) and: [(o at: 6) = (n at: 6)]
! !

!SourceUpdate methodsFor: 'conflicts'!
imageClassNamed: aString
	| c |
	c := Smalltalk at: aString asSymbol ifAbsent: [nil].
	^(c notNil and: [c isBehavior]) ifTrue: [c] ifFalse: [nil]
!
imageValueOf: aChange
	"What the image has where aChange applies: a method's source, a class's spec, comment or class-side instance variables; nil if nothing."
	| class |
	class := self imageClassNamed: aChange className.
	class isNil ifTrue: [^nil].
	aChange kind == #definition ifTrue: [^self class specOfClass: class].
	aChange kind == #comment ifTrue: [^class comment].
	aChange kind == #classSide ifTrue: [^(class class instVarNames collect: [:n | n asString]) asArray].
	aChange isMeta ifTrue: [class := class class].
	^(class compiledMethodAt: aChange selector asSymbol ifAbsent: [^nil]) sourceCode
!
pendingValueOf: aChange
	"What the SourceFiler's pending change set has for aChange (#none when it has not touched its file)."
	| text entity |
	(pendingPaths includes: aChange path) ifFalse: [^#none].
	text := filer gitHubStore textAt: aChange path.
	entity := (self entitiesOf: (Dictionary new at: aChange path put: text; yourself)) at: (self keyOf: aChange) ifAbsent: [nil].
	^entity isNil ifTrue: [nil] ifFalse: [entity at: 5]
!
keyOf: aChange
	aChange isMethod ifTrue: [^aChange label].
	^aChange kind asString, ' ', aChange className
!
value: a sameAs: b for: aChange
	aChange kind == #definition ifTrue: [^self class spec: a sameAs: b].
	aChange kind == #classSide ifTrue: [^(a ifNil: [#()]) asArray = (b ifNil: [#()]) asArray].
	^a = b
!
decide
	"Each change: #apply, #already or #conflict (see my comment)."
	| held |
	changes do: [:c |
		| local pending |
		local := self imageValueOf: c.
		pending := self pendingValueOf: c.
		(self value: local sameAs: c new for: c)
			ifTrue: [c decision: #already]
			ifFalse: [
				(self value: local sameAs: c old for: c)
					ifFalse: [c decision: #conflict reason: 'changed in this image']
					ifTrue: [
						(pending == #none or: [(self value: pending sameAs: c old for: c) or: [self value: pending sameAs: c new for: c]])
							ifTrue: [c decision: #apply]
							ifFalse: [c decision: #conflict reason: 'changed in the pending change set']]]].
	"A removed class whose methods conflict stays; a conflicting definition holds back its class."
	held := Set new.
	changes do: [:c | (c decision == #conflict and: [c kind == #definition or: [self isRemovedClass: c className]]) ifTrue: [held add: c className]].
	changes do: [:c |
		(c decision == #conflict and: [takeTheirs]) ifTrue: [c decision: #apply reason: 'overwrites a change in this image'].
		((held includes: c className) and: [takeTheirs not and: [c decision ~~ #conflict]])
			ifTrue: [c decision: #skip reason: 'its class conflicts']].
	changes do: [:c |
		c decision == #already ifTrue: [already add: c].
		c decision == #conflict ifTrue: [conflicts add: c].
		c decision == #skip ifTrue: [notApplied add: c label, ' (', c reason, ')']].
	changes do: [:c |
		(c applies and: [c isMethod and: [c isMeta and: [c selector = #initialize and: [c isAdded not and: [(self isNewClass: c className) not]]]]]) ifTrue: [
			notes add: c className, ' class>>initialize changed: not run (evaluate ', c className, ' initialize if its state needs it)']]
!
isRemovedClass: aString
	^changes anySatisfy: [:c | c kind == #definition and: [c className = aString and: [c isRemoved]]]
!
isNewClass: aString
	^changes anySatisfy: [:c | c kind == #definition and: [c className = aString and: [c isAdded]]]
!
applying: aKind
	^changes select: [:c | c applies and: [c kind == aKind]]
! !

!SourceUpdate methodsFor: 'checking'!
check
	"Compile everything against shadow classes, installing nothing (see my comment)."
	shadows := Dictionary new.
	bindings := Dictionary new.
	(self applying: #definition) do: [:c |
		(c isAdded and: [(self imageClassNamed: c className) isNil]) ifTrue: [
			bindings at: c className asSymbol put: (Association key: c className asSymbol value: nil)]].
	classes := self orderedDefinitions.
	failures isEmpty ifFalse: [^self].
	classes do: [:c | self shadowFor: c].
	(self applying: #classSide) do: [:c | self shadowForClassSide: c].
	reshaped copy do: [:name | self shadowSubclassesOf: (self imageClassNamed: name)].
	failures isEmpty ifFalse: [^self].
	(self applying: #method) do: [:c |
		c isRemoved ifFalse: [
			(self targetOf: c)
				ifNil: [(self isRemovedClass: c className) ifFalse: [failures add: c label, ': there is no class ', c className]]
				ifNotNil: [:target | self trialCompile: c new in: target label: c label]]].
	reshaped do: [:name | self checkKeptMethodsOf: name].
	self checkRemovedClasses
!
orderedDefinitions
	"The definitions to apply, a superclass before its subclasses."
	| pending ordered |
	pending := ((self applying: #definition) reject: [:c | c isRemoved]) asOrderedCollection.
	ordered := OrderedCollection new.
	[pending isEmpty] whileFalse: [
		| ready |
		ready := pending select: [:c | pending noneSatisfy: [:other | other className = c new first]].
		ready isEmpty ifTrue: [
			failures add: 'circular superclasses: ', ((pending collect: [:c | c className]) inject: '' into: [:a :b | a, ' ', b]).
			^ordered].
		ordered addAll: ready.
		pending removeAll: ready].
	^ordered
!
superclassNamed: aString
	"A shadow, the image's class, or nil for 'nil'; #missing if none."
	aString = 'nil' ifTrue: [^nil].
	^shadows at: aString ifAbsent: [(self imageClassNamed: aString) ifNil: [#missing]]
!
shadowFor: aChange
	"A shadow of the class aChange defines; note whether its instances change shape."
	| spec superclass existing builder civars shadow format |
	spec := aChange new.
	superclass := self superclassNamed: spec first.
	superclass == #missing ifTrue: [^failures add: aChange label, ': there is no superclass ', spec first].
	existing := self imageClassNamed: aChange className.
	builder := ClassBuilder new.
	[builder validateName: aChange className asSymbol instanceVariables: (spec at: 4) superclass: superclass.
	 format := builder formatFor: (spec at: 4) superclass: superclass type: (self class typeOf: (spec at: 2))]
		on: Error do: [:e | ^failures add: aChange label, ': ', e messageText asString].
	civars := (self applying: #classSide) detect: [:c | c className = aChange className] ifNone: [nil].
	civars := civars isNil
		ifTrue: [existing isNil ifTrue: [#()] ifFalse: [existing class instVarNames asArray]]
		ifFalse: [civars new ifNil: [#()]].
	shadow := self shadowNamed: aChange className superclass: superclass instanceVariables: (spec at: 4) classVariables: (spec at: 5) classInstanceVariables: civars format: format.
	shadows at: aChange className put: shadow.
	existing isNil
		ifTrue: [newClasses add: aChange className]
		ifFalse: [
			(existing superclass ~~ (self realClassOf: superclass)
				or: [existing format ~= format or: [(existing instVarNames collect: [:n | n asString]) asArray ~= (spec at: 4) asArray]])
					ifTrue: [reshaped add: aChange className]]
!
realClassOf: aClassOrShadow
	aClassOrShadow isNil ifTrue: [^nil].
	^(self imageClassNamed: aClassOrShadow name) ifNil: [aClassOrShadow]
!
shadowForClassSide: aChange
	"Class-side instance variables change on a class whose definition does not."
	| class |
	(shadows includesKey: aChange className) ifTrue: [^self].
	class := self imageClassNamed: aChange className.
	class isNil ifTrue: [^failures add: aChange label, ': there is no class ', aChange className].
	shadows at: aChange className put: (self shadowNamed: class name superclass: class superclass
		instanceVariables: class instVarNames classVariables: class classVarNames
		classInstanceVariables: (aChange new ifNil: [#()]) format: class format)
!
shadowSubclassesOf: aClass
	"Shadows of the image's subclasses of a reshaped class (their instances change shape too)."
	aClass subclasses do: [:sub |
		| superShadow |
		superShadow := shadows at: aClass name.
		(shadows includesKey: sub name) ifFalse: [
			shadows at: sub name put: (self shadowNamed: sub name superclass: superShadow
				instanceVariables: sub instVarNames classVariables: sub classVarNames classInstanceVariables: sub class instVarNames
				format: (ClassBuilder new formatWithSpec: sub instSpec size: superShadow instSize + sub instVarNames size))].
		(reshaped includes: sub name) ifFalse: [reshaped add: sub name].
		self shadowSubclassesOf: sub]
!
shadowNamed: aName superclass: aSuperclass instanceVariables: ivars classVariables: cvars classInstanceVariables: civars format: aFormat
	"A class like the one ClassBuilder would make, but in neither Smalltalk nor its superclass's subclasses: methods compile against it."
	| superMeta meta class pool |
	superMeta := aSuperclass isNil ifTrue: [Class] ifFalse: [aSuperclass class].
	meta := Metaclass basicNew.
	meta superclass: superMeta methodDictionary: MethodDictionary new format: superMeta format + civars size.
	meta setInstanceVariables: (civars collect: [:n | n asString]) asArray.
	class := meta basicNew.
	class superclass: aSuperclass methodDictionary: MethodDictionary new format: aFormat.
	class setInstanceVariables: (ivars collect: [:n | n asString]) asArray.
	class setName: aName asSymbol.
	class setSubclasses: #().
	pool := Dictionary new.
	cvars do: [:n | pool add: (Association key: n asSymbol value: nil)].
	class classPool: pool.
	meta thisClass: class.
	^class
!
targetOf: aChange
	"The behavior aChange's method compiles in: a shadow's or the image's class, or nil."
	| class |
	class := shadows at: aChange className ifAbsent: [self imageClassNamed: aChange className].
	class isNil ifTrue: [^nil].
	^aChange isMeta ifTrue: [class class] ifFalse: [class]
!
trialCompile: aString in: aBehavior label: aLabel
	| b ok |
	b := bindings copy.
	ok := [CodeGenerator new generate: (Parser new parseMethod: aString) class: aBehavior bindings: b. true]
		on: Error do: [:e |
			failures add: aLabel, ': ', e messageText asString.
			e return: false].
	(ok and: [b size > bindings size]) ifTrue: [
		failures add: aLabel, ': undeclared variable ', ((b keys reject: [:k | bindings includesKey: k]) asArray first)]
!
touches: aClassName meta: aBoolean selector: aSelector
	^changes anySatisfy: [:c | c applies and: [c isMethod and: [c className = aClassName and: [c isMeta = aBoolean and: [c selector = aSelector]]]]]
!
checkKeptMethodsOf: aName
	"The methods of a reshaped class that the update leaves must compile on its new shape."
	| class shadow |
	class := self imageClassNamed: aName.
	shadow := shadows at: aName.
	class selectors do: [:sel |
		| source |
		source := (class compiledMethodAt: sel) sourceCode.
		(source notNil and: [(self touches: aName meta: false selector: sel) not])
			ifTrue: [self trialCompile: source in: shadow label: aName, '>>', sel, ' (kept, on the new shape)']]
!
checkRemovedClasses
	(self applying: #definition) do: [:c |
		| class |
		class := c isRemoved ifTrue: [self imageClassNamed: c className].
		class notNil ifTrue: [
			removedClasses add: c className.
			class subclasses do: [:sub |
				(self isRemovedClass: sub name) ifFalse: [
					failures add: c label, ': removed, but its subclass ', sub name, ' is not']]]]
! !

!SourceUpdate methodsFor: 'installing'!
install
	| process priority |
	process := Processor activeProcess.
	priority := process priority.
	process priority: (priority max: Processor userInterruptPriority).
	[[self installChanges]
		on: Error do: [:e |
			failures add: 'stopped at ', step, ': ', e messageText asString.
			state := #partial.
			e return: nil]]
		ensure: [process priority: priority].
	state == #partial ifTrue: [^self].
	self initializeNewClasses.
	state := #applied
!
installChanges
	| methods |
	newPackages do: [:line |
		step := 'package ', line first.
		Smalltalk addPackageNamed: line first layer: line last].
	methods := self applying: #method.
	"A reshaped class recompiles its methods: first drop those the update changes or removes."
	methods do: [:c |
		| class |
		class := self imageClassNamed: c className.
		(class notNil and: [c isMeta
			ifTrue: [(self applying: #classSide) anySatisfy: [:s | s className = c className]]
			ifFalse: [reshaped includes: c className]]) ifTrue: [
			step := c label.
			(c isMeta ifTrue: [class class] ifFalse: [class]) removeSelector: c selector asSymbol]].
	classes do: [:c |
		step := c label.
		Compiler evaluate: (definitionBodies at: c className).
		applied add: c].
	(self applying: #classSide) do: [:c |
		step := c label.
		(self imageClassNamed: c className) class instanceVariableNames: ((c new ifNil: [#()]) inject: '' into: [:a :b | a, b, ' ']).
		applied add: c].
	(self applying: #comment) do: [:c |
		(self isRemovedClass: c className) ifFalse: [
			step := c label.
			(self imageClassNamed: c className) comment: c new.
			applied add: c]].
	methods do: [:c |
		| class |
		c isRemoved ifFalse: [
			step := c label.
			class := self imageClassNamed: c className.
			Compiler compile: c new in: (c isMeta ifTrue: [class class] ifFalse: [class]) classified: c newCategory.
			applied add: c]].
	methods do: [:c |
		| class |
		(c isRemoved and: [(removedClasses includes: c className) not]) ifTrue: [
			step := c label.
			class := self imageClassNamed: c className.
			class isNil ifFalse: [(c isMeta ifTrue: [class class] ifFalse: [class]) removeSelector: c selector asSymbol].
			applied add: c]].
	(removedClasses asSortedCollection: [:a :b | (self imageClassNamed: a) allSuperclasses size >= (self imageClassNamed: b) allSuperclasses size]) do: [:name |
		step := name, ' (removing the class)'.
		(self imageClassNamed: name) removeFromSystem.
		applied addAll: (changes select: [:c | c applies and: [c className = name and: [c kind == #definition]]])]
!
initializeNewClasses
	"Each new class's class-side initialize, in definition order."
	newClasses do: [:name |
		| class |
		class := self imageClassNamed: name.
		(class notNil and: [class class includesSelector: #initialize]) ifTrue: [
			[class initialize] on: Error do: [:e |
				notes add: name, ' initialize failed: ', e messageText asString.
				e return: nil]]]
! !

!SourceUpdate methodsFor: 'reporting'!
summary
	"What happened, in a sentence (see my comment)."
	^String new: 200 streamContents: [:s |
		state == #upToDate ifTrue: [s nextPutAll: 'up to date at '; nextPutAll: (head ifNil: [base]) ; nextPutAll: (ref = head ifTrue: [''] ifFalse: [' (', ref, ')'])].
		state == #failed ifTrue: [
			s nextPutAll: 'nothing applied: '.
			self printList: failures on: s].
		state == #partial ifTrue: [
			s nextPutAll: 'partly applied, then '.
			self printList: failures on: s.
			s nextPutAll: '; applied before: '.
			self printCountsOn: s].
		(#(#preview #applied) includes: state) ifTrue: [
			s nextPutAll: (state == #preview ifTrue: ['would apply '] ifFalse: ['applied ']).
			self printCountsOn: s].
		(head notNil and: [state ~~ #upToDate]) ifTrue: [
			s nextPutAll: ' ('; nextPutAll: (self class short: base); nextPutAll: '..'; nextPutAll: (self class short: head).
			comparison isNil ifFalse: [s nextPutAll: ', '; print: self commitCount; nextPutAll: (self commitCount = 1 ifTrue: [' commit'] ifFalse: [' commits'])].
			s nextPut: $)].
		conflicts isEmpty ifFalse: [
			s nextPutAll: '; conflicts, kept as this image has them (takeTheirs: true overwrites): '.
			self printList: (conflicts collect: [:c | c label, ' (', c reason, ')']) on: s].
		(needsRestart isEmpty and: [previousRestart isEmpty]) ifFalse: [
			s nextPutAll: '; needs restart for: '.
			self printList: (needsRestart asArray, (previousRestart reject: [:p | needsRestart includes: p])) on: s].
		hostSide isEmpty ifFalse: [
			s nextPutAll: '; host side, not in the image: '.
			self printList: hostSide on: s].
		notApplied isEmpty ifFalse: [
			s nextPutAll: '; not applied: '.
			self printList: notApplied on: s].
		notes isEmpty ifFalse: [
			s nextPutAll: '; note: '.
			self printList: notes on: s]]
!
printCountsOn: aStream
	| methods classNames parts defs |
	methods := applied select: [:c | c isMethod].
	classNames := (applied collect: [:c | c className]) asSet.
	parts := OrderedCollection new.
	parts add: (self count: methods size of: 'method'), ' in ', (self count: classNames size of: 'class').
	defs := applied select: [:c | c kind == #definition].
	(defs select: [:c | c isAdded]) isEmpty ifFalse: [parts add: (self count: (defs select: [:c | c isAdded]) size of: 'new class')].
	(defs select: [:c | c isAdded not and: [c isRemoved not]]) isEmpty ifFalse: [parts add: (self count: (defs select: [:c | c isAdded not and: [c isRemoved not]]) size of: 'class definition'), ' changed'].
	(defs select: [:c | c isRemoved]) isEmpty ifFalse: [parts add: (self count: (defs select: [:c | c isRemoved]) size of: 'class'), ' removed'].
	(applied select: [:c | c kind == #comment]) isEmpty ifFalse: [parts add: (self count: (applied select: [:c | c kind == #comment]) size of: 'comment')].
	newPackages isEmpty ifFalse: [parts add: (self count: newPackages size of: 'new package'), ' (', ((newPackages collect: [:l | l first]) inject: '' into: [:a :b | a isEmpty ifTrue: [b] ifFalse: [a, ', ', b]]), ')'].
	already isEmpty ifFalse: [parts add: (self count: already size of: 'change'), ' already in the image'].
	self printList: parts on: aStream
!
count: anInteger of: aNoun
	^anInteger printString, ' ', aNoun, (anInteger = 1 ifTrue: [''] ifFalse: [(aNoun endsWith: 's') ifTrue: ['es'] ifFalse: ['s']])
!
printList: aCollection on: aStream
	aCollection doWithIndex: [:each :i |
		i > 1 ifTrue: [aStream nextPutAll: ', '].
		aStream nextPutAll: each]
!
printOn: aStream
	aStream nextPutAll: 'a SourceUpdate ('; nextPutAll: (state ifNil: ['not run']); nextPutAll: ': '; nextPutAll: self summary; nextPut: $)
!
asDictionary
	"For the update control command: state, summary and the lists as strings."
	^Dictionary new
		at: 'state' put: (state ifNil: ['not run']) asString;
		at: 'summary' put: self summary;
		at: 'ref' put: ref;
		at: 'base' put: base;
		at: 'head' put: head;
		at: 'commits' put: self commitCount;
		at: 'applied' put: (applied collect: [:c | c label, ' (', c verb, ')']) asArray;
		at: 'conflicts' put: (conflicts collect: [:c | c label, ' (', c reason, ')']) asArray;
		at: 'needsRestart' put: (needsRestart asArray, (previousRestart reject: [:p | needsRestart includes: p]));
		at: 'hostSide' put: hostSide asArray;
		at: 'notApplied' put: notApplied asArray;
		at: 'failures' put: failures asArray;
		at: 'notes' put: notes asArray;
		yourself
! !

!SourceUpdate class methodsFor: 'instance creation'!
account: aGitHubAccount ref: aString base: aShaOrNil
	^self new setAccount: aGitHubAccount ref: aString base: aShaOrNil
! !

!SourceUpdate class methodsFor: 'specs'!
specOf: aChunk
	"{superclass name. kind keyword. class name. instance variable names. sorted class variable names. package} of a class definition chunk, or nil."
	| pair node statement args |
	pair := Compiler classDefinitionIn: aChunk.
	pair isNil ifTrue: [^nil].
	node := Parser new parseExpression: aChunk.
	statement := node body statements first.
	args := statement arguments.
	args size >= 4 ifFalse: [^nil].
	(args allSatisfy: [:a | a isLiteral]) ifFalse: [^nil].
	^{pair first.
		statement selector keywords first asString.
		pair last.
		(args at: 2) value substrings asArray.
		(args at: 3) value substrings asSortedCollection asArray.
		args last value}
!
specOfClass: aClass
	"The spec (specOf:) of the image's class, its kind unknown (nil)."
	^{aClass superclass isNil ifTrue: ['nil'] ifFalse: [aClass superclass name asString].
		nil.
		aClass name asString.
		(aClass instVarNames collect: [:n | n asString]) asArray.
		(aClass classVarNames collect: [:n | n asString]) asSortedCollection asArray.
		aClass packageName}
!
spec: a sameAs: b
	"Same superclass, name, variables and package (the kind is not compared: the image's is not known)."
	(a isNil or: [b isNil]) ifTrue: [^a == b].
	^#(1 3 4 5 6) allSatisfy: [:i | (a at: i) = (b at: i)]
!
typeOf: aKeyword
	^#('subclass:' #normal 'variableSubclass:' #variable 'variableByteSubclass:' #bytes 'variableWordSubclass:' #words
		'variableDoubleWordSubclass:' #doubleWords 'weakSubclass:' #weak 'immediateSubclass:' #immediate)
			at: (#('subclass:' 'variableSubclass:' 'variableByteSubclass:' 'variableWordSubclass:' 'variableDoubleWordSubclass:' 'weakSubclass:' 'immediateSubclass:') indexOf: aKeyword) * 2
!
isSha: aString
	^aString size = 40 and: [aString allSatisfy: [:c | '0123456789abcdef' includes: c]]
!
short: aShaOrNil
	aShaOrNil isNil ifTrue: [^'?'].
	^aShaOrNil size > 7 ifTrue: [aShaOrNil copyFrom: 1 to: 7] ifFalse: [aShaOrNil]
! !
