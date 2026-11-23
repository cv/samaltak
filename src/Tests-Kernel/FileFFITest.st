TestCase subclass: #FileFFITest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

FileFFITest comment: 'Hosted headless file FFI contract. Native-only checks trap eligible calls that would otherwise fall back silently.'!

!FileFFITest methodsFor: 'support'!
withoutLegacy: signatures do: aBlock
	| side originals |
	side := File class.
	originals := OrderedCollection new.
	[
		signatures do: [:signature |
			| stub old |
			stub := Compiler compileMethod: signature, Character lf asString, 'self error: ''Unexpected legacy file fallback'''
				in: side classified: 'file FFI proof'.
			old := side compiledMethodAt: stub selector.
			originals add: old.
			side addSelector: stub selector withMethod: stub].
		aBlock value
	] ensure: [originals do: [:method | side addSelector: method selector withMethod: method]]
! !

!FileFFITest methodsFor: 'tests'!
testFileDescriptorOperations
	| handle path mutable source wideHandle stream |
	path := self scratchPath: 'io'.
	handle := File primOpen: path mode: 3.
	self deny: handle isNil.
	mutable := ByteArray new: 6 withAll: 238.
	source := #[77 1 2 3 88].
	wideHandle := handle + 16r100000000.
	[
		self withoutLegacy: #('primPosition: h' 'primSize: h' 'primSeek: h to: pos' 'primFlush: h'
			'primWrite: h from: bytes startingAt: start count: count' 'primRead: h into: bytes startingAt: start count: count') do: [
			self assert: (File ffiCandidatePrimPosition: wideHandle) equals: 0.
			self assert: (File ffiCandidatePrimSize: handle) equals: 0.
			self assert: (File ffiCandidatePrimWrite: handle from: source startingAt: 2 count: 3) equals: 3.
			self assert: (File ffiCandidatePrimWrite: handle from: source startingAt: 6 count: 0) equals: 0.
			self assert: (File ffiCandidatePrimPosition: handle) equals: 3.
			self assert: (File ffiCandidatePrimSize: handle) equals: 3.
			self assert: (File ffiCandidatePrimFlush: handle) identicalTo: File.
			self assert: (File ffiCandidatePrimSeek: handle to: 1) identicalTo: File.
			self assert: (File ffiCandidatePrimRead: handle into: mutable startingAt: 3 count: 3) equals: 2.
			self assert: mutable equals: #[238 238 2 3 238 238].
			self assert: (File ffiCandidatePrimRead: handle into: mutable startingAt: 7 count: 0) equals: 0.
			self assert: (File ffiCandidatePrimRead: handle into: mutable startingAt: 2 count: 3) equals: 0.
			self assert: (File ffiCandidatePrimSeek: handle to: -1) isNil.
			self assert: (File ffiCandidatePrimPosition: handle) equals: 3.
			self assert: (File ffiCandidatePrimSeek: handle to: 16r100000007) identicalTo: File.
			self assert: (File ffiCandidatePrimPosition: handle) equals: 16r100000007.
			self assert: (File ffiCandidatePrimSize: handle) equals: 3]
	] ensure: [File primClose: handle].
	FileStream readOnlyFileNamed: path do: [:s |
		stream := s.
		s binary.
		self assert: s next equals: 1.
		"Read-ahead moved the descriptor to EOF; FileStream still discounts the unread bytes."
		self assert: (File ffiCandidatePrimPosition: (s instVarNamed: 'handle')) equals: 3.
		self assert: s position equals: 1].
	self assert: stream isClosed
