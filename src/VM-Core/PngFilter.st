VMModule subclass: #PngFilter
	instanceVariableNames: 'libc rows'
	classVariableNames: ''
	package: 'VM-Core'!

PngFilter comment: 'PNG''s row filtering for the core_png_filter export (FFIPrimitives>>nativePngFilter:..., PNGWriter class>>filtered:width:height:channels:), bit for bit what PNGWriter''s Smalltalk does: each row of an RGBA image packed to n channels (3 drops alpha, 4 keeps it) and filtered with the first of None, Sub, Up, Average and Paeth whose output has the smallest sum of magnitudes as signed bytes, its type byte before it. In place and without scratch memory: the rows are packed into their places in raw and filtered from the bottom up, each from the end to the start, since a row''s output needs only its own bytes to the left and the row above as they were (packed, not yet filtered). The bytes after a row''s first pixel go 16 at a time (rows, PngRows: NEON or SSE2), the rest and the first row (which has none above) one by one here.'!

!PngFilter class methodsFor: 'declaring'!
declarations
	^#((libc LibC) (rows PngRows))
! !

!PngFilter methodsFor: 'filtering'!
filterPng: rgba width: w height: h channels: n into: raw
	"raw := the PNG rows of rgba (w * h pixels of 4 bytes): for each row its filter type byte, then its w * n filtered bytes. w >= 1, h >= 1, n 3 or 4; raw has (w * n + 1) * h bytes and does not overlap rgba."
	<function>
	<var: #rgba type: 'uint8_t *'>
	<var: #raw type: 'uint8_t *'>
	<var: #w type: 'int64_t'>
	<var: #h type: 'int64_t'>
	<var: #n type: 'int64_t'>
	| stride y row prior |
	stride := w * n.
	self pack: rgba + ((h - 1) * w * 4) width: w channels: n into: raw + ((h - 1) * (stride + 1)) + 1.
	y := h - 1.
	[y >= 0] whileTrue: [
		row := raw + (y * (stride + 1)).
		prior := self cCoerce: self null to: 'uint8_t *'.
		y > 0 ifTrue: [
			prior := row - stride.
			self pack: rgba + ((y - 1) * w * 4) width: w channels: n into: prior].
		row at: 0 put: (self filterRow: row + 1 prior: prior stride: stride channels: n).
		y := y - 1]
!
pack: s width: w channels: n into: d
	"d[0 .. w * n) := the w pixels at s, alpha dropped if n is 3."
	<function>
	<var: #s type: 'uint8_t *'>
	<var: #d type: 'uint8_t *'>
	<var: #w type: 'int64_t'>
	<var: #n type: 'int64_t'>
	n = 4 ifTrue: [
		libc memcpy: d from: s size: (w * 4) asUInt64.
		^self].
	0 to: w - 1 do: [:x |
		d at: x * 3 put: (s at: x * 4).
		d at: x * 3 + 1 put: (s at: x * 4 + 1).
		d at: x * 3 + 2 put: (s at: x * 4 + 2)]
!
filterRow: r prior: q stride: stride channels: n
	"Filter the stride bytes at r in place with the filter of the smallest cost (the first of the cheapest), q the row above (null for the first row); answer the filter, 0 to 4."
	<function>
	<var: #r type: 'uint8_t *'>
	<var: #q type: 'uint8_t *'>
	<var: #stride type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<returns: 'uint8_t'>
	| sums k best |
	sums := self local: 'uint64_t[5]'.
	k := 0.
	q notNull ifTrue: [k := rows costs: r + n prior: q + n count: stride - n channels: n into: sums].
	self addCosts: r prior: q count: stride - k channels: n into: sums.
	best := 0.
	1 to: 4 do: [:f | (sums at: f) < (sums at: best) ifTrue: [best := f]].
	best = 0 ifTrue: [^0].
	k := 0.
	q notNull ifTrue: [k := rows apply: best to: r + n prior: q + n count: stride - n channels: n].
	self applyFilter: best to: r prior: q count: stride - k channels: n.
	^best asUInt8
!
addCosts: r prior: q count: e channels: n into: sums
	"sums[f] := sums[f] + the cost of filter f over r[0 .. e)."
	<function>
	<var: #r type: 'uint8_t *'>
	<var: #q type: 'uint8_t *'>
	<var: #e type: 'int64_t'>
	<var: #n type: 'int64_t'>
	<var: #sums type: 'uint64_t *'>
	| x a b c |
	0 to: e - 1 do: [:i |
		x := (r at: i) asInt32.
		a := i >= n ifTrue: [(r at: i - n) asInt32] ifFalse: [0].
		b := q notNull ifTrue: [(q at: i) asInt32] ifFalse: [0].
		c := (i >= n and: [q notNull]) ifTrue: [(q at: i - n) asInt32] ifFalse: [0].
		sums at: 0 put: (sums at: 0) + (self costOf: x).
		1 to: 4 do: [:f | sums at: f put: (sums at: f) + (self costOf: x - (self predictor: f left: a up: b upLeft: c))]]
!
applyFilter: f to: r prior: q count: e channels: n
	"r[i] := filter f''s output for i < e, from the end (q the row above, null for the first row)."
	<function>
	<var: #f type: 'int64_t'>
	<var: #r type: 'uint8_t *'>
	<var: #q type: 'uint8_t *'>
	<var: #e type: 'int64_t'>
	<var: #n type: 'int64_t'>
	| i x a b c |
	i := e - 1.
	[i >= 0] whileTrue: [
		x := (r at: i) asInt32.
		a := i >= n ifTrue: [(r at: i - n) asInt32] ifFalse: [0].
		b := q notNull ifTrue: [(q at: i) asInt32] ifFalse: [0].
		c := (i >= n and: [q notNull]) ifTrue: [(q at: i - n) asInt32] ifFalse: [0].
		r at: i put: (x - (self predictor: f left: a up: b upLeft: c) bitAnd: 255).
		i := i - 1]
!
predictor: f left: a up: b upLeft: c
	"What filter f (0 None, 1 Sub, 2 Up, 3 Average, 4 Paeth) subtracts from a byte."
	f = 1 ifTrue: [^a].
	f = 2 ifTrue: [^b].
	f = 3 ifTrue: [^a + b >> 1].
	f = 4 ifTrue: [^self paeth: a with: b with: c].
	^0
!
paeth: a with: b with: c
	"a, b or c, whichever is nearest a + b - c (ties: a, then b)."
	| pa pb pc |
	pa := self magnitude: b - c.
	pb := self magnitude: a - c.
	pc := self magnitude: a + b - c - c.
	(pa <= pb and: [pa <= pc]) ifTrue: [^a].
	pb <= pc ifTrue: [^b].
	^c
!
magnitude: v
	^v < 0 ifTrue: [0 - v] ifFalse: [v]
!
costOf: v
	"The byte v (modulo 256) read as a signed byte, its magnitude."
	| u |
	u := v bitAnd: 255.
	^u < 128 ifTrue: [u] ifFalse: [256 - u]
! !
