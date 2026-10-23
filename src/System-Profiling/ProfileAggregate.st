Object subclass: #ProfileAggregate
	instanceVariableNames: 'profiler kind live cursor samples root idleRoot tracks groups labels touched sites generation'
	classVariableNames: ''
	package: 'System-Profiling'!

ProfileAggregate comment: 'I keep the call tree, the per-Process counts and (for allocations) the allocation sites of the samples of one kind (#cpu or #allocation) up to date as the profiler records them: update folds in only the samples recorded since the previous update and takes out the ones the ring dropped since (it is fixed-size, so the oldest go). Live tools update me a few times a second instead of rebuilding everything from a snapshot.

	| live |
	live := ProfileAggregate on: Profiler default kind: #cpu.
	live update.
	live root.	"all Processes: busy samples, one node per Process, then frames from the outermost inwards"
	live nodeFor: aProcess.
	live topSites: 8 for: nil.	"(an allocation aggregate)"

Adding or removing a sample costs a dictionary lookup: samples are counted per (Process, stack) in a ProfilePath (the profiler decodes equal stacks into the same Array), and once per update each changed ProfilePath adds its net change along its nodes, O(depth). Nodes whose samples are all gone are removed. Idle samples go into a tree of their own (idleRoot), so root counts the busy samples only. Each Process has a ProfileTrack; when a Process has terminated, its track is merged into the first terminated one with the same label (short-lived Processes such as each ''remote request'' count as one). Trees use ProfileNodes: the root is ''all Processes'', process nodes are named Process ''label''.

ProfileAggregate kind: #cpu samples: aCollection profiler: aProfiler builds the same from a fixed set of samples (a pinned range); it equals a live one over the same samples.'!

!ProfileAggregate methodsFor: 'initialization'!
setProfiler: aProfiler kind: aSymbol live: aBoolean
	profiler := aProfiler.
	kind := aSymbol.
	live := aBoolean.
	self clear
!
clear
	cursor := nil.
	samples := OrderedCollection new.
	root := ProfileNode new setName: 'all Processes' frame: nil process: nil parent: nil.
	idleRoot := ProfileNode new setName: 'idle' frame: nil process: nil parent: nil.
	tracks := OrderedCollection new.
	groups := IdentityDictionary new.
	labels := Dictionary new.
	touched := OrderedCollection new.
	sites := IdentityDictionary new.
	generation := (generation ifNil: [0]) + 1
! !

!ProfileAggregate methodsFor: 'accessing'!
profiler
	^profiler
!
kind
	^kind
!
isLive
	^live
!
generation
	"Answer a number that changes whenever my contents change."
	^generation
