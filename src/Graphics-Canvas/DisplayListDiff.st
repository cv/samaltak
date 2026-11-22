Object subclass: #DisplayListDiff
	instanceVariableNames: 'region quadLimit stableSurfaces scratch oldList oldFirst oldRuns newList newFirst newRuns changed'
	classVariableNames: ''
	package: 'Graphics-Canvas'!

DisplayListDiff comment: 'I find where two drawings of the same target differ, as damage (a DamageRegion of device pixels): the quads of one DisplayList range that the other does not draw the same, in the same place and order, with the same texture, clip and move. Damage-limited rendering then draws only there (Renderer>>render:into:clear:commandBuffer:within:), with identical pixels.

Quads are compared by their vertex bytes, 64 quads at a time (a copy into scratch ByteArrays and the stringCompare primitive, which compares any two byte objects), narrowed down by halves where they differ. The equal quads at the start and at the end are skipped; if what is left has as many quads in both, they are compared place by place (a scrolled list, recolored text, a moved pointer: only the quads that differ damage their old and new bounds), otherwise every quad left damages its bounds in its list (text appended in the middle of a transcript). More than quadLimit (512) such quads: the whole target is damaged instead (drawing it whole is cheaper then than bounding them).

A quad''s texture counts by identity and, for a Form, its version at the time its list was drawn (stampsOf:, kept with the list): a Form changed in place damages every quad that shows it (glyphs and images; a solid quad batched with them does not sample it). A Surface''s pixels can change without anything in the list saying so: its quads are always damaged, unless stableSurfaces (the compositor: its layers'' surfaces report their own damage).

	| d |
	d := DisplayListDiff region: (DamageRegion extent: 800 @ 600).
	d diff: oldList stamps: (DisplayListDiff stampsOf: oldList) to: newList stamps: (DisplayListDiff stampsOf: newList).
	d region rects'!

!DisplayListDiff methodsFor: 'initialization'!
setRegion: aDamageRegion
	region := aDamageRegion.
	quadLimit := 512.
	stableSurfaces := false.
	scratch := Dictionary new
! !

!DisplayListDiff methodsFor: 'accessing'!
region
	^region
!
region: aDamageRegion
	"Damage into aDamageRegion from now on (my scratch buffers stay)."
	region := aDamageRegion
!
quadLimit: anInteger
	quadLimit := anInteger
!
stableSurfaces: aBoolean
	stableSurfaces := aBoolean
! !

!DisplayListDiff methodsFor: 'diffing'!
diff: anOldList stamps: oldStamps to: aNewList stamps: newStamps
	"Damage where aNewList draws differently from anOldList (nil: nothing was drawn)."
	^self diff: anOldList stamps: oldStamps from: 0 count: (anOldList isNil ifTrue: [0] ifFalse: [anOldList quadCount])
		to: aNewList stamps: newStamps from: 0 count: (aNewList isNil ifTrue: [0] ifFalse: [aNewList quadCount])
!
diff: anOldList stamps: oldStamps from: oq count: on to: aNewList stamps: newStamps from: nq count: nn
	"Damage where quads nq .. nq + nn - 1 of aNewList draw differently from quads oq .. oq + on - 1 of anOldList."
	| prefix suffix mo mn |
	region isFull ifTrue: [^self].
	oldList := anOldList. oldFirst := oq. oldRuns := self runsOf: anOldList stamps: oldStamps from: oq count: on.
	newList := aNewList. newFirst := nq. newRuns := self runsOf: aNewList stamps: newStamps from: nq count: nn.
	changed := 0.
	prefix := self prefixUpTo: (on min: nn).
	suffix := self suffixOf: on and: nn upTo: (on min: nn) - prefix.
	mo := on - prefix - suffix.
	mn := nn - prefix - suffix.
	(mo = mn and: [mo > 0]) ifTrue: [^self comparePlacesFrom: prefix count: mo].
	mo + mn > quadLimit ifTrue: [^region beFull].
	self damage: mo quadsOf: oldList runs: oldRuns first: oldFirst from: prefix.
	self damage: mn quadsOf: newList runs: newRuns first: newFirst from: prefix
!
damageAll: aList stamps: stamps from: q count: n
	"Damage the bounds of quads q .. q + n - 1 of aList (drawn or gone)."
	| runs |
	region isFull ifTrue: [^self].
	n > quadLimit ifTrue: [^region beFull].
	runs := self runsOf: aList stamps: stamps from: q count: n.
	changed := 0.
	self damage: n quadsOf: aList runs: runs first: q from: 0
