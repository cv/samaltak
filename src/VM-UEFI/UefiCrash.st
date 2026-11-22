UefiModule subclass: #UefiCrash
	instanceVariableNames: 'build log logUsed recent recentTotal startNs reporting'
	classVariableNames: 'UEFI_CRASH_LOG UEFI_CRASH_RECENT UEFI_CRASH_WAIT_S'
	package: 'VM-UEFI'!

UefiCrash comment: 'What a fatal error leaves on a machine without a serial port (docs/uefi.md, Crash reports). The console''s output goes through note:count: (UefiLibC): the last UEFI_CRASH_RECENT bytes are kept in a ring, and from the fatal error on (Interpreter>>isFatal: its message and the Smalltalk stack, as the VM prints them) up to UEFI_CRASH_LOG bytes in log. At its exit (UefiLibC>>exit:) report: writes samaltak-crash-<n>.txt (the first n not taken) in the root of the boot volume (the ESP, the image''s /esp): the fatal message, the time and uptime, the VM''s build (its commit: SAMALTAK_COMMIT, make uefi''s git describe), its arguments, the heap''s statistics, the fatal output and the console before it. Then it takes over the firmware''s text console (FirmwareScreen silenced it: UefiFirmware>>takeOverConsole:), shows the message, the file''s name and the top of the stack on red, and waits for a key, then resets the machine (EfiResetCold; QEMU''s -no-reboot ends there); with a serial port (someone reads the console: QEMU''s tests) at most UEFI_CRASH_WAIT_S seconds, after which the exit goes on (power off with status 70). Nothing here uses the heap or allocates: the heap may be what failed.'!

!UefiCrash class methodsFor: 'declaring'!
declarations
	^#((build UefiBuildInfo) (log 'char[UEFI_CRASH_LOG]') (logUsed int64_t) (recent 'char[UEFI_CRASH_RECENT]') (recentTotal uint64_t)
		(startNs int64_t) (reporting bool))
!
initialize
	"UEFI_CRASH_RECENT a power of 2."
	UEFI_CRASH_LOG := 65536.
	UEFI_CRASH_RECENT := 4096.
	UEFI_CRASH_WAIT_S := 15
!
cPreamble
	^'#ifndef SAMALTAK_COMMIT
#define SAMALTAK_COMMIT "unknown"
#endif
static inline const char *uefi_build_commit(void) { return SAMALTAK_COMMIT; }
#ifdef __aarch64__
static inline const char *uefi_build_arch(void) { return "arm64"; }
#else
static inline const char *uefi_build_arch(void) { return "x86_64"; }
#endif'
! !

!UefiCrash methodsFor: 'recording'!
start
	"At the VM's start (its uptime counts from here)."
	<function>
	startNs := posix nowNs
!
note: bytes count: n
	"Console output: into the log once the VM is dying, else into the ring of recent output."
	<function>
	<var: #bytes type: 'const char *'>
	<var: #n type: 'uint64_t'>
	reporting ifTrue: [^self].
	interpreter isFatal
		ifTrue: [
			0 to: (n asInt64) - 1 do: [:i |
				logUsed < UEFI_CRASH_LOG ifTrue: [
					log at: logUsed put: (bytes at: i).
					logUsed := logUsed + 1]]]
		ifFalse: [
			0 to: (n asInt64) - 1 do: [:i |
				recent at: (recentTotal bitAnd: UEFI_CRASH_RECENT - 1) put: (bytes at: i).
				recentTotal := recentTotal + 1]]
! !

