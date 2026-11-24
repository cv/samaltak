VMCoreModule subclass: #VMMain
	instanceVariableNames: 'headless argc argv argsStart runtimeNative'
	classVariableNames: ''
	package: 'VM-Core'!

VMMain comment: 'The entry point: samaltak [--max-heap MB] [--eden MB] [--survivor MB] [--tenure-age N] [--jit MODE] [--jit-threshold N] [--jit-osr N] [--jit-opt N] [--jit-flags a,b,-c] [--jit-cache MB] image [--headless] [image arguments...].'!

!VMMain class methodsFor: 'declaring'!
declarations
	^#((headless bool) (argc int32_t) (argv 'char **') (argsStart int32_t) (runtimeNative RuntimeNativeLoader))
! !

!VMMain methodsFor: 'accessing'!
headless
	^headless
!
argc
	^argc
!
argv
	^argv
!
argsStart
	^argsStart
! !

!VMMain methodsFor: 'running'!
banner
	"What the VM calls itself (primitive vmBanner)."
	<function>
	^'Samaltak VM'
!
usage
	<noreturn>
	libc fputs: 'usage: samaltak [--max-heap MB] [--eden MB] [--survivor MB] [--tenure-age N] [--jit none|baseline|opt (default)]
	[--jit-threshold N] [--jit-osr N] [--jit-opt N] [--jit-flags [-]flag,...] [--jit-cache MB] image [--headless] [arguments...]
  --eden MB          the young generation''s allocation space (default: a 64th of --max-heap, 16 to 64 MB; SAMALTAK_EDEN_MB)
  --survivor MB      each of its two survivor spaces (default: a quarter of eden; SAMALTAK_SURVIVOR_MB)
  --tenure-age N     tenure a survivor on its Nth scavenge, 1 to 4; 0 (default): adaptive (SAMALTAK_TENURE_AGE)
  --jit-threshold N  activations before a method is compiled (0: the first one)
  --jit-osr N        backward jumps before a running method is compiled and entered
  --jit-opt N        with --jit opt: entries and backward jumps in compiled code before a method is optimized
  --jit-flags        ablations: baseline: ic pic mega regs arith fuse float access prims blocks quick
                     barrier; opt: inline blocks prims unbox calls alloc gvn hoist live ffi-site;
                     listings: notes; stress: eager deopt (-name turns one off)
' to: libc stderr.
	libc exit: 64
!
main: n argv: v
	<function>
	<var: #n type: 'int'>
	<var: #v type: 'char **'>
	| maxHeap eden surv tenure i image proc ctx |
	jit defaults.
	maxHeap := (4096 << 20) asUInt64.
	eden := self envMB: 'SAMALTAK_EDEN_MB'.
	surv := self envMB: 'SAMALTAK_SURVIVOR_MB'.
	tenure := (libc getenv: 'SAMALTAK_TENURE_AGE') isNull ifTrue: [0] ifFalse: [libc atol: (libc getenv: 'SAMALTAK_TENURE_AGE')].
	i := 1.
	[i < n and: [((v at: i) at: 0) = $- value]] whileTrue: [
		((libc strcmp: (v at: i) with: '--max-heap') = 0 and: [i + 1 < n])
			ifTrue: [
				i := i + 1.
				maxHeap := (libc atol: (v at: i)) asUInt64 << 20]
			ifFalse: [
				((libc strcmp: (v at: i) with: '--eden') = 0 and: [i + 1 < n])
					ifTrue: [
						i := i + 1.
						eden := (libc atol: (v at: i)) asUInt64 << 20]
					ifFalse: [
						((libc strcmp: (v at: i) with: '--survivor') = 0 and: [i + 1 < n])
							ifTrue: [
								i := i + 1.
								surv := (libc atol: (v at: i)) asUInt64 << 20]
							ifFalse: [
								((libc strcmp: (v at: i) with: '--tenure-age') = 0 and: [i + 1 < n])
									ifTrue: [
										i := i + 1.
										tenure := libc atol: (v at: i)]
									ifFalse: [
										(libc strcmp: (v at: i) with: '--headless') = 0
											ifTrue: [headless := true]
											ifFalse: [
												(self jitOption: v at: i asInt32 count: n)
													ifTrue: [i := i + 1]
													ifFalse: [self usage]]]]]].
		i := i + 1].
	i >= n ifTrue: [self usage].
	image := v at: i.
	argc := n.
	argv := v.
	argsStart := (i + 1) asInt32.
	i + 1 to: n - 1 do: [:k | (libc strcmp: (v at: k) with: '--headless') = 0 ifTrue: [headless := true]].
	runtimeNative configure ifFalse: [
		libc fputs: 'samaltak: invalid or unresolved SAMALTAK_NATIVE_GRANTS manifest
' to: libc stderr.
		libc exit: 64].
	(tenure < 0 or: [tenure > 4]) ifTrue: [self usage].
	gc tenureAge: tenure asUInt32.
	eden = 0 ifTrue: [eden := self defaultEden: maxHeap].
	memory memoryInit: eden survivor: surv maxHeap: maxHeap.
	imageFile loadImage: image.
	scheduler init.
	jit start.
	headless ifFalse: [platform init].
	proc := self loadRef: (memory special: SO_PROCESSOR) at: SCHED_ACTIVE.
	ctx := self loadRef: proc at: PROC_SUSPENDED.
	((self isPtr: ctx) not or: [ctx = memory nilOop]) ifTrue: [self fatal: 'image has no active context'].
	interpreter activeCtx: ctx.
	self storeRef: proc at: PROC_SUSPENDED put: memory nilOop.
	gc rememberIfOld: ctx.
	interpreter interpret.
	^0
