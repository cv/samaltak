Object subclass: #TextHighlighter
	instanceVariableNames: 'buffer enabled methodMode types starts stops depths'
	classVariableNames: ''
	package: 'UI-Widgets'!

TextHighlighter comment: 'I highlight a TextBuffer''s Smalltalk source with the Compiler''s Scanner: tokens (type, 1-based start and stop) computed lazily, and after an edit rescanned only from the last token before it until they agree with the old ones again. styledRunsFrom:to:color:do: answers runs of neighbouring tokens with the same {font. color} (Theme syntaxStyleFor:); in methodMode the first line is styled as a method pattern.

	(TextHighlighter on: (TextBuffer string: ''^self'')) tokens   "#(#(#return 1 1) #(#self 2 5))"'!

!TextHighlighter methodsFor: 'initialization'!
initialize
	enabled := true.
	methodMode := false
!
buffer: aTextBuffer
	"Highlight aTextBuffer and follow its changes."
	buffer := aTextBuffer.
	types := nil.
	aTextBuffer addListener: self
! !

!TextHighlighter methodsFor: 'accessing'!
theme
	^Theme current
!
isEnabled
	^enabled
!
enabled: aBoolean
	enabled := aBoolean.
	types := nil
!
methodMode: aBoolean
	methodMode := aBoolean
!
isActive
	"Whether I have tokens to draw (enabled and computed by ensureTokens)."
	^types notNil
!
tokenTypes
	"The token types, a new Array whenever the tokens changed (nil when not computed)."
	^types
! !

!TextHighlighter methodsFor: 'buffer changes'!
textReset
	types := nil
!
textReplacedFrom: start to: stop with: aString
	"Re-highlight after the characters start + 1 .. stop became aString: rescan from the last token ending before the change (outside literal arrays) until the tokens agree with the old ones again."
	| delta k0 base newTypes newStarts newStops newDepths j oldStops n resynced editEnd text |
	types isNil ifTrue: [^self].
	text := buffer string.
	delta := aString size - (stop - start).
	n := types size.
	k0 := (self firstTokenEndingAtOrAfter: start) - 1.
	[k0 > 0 and: [(depths at: k0) ~= 0]] whileTrue: [k0 := k0 - 1].
	base := k0 = 0 ifTrue: [0] ifFalse: [stops at: k0].
	newTypes := OrderedCollection new.
	newStarts := OrderedCollection new.
	newStops := OrderedCollection new.
	newDepths := OrderedCollection new.
	editEnd := start + aString size.
	oldStops := stops.
	j := k0 + 1.
	[j <= n and: [(starts at: j) <= stop]] whileTrue: [j := j + 1].
	resynced := false.
	self scan: (text copyFrom: base + 1 to: text size) from: base types: newTypes starts: newStarts stops: newStops depths: newDepths
		until: [:type :s :e :d |
			s > editEnd and: [
				[j <= n and: [(starts at: j) + delta < s]] whileTrue: [j := j + 1].
				(j <= n and: [(starts at: j) + delta = s and: [(oldStops at: j) + delta = e
					and: [(types at: j) == type and: [(depths at: j) = d]]]])
					ifTrue: [resynced := true]
					ifFalse: [false]]].
	resynced ifFalse: [j := n + 1].
	types := (types copyFrom: 1 to: k0) , newTypes asArray , (types copyFrom: j to: n).
	depths := (depths copyFrom: 1 to: k0) , newDepths asArray , (depths copyFrom: j to: n).
	starts := (starts copyFrom: 1 to: k0) , newStarts asArray , ((starts copyFrom: j to: n) collect: [:x | x + delta]).
	stops := (oldStops copyFrom: 1 to: k0) , newStops asArray , ((oldStops copyFrom: j to: n) collect: [:x | x + delta])
! !

