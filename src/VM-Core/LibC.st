CLibrary subclass: #LibC
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

LibC comment: 'The C standard library functions the VM calls (stdio, stdlib, string). The method bodies simulate them for VMSimulation; stdout and stderr go to the simulation''s streams.'!

!LibC class methodsFor: 'declaring'!
headers
	^#('<stdio.h>' '<stdlib.h>' '<string.h>')
!
typedefs
	^#((FILE opaque))
! !

!LibC methodsFor: 'stdio'!
stdout
	<cVariable: 'FILE *stdout'>
	^sim stdoutFile
!
stderr
	<cVariable: 'FILE *stderr'>
	^sim stderrFile
!
fileFor: aFile
	(aFile isKindOf: SimulatedFile) ifTrue: [^aFile].
	^self memory objectAt: (self memory addressOf: aFile)
!
streamFor: aFile
	^(self fileFor: aFile) stream
!
format: aFormat arguments: anArray
	^CFormatter format: (self memory stringAt: aFormat) arguments: anArray memory: self memory
!
printf: fmt
	<c: 'int printf(const char *fmt, ...)'>
	^self fprintf: sim stdoutFile format: fmt
!
printf: fmt with: a
	<c: 'int printf(const char *fmt, ...)'>
	^self fprintf: sim stdoutFile format: fmt with: a
!
printf: fmt with: a with: b
	<c: 'int printf(const char *fmt, ...)'>
	^self fprintf: sim stdoutFile format: fmt with: a with: b
!
printf: fmt with: a with: b with: c
	<c: 'int printf(const char *fmt, ...)'>
	^self fprintf: sim stdoutFile format: fmt with: a with: b with: c
