UefiModule subclass: #UefiLibC
	instanceVariableNames: 'files consoleBuffer consoleUsed store'
	classVariableNames: 'UEFI_CONSOLE_BUFFER UEFI_FILES UEFI_FILE_CONSOLE UEFI_FILE_DISK UEFI_FILE_FREE UEFI_FILE_STORE'
	package: 'VM-UEFI'!

UefiLibC comment: 'The C library functions the core calls (LibC), on UEFI. stdout and stderr are the console (a line at a time, UTF-8 to UCS-2); fopen of disk: is the image in UefiImageStore (read: the newest slot, write: the other); fopen of any other path opens a file on the volume the VM was loaded from, relative to its root ("w" replaces a file: UEFI cannot truncate). malloc is the firmware''s pool, 16-byte aligned. printf and friends take their variadic arguments as 64-bit words (varargBits:) and format them with format:args:into:size: (d i u x X o c s p e f g, flags, width, precision, length modifiers); doubles by UefiLibM>>formatDouble:precision:conversion:into:size:.'!

!UefiLibC class methodsFor: 'declaring'!
declarations
	^#((files 'UefiFile[UEFI_FILES]') (consoleBuffer 'char[UEFI_CONSOLE_BUFFER]') (consoleUsed int64_t) (store UefiImageStore))
!
replaces
	^LibC
!
typedefs
	^#((FILE opaque))
!
initialize
	UEFI_FILES := 16.
	UEFI_FILE_FREE := 0.
	UEFI_FILE_CONSOLE := 1.
	UEFI_FILE_DISK := 2.
	UEFI_FILE_STORE := 3.
	UEFI_CONSOLE_BUFFER := 1024
! !

!UefiLibC methodsFor: 'starting'!
start
	"stdout and stderr: files 0 and 1."
	<function>
	(files at: 0) kind: UEFI_FILE_CONSOLE.
	(files at: 1) kind: UEFI_FILE_CONSOLE
! !

!UefiLibC methodsFor: 'stdio'!
stdout
	^self cCoerce: (files at: 0) to: 'FILE *'
!
stderr
	^self cCoerce: (files at: 1) to: 'FILE *'
!
SEEK_SET
	^0
!
printf: fmt
	^self vfprintf: self stdout format: fmt args: self null
!
printf: fmt with: a
	| args |
	args := self local: 'uint64_t[1]'.
	args at: 0 put: (self varargBits: a).
	^self vfprintf: self stdout format: fmt args: args
!
printf: fmt with: a with: b
	| args |
	args := self local: 'uint64_t[2]'.
	args at: 0 put: (self varargBits: a).
	args at: 1 put: (self varargBits: b).
	^self vfprintf: self stdout format: fmt args: args
!
printf: fmt with: a with: b with: c
	| args |
	args := self local: 'uint64_t[3]'.
	args at: 0 put: (self varargBits: a).
	args at: 1 put: (self varargBits: b).
	args at: 2 put: (self varargBits: c).
	^self vfprintf: self stdout format: fmt args: args
!
fprintf: f format: fmt
	^self vfprintf: f format: fmt args: self null
!
fprintf: f format: fmt with: a
	| args |
	args := self local: 'uint64_t[1]'.
	args at: 0 put: (self varargBits: a).
	^self vfprintf: f format: fmt args: args
!
fprintf: f format: fmt with: a with: b
	| args |
	args := self local: 'uint64_t[2]'.
	args at: 0 put: (self varargBits: a).
	args at: 1 put: (self varargBits: b).
	^self vfprintf: f format: fmt args: args
!
fprintf: f format: fmt with: a with: b with: c
	| args |
	args := self local: 'uint64_t[3]'.
	args at: 0 put: (self varargBits: a).
	args at: 1 put: (self varargBits: b).
	args at: 2 put: (self varargBits: c).
	^self vfprintf: f format: fmt args: args
