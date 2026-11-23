TestCase subclass: #NvGspLayoutTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-NV'!

NvGspLayoutTest comment: 'Tests NvGsp''s declarations of the GSP boot and RPC structures against the C compiler: NvGspLayouts holds sizeof and every offsetof and member size from NVIDIA''s 580.178.04 headers (tools/nv-gsp-layouts.sh), and each must be NvLayout''s, byte for byte; the constants too. Also NvLayout''s C rules on small cases. Needs no GPU.'!

!NvGspLayoutTest methodsFor: 'tests'!
testEveryStructureAsTheCompilerLaysItOut
	NvGspLayouts layouts do: [:entry | | layout |
		layout := NvGsp layout: entry first.
		self assert: layout size = (entry at: 2) description: [entry first, ' size ', layout size printString].
		(entry at: 3) do: [:field |
			self assert: (layout includes: field first) description: entry first, ' has ', field first.
			self assert: (layout offsetOf: field first) = (field at: 2) description: [entry first, '.', field first, ' offset ', (layout offsetOf: field first) printString].
			self assert: (layout sizeOf: field first) = (field at: 3) description: [entry first, '.', field first, ' size ', (layout sizeOf: field first) printString]]].
	self assert: (NvGspLayouts layouts collect: [:entry | entry first]) asSet equals: NvGsp layouts keys asSet
!
testConstantsAsTheHeadersDefineThem
	NvGspLayouts constants do: [:pair |
		self assert: (NvGsp constant: pair first) = pair last description: pair first].
	self assert: (NvGspLayouts constants collect: [:pair | pair first]) asSet equals: NvGsp constants keys asSet
!
testCRules
	| l |
	l := NvLayout named: 'x' declaration: #(('a' #u8) ('b' #u32) ('c' #u16) ('d' #u64) ('e' #bool)).
	self assert: (#('a' 'b' 'c' 'd' 'e') collect: [:f | l offsetOf: f]) equals: #(0 4 8 16 24).
	self assert: l size equals: 32.
	l := NvLayout named: 'x' declaration: #(('a' #u8) ('b' #u32) ('c' #u64)) packed: true.
	self assert: (#('a' 'b' 'c') collect: [:f | l offsetOf: f]) equals: #(0 1 5).
	self assert: l size equals: 13.
	l := NvLayout named: 'x' declaration: #(('a' #u32) ('s' (#struct (('p' #u8) ('q' #u64)))) (nil (#union ('u' #u16) ('v' (#array #u8 3)))) ('w' (#array #u8 0))).
	self assert: (l offsetOf: 's.q') equals: 16.
	self assert: (l sizeOf: 's') equals: 16.
	self assert: (l offsetOf: 'u') equals: 24.
	self assert: (l offsetOf: 'v') equals: 24.
	self assert: (l offsetOf: 'w') equals: 28.
	self assert: l size equals: 32
! !