!UefiCrash methodsFor: 'reporting'!
report: status
	"At the VM's exit: if it dies of a fatal error, once: the report, the panel, a key (then reset) or the timeout (then the exit goes on)."
	<function>
	<var: #status type: 'int'>
	| name written |
	(interpreter isFatal not or: [reporting]) ifTrue: [^self].
	libc fflush: libc stderr.
	reporting := true.
	name := self local: 'char[64]'.
	name at: 0 put: 0.
	written := self writeReportAs: name.
	written
		ifTrue: [libc fprintf: libc stderr format: 'samaltak: crash report %s on the boot volume
' with: name]
		ifFalse: [libc fputs: 'samaltak: no crash report: the boot volume cannot be written
' to: libc stderr].
	libc fflush: libc stderr.
	self showPanel: name written: written.
	(self waitForKey: (firmware hasSerial ifTrue: [UEFI_CRASH_WAIT_S] ifFalse: [-1])) ifTrue: [
		libc fputs: 'samaltak: a key: reset
' to: libc stderr.
		libc fflush: libc stderr.
		firmware reset]
!
messageLength
	"The length of the fatal message (log from messageStart to its line's end)."
	<function>
	<returns: 'int64_t'>
	| i |
	i := self messageStart.
	[i < logUsed and: [(log at: i) ~= 10]] whileTrue: [i := i + 1].
	^i - self messageStart
!
messageStart
	"Where the fatal message starts in log: after samaltak: fatal: ."
	<function>
	<returns: 'int64_t'>
	(logUsed >= 17 and: [(libc memcmp: log with: 'samaltak: fatal: ' size: 17) = 0]) ifTrue: [^17].
	^0
!
writeReportAs: name
	"Write samaltak-crash-<n>.txt, the first n not taken, in the boot volume's root; its name into name (64 bytes); answer whether it was written."
	<function>
	<var: #name type: 'char *'>
	<returns: 'bool'>
	| f n free |
	firmware root isNull ifTrue: [^false].
	n := 0.
	free := false.
	[free not and: [n < 9999]] whileTrue: [
		n := n + 1.
		libc snprintf: name size: 64 format: 'samaltak-crash-%d.txt' with: n.
		f := libc fopen: name mode: 'rb'.
		f isNull ifTrue: [free := true] ifFalse: [libc fclose: f]].
	free ifFalse: [^false].
	f := libc fopen: name mode: 'wb'.
	f isNull ifTrue: [^false].
	self writeReportOn: f.
	^(libc fclose: f) = 0
!
writeReportOn: f
	<function>
	<var: #f type: 'FILE *'>
	| t up start kept |
	libc fputs: 'Samaltak crash report
fatal: ' to: f.
	libc fwrite: log + self messageStart size: 1 count: self messageLength asUInt64 file: f.
	t := self local: 'EfiTime'.
	(self efiFailed: (self efi: self runtime getTime with: t with: self null)) ifFalse: [
		libc fprintf: f format: '
time: %04d-%02d-%02d ' with: t year asInt32 with: t month asInt32 with: t day asInt32.
		libc fprintf: f format: '%02d:%02d:%02d (the firmware''s clock)' with: t hour asInt32 with: t minute asInt32 with: t second asInt32].
	up := (posix nowNs - startNs) quo: 1000000.
	libc fprintf: f format: '
uptime: %lld.%03lld s
' with: (up quo: 1000) with: (up rem: 1000).
	libc fprintf: f format: 'vm: %s, UEFI %s, built from %s
' with: vmMain banner with: build arch with: build commit.
	libc fputs: 'arguments:' to: f.
	0 to: vmMain argc - 1 do: [:i | libc fprintf: f format: ' %s' with: (vmMain argv at: i)].
	libc fprintf: f format: '
heap: limit %llu MB, old space %llu MB, allocated %llu MB in all' with: gc maxHeapBytes >> 20 with: (gc oldTop - gc oldLo) >> 20 with: (gc statAllocated + (gc edenTop - gc edenLo)) >> 20.
	libc fprintf: f format: ', %llu scavenges, %llu full GCs, low space level %d
' with: gc statScavenges with: gc statFullGcs with: gc lowSpaceLevel asInt32.
	libc fputs: '
The fatal error, as the VM printed it:
' to: f.
	libc fwrite: log size: 1 count: logUsed asUInt64 file: f.
	logUsed >= UEFI_CRASH_LOG ifTrue: [libc fputs: '
(cut short)
' to: f].
	kept := recentTotal.
	kept > UEFI_CRASH_RECENT ifTrue: [kept := UEFI_CRASH_RECENT].
	libc fprintf: f format: '
The console before it (its last %llu bytes):
' with: kept.
	recentTotal > UEFI_CRASH_RECENT
		ifTrue: [
			start := (recentTotal bitAnd: UEFI_CRASH_RECENT - 1) asInt64.
			libc fwrite: recent + start size: 1 count: (UEFI_CRASH_RECENT - start) asUInt64 file: f.
			libc fwrite: recent size: 1 count: start asUInt64 file: f]
		ifFalse: [libc fwrite: recent size: 1 count: recentTotal file: f]
! !

!UefiCrash methodsFor: 'screen'!
showPanel: name written: written
	"The firmware's text console, white on red: the message, the report's name, the top of the stack, what a key does."
	<function>
	<var: #name type: 'const char *'>
	<var: #written type: 'bool'>
	| i e lines stack |
	firmware takeOverConsole: 16r4F.
	self say: '
  Samaltak stopped: a fatal error in the VM.

  '.
	self say: log + self messageStart count: self messageLength.
	written
		ifTrue: [
			self say: '

  The report is '.
			self say: name.
			self say: ' on the boot volume (the ESP; /esp in the image).
']
		ifFalse: [self say: '

  No report: the boot volume cannot be written.
'].
	stack := self stackStart.
	stack < logUsed ifTrue: [
		self say: '
'.
		i := stack.
		lines := 0.
		[i < logUsed and: [lines < 16]] whileTrue: [
			e := i.
			[e < logUsed and: [(log at: e) ~= 10]] whileTrue: [e := e + 1].
			self say: '  '.
			self say: log + i count: (e - i min: 76).
			self say: '
'.
			lines := lines + 1.
			i := e + 1]].
	firmware hasSerial
		ifTrue: [self say: '
  Press a key to restart (in 15 s without one: power off).
']
		ifFalse: [self say: '
  Press a key to restart.
']
!
stackStart
	"Where Smalltalk stack: starts in log, else logUsed."
	<function>
	<returns: 'int64_t'>
	0 to: logUsed - 17 do: [:i |
		(libc memcmp: log + i with: 'Smalltalk stack:' size: 16) = 0 ifTrue: [^i asInt64]].
	^logUsed
!
say: text
	<function>
	<var: #text type: 'const char *'>
	self say: text count: (libc strlen: text) asInt64
!
say: text count: n
	"n bytes of text on the firmware's console: ASCII, other characters as ?, LF as CR LF."
	<function>
	<var: #text type: 'const char *'>
	<var: #n type: 'int64_t'>
	| out o c |
	out := self local: 'uint16_t[264]'.
	o := 0.
	0 to: n - 1 do: [:i |
		c := (text at: i) asUInt8 asInt64.
		c = 10 ifTrue: [
			out at: o put: 13.
			o := o + 1].
		(c = 10 or: [c >= 32 and: [c < 127]]) ifTrue: [
			out at: o put: c.
			o := o + 1].
		c >= 16rC0 ifTrue: [
			out at: o put: $? value.
			o := o + 1].
		o >= 256 ifTrue: [
			out at: o put: 0.
			firmware outputString: out.
			o := 0]].
	out at: o put: 0.
	o > 0 ifTrue: [firmware outputString: out]
!
waitForKey: seconds
	"Wait for a key, at most seconds (forever if negative); answer whether one came. Polled (ReadKeyStroke, Stall): it works at any TPL."
	<function>
	<var: #seconds type: 'int64_t'>
	<returns: 'bool'>
	| conIn key ticks |
	conIn := self cCoerce: firmware systemTable conIn to: 'EfiTextInput *'.
	key := self local: 'uint64_t'.
	conIn notNull ifTrue: [
		ticks := 0.
		[ticks < 64 and: [(self efiFailed: (self efi: conIn readKeyStroke with: conIn with: key)) not]] whileTrue: [ticks := ticks + 1]].
	ticks := 0.
	[seconds < 0 or: [ticks < (seconds * 100)]] whileTrue: [
		(conIn notNull and: [(self efiFailed: (self efi: conIn readKeyStroke with: conIn with: key)) not]) ifTrue: [^true].
		self efi: self boot stall with: 10000.
		ticks := ticks + 1].
	^false
! !

CLibrary subclass: #UefiBuildInfo
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

UefiBuildInfo comment: 'What UefiCrash says of the build (its C preamble): the commit (SAMALTAK_COMMIT, from make uefi: git describe --always --dirty) and the CPU.'!

!UefiBuildInfo class methodsFor: 'declaring'!
targetOS
	^#uefi
! !

!UefiBuildInfo methodsFor: 'functions'!
commit
	<c: 'const char *uefi_build_commit(void)'>
	^'simulated'
!
arch
	<c: 'const char *uefi_build_arch(void)'>
	^'simulated'
! !

VMStruct subclass: #EfiTextInput
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-UEFI'!

EfiTextInput comment: 'EFI_SIMPLE_TEXT_INPUT_PROTOCOL (UEFI 2.10, 12.3).'!

!EfiTextInput class methodsFor: 'declaring'!
fields
	^#((reset 'void *') (readKeyStroke 'void *') (waitForKey 'void *'))
! !