!
samples
	"Answer a SampleSet of my samples, oldest first (not a copy: it changes with update)."
	^SampleSet unit: (kind == #cpu ifTrue: [#samples] ifFalse: [#bytes]) samples: samples
!
samplesCopy
	^SampleSet unit: (kind == #cpu ifTrue: [#samples] ifFalse: [#bytes]) samples: samples copy
!
size
	^samples size
!
oldestTime
	^samples isEmpty ifTrue: [nil] ifFalse: [samples first time]
!
newestTime
	^samples isEmpty ifTrue: [nil] ifFalse: [samples last time]
!
root
	"Answer the call tree of the busy samples (all Processes but idle)."
	^root
!
idleRoot
	"Answer the tree of the idle process's samples (its only child is the idle process's node)."
	^idleRoot
!
tracks
	"Answer the ProfileTracks (one per Process, terminated ones with the same label merged), in the order of their first sample."
	^tracks
!
trackOf: aProcess
	"Answer the ProfileTrack aProcess counts in (nil: none), also for a terminated Process whose label has a merged track."
	| track |
	track := groups at: (aProcess ifNil: [#unknown]) ifAbsent: [nil].
	(track isNil and: [aProcess notNil and: [aProcess isTerminated]]) ifTrue: [
		track := labels at: (Profiler labelFor: aProcess) ifAbsent: [nil]].
	^track
!
nodeFor: aProcess
	"Answer the process node of aProcess (idle included), or nil."
	| track |
	track := self trackOf: aProcess.
	^track isNil ifTrue: [nil] ifFalse: [track node]
!
groupOf: aProcess
	"Answer the Process standing for aProcess (itself, or the first terminated Process with its label)."
	| track |
	track := self trackOf: aProcess.
	^track isNil ifTrue: [aProcess] ifFalse: [track process]
!
busyWeight
	^root weight
!
leavesFor: aProcessOrNil
	"Answer Associations ProfileFrame -> weight of the samples ending there, heaviest first: of aProcessOrNil's track, or of all busy ones."
	| totals track |
	aProcessOrNil isNil
		ifTrue: [
			totals := IdentityDictionary new.
			tracks do: [:t | t root == root ifTrue: [
				t leaves keysAndValuesDo: [:f :w | totals at: f put: (totals at: f ifAbsent: [0]) + w]]]]
		ifFalse: [
			track := self trackOf: aProcessOrNil.
			totals := track isNil ifTrue: [IdentityDictionary new] ifFalse: [track leaves]].
	^totals associations asArray sort: [:a :b | a value > b value]
!
totalWeight
	^root weight + idleRoot weight
! !

!ProfileAggregate methodsFor: 'updating'!
update
	"Fold in the samples recorded since the previous update and take out the ones the ring dropped since. Answer whether anything changed."
	| new old |
	live ifFalse: [^false].
	(cursor notNil and: [(profiler isCurrent: cursor) not]) ifTrue: [self clear].
	old := generation.
	new := OrderedCollection new.
	cursor := profiler samplesSince: cursor kind: kind into: new.
	[samples notEmpty and: [(profiler isValidSerial: samples first serial) not]] whileTrue: [
		self count: samples removeFirst sign: -1].
	new do: [:s |
		samples addLast: s.
		self count: s sign: 1].
	(touched notEmpty or: [self hasNewlyTerminated]) ifTrue: [
		self flush.
		self retireTerminated.
		generation := generation + 1].
	^generation ~= old
!
addAll: aCollection
	"Count aCollection's samples (oldest first)."
	aCollection do: [:s |
		samples addLast: s.
		self count: s sign: 1].
	self flush.
	self retireTerminated.
	generation := generation + 1
!
removeOldest: n
	"Take out my n oldest samples."
	(n min: samples size) timesRepeat: [self count: samples removeFirst sign: -1].
	self flush.
	self retireTerminated.
	generation := generation + 1
! !

!ProfileAggregate methodsFor: 'allocation sites'!
topSites: n for: aProcessOrNil
	"Answer the n heaviest AllocationSites (allocation aggregates), of the Process aProcessOrNil stands for (its bytes only), or of all."
	| all track |
	all := OrderedCollection new.
	aProcessOrNil isNil
		ifTrue: [sites do: [:perClass | all addAll: perClass values]]
		ifFalse: [
			track := self trackOf: aProcessOrNil.
			track isNil ifFalse: [
				sites do: [:perClass | perClass do: [:site | | r |
					r := site restrictedTo: track members.
					r isNil ifFalse: [all add: r]]]]].
	all := all asArray sort: [:a :b | a bytes > b bytes].
	^all first: (n min: all size)
! !

!ProfileAggregate methodsFor: 'private'!
count: aSample sign: anInteger
	| path |
	path := (self trackFor: aSample) pathFor: aSample.
	path pending isNil ifTrue: [touched add: path].
	path addPending: aSample weight * anInteger count: anInteger.
	kind == #allocation ifTrue: [self countSite: aSample sign: anInteger]
!
trackFor: aSample
	| p |
	p := aSample process.
	^groups at: (p ifNil: [#unknown]) ifAbsent: [self newTrackFor: p idle: (kind == #cpu and: [aSample isIdle])]
!
newTrackFor: aProcess idle: aBoolean
	| top key track |
	top := aBoolean ifTrue: [idleRoot] ifFalse: [root].
	key := aProcess ifNil: [#unknown].
	track := ProfileTrack new
		setProcess: aProcess
		node: (top childAt: key name: (aProcess isNil ifTrue: ['unknown'] ifFalse: [nil]) frame: nil process: aProcess)
		root: top.
	tracks add: track.
	groups at: key put: track.
	^track
!
flush
	"Add each touched ProfilePath's net change along its nodes, then remove the paths and nodes left without samples."
	| empty |
	empty := OrderedCollection new.
	touched do: [:path |
		path apply.
		path count = 0 ifTrue: [empty add: path]].
	touched := OrderedCollection new.
	empty do: [:path | self discard: path]
!
discard: aPath
	| track nodes |
	track := aPath track.
	track forget: aPath.
	nodes := aPath nodes.
	nodes size to: 2 by: -1 do: [:i | | node |
		node := nodes at: i.
		(node sampleCount = 0 and: [node parent notNil]) ifTrue: [node parent removeChild: node]].
	track node sampleCount = 0 ifTrue: [self discardTrack: track]
!
discardTrack: aTrack
	tracks remove: aTrack ifAbsent: [nil].
	aTrack members do: [:m | (groups at: m ifAbsent: [nil]) == aTrack ifTrue: [groups removeKey: m]].
	(aTrack label notNil and: [(labels at: aTrack label ifAbsent: [nil]) == aTrack]) ifTrue: [labels removeKey: aTrack label]
!
hasNewlyTerminated
	^tracks anySatisfy: [:t | t isRetired not and: [t process notNil and: [t root == root and: [t process isTerminated]]]]
!
retireTerminated
	"Merge the tracks of Processes that terminated into the first terminated track with the same label."
	tracks copy do: [:t |
		(t isRetired not and: [t process notNil and: [t root == root and: [t process isTerminated]]])
			ifTrue: [self retire: t]]
!
retire: aTrack
	| label rep |
	label := Profiler labelFor: aTrack process.
	aTrack retire: label.
	rep := labels at: label ifAbsent: [nil].
	rep isNil ifTrue: [^labels at: label put: aTrack].
	self merge: aTrack into: rep
!
merge: aTrack into: aRepresentative
	aTrack pathsDo: [:path | | target nodes |
		target := aRepresentative pathForStack: path stack truncated: path isTruncated.
		nodes := target nodes.
		2 to: nodes size do: [:i | (nodes at: i) add: path weight count: path count].
		nodes last addSelf: path weight.
		aRepresentative addLeaf: nodes last frame weight: path weight.
		target count: target count + path count weight: target weight + path weight].
	root removeChild: aTrack node.
	tracks remove: aTrack.
	aTrack members do: [:m |
		groups at: m put: aRepresentative.
		aRepresentative members add: m]
!
countSite: aSample sign: anInteger
	| frameKey classKey perClass site |
	frameKey := aSample allocationSite ifNil: [#none].
	classKey := aSample allocatedClass ifNil: [#none].
	perClass := sites at: frameKey ifAbsent: [sites at: frameKey put: IdentityDictionary new].
	site := perClass at: classKey ifAbsent: [
		perClass at: classKey put: (AllocationSite frame: aSample allocationSite allocatedClass: aSample allocatedClass)].
	anInteger > 0 ifTrue: [^site addSample: aSample].
	site removeSample: aSample.
	site count <= 0 ifTrue: [
		perClass removeKey: classKey.
		perClass isEmpty ifTrue: [sites removeKey: frameKey]]
! !

!ProfileAggregate methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a ProfileAggregate('; print: kind; nextPutAll: ', '; print: samples size; nextPutAll: ' samples, ';
		print: tracks size; nextPutAll: ' Processes)'
! !

!ProfileAggregate class methodsFor: 'instance creation'!
on: aProfiler kind: aSymbol
	"Answer a live aggregate of aProfiler's samples of aSymbol (#cpu or #allocation); send it update to catch up."
	^self new setProfiler: aProfiler kind: aSymbol live: true
!
kind: aSymbol samples: aCollection profiler: aProfiler
	"Answer an aggregate of the fixed samples in aCollection (oldest first)."
	^(self new setProfiler: aProfiler kind: aSymbol live: false) addAll: aCollection; yourself
! !
