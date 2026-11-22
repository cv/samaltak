Object subclass: #RfbZStream
	instanceVariableNames: 'started coder'
	classVariableNames: ''
	package: 'System-Remote'!

RfbZStream comment: 'I am the zlib stream of an RFB connection''s ZRLE rectangles (RFC 6143, 7.7.6): one stream for the whole session, which the viewer inflates as it comes; each rectangle''s data ends byte-aligned (a sync flush) so that the viewer can decode it before the next arrives. The zlib header goes out once, with the first rectangle; the stream never ends (no final block, no Adler-32).

Where ZLib can deflate a stream (deflate:final:, png-neon/rfb-prep''s streaming, which ends each call byte-aligned) I use it; else I write stored blocks (uncompressed, at most 65535 bytes each): a valid stream at 1.00x, so ZRLE''s own tile coding (solid, palette, runs) is all the compression.'!

!RfbZStream methodsFor: 'deflating'!
deflate: bytes
	"The next piece of the stream: bytes compressed and flushed to a byte boundary (with the zlib header the first time)."
	| out body |
	out := WriteStream on: (ByteArray new: bytes size + (bytes size // 65535 + 1 * 5) + 2).
	started == true ifFalse: [
		started := true.
		out nextPut: 16r78; nextPut: 16r01].
	body := self streamingDeflate: bytes.
	body isNil
		ifTrue: [self stored: bytes on: out]
		ifFalse: [out nextPutAll: body].
	^out contents
! !

!RfbZStream methodsFor: 'private'!
streamingDeflate: bytes
	"ZLib's streaming deflate (non-final blocks and a sync flush, its window kept across calls), or nil where ZLib has none."
	coder isNil ifTrue: [
		((Smalltalk at: #ZLib) canUnderstand: #deflate:final:) ifFalse: [^nil].
		coder := (Smalltalk at: #ZLib) new].
	^coder deflate: bytes final: false
!
stored: bytes on: out
	"Stored blocks, not final: 00, LEN, NLEN (little-endian), the bytes; byte-aligned by their nature."
	| start |
	start := 1.
	[| n |
	 n := bytes size - start + 1 min: 65535.
	 out nextPut: 0.
	 out nextPut: (n bitAnd: 255); nextPut: (n bitShift: -8).
	 out nextPut: 255 - (n bitAnd: 255); nextPut: 255 - (n bitShift: -8).
	 n > 0 ifTrue: [out nextPutAll: (bytes copyFrom: start to: start + n - 1)].
	 start := start + n.
	 start <= bytes size] whileTrue
! !