!
fprintf: f format: fmt
	<c: 'int fprintf(FILE *f, const char *fmt, ...)'>
	^self write: (self format: fmt arguments: #()) to: f
!
fprintf: f format: fmt with: a
	<c: 'int fprintf(FILE *f, const char *fmt, ...)'>
	^self write: (self format: fmt arguments: {a}) to: f
!
fprintf: f format: fmt with: a with: b
	<c: 'int fprintf(FILE *f, const char *fmt, ...)'>
	^self write: (self format: fmt arguments: {a. b}) to: f
!
fprintf: f format: fmt with: a with: b with: c
	<c: 'int fprintf(FILE *f, const char *fmt, ...)'>
	^self write: (self format: fmt arguments: {a. b. c}) to: f
!
fprintf: f format: fmt with: a with: b with: c with: d
	<c: 'int fprintf(FILE *f, const char *fmt, ...)'>
	^self write: (self format: fmt arguments: {a. b. c. d}) to: f
!
snprintf: buf size: n format: fmt with: a
	<c: 'int snprintf(char *buf, size_t n, const char *fmt, ...)'>
	^self store: (self format: fmt arguments: {a}) in: buf size: n
!
snprintf: buf size: n format: fmt with: a with: b
	<c: 'int snprintf(char *buf, size_t n, const char *fmt, ...)'>
	^self store: (self format: fmt arguments: {a. b}) in: buf size: n
!
snprintf: buf size: n format: fmt with: a with: b with: c
	<c: 'int snprintf(char *buf, size_t n, const char *fmt, ...)'>
	^self store: (self format: fmt arguments: {a. b. c}) in: buf size: n
!
store: aString in: buf size: n
	"snprintf's output: at most n - 1 bytes and a NUL; answer the full length."
	| bytes a |
	bytes := aString utf8Encoded.
	a := self memory addressOf: buf.
	n > 0 ifTrue: [
		self memory bytesAt: a put: (bytes first: (bytes size min: n - 1)).
		self memory uint8At: a + (bytes size min: n - 1) put: 0].
	^bytes size
!
write: aString to: f
	(self streamFor: f) nextPutAll: aString.
	^aString utf8Encoded size
!
fputs: s to: f
	<c: 'int fputs(const char *s, FILE *f)'>
	self write: (self memory stringAt: s) to: f.
	^0
!
fputc: c to: f
	<c: 'int fputc(int c, FILE *f)'>
	(self streamFor: f) nextPut: (Character value: c).
	^c
!
fflush: f
	<c: 'int fflush(FILE *f)'>
	^0
! !

!LibC methodsFor: 'files'!
fopen: path mode: mode
	<c: 'FILE *fopen(const char *path, const char *mode)'>
	| p m f |
	p := self memory stringAt: path.
	m := self memory stringAt: mode.
	f := [(m includes: $w)
		ifTrue: [FileStream newFileNamed: p]
		ifFalse: [FileStream readOnlyFileNamed: p]] on: Error do: [:e | e return: nil].
	f isNil ifTrue: [^CPointer null].
	f binary.
	^self memory pointerTo: (CTypeRegistry default at: 'FILE') at: (self memory registerObject: (SimulatedFile name: p stream: f))
!
fread: buf size: size count: n file: f
	<c: 'size_t fread(void *buf, size_t size, size_t n, FILE *f)'>
	| bytes |
	bytes := (self streamFor: f) next: size * n.
	self memory bytesAt: (self memory addressOf: buf) put: bytes asByteArray.
	^bytes size // size
!
fwrite: buf size: size count: n file: f
	<c: 'size_t fwrite(const void *buf, size_t size, size_t n, FILE *f)'>
	(self streamFor: f) nextPutAll: (self memory bytesAt: (self memory addressOf: buf) count: size * n).
	^n
!
fseek: f offset: offset whence: whence
	<c: 'int fseek(FILE *f, long offset, int whence)'>
	(self streamFor: f) position: offset.
	^0
!
fclose: f
	<c: 'int fclose(FILE *f)'>
	(self streamFor: f) close.
	self memory forgetObject: (self fileFor: f).
	^0
!
SEEK_SET
	<cMacro: 'int SEEK_SET'>
	^0
! !

!LibC methodsFor: 'memory'!
malloc: n
	<c: 'void *malloc(size_t n)'>
	^self memory pointerTo: CVoidType new at: (self memory allocate: n)
!
calloc: count size: n
	<c: 'void *calloc(size_t count, size_t n)'>
	^self memory pointerTo: CVoidType new at: (self memory allocate: count * n)
!
realloc: p size: n
	<c: 'void *realloc(void *p, size_t n)'>
	^self memory pointerTo: CVoidType new at: (self memory reallocate: (self memory addressOf: p) size: n)
!
free: p
	<c: 'void free(void *p)'>
	self memory free: (self memory addressOf: p)
!
memcpy: dst from: src size: n
	<c: 'void *memcpy(void *dst, const void *src, size_t n)'>
	self memory copy: n from: (self memory addressOf: src) to: (self memory addressOf: dst).
	^dst
!
memmove: dst from: src size: n
	<c: 'void *memmove(void *dst, const void *src, size_t n)'>
	self memory copy: n from: (self memory addressOf: src) to: (self memory addressOf: dst).
	^dst
!
memset: dst value: c size: n
	<c: 'void *memset(void *dst, int c, size_t n)'>
	self memory fill: (self memory addressOf: dst) with: (c bitAnd: 255) count: n.
	^dst
!
memcmp: a with: b size: n
	<c: 'int memcmp(const void *a, const void *b, size_t n)'>
	^self memory compare: (self memory addressOf: a) with: (self memory addressOf: b) count: n
!
strlen: s
	<c: 'size_t strlen(const char *s)'>
	s isString ifTrue: [^s utf8Encoded size].
	^self memory cStringLengthAt: (self memory addressOf: s)
!
strcmp: a with: b
	<c: 'int strcmp(const char *a, const char *b)'>
	| x y |
	x := (self memory stringAt: a) utf8Encoded.
	y := (self memory stringAt: b) utf8Encoded.
	1 to: (x size min: y size) do: [:i | (x at: i) = (y at: i) ifFalse: [^(x at: i) - (y at: i)]].
	^x size - y size
!
atol: s
	<c: 'long atol(const char *s)'>
	^self parseInteger: (self memory stringAt: s)
!
atoi: s
	<c: 'int atoi(const char *s)'>
	^(self parseInteger: (self memory stringAt: s)) asInt32
!
parseInteger: aString
	"As atol: leading white space, an optional sign, then digits up to the first non-digit."
	| in negative v |
	in := ReadStream on: aString.
	[in atEnd not and: [in peek isSeparator]] whileTrue: [in next].
	negative := false.
	(in atEnd not and: [in peek = $- or: [in peek = $+]]) ifTrue: [negative := in next = $-].
	v := 0.
	[in atEnd not and: [in peek isDigit]] whileTrue: [v := v * 10 + in next digitValue].
	^negative ifTrue: [v negated] ifFalse: [v]
!
strdup: s
	<c: 'char *strdup(const char *s)'>
	^self memory pointerTo: (CTypeRegistry default at: 'char') at: (self memory newCString: (self memory stringAt: s))
! !

!LibC methodsFor: 'process'!
exit: status
	<c: 'void exit(int status)'>
	<noreturn>
	^sim exit: status
!
abort
	<c: 'void abort(void)'>
	<noreturn>
	^sim exit: 134
!
getenv: name
	<c: 'char *getenv(const char *name)'>
	| v |
	v := sim environment at: (self memory stringAt: name) ifAbsent: [^CPointer null].
	^self memory pointerTo: (CTypeRegistry default at: 'char') at: (self memory cStringFor: v)
! !