!
fprintf: f format: fmt with: a with: b with: c with: d
	| args |
	args := self local: 'uint64_t[4]'.
	args at: 0 put: (self varargBits: a).
	args at: 1 put: (self varargBits: b).
	args at: 2 put: (self varargBits: c).
	args at: 3 put: (self varargBits: d).
	^self vfprintf: f format: fmt args: args
!
snprintf: buf size: n format: fmt with: a
	| args |
	args := self local: 'uint64_t[1]'.
	args at: 0 put: (self varargBits: a).
	^(self format: fmt args: args into: buf size: n asInt64) asInt32
!
snprintf: buf size: n format: fmt with: a with: b
	| args |
	args := self local: 'uint64_t[2]'.
	args at: 0 put: (self varargBits: a).
	args at: 1 put: (self varargBits: b).
	^(self format: fmt args: args into: buf size: n asInt64) asInt32
!
snprintf: buf size: n format: fmt with: a with: b with: c
	| args |
	args := self local: 'uint64_t[3]'.
	args at: 0 put: (self varargBits: a).
	args at: 1 put: (self varargBits: b).
	args at: 2 put: (self varargBits: c).
	^(self format: fmt args: args into: buf size: n asInt64) asInt32
!
vfprintf: f format: fmt args: args
	"Format into a buffer, then write it (at most 4095 bytes)."
	<function>
	<var: #f type: 'FILE *'>
	<var: #fmt type: 'const char *'>
	<var: #args type: 'uint64_t *'>
	<returns: 'int'>
	| buf n |
	buf := self local: 'char[4096]'.
	n := self format: fmt args: args into: buf size: 4096.
	n > 4095 ifTrue: [n := 4095].
	self write: buf count: n asUInt64 to: f.
	^n asInt32
!
fputs: s to: f
	<function>
	<var: #s type: 'const char *'>
	<var: #f type: 'FILE *'>
	<returns: 'int'>
	self write: s count: (self strlen: s) to: f.
	^0
!
fputc: c to: f
	<function>
	<var: #c type: 'int'>
	<var: #f type: 'FILE *'>
	<returns: 'int'>
	| b |
	b := self local: 'char'.
	b value: c.
	self write: b count: 1 to: f.
	^c
!
fflush: f
	<function>
	<var: #f type: 'FILE *'>
	<returns: 'int'>
	(f isNull or: [(self fileOf: f) kind = UEFI_FILE_CONSOLE]) ifTrue: [self consoleFlush].
	^0
!
fileOf: f
	^self cCoerce: f to: 'UefiFile *'
! !

!UefiLibC methodsFor: 'files'!
fopen: path mode: mode
	"Read (r), replace (w) or append (a) a file of the boot volume; null if it cannot."
	<function>
	<var: #path type: 'const char *'>
	<var: #mode type: 'const char *'>
	<returns: 'FILE *'>
	| slot name handle status m |
	slot := -1.
	2 to: UEFI_FILES - 1 do: [:k | (slot < 0 and: [(files at: k) kind = UEFI_FILE_FREE]) ifTrue: [slot := k]].
	slot < 0 ifTrue: [^self null].
	(self strcmp: path with: 'disk:') = 0 ifTrue: [
		((mode at: 0) = $r value
			ifTrue: [store openForReading]
			ifFalse: [(mode at: 0) = $w value and: [store openForWriting]]) ifFalse: [^self null].
		(files at: slot) kind: UEFI_FILE_STORE.
		^self cCoerce: (files at: slot) to: 'FILE *'].
	firmware root isNull ifTrue: [^self null].
	name := self local: 'uint16_t[512]'.
	(self ucs2Path: path into: name size: 512) ifFalse: [^self null].
	handle := self local: 'EfiFile *'.
	m := mode at: 0.
	m = $r value ifTrue: [
		status := self efi: firmware root open with: firmware root with: handle with: name with: EFI_FILE_MODE_READ with: 0].
	m = $w value ifTrue: [
		status := self efi: firmware root open with: firmware root with: handle with: name with: (EFI_FILE_MODE_READ bitOr: EFI_FILE_MODE_WRITE) with: 0.
		(self efiFailed: status) ifFalse: [self efi: handle value delete with: handle value].
		status := self efi: firmware root open with: firmware root with: handle with: name
			with: ((EFI_FILE_MODE_READ bitOr: EFI_FILE_MODE_WRITE) bitOr: EFI_FILE_MODE_CREATE) with: 0].
	m = $a value ifTrue: [
		status := self efi: firmware root open with: firmware root with: handle with: name
			with: ((EFI_FILE_MODE_READ bitOr: EFI_FILE_MODE_WRITE) bitOr: EFI_FILE_MODE_CREATE) with: 0.
		(self efiFailed: status) ifFalse: [self efi: handle value setPosition with: handle value with: 16rFFFFFFFFFFFFFFFF]].
	((m = $r value or: [m = $w value or: [m = $a value]]) not or: [self efiFailed: status]) ifTrue: [^self null].
	(files at: slot) kind: UEFI_FILE_DISK.
	(files at: slot) handle: handle value.
	^self cCoerce: (files at: slot) to: 'FILE *'