!
testRejectedAndCompletedFailures
	| path handle legacyBytes frozen |
	path := self scratchPath: 'failures'.
	File writeBytes: #[1 2 3] to: path.
	handle := File primOpen: path mode: 0.
	self deny: handle isNil.
	legacyBytes := String new: 3.
	frozen := #[9 9 9].
	[
		"Immutable and malformed slices fail before entry; the legacy accepts mutable byte strings."
		self assert: (File ffiCandidatePrimRead: handle into: frozen startingAt: 1 count: 1) isNil.
		self assert: (File ffiCandidatePrimRead: handle into: frozen copy startingAt: 0 count: 1) isNil.
		self assert: (File ffiCandidatePrimRead: handle into: frozen copy startingAt: 4 count: 1) isNil.
		self assert: (File ffiCandidatePrimPosition: handle) equals: 0.
		self assert: (File ffiCandidatePrimRead: handle into: legacyBytes startingAt: 1 count: 3) equals: 3.
		self assert: legacyBytes asByteArray equals: #[1 2 3].
		self withoutLegacy: #('primWrite: h from: bytes startingAt: start count: count'
			'primClose: h') do: [
			self assert: (File ffiCandidatePrimWrite: handle from: frozen startingAt: 1 count: 1) isNil.
			self assert: (File lastError includesSubstring: 'write').
			self assert: (File ffiCandidatePrimClose: handle) identicalTo: File.
			self assert: (File ffiCandidatePrimClose: handle) isNil]
	] ensure: [File primClose: handle].
	self withoutLegacy: #('primPosition: h' 'primSize: h' 'primSeek: h to: pos' 'primFlush: h'
		'primRead: h into: bytes startingAt: start count: count') do: [
		self assert: (File ffiCandidatePrimPosition: handle) isNil.
		self assert: (File ffiCandidatePrimSize: handle) isNil.
		self assert: (File ffiCandidatePrimSeek: handle to: 0) isNil.
		self assert: (File ffiCandidatePrimFlush: handle) isNil.
		self assert: (File ffiCandidatePrimRead: handle into: (ByteArray new: 1) startingAt: 1 count: 1) isNil]
