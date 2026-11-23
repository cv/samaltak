Object subclass: #FFITrial
	instanceVariableNames: ''
	classVariableNames: 'Installed'
	package: 'System-Support'!

FFITrial comment: 'Publish reviewed FFI candidates for a workload in a disposable hosted VM (SAMALTAK_FFI_TRIAL=1). Install and uninstall at quiescent workload boundaries; stop and drain callers first. Methods are changed only at those boundaries, never at bootstrap or on each call. Supported snapshots remove trial routes before saving. No default candidates.'!

!FFITrial class methodsFor: 'routes'!
routes
	"Class name, class side?, public selector, original primitive ID, candidate selector, preserved alias, exact native binding. Only reviewed trial bundles belong here."
	^#(
		(#File true #primPosition: 505 #ffiCandidatePrimPosition: #ffiLegacyPrimPosition: #(call 'platform' 'platform_files_position' (i64) i64))
		(#File true #primSize: 504 #ffiCandidatePrimSize: #ffiLegacyPrimSize: #(call 'platform' 'platform_files_size' (i64) i64)))
!
withInstalled: aSelector on: aBehavior do: aBlock
	| trial |
	trial := self install: aSelector on: aBehavior.
	^aBlock ensure: [
		(Installed at: aSelector ifAbsent: [nil]) == trial
			ifTrue: [self uninstall: aSelector on: aBehavior]]
!
install: aSelector on: aBehavior
	| route original candidate alias legacy published sibling entry |
	(Smalltalk isStartingUp or: [(Smalltalk vm arguments includes: '--stage2') or: [
		(Smalltalk vm getenv: 'SAMALTAK_FFI_TRIAL') ~= '1']])
		ifTrue: [self error: 'FFI trials require an opted-in disposable VM after startup'].
	route := self route: aSelector on: aBehavior.
	Installed isNil ifTrue: [Installed := IdentityDictionary new].
	(Installed includesKey: aSelector) ifTrue: [self error: 'FFI trial already installed'].
	original := aBehavior compiledMethodAt: aSelector.
	candidate := aBehavior compiledMethodAt: route fifth.
	alias := route at: 6.
	((original primitiveNumber = route fourth and: [original numArgs = candidate numArgs])
		and: [(aBehavior lookupSelector: alias) isNil]) ifFalse: [self error: 'Unexpected trial route shape'].
	(PlatformFFI bind: (route at: 7)) isNil ifTrue: [self error: 'Native target not available in this VM'].
	legacy := original copy selector: alias; yourself.
	sibling := self candidate: candidate replacing: aSelector with: alias.
	published := sibling copy selector: aSelector; yourself.
	Smalltalk addToShutDownList: self.
	entry := {aBehavior. original. candidate. alias. legacy. published. sibling}.
	Installed at: aSelector put: entry.
	aBehavior addSelectorSilently: alias withMethod: legacy.
	aBehavior addSelectorSilently: candidate selector withMethod: sibling.
	aBehavior addSelectorSilently: aSelector withMethod: published.
	^entry
!
uninstall: aSelector on: aBehavior
	| entry original candidate alias |
	entry := Installed ifNotNil: [Installed at: aSelector ifAbsent: [nil]].
	(entry isNil or: [entry first ~~ aBehavior]) ifTrue: [self error: 'FFI trial is not installed'].
	original := entry second.
	candidate := entry third.
	alias := entry fourth.
	((aBehavior compiledMethodAt: alias ifAbsent: [nil]) == entry fifth and: [
		(aBehavior compiledMethodAt: aSelector ifAbsent: [nil]) == (entry at: 6) and: [
		(aBehavior compiledMethodAt: candidate selector ifAbsent: [nil]) == (entry at: 7)]])
			ifFalse: [self error: 'Do not edit methods with an active FFI trial'].
	aBehavior addSelectorSilently: aSelector withMethod: original.
	aBehavior addSelectorSilently: candidate selector withMethod: candidate.
	aBehavior removeSelector: alias.
	Installed removeKey: aSelector
!
shutDown: quitting
	Installed isNil ifTrue: [^self].
	Installed keys do: [:selector | self uninstall: selector on: (Installed at: selector) first]
! !

!FFITrial class methodsFor: 'private'!
route: aSelector on: aBehavior
	^self routes detect: [:row |
		| cls |
		cls := Smalltalk at: row first ifAbsent: [nil].
		row third == aSelector and: [cls notNil and: [
			(row second ifTrue: [cls class] ifFalse: [cls]) == aBehavior]]]
		ifNone: [self error: 'This route is not enabled for FFI trials']
!
candidate: aMethod replacing: publicSelector with: alias
	"The approved fallback must be a literal self send. Reject special-selector sends, which cannot be rebound by copying literals."
	| clone index |
	(aMethod sendsSelector: publicSelector) ifFalse: [self error: 'Candidate has no legacy fallback send'].
	(CompiledMethod specialSelectors includes: publicSelector) ifTrue: [self error: 'Special selectors are not trial routes'].
	clone := aMethod copy.
	index := clone literals identityIndexOf: publicSelector.
	index = 0 ifTrue: [self error: 'Candidate fallback is not a literal send'].
	clone literals at: index put: alias.
	^clone
! !