!
ucs2Path: path into: name size: n
	"path (UTF-8, / or \ separated, relative to the root) as a UCS-2 EFI file name; false if it does not fit."
	<function>
	<var: #path type: 'const char *'>
	<var: #name type: 'uint16_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'bool'>
	| i o c |
	i := 0.
	[(path at: i) = $/ value or: [(path at: i) = $\ value]] whileTrue: [i := i + 1].
	o := 0.
	[(path at: i) ~= 0] whileTrue: [
		o >= (n - 1) ifTrue: [^false].
		c := (path at: i) asUInt8.
		c = $/ value ifTrue: [c := $\ value].
		name at: o put: c.
		o := o + 1.
		i := i + 1].
	name at: o put: 0.
	^true
!
fread: buf size: size count: n file: f
	<function>
	<var: #buf type: 'void *'>
	<var: #size type: 'size_t'>
	<var: #n type: 'size_t'>
	<var: #f type: 'FILE *'>
	<returns: 'size_t'>
	| file want got |
	file := self fileOf: f.
	size = 0 ifTrue: [^0].
	file kind = UEFI_FILE_STORE ifTrue: [^(store read: (self cCoerce: buf to: 'uint8_t *') count: size * n) quo: size].
	file kind ~= UEFI_FILE_DISK ifTrue: [^0].
	want := size * n.
	got := self local: 'uint64_t'.
	got value: want.
	(self efiFailed: (self efi: file handle read with: file handle with: got with: buf)) ifTrue: [^0].
	^got value quo: size
!
fwrite: buf size: size count: n file: f
	<function>
	<var: #buf type: 'const void *'>
	<var: #size type: 'size_t'>
	<var: #n type: 'size_t'>
	<var: #f type: 'FILE *'>
	<returns: 'size_t'>
	size = 0 ifTrue: [^0].
	^(self write: buf count: size * n to: f) quo: size
!
write: buf count: n to: f
	"Answer how many bytes were written."
	<function>
	<var: #buf type: 'const void *'>
	<var: #n type: 'uint64_t'>
	<var: #f type: 'FILE *'>
	<returns: 'uint64_t'>
	| file bytes done |
	file := self fileOf: f.
	file kind = UEFI_FILE_CONSOLE ifTrue: [
		bytes := self cCoerce: buf to: 'const char *'.
		0 to: (n asInt64) - 1 do: [:i |
			consoleUsed >= (UEFI_CONSOLE_BUFFER - 1) ifTrue: [self consoleFlush].
			consoleBuffer at: consoleUsed put: (bytes at: i).
			consoleUsed := consoleUsed + 1.
			(bytes at: i) = 10 ifTrue: [self consoleFlush]].
		^n].
	file kind = UEFI_FILE_STORE ifTrue: [^store write: (self cCoerce: buf to: 'const uint8_t *') count: n].
	file kind ~= UEFI_FILE_DISK ifTrue: [^0].
	done := self local: 'uint64_t'.
	done value: n.
	(self efiFailed: (self efi: file handle write with: file handle with: done with: buf)) ifTrue: [^0].
	^done value