!
boundsOf: aList from: q count: n into: aDamageRegion
	"Add the bounds of quads q .. q + n - 1 of aList (each, merged) to aDamageRegion."
	| saved |
	saved := region.
	region := aDamageRegion.
	[self damageAll: aList stamps: nil from: q count: n] ensure: [region := saved]
! !

!DisplayListDiff methodsFor: 'private'!
runsOf: aList stamps: stamps from: q count: n
	"The batches drawing quads q .. q + n - 1 of aList: {first. end (quads, relative to q). batch. stamp} each."
	| runs end |
	runs := OrderedCollection new.
	(aList isNil or: [n = 0]) ifTrue: [^runs].
	end := q + n.
	aList batches doWithIndex: [:b :i | | s e |
		s := b first // 6 max: q.
		e := b first + b count // 6 min: end.
		s < e ifTrue: [
			runs add: (Array with: s - q with: e - q with: b with: (stamps isNil ifTrue: [self class stampOf: b texture] ifFalse: [stamps at: i]))]].
	^runs
!
run: a matches: b
	"How the quads of runs a and b compare: #same (equal bytes draw alike), #untextured (only those that do not sample the texture do: it is another, or changed), nil (none: another clip or move)."
	| ba bb t |
	ba := a at: 3.
	bb := b at: 3.
	(ba dx = bb dx and: [ba dy = bb dy and: [ba scissor = bb scissor]]) ifFalse: [^nil].
	t := ba texture.
	t == bb texture ifFalse: [^#untextured].
	(stableSurfaces not and: [t isKindOf: Surface]) ifTrue: [^#untextured].
	(a at: 4) = (b at: 4) ifFalse: [^#untextured].
	^#same
!
samples: aByteArray quad: q
	"Whether quad q (0-based, absolute) of these vertex bytes samples the texture: a glyph or an image."
	| mode |
	mode := (aByteArray uint32At: q * 240 + 29) bitAnd: 16r7FFFFFFF.
	^mode = 1 or: [mode = 2]
!
sameUntextured: i
	"Whether quad i (relative) of both lists is equal and samples no texture."
	^(self equal: oldList vertices at: oldFirst + i * 240 with: newList vertices at: newFirst + i * 240 bytes: 240)
		and: [(self samples: newList vertices quad: newFirst + i) not]
!
runIn: runs at: i from: start
	"The index of the run of runs holding quad i (relative), searching from start; 0 if none."
	| k |
	k := start max: 1.
	[k <= runs size and: [((runs at: k) at: 2) <= i]] whileTrue: [k := k + 1].
	(k <= runs size and: [(runs at: k) first <= i]) ifTrue: [^k].
	^0
!
prefixUpTo: max
	"How many quads at the start are drawn alike (at most max)."
	| i a b ro rn span k m |
	i := 0. a := 1. b := 1.
	[i < max] whileTrue: [
		a := self runIn: oldRuns at: i from: a.
		b := self runIn: newRuns at: i from: b.
		(a = 0 or: [b = 0]) ifTrue: [^i].
		ro := oldRuns at: a.
		rn := newRuns at: b.
		m := self run: ro matches: rn.
		m isNil ifTrue: [^i].
		span := ((ro at: 2) min: (rn at: 2)) - i min: max - i.
		k := m == #same
			ifTrue: [self firstMismatchIn: oldList vertices at: oldFirst + i * 240 with: newList vertices at: newFirst + i * 240 quads: span]
			ifFalse: [| e | e := 0. [e < span and: [self sameUntextured: i + e]] whileTrue: [e := e + 1]. e].
		i := i + k.
		k < span ifTrue: [^i]].
	^i
!
suffixOf: on and: nn upTo: max
	"How many quads at the end are drawn alike (at most max)."
	| j a b ro rn io in span k m |
	j := 0. a := oldRuns size. b := newRuns size.
	[j < max] whileTrue: [
		io := on - j.
		in := nn - j.
		[a >= 1 and: [(oldRuns at: a) first >= io]] whileTrue: [a := a - 1].
		[b >= 1 and: [(newRuns at: b) first >= in]] whileTrue: [b := b - 1].
		(a < 1 or: [b < 1]) ifTrue: [^j].
		ro := oldRuns at: a.
		rn := newRuns at: b.
		((ro at: 2) < io or: [(rn at: 2) < in]) ifTrue: [^j].
		m := self run: ro matches: rn.
		m isNil ifTrue: [^j].
		span := (io - ro first min: in - rn first) min: max - j.
		k := m == #same
			ifTrue: [self equalQuadsBefore: oldFirst + io * 240 in: oldList vertices and: newFirst + in * 240 in: newList vertices quads: span]
			ifFalse: [| e |
				e := 0.
				[e < span and: [(self equal: oldList vertices at: oldFirst + io - e - 1 * 240 with: newList vertices at: newFirst + in - e - 1 * 240 bytes: 240)
					and: [(self samples: newList vertices quad: newFirst + in - e - 1) not]]] whileTrue: [e := e + 1].
				e].
		j := j + k.
		k < span ifTrue: [^j]].
	^j
!
comparePlacesFrom: start count: n
	"Quads start .. start + n - 1 of both lists, place by place: those that differ damage their old and new bounds."
	| i end a b ro rn span m |
	i := start.
	end := start + n.
	a := b := 1.
	[i < end] whileTrue: [
		a := self runIn: oldRuns at: i from: a.
		b := self runIn: newRuns at: i from: b.
		(a = 0 or: [b = 0])
			ifTrue: [
				self damageQuad: i side: true; damageQuad: i side: false.
				i := i + 1]
			ifFalse: [
				ro := oldRuns at: a.
				rn := newRuns at: b.
				span := (((ro at: 2) min: (rn at: 2)) min: end) - i.
				m := self run: ro matches: rn.
				m == #same ifTrue: [self compareSpanFrom: i count: span].
				m == #untextured ifTrue: [
					i to: i + span - 1 do: [:q | (self sameUntextured: q) ifFalse: [self damageQuad: q side: true; damageQuad: q side: false]]].
				m isNil ifTrue: [i to: i + span - 1 do: [:q | self damageQuad: q side: true; damageQuad: q side: false]].
				i := i + span].
		region isFull ifTrue: [^self]]
!
compareSpanFrom: start count: n
	"Quads alike in texture, clip and move: compare their bytes 16 at a time, then one by one."
	| i c ov nv |
	ov := oldList vertices.
	nv := newList vertices.
	i := start.
	[i < (start + n)] whileTrue: [
		c := 16 min: start + n - i.
		(self equal: ov at: oldFirst + i * 240 with: nv at: newFirst + i * 240 bytes: c * 240)
			ifFalse: [
				i to: i + c - 1 do: [:q |
					(self equal: ov at: oldFirst + q * 240 with: nv at: newFirst + q * 240 bytes: 240)
						ifFalse: [self damageQuad: q side: true; damageQuad: q side: false]].
				region isFull ifTrue: [^self]].
		i := i + c]
!
damageQuad: i side: isOld
	"Damage the bounds of quad i (relative) of the old or the new list."
	| runs k |
	changed := changed + 1.
	changed > quadLimit ifTrue: [^region beFull].
	runs := isOld ifTrue: [oldRuns] ifFalse: [newRuns].
	k := self runIn: runs at: i from: 1.
	k = 0 ifTrue: [^self].
	self damageQuad: (isOld ifTrue: [oldFirst] ifFalse: [newFirst]) + i of: (isOld ifTrue: [oldList] ifFalse: [newList]) batch: ((runs at: k) at: 3)
!
damage: n quadsOf: aList runs: runs first: q from: start
	"Damage the bounds of quads start .. start + n - 1 (relative to q) of aList."
	| k i end |
	n = 0 ifTrue: [^self].
	k := 1.
	i := start.
	end := start + n.
	[i < end] whileTrue: [
		k := self runIn: runs at: i from: k.
		k = 0
			ifTrue: [i := i + 1]
			ifFalse: [| r stop |
				r := runs at: k.
				stop := (r at: 2) min: end.
				i to: stop - 1 do: [:j | self damageQuad: q + j of: aList batch: (r at: 3)].
				i := stop].
		region isFull ifTrue: [^self]]
!
damageQuad: q of: aList batch: aBatch
	"Damage the device-pixel bounds of quad q of aList, moved by its batch and within its clip."
	| v p mode x0 y0 x1 y1 s |
	v := aList vertices.
	p := q * 240 + 1.
	mode := v uint32At: p + 28.
	(mode bitAnd: 16r80000000) = 0
		ifTrue: [| ox oy |
			ox := (v float32At: p + 32) + aBatch dx.
			oy := (v float32At: p + 36) + aBatch dy.
			x0 := (v float32At: p) + ox.
			y0 := (v float32At: p + 4) + oy.
			x1 := (v float32At: p + 8) + ox.
			y1 := (v float32At: p + 12) + oy]
		ifFalse: [
			x0 := y0 := 1.0e30.
			x1 := y1 := -1.0e30.
			0 to: 5 do: [:k | | r x y |
				r := p + (k * 40).
				x := (v float32At: r) + (v float32At: r + 32) + aBatch dx.
				y := (v float32At: r + 4) + (v float32At: r + 36) + aBatch dy.
				x0 := x0 min: x. y0 := y0 min: y. x1 := x1 max: x. y1 := y1 max: y].
			x0 := x0 - 1. y0 := y0 - 1. x1 := x1 + 1. y1 := y1 + 1].
	s := aBatch scissor.
	s isNil ifFalse: [
		x0 := x0 max: (s at: 1).
		y0 := y0 max: (s at: 2).
		x1 := x1 min: (s at: 1) + (s at: 3).
		y1 := y1 min: (s at: 2) + (s at: 4)].
	region addLeft: x0 top: y0 right: x1 bottom: y1
!
firstMismatchIn: a at: ao with: b at: bo quads: n
	"The first of n quads (bytes from 0-based ao in a, bo in b) that differ; n if none does."
	| i c |
	i := 0.
	[i < n] whileTrue: [
		c := self chunkFor: n - i.
		(self equal: a at: ao + (i * 240) with: b at: bo + (i * 240) bytes: c * 240)
			ifTrue: [i := i + c]
			ifFalse: [
				[c > 1] whileTrue: [
					c := c // 2.
					(self equal: a at: ao + (i * 240) with: b at: bo + (i * 240) bytes: c * 240) ifTrue: [i := i + c]].
				^i]].
	^n
!
equalQuadsBefore: ao in: a and: bo in: b quads: n
	"How many of the n quads before the 0-based byte offsets ao in a and bo in b are equal, counted from there backwards."
	| j c |
	j := 0.
	[j < n] whileTrue: [
		c := self chunkFor: n - j.
		(self equal: a at: ao - ((j + c) * 240) with: b at: bo - ((j + c) * 240) bytes: c * 240)
			ifTrue: [j := j + c]
			ifFalse: [
				[c > 1] whileTrue: [
					c := c // 2.
					(self equal: a at: ao - ((j + c) * 240) with: b at: bo - ((j + c) * 240) bytes: c * 240) ifTrue: [j := j + c]].
				^j]].
	^n
!
chunkFor: n
	"The largest power of two up to 64 and n."
	| c |
	c := 64.
	[c > n] whileTrue: [c := c // 2].
	^c
!
equal: a at: ao with: b at: bo bytes: n
	"Whether the n bytes of a from 0-based offset ao are those of b from bo."
	| pair x y |
	(a == b and: [ao = bo]) ifTrue: [^true].
	pair := scratch at: n ifAbsent: [scratch at: n put: (Array with: (ByteArray new: n) with: (ByteArray new: n))].
	x := pair first.
	y := pair last.
	x replaceFrom: 1 to: n with: a startingAt: ao + 1.
	y replaceFrom: 1 to: n with: b startingAt: bo + 1.
	^(x compareBytes: y) = 0
! !

!DisplayListDiff class methodsFor: 'instance creation'!
region: aDamageRegion
	^self new setRegion: aDamageRegion
! !

!DisplayListDiff class methodsFor: 'stamps'!
stampOf: aTexture
	"What a quad's texture shows besides its identity: a Form's version (it changes in place); nil for the rest."
	(aTexture notNil and: [aTexture isKindOf: Form]) ifTrue: [^aTexture version].
	^nil
!
stampsOf: aDisplayListOrNil
	"The stamps of aDisplayList's batches' textures now (keep them with the list for a later diff)."
	aDisplayListOrNil isNil ifTrue: [^#()].
	^aDisplayListOrNil batches collect: [:b | self stampOf: b texture]
! !
