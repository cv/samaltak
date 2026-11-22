VMModule subclass: #DeflateMatcher
	instanceVariableNames: 'search'
	classVariableNames: ''
	package: 'VM-Core'!

DeflateMatcher comment: 'ZLib''s hot loops for the zlibMatches and zlibAdler32 primitives (ObjectPrimitives), token for token and bit for bit what ZLib''s Smalltalk does (ZLib>>matchesFrom:, ZLib class>>adler32Of:). matches: is the LZ77 of a deflate block: positions are 1-based, the hash chains head (by the hash of three bytes) and prev (by position modulo 32768) uint32 each, 0 for none; greedy, at most chain candidates a position, nearer than 32768; the bytes a match covers are hashed if it is at most 16 long. A token is a literal (its byte) or 256 + a match''s length with its distance, uint16 each. Matches are measured 16 bytes at a time (ByteSearch>>mismatchOf:with:from:size:). Nothing is read outside the input: a candidate is a position before the current one, whatever the chains hold.'!

!DeflateMatcher class methodsFor: 'declaring'!
declarations
	^#((search ByteSearch))
! !

!DeflateMatcher methodsFor: 'deflate'!
hashAt: p in: input
	"The hash (0 .. 32767) of the three bytes at the 1-based position p."
	^((((input at: p - 1) asInt64 << 7) bitXor: ((input at: p) asInt64 << 4)) bitXor: (input at: p + 1) asInt64) asInt64
!
matches: input size: n from: start head: head prev: prev literals: lits distances: dists max: maxTokens chain: maxChain
	"Tokens of the input from the 1-based start until maxTokens are made or the input ends; answer the position after them times 65536 plus their count."
	<function>
	<var: #input type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<var: #start type: 'int64_t'>
	<var: #head type: 'uint32_t *'>
	<var: #prev type: 'uint32_t *'>
	<var: #lits type: 'uint16_t *'>
	<var: #dists type: 'uint16_t *'>
	<var: #maxTokens type: 'int64_t'>
	<var: #maxChain type: 'int64_t'>
	<returns: 'int64_t'>
	| pos count best bestDistance hash candidate limit chain length last |
	pos := start.
	count := 0.
	[pos <= n and: [count < maxTokens]] whileTrue: [
		best := 0.
		bestDistance := 0.
		pos + 2 <= n ifTrue: [
			hash := self hashAt: pos in: input.
			candidate := (head at: hash) asInt64.
			prev at: (pos bitAnd: 32767) put: candidate asUInt32.
			head at: hash put: pos asUInt32.
			limit := n - pos + 1.
			limit > 258 ifTrue: [limit := 258].
			chain := maxChain.
			[candidate > 0 and: [candidate < pos and: [chain > 0 and: [pos - candidate < 32768]]]] whileTrue: [
				(input at: candidate + best - 1) = (input at: pos + best - 1) ifTrue: [
					length := search mismatchOf: input + candidate - 1 with: input + pos - 1 from: 0 size: limit.
					length > best ifTrue: [
						best := length.
						bestDistance := pos - candidate.
						best = limit ifTrue: [chain := 1]]].
				candidate := (prev at: (candidate bitAnd: 32767)) asInt64.
				chain := chain - 1]].
		best >= 3
			ifTrue: [
				lits at: count put: (256 + best) asUInt16.
				dists at: count put: bestDistance asUInt16.
				best <= 16 ifTrue: [
					last := pos + best - 1.
					last > (n - 2) ifTrue: [last := n - 2].
					pos + 1 to: last do: [:p |
						hash := self hashAt: p in: input.
						prev at: (p bitAnd: 32767) put: (head at: hash).
						head at: hash put: p asUInt32]].
				pos := pos + best]
			ifFalse: [
				lits at: count put: (input at: pos - 1) asUInt16.
				dists at: count put: 0.
				pos := pos + 1].
		count := count + 1].
	^(pos << 16) + count
!
adler32: p size: n
	"The Adler-32 of the n bytes at p: the sums reduced modulo 65521 every 5552 bytes, which they cannot overflow before."
	<function>
	<var: #p type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'uint32_t'>
	| a b i stop |
	a := 1 asUInt32.
	b := 0 asUInt32.
	i := 0.
	[i < n] whileTrue: [
		stop := i + 5552.
		stop > n ifTrue: [stop := n].
		[i + 4 <= stop] whileTrue: [
			a := a + (p at: i).
			b := b + a.
			a := a + (p at: i + 1).
			b := b + a.
			a := a + (p at: i + 2).
			b := b + a.
			a := a + (p at: i + 3).
			b := b + a.
			i := i + 4].
		[i < stop] whileTrue: [
			a := a + (p at: i).
			b := b + a.
			i := i + 1].
		a := a rem: 65521.
		b := b rem: 65521].
	^((b asUInt64 << 16) bitOr: a asUInt64) asUInt32
! !