!
fseek: f offset: offset whence: whence
	"SEEK_SET only."
	<function>
	<var: #f type: 'FILE *'>
	<var: #offset type: 'long'>
	<var: #whence type: 'int'>
	<returns: 'int'>
	| file |
	file := self fileOf: f.
	whence ~= 0 ifTrue: [^-1].
	file kind = UEFI_FILE_STORE ifTrue: [^(store seek: offset asUInt64) ifTrue: [0] ifFalse: [-1]].
	file kind ~= UEFI_FILE_DISK ifTrue: [^-1].
	(self efiFailed: (self efi: file handle setPosition with: file handle with: offset)) ifTrue: [^-1].
	^0
!
fclose: f
	<function>
	<var: #f type: 'FILE *'>
	<returns: 'int'>
	| file |
	file := self fileOf: f.
	file kind = UEFI_FILE_STORE ifTrue: [
		file kind: UEFI_FILE_FREE.
		^store close ifTrue: [0] ifFalse: [-1]].
	file kind ~= UEFI_FILE_DISK ifTrue: [^0].
	self efi: file handle flush with: file handle.
	self efi: file handle close with: file handle.
	file kind: UEFI_FILE_FREE.
	^0
! !

!UefiLibC methodsFor: 'console'!
consoleFlush
	"The console buffer (UTF-8) to the serial port, else to the firmware's console (UCS-2, CR LF) unless the VM draws on the screen."
	<function>
	| out i o c n |
	consoleUsed = 0 ifTrue: [^self].
	(firmware writeConsole: consoleBuffer count: consoleUsed) ifTrue: [
		consoleUsed := 0.
		^self].
	firmware isScreenOwned ifTrue: [
		consoleUsed := 0.
		^self].
	out := self local: 'uint16_t[2050]'.
	i := 0.
	o := 0.
	[i < consoleUsed] whileTrue: [
		c := (consoleBuffer at: i) asUInt8 asInt64.
		n := 1.
		c >= 16rC0 ifTrue: [
			c >= 16rE0
				ifTrue: [
					c >= 16rF0
						ifTrue: [c := 16rFFFD. n := 4]
						ifFalse: [
							n := 3.
							c := (c bitAnd: 15) << 12.
							i + 2 < consoleUsed ifTrue: [
								c := (c bitOr: (((consoleBuffer at: i + 1) asUInt8 asInt64 bitAnd: 63) << 6)) bitOr: ((consoleBuffer at: i + 2) asUInt8 asInt64 bitAnd: 63)]]]
				ifFalse: [
					n := 2.
					c := (c bitAnd: 31) << 6.
					i + 1 < consoleUsed ifTrue: [c := c bitOr: ((consoleBuffer at: i + 1) asUInt8 asInt64 bitAnd: 63)]]].
		(c >= 16r80 and: [n = 1]) ifTrue: [c := 16rFFFD].
		c = 10 ifTrue: [
			out at: o put: 13.
			o := o + 1].
		out at: o put: c.
		o := o + 1.
		i := i + n].
	out at: o put: 0.
	consoleUsed := 0.
	firmware outputString: out
! !

