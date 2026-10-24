VMCoreModule subclass: #VMMain
	instanceVariableNames: 'headless argc argv argsStart'
	classVariableNames: ''
	package: 'VM-Core'!

VMMain comment: 'The entry point: samaltak [--max-heap MB] [--eden MB] image [--headless] [image arguments...].'!

!VMMain class methodsFor: 'declaring'!
declarations
	^#((headless bool) (argc int32_t) (argv 'char **') (argsStart int32_t))
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
	<c: 'const char *vm_banner(void)'>
	^'Samaltak VM'
!
usage
	<c: 'void usage(void)'>
	<noreturn>
	libc fputs: 'usage: samaltak [--max-heap MB] [--eden MB] image [--headless] [arguments...]
' to: libc stderr.
	libc exit: 64
!
main: n argv: v
	<c: 'int main(int argc, char **argv)'>
	| maxHeap eden i image proc ctx |
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
							ifFalse: [self usage]]].
		i := i + 1].
	i >= n ifTrue: [self usage].
	image := v at: i.
	argc := n.
	argv := v.
	argsStart := (i + 1) asInt32.
	i + 1 to: n - 1 do: [:k | (libc strcmp: (v at: k) with: '--headless') = 0 ifTrue: [headless := true]].
	memory memoryInit: eden maxHeap: maxHeap.
	imageFile loadImage: image.
	scheduler init.
	headless ifFalse: [platform init].
	proc := self loadRef: (memory special: SO_PROCESSOR) at: SCHED_ACTIVE.
	ctx := self loadRef: proc at: PROC_SUSPENDED.
	((self isPtr: ctx) not or: [ctx = memory nilOop]) ifTrue: [self fatal: 'image has no active context'].
	interpreter activeCtx: ctx.
	self storeRef: proc at: PROC_SUSPENDED put: memory nilOop.
	gc rememberIfOld: ctx.
	interpreter interpret.
	^0
! !