!TextHighlighter methodsFor: 'tokens'!
ensureTokens
	| text t s e d |
	(types notNil or: [enabled not]) ifTrue: [^self].
	text := buffer string.
	t := OrderedCollection new: text size // 4 + 4.
	s := OrderedCollection new: text size // 4 + 4.
	e := OrderedCollection new: text size // 4 + 4.
	d := OrderedCollection new: text size // 4 + 4.
	self scan: text from: 0 types: t starts: s stops: e depths: d until: nil.
	types := t asArray.
	starts := s asArray.
	stops := e asArray.
	depths := d asArray
!
scan: aString from: base types: typeList starts: startList stops: stopList depths: depthList until: aBlock
	"Highlight aString (the text after the gap position base) into the collections; depths get the literal-array depth after each token. aBlock (type start stop depth, absolute positions) may answer true to stop."
	| depth |
	depth := 0.
	Scanner highlight: aString do: [:type :start :stop |
		type == #literalArrayStart
			ifTrue: [depth := depth + 1]
			ifFalse: [
				(depth > 0 and: [type == #punctuation and: [')]' includes: (aString at: start)]])
					ifTrue: [depth := depth - 1]].
		(aBlock notNil and: [aBlock value: type value: start + base value: stop + base value: depth])
			ifTrue: [^self].
		typeList add: type.
		startList add: start + base.
		stopList add: stop + base.
		depthList add: depth]
!
tokens
	"The highlight tokens as {type. start. stop} triples (1-based character indices)."
	self ensureTokens.
	types isNil ifTrue: [^#()].
	^(1 to: types size) collect: [:i | Array with: (types at: i) with: (starts at: i) with: (stops at: i)]
!
tokenTypeAt: anIndex
	"The highlight type of the character at anIndex (1-based), or nil for white space."
	| i |
	self ensureTokens.
	types isNil ifTrue: [^nil].
	i := self firstTokenEndingAtOrAfter: anIndex.
	(i <= types size and: [(starts at: i) <= anIndex]) ifTrue: [^types at: i].
	^nil
!
firstTokenEndingAtOrAfter: anIndex
	"Binary search over the token stops."
	| lo hi mid |
	lo := 1.
	hi := stops size + 1.
	[lo < hi] whileTrue: [
		mid := lo + hi // 2.
		(stops at: mid) < anIndex ifTrue: [lo := mid + 1] ifFalse: [hi := mid]].
	^lo
! !

!TextHighlighter methodsFor: 'styling'!
styleFor: aType at: anIndex
	(methodMode and: [aType ~~ #comment and: [anIndex <= (buffer lineEndAt: 1)]]) ifTrue: [^self theme syntaxStyleFor: #pattern].
	^self theme syntaxStyleFor: aType
!
styledRunsFrom: rs to: re color: forced do: aBlock
	"Evaluate aBlock with the gap positions, font and color of each run of the tokens touching the characters rs + 1 .. re (clipped to them); neighbouring tokens of the same style form one run, the white space between included. A non-nil forced color replaces the tokens' colors. Requires isActive."
	| n k runStart runStop runFont runColor |
	n := types size.
	k := self firstTokenEndingAtOrAfter: rs + 1.
	runStart := nil.
	[k <= n and: [(starts at: k) - 1 < re]] whileTrue: [
		| a b style f c |
		a := (starts at: k) - 1 max: rs.
		b := (stops at: k) min: re.
		style := self styleFor: (types at: k) at: a + 1.
		f := style at: 1.
		c := forced ifNil: [style at: 2].
		(runStart notNil and: [f == runFont and: [c == runColor]])
			ifTrue: [runStop := b]
			ifFalse: [
				runStart isNil ifFalse: [aBlock value: runStart value: runStop value: runFont value: runColor].
				runStart := a.
				runStop := b.
				runFont := f.
				runColor := c].
		k := k + 1].
	runStart isNil ifFalse: [aBlock value: runStart value: runStop value: runFont value: runColor]
! !

!TextHighlighter class methodsFor: 'instance creation'!
on: aTextBuffer
	^self new buffer: aTextBuffer; yourself
! !
