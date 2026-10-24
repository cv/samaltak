Object subclass: #GlyphAtlas
	instanceVariableNames: 'pages pageSize lock'
	classVariableNames: 'Default'
	package: 'Graphics-Canvas'!

GlyphAtlas comment: 'I store rasterized glyphs (8-bit coverage at device resolution) in square pages (GlyphAtlasPage), packed in shelves; when a page is full I open another. All standard fonts share "GlyphAtlas default", so text in different fonts batches together. Entries are never moved or evicted: texture coordinates recorded in a DisplayList stay valid.'!

!GlyphAtlas methodsFor: 'initialization'!
setPageSize: anInteger
	pageSize := anInteger.
	pages := OrderedCollection new.
	lock := Mutex new
! !

!GlyphAtlas methodsFor: 'accessing'!
pages
	^pages
!
pageSize
	^pageSize
! !

!GlyphAtlas methodsFor: 'adding'!
add: coverage width: w height: h
	"Store a w×h coverage ByteArray; answer {page. x. y} (0-based pixel position). Window Processes rasterize concurrently: one at a time allocates and stores."
	(w > pageSize or: [h > pageSize]) ifTrue: [^self error: 'Glyph larger than an atlas page'].
	^lock critical: [self primAdd: coverage width: w height: h]
!
primAdd: coverage width: w height: h
	| position page |
	pages isEmpty ifFalse: [
		page := pages last.
		position := page allocateWidth: w height: h].
	position isNil ifTrue: [
		page := GlyphAtlasPage size: pageSize.
		pages add: page.
		position := page allocateWidth: w height: h].
	page store: coverage width: w height: h at: position.
	^Array with: page with: position x with: position y
! !

!GlyphAtlas class methodsFor: 'instance creation'!
pageSize: anInteger
	^self new setPageSize: anInteger
! !

!GlyphAtlas class methodsFor: 'accessing'!
default
	^Default ifNil: [Default := self pageSize: 2048]
!
reset
	"Forget all glyphs (fonts must drop their caches too: see Font class>>resetGlyphs)."
	Default := nil
! !