!
testCountedPathsAndAtomicStat
	| root raw escaped target absent nul stat sub fifo handle |
	root := self scratchDirectory.
	raw := (root, '/b') utf8Encoded , #[16rFF 16rED 16rA0 16r80 16rC3 16rA9].
	escaped := root / (String withAll: (#(98 16rDCFF 16rDCED 16rDCA0 16rDC80 16rE9)
		collect: [:code | Character value: code])).
	target := root / 'renamed'.
	absent := root / 'missing'.
	nul := target utf8Encoded , #[0 98].
	sub := root / 'newdir'.
	fifo := root / 'pipe'.
	self assert: (File ffiCandidatePrimOpen: nul mode: 3) isNil.
	self deny: (File exists: target).
	self withoutLegacy: #('primOpen: path mode: mode' 'primDelete: path' 'primRename: from to: to'
		'primStat: path' 'primDirCreate: path' 'primMkfifo: path') do: [
		self assert: (File ffiCandidatePrimOpen: absent mode: 0) isNil.
		self assert: (File ffiCandidatePrimOpen: absent mode: -1) isNil.
		handle := File ffiCandidatePrimOpen: raw mode: 16r100000004.
		self deny: handle isNil.
		[self assert: (File primWrite: handle from: #[10 20 30] startingAt: 1 count: 3) equals: 3]
			ensure: [File primClose: handle].
		self assert: (File ffiCandidatePrimRename: escaped to: target) identicalTo: File.
		self assert: (File ffiCandidatePrimRename: absent to: target) isNil.
		stat := File ffiCandidatePrimStat: target.
		self assert: (stat first: 3) equals: #(true false 3).
		self assert: stat fourth > 0.
		self assert: (File ffiCandidatePrimStat: escaped) equals: #(false false 0 0).
		self assert: (File ffiCandidatePrimDirCreate: sub) identicalTo: File.
		self assert: (File ffiCandidatePrimDirCreate: sub) isNil.
		self assert: ((File ffiCandidatePrimStat: sub) first: 2) equals: #(true true).
		self assert: (File ffiCandidatePrimMkfifo: fifo) identicalTo: File.
		self assert: ((File ffiCandidatePrimStat: fifo) first: 2) equals: #(true false).
		self assert: (File ffiCandidatePrimDelete: target) identicalTo: File.
		self assert: (File ffiCandidatePrimDelete: sub) identicalTo: File.
		self assert: (File ffiCandidatePrimDelete: fifo) identicalTo: File.
		self assert: (File ffiCandidatePrimDelete: absent) isNil]
!
testOwnedNamesAndCwd
	| root raw name expected cwd empty |
	root := self scratchDirectory.
	empty := root / 'empty'.
	Directory create: empty.
	raw := (root, '/b') utf8Encoded , #[16rFF 16rED 16rA0 16r80 16rC3 16rA9].
	name := String withAll: (#(98 16rDCFF 16rDCED 16rDCA0 16rDC80 16rE9)
		collect: [:code | Character value: code]).
	File writeBytes: #[9] to: raw.
	expected := File primDirEntries: root.
	cwd := File primCwd.
	self withoutLegacy: #('primDirEntries: path' 'primCwd') do: [
		"More than the native table can hold: each candidate must release its own observation."
		20 timesRepeat: [
			self assert: (File ffiCandidatePrimDirEntries: root) asSortedCollection asArray
				equals: expected asSortedCollection asArray.
			self assert: (File ffiCandidatePrimCwd) equals: cwd].
		self assert: (File ffiCandidatePrimDirEntries: empty) equals: #().
		self assert: (File ffiCandidatePrimDirEntries: root / 'missing') isNil.
		self assert: ((File ffiCandidatePrimDirEntries: root) includes: name)]
!
testOwnedNamesObservationAndRelease
	| path root raw open size copy release receipt ticket bytes |
	root := self scratchDirectory.
	path := root / 'first'.
	File writeBytes: #[1] to: path.
	raw := root utf8Encoded.
	open := FFI bind: #(call 'platform' 'platform_files_dir_entries' (bytesWithLength writableBytesWithLength) i32).
	size := FFI bind: #(call 'platform' 'platform_files_name_size' (u64 u32) i64).
	copy := FFI bind: #(call 'platform' 'platform_files_name_copy' (u64 u32 writableBytesWithLength) i32).
	release := FFI bind: #(call 'platform' 'platform_files_name_release' (u64) i32).
	receipt := ByteArray new: 12.
	[
		self assert: (open tryInvoke2: {raw. 1. raw size} with: {receipt. 1. 12}) equals: 1.
		ticket := FFIWire uint64At: 1 in: receipt.
		self assert: (FFIWire uint32At: 9 in: receipt) equals: 1.
		self assert: (open tryInvoke2: {raw. 1. raw size} with: {receipt. 1. 12}) equals: 0.
		File rename: path to: root / 'other'.
		self assert: (size tryInvoke2: ticket with: 0) equals: 5.
		self assert: (size tryInvoke2: ticket with: 1) equals: -1.
		bytes := ByteArray new: 7 withAll: 255.
		self assert: (copy tryInvoke3: ticket with: 0 with: {bytes. 2. 4}) equals: 0.
		self assert: bytes equals: #[255 255 255 255 255 255 255].
		self assert: (copy tryInvoke3: ticket with: 0 with: {bytes. 2. 5}) equals: 1.
		self assert: bytes equals: #[255 102 105 114 115 116 255]
	] ensure: [
		ticket := FFIWire uint64At: 1 in: receipt.
		ticket = 0 ifFalse: [self assert: (release tryInvoke1: ticket) equals: 1]].
	self assert: (release tryInvoke1: ticket) equals: 0.
	self assert: (size tryInvoke2: ticket with: 0) equals: -1
!
testOwnedNamesReleaseOnTermination
	| path open size ticket worker ready held |
	path := self scratchDirectory utf8Encoded.
	open := FFI bind: #(call 'platform' 'platform_files_dir_entries' (bytesWithLength writableBytesWithLength) i32).
	size := FFI bind: #(call 'platform' 'platform_files_name_size' (u64 u32) i64).
	ready := Semaphore new.
	held := Semaphore new.
	File writeBytes: #[1] to: self scratchDirectory / 'test'.
	worker := self fork: [
		File captureNames: [:receipt |
			(open tryInvoke2: {path. 1. path size} with: receipt) = 1
				ifFalse: [self error: 'Could not capture directory'].
			ticket := FFIWire uint64At: 1 in: receipt first.
			ready signal.
			held wait.
			1]].
	self assert: (ready waitTimeoutMSecs: 2000) not.
	self assert: (size tryInvoke2: ticket with: 0) equals: 4.
	worker terminate.
	self assert: (size tryInvoke2: ticket with: 0) equals: -1
! !
