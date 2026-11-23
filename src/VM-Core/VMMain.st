VMCoreModule subclass: #VMMain
	instanceVariableNames: 'headless argc argv argsStart runtimeNative'
	classVariableNames: ''
	package: 'VM-Core'!

VMMain comment: 'The entry point: samaltak [--max-heap MB] [--eden MB] [--jit MODE] [--jit-threshold N] [--jit-osr N] [--jit-opt N] [--jit-flags a,b,-c] [--jit-cache MB] image [--headless] [image arguments...].'!

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
	libc fputs: 'usage: samaltak [--max-heap MB] [--eden MB] [--jit none|baseline|opt (default)] [--jit-threshold N] [--jit-osr N]
	[--jit-opt N] [--jit-flags [-]flag,...] [--jit-cache MB] image [--headless] [arguments...]
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
	| maxHeap eden i image proc ctx |
	jit defaults.
	maxHeap := (4096 << 20) asUInt64.
	eden := (16 << 20) asUInt64.
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
						(libc strcmp: (v at: i) with: '--headless') = 0
							ifTrue: [headless := true]
							ifFalse: [
								(self jitOption: v at: i asInt32 count: n)
									ifTrue: [i := i + 1]
									ifFalse: [self usage]]]].
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
	memory memoryInit: eden maxHeap: maxHeap.
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