!UefiLibC methodsFor: 'formatting'!
format: fmt args: args into: out size: cap
	"C's vsnprintf over 64-bit argument words: at most cap - 1 characters and a NUL into out; answer the length of the whole."
	<function>
	<var: #fmt type: 'const char *'>
	<var: #args type: 'uint64_t *'>
	<var: #out type: 'char *'>
	<var: #cap type: 'int64_t'>
	<returns: 'int64_t'>
	| i pos argi c left zero plus space width prec lng body bodyLen prefix prefixLen pad v mag neg s base upper k |
	body := self local: 'char[512]'.
	prefix := self local: 'char[4]'.
	i := 0.
	pos := 0.
	argi := 0.
	[(fmt at: i) ~= 0] whileTrue: [
		c := (fmt at: i) asInt64.
		i := i + 1.
		c ~= $% value
			ifTrue: [pos := self put: c into: out at: pos size: cap]
			ifFalse: [
				left := false.
				zero := false.
				plus := false.
				space := false.
				[(fmt at: i) = $- value or: [(fmt at: i) = $0 value or: [(fmt at: i) = $+ value or: [(fmt at: i) = $  value or: [(fmt at: i) = $# value]]]]] whileTrue: [
					(fmt at: i) = $- value ifTrue: [left := true].
					(fmt at: i) = $0 value ifTrue: [zero := true].
					(fmt at: i) = $+ value ifTrue: [plus := true].
					(fmt at: i) = $  value ifTrue: [space := true].
					i := i + 1].
				width := 0.
				(fmt at: i) = $* value
					ifTrue: [
						width := (args at: argi) asInt32 asInt64.
						argi := argi + 1.
						i := i + 1.
						width < 0 ifTrue: [left := true. width := width negated]]
					ifFalse: [
						[(fmt at: i) >= $0 value and: [(fmt at: i) <= $9 value]] whileTrue: [
							width := (width * 10) + ((fmt at: i) - $0 value).
							i := i + 1]].
				prec := -1.
				(fmt at: i) = $. value ifTrue: [
					i := i + 1.
					prec := 0.
					(fmt at: i) = $* value
						ifTrue: [
							prec := (args at: argi) asInt32 asInt64.
							argi := argi + 1.
							i := i + 1]
						ifFalse: [
							[(fmt at: i) >= $0 value and: [(fmt at: i) <= $9 value]] whileTrue: [
								prec := (prec * 10) + ((fmt at: i) - $0 value).
								i := i + 1]]].
				lng := 0.
				[(fmt at: i) = $l value or: [(fmt at: i) = $h value or: [(fmt at: i) = $z value or: [(fmt at: i) = $j value or: [(fmt at: i) = $t value or: [(fmt at: i) = $L value]]]]]] whileTrue: [
					((fmt at: i) = $h value) ifFalse: [lng := 1].
					i := i + 1].
				c := (fmt at: i) asInt64.
				c ~= 0 ifTrue: [i := i + 1].
				bodyLen := 0.
				prefixLen := 0.
				(c = $d value or: [c = $i value])
					ifTrue: [
						v := lng = 0 ifTrue: [(args at: argi) asInt32 asInt64] ifFalse: [(args at: argi) asInt64].
						argi := argi + 1.
						neg := v < 0.
						mag := neg ifTrue: [(0 asUInt64 - v asUInt64) asUInt64] ifFalse: [v asUInt64].
						bodyLen := self digitsOf: mag base: 10 upper: false precision: prec into: body.
						neg
							ifTrue: [prefix at: 0 put: $- value. prefixLen := 1]
							ifFalse: [
								plus ifTrue: [prefix at: 0 put: $+ value. prefixLen := 1].
								(plus not and: [space]) ifTrue: [prefix at: 0 put: $  value. prefixLen := 1]].
						prec >= 0 ifTrue: [zero := false]].
				(c = $u value or: [c = $x value or: [c = $X value or: [c = $o value]]]) ifTrue: [
					mag := lng = 0 ifTrue: [(args at: argi) asUInt32 asUInt64] ifFalse: [args at: argi].
					argi := argi + 1.
					base := c = $o value ifTrue: [8] ifFalse: [c = $u value ifTrue: [10] ifFalse: [16]].
					upper := c = $X value.
					bodyLen := self digitsOf: mag base: base upper: upper precision: prec into: body.
					prec >= 0 ifTrue: [zero := false]].
				c = $p value ifTrue: [
					mag := args at: argi.
					argi := argi + 1.
					prefix at: 0 put: $0 value.
					prefix at: 1 put: $x value.
					prefixLen := 2.
					bodyLen := self digitsOf: mag base: 16 upper: false precision: -1 into: body].
				c = $c value ifTrue: [
					body at: 0 put: (args at: argi) asUInt8.
					argi := argi + 1.
					bodyLen := 1].
				c = $s value ifTrue: [
					s := self cCoerce: (args at: argi) to: 'const char *'.
					argi := argi + 1.
					s isNull ifTrue: [s := '(null)'].
					k := 0.
					[(s at: k) ~= 0 and: [prec < 0 or: [k < prec]]] whileTrue: [k := k + 1].
					(left not and: [width > k]) ifTrue: [
						1 to: width - k do: [:j | pos := self put: $  value into: out at: pos size: cap]].
					0 to: k - 1 do: [:j | pos := self put: (s at: j) asInt64 into: out at: pos size: cap].
					(left and: [width > k]) ifTrue: [
						1 to: width - k do: [:j | pos := self put: $  value into: out at: pos size: cap]].
					width := 0].
				(c = $e value or: [c = $E value or: [c = $f value or: [c = $F value or: [c = $g value or: [c = $G value]]]]]) ifTrue: [
					bodyLen := (libm formatDouble: (self doubleFromBits: (args at: argi)) precision: prec asInt32 conversion: c asInt32 into: body size: 512) asInt64.
					argi := argi + 1.
					bodyLen > 511 ifTrue: [bodyLen := 511].
					(bodyLen > 0 and: [(body at: 0) ~= $- value]) ifTrue: [
						plus ifTrue: [prefix at: 0 put: $+ value. prefixLen := 1].
						(plus not and: [space]) ifTrue: [prefix at: 0 put: $  value. prefixLen := 1]].
					(bodyLen > 0 and: [(body at: 0) = $- value]) ifTrue: [
						prefix at: 0 put: $- value.
						prefixLen := 1.
						0 to: bodyLen - 2 do: [:j | body at: j put: (body at: j + 1)].
						bodyLen := bodyLen - 1].
					(bodyLen > 0 and: [((body at: 0) < $0 value) or: [(body at: 0) > $9 value]]) ifTrue: [zero := false]].
				c = $% value ifTrue: [
					body at: 0 put: $% value.
					bodyLen := 1].
				pad := width - prefixLen - bodyLen.
				(left not and: [zero not]) ifTrue: [1 to: pad do: [:j | pos := self put: $  value into: out at: pos size: cap]].
				0 to: prefixLen - 1 do: [:j | pos := self put: (prefix at: j) asInt64 into: out at: pos size: cap].
				(left not and: [zero]) ifTrue: [1 to: pad do: [:j | pos := self put: $0 value into: out at: pos size: cap]].
				0 to: bodyLen - 1 do: [:j | pos := self put: (body at: j) asInt64 into: out at: pos size: cap].
				left ifTrue: [1 to: pad do: [:j | pos := self put: $  value into: out at: pos size: cap]]]].
	cap > 0 ifTrue: [out at: (pos < cap ifTrue: [pos] ifFalse: [cap - 1]) put: 0].
	^pos
!
put: c into: out at: pos size: cap
	(pos < (cap - 1)) ifTrue: [out at: pos put: c].
	^pos + 1
!
digitsOf: mag base: base upper: upper precision: prec into: body
	"mag's digits in base, at least prec of them (C: precision 0 and value 0 print nothing); answer how many."
	<function>
	<var: #mag type: 'uint64_t'>
	<var: #base type: 'int64_t'>
	<var: #prec type: 'int64_t'>
	<var: #body type: 'char *'>
	<returns: 'int64_t'>
	| tmp n m d |
	tmp := self local: 'char[64]'.
	n := 0.
	m := mag.
	[m ~= 0] whileTrue: [
		d := (m rem: base asUInt64) asInt64.
		tmp at: n put: (d < 10 ifTrue: [$0 value + d] ifFalse: [(upper ifTrue: [$A value] ifFalse: [$a value]) + d - 10]).
		n := n + 1.
		m := m quo: base asUInt64].
	(n = 0 and: [prec ~= 0]) ifTrue: [
		tmp at: 0 put: $0 value.
		n := 1].
	[n < prec and: [n < 60]] whileTrue: [
		tmp at: n put: $0 value.
		n := n + 1].
	0 to: n - 1 do: [:k | body at: k put: (tmp at: n - 1 - k)].
	^n
! !

!UefiLibC methodsFor: 'memory'!
malloc: n
	"From the firmware's pool, 16-byte aligned: the pool's address and the size are the 16 bytes before."
	<function>
	<var: #n type: 'size_t'>
	<returns: 'void *'>
	| raw p |
	raw := self local: 'void *'.
	(self efiFailed: (self efi: self boot allocatePool with: EFI_LOADER_DATA with: n + 32 with: raw)) ifTrue: [^self null].
	p := ((self cCoerce: raw value to: 'uint64_t') + 32) bitClear: 15.
	self uint64At: p - 8 put: (self cCoerce: raw value to: 'uint64_t').
	self uint64At: p - 16 put: n.
	^self cCoerce: p to: 'void *'
!
calloc: count size: n
	<function>
	<var: #count type: 'size_t'>
	<var: #n type: 'size_t'>
	<returns: 'void *'>
	| p |
	p := self malloc: count * n.
	p notNull ifTrue: [self memset: p value: 0 size: count * n].
	^p
!
realloc: p size: n
	<function>
	<var: #p type: 'void *'>
	<var: #n type: 'size_t'>
	<returns: 'void *'>
	| q old |
	p isNull ifTrue: [^self malloc: n].
	q := self malloc: n.
	q isNull ifTrue: [^q].
	old := self uint64At: (self cCoerce: p to: 'uint64_t') - 16.
	self memcpy: q from: p size: (old < n ifTrue: [old] ifFalse: [n]).
	self free: p.
	^q
!
free: p
	<function>
	<var: #p type: 'void *'>
	p isNull ifTrue: [^self].
	self efi: self boot freePool with: (self uint64At: (self cCoerce: p to: 'uint64_t') - 8)
!
memcpy: dst from: src size: n
	"Eight bytes at a time, then the rest (the compiler's own calls of memcpy come here too)."
	<function>
	<var: #dst type: 'void *'>
	<var: #src type: 'const void *'>
	<var: #n type: 'size_t'>
	<returns: 'void *'>
	| d s i words |
	d := self cCoerce: dst to: 'uint64_t'.
	s := self cCoerce: src to: 'uint64_t'.
	words := n bitClear: 7.
	i := 0 asUInt64.
	[i < words] whileTrue: [
		self uint64At: d + i put: (self uint64At: s + i).
		i := i + 8].
	[i < n] whileTrue: [
		self uint8At: d + i put: (self uint8At: s + i).
		i := i + 1].
	^dst
!
memmove: dst from: src size: n
	<function>
	<var: #dst type: 'void *'>
	<var: #src type: 'const void *'>
	<var: #n type: 'size_t'>
	<returns: 'void *'>
	| d s i |
	d := self cCoerce: dst to: 'uint64_t'.
	s := self cCoerce: src to: 'uint64_t'.
	(d <= s or: [d >= (s + n)]) ifTrue: [^self memcpy: dst from: src size: n].
	i := n.
	[i >= 8] whileTrue: [
		i := i - 8.
		self uint64At: d + i put: (self uint64At: s + i)].
	[i > 0] whileTrue: [
		i := i - 1.
		self uint8At: d + i put: (self uint8At: s + i)].
	^dst
!
memset: dst value: c size: n
	<function>
	<var: #dst type: 'void *'>
	<var: #c type: 'int'>
	<var: #n type: 'size_t'>
	<returns: 'void *'>
	| d i words w |
	d := self cCoerce: dst to: 'uint64_t'.
	w := (c bitAnd: 255) asUInt64 * 16r0101010101010101.
	words := n bitClear: 7.
	i := 0 asUInt64.
	[i < words] whileTrue: [
		self uint64At: d + i put: w.
		i := i + 8].
	[i < n] whileTrue: [
		self uint8At: d + i put: (c bitAnd: 255).
		i := i + 1].
	^dst
!
memcmp: a with: b size: n
	<function>
	<var: #a type: 'const void *'>
	<var: #b type: 'const void *'>
	<var: #n type: 'size_t'>
	<returns: 'int'>
	| p q x y |
	p := self cCoerce: a to: 'const uint8_t *'.
	q := self cCoerce: b to: 'const uint8_t *'.
	0 to: (n asInt64) - 1 do: [:i |
		x := (p at: i) asInt32.
		y := (q at: i) asInt32.
		x ~= y ifTrue: [^x - y]].
	^0
!
memchr: s value: c size: n
	<function>
	<var: #s type: 'const void *'>
	<var: #c type: 'int'>
	<var: #n type: 'size_t'>
	<returns: 'void *'>
	| p |
	p := self cCoerce: s to: 'const uint8_t *'.
	0 to: (n asInt64) - 1 do: [:i | (p at: i) = (c bitAnd: 255) ifTrue: [^self cCoerce: p + i to: 'void *']].
	^self null
! !

!UefiLibC methodsFor: 'strings'!
strlen: s
	<function>
	<var: #s type: 'const char *'>
	<returns: 'size_t'>
	| n |
	n := 0 asUInt64.
	[(s at: n) ~= 0] whileTrue: [n := n + 1].
	^n
!
strcmp: a with: b
	<function>
	<var: #a type: 'const char *'>
	<var: #b type: 'const char *'>
	<returns: 'int'>
	| i x y |
	i := 0.
	[x := (a at: i) asUInt8 asInt32.
	 y := (b at: i) asUInt8 asInt32.
	 x = y and: [x ~= 0]] whileTrue: [i := i + 1].
	^x - y
!
strdup: s
	<function>
	<var: #s type: 'const char *'>
	<returns: 'char *'>
	| n p |
	n := (self strlen: s) + 1.
	p := self malloc: n.
	p notNull ifTrue: [self memcpy: p from: s size: n].
	^self cCoerce: p to: 'char *'
!
atol: s
	<function>
	<var: #s type: 'const char *'>
	<returns: 'long'>
	| i neg v |
	i := 0.
	[(s at: i) = $  value or: [(s at: i) = 9]] whileTrue: [i := i + 1].
	neg := (s at: i) = $- value.
	((s at: i) = $- value or: [(s at: i) = $+ value]) ifTrue: [i := i + 1].
	v := 0.
	[(s at: i) >= $0 value and: [(s at: i) <= $9 value]] whileTrue: [
		v := (v * 10) + ((s at: i) - $0 value).
		i := i + 1].
	^neg ifTrue: [v negated] ifFalse: [v]
!
atoi: s
	<function>
	<var: #s type: 'const char *'>
	<returns: 'int'>
	^(self atol: s) asInt32
!
getenv: name
	"There is no environment."
	<function>
	<var: #name type: 'const char *'>
	<returns: 'char *'>
	^self null
! !

!UefiLibC methodsFor: 'exiting'!
exit: status
	"Say the status on the console, power off."
	<function>
	<noreturn>
	<var: #status type: 'int'>
	self fprintf: self stdout format: '
samaltak: exit %d
' with: status.
	self consoleFlush.
	firmware shutdown: status
!
abort
	<function>
	<noreturn>
	self fputs: 'samaltak: abort
' to: self stderr.
	self exit: 134
! !

VMStruct subclass: #UefiFile
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiFile comment: 'A FILE of UefiLibC: free, the console, or a file of the boot volume (its EFI_FILE_PROTOCOL).'!

!UefiFile class methodsFor: 'declaring'!
fields
	^#((kind int32_t) (handle 'EfiFile *'))
! !