!
envMB: name
	"The environment variable name, a number of MB, in bytes; 0 if it is not set."
	<function>
	<var: #name type: 'const char *'>
	<returns: 'uint64_t'>
	(libc getenv: name) isNull ifTrue: [^0].
	^(libc atol: (libc getenv: name)) asUInt64 << 20
!
defaultEden: maxHeap
	"A 64th of the heap limit, from 16 MB to 64 MB: 64 MB hosted (the default limit of 4 GB), 16 MB on UEFI (256 MB to 1 GB). A larger eden scavenges less often and lets more objects die young (Havlak: a third of the scavenge time of 16 MB); a scavenge's pause grows with its survivors, not with eden, but they grow too, so pauses stay at about a millisecond."
	<function>
	<var: #maxHeap type: 'uint64_t'>
	<returns: 'uint64_t'>
	| e |
	e := maxHeap quo: 64.
	e < (16 << 20) ifTrue: [^16 << 20].
	e > (64 << 20) ifTrue: [^64 << 20].
	^(e + 16r3FFF) bitClear: 16r3FFF
!
jitOption: v at: i count: n
	"--jit MODE, --jit-threshold N, --jit-osr N, --jit-opt N, --jit-flags a,b,-c or --jit-cache MB at v[i]: answer whether it is one (its value is v[i + 1])."
	<function>
	| a m |
	i + 1 < n ifFalse: [^false].
	a := v at: i + 1.
	(libc strcmp: (v at: i) with: '--jit') = 0 ifTrue: [
		m := jit modeNamed: a.
		m < 0 ifTrue: [self usage].
		jit mode: m.
		^true].
	(libc strcmp: (v at: i) with: '--jit-threshold') = 0 ifTrue: [
		jit threshold: (libc atol: a).
		^true].
	(libc strcmp: (v at: i) with: '--jit-osr') = 0 ifTrue: [
		jit osrThreshold: (libc atol: a).
		^true].
	(libc strcmp: (v at: i) with: '--jit-opt') = 0 ifTrue: [
		jit optThreshold: (libc atol: a).
		^true].
	(libc strcmp: (v at: i) with: '--jit-flags') = 0 ifTrue: [
		(jit parseFlags: a) ifFalse: [self usage].
		^true].
	(libc strcmp: (v at: i) with: '--jit-cache') = 0 ifTrue: [
		jit cacheMB: (libc atol: a).
		^true].
	^false
! !
