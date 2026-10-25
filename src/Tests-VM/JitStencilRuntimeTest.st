JitRuntimeTest subclass: #JitStencilRuntimeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

JitStencilRuntimeTest comment: 'JitRuntimeTest under the copy-and-patch compiler (--jit stencil).'!

!JitStencilRuntimeTest methodsFor: 'running'!
mode
	^'stencil'
! !

!JitStencilRuntimeTest methodsFor: 'helpers'!
disassemblyNotes
	^#('x24 := the frame' 'compareOperandsJumpFalse 6' 'hole A: ' 'continue: out of line' 'floatOperation 8' 'returnTop' 'the interpreter resumes pc')
! !

JitRuntimeTest subclass: #JitThreadedRuntimeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-VM'!

JitThreadedRuntimeTest comment: 'JitRuntimeTest under the call-threading compiler (--jit threaded).'!

!JitThreadedRuntimeTest methodsFor: 'running'!
mode
	^'threaded'
! !

!JitThreadedRuntimeTest methodsFor: 'helpers'!
disassemblyNotes
	^#('x24 := the frame' 'compareOperandsJumpFalse 6' 'the continuation the stencil answers' 'floatOperation 8' 'returnTop' 'the interpreter resumes pc')
! !

!JitThreadedRuntimeTest methodsFor: 'tests'!
testCodeCacheFlush
	"Threaded code is small: the compiler's tests fill the 1 MB cache, and pass."
	| run |
	run := OSProcess run: (OSProcess commandFor: {'vm/build/samaltak'. '--jit'. self mode. '--jit-threshold'. '0'. '--jit-cache'. '1'. '--jit-flags'. 'notes'. Smalltalk vm imagePath. '--headless'. '--eval'.
		'| r | r := TestCase runNamed: #(''Tests-Compiler''). {r failures size + r errors size. r runCount > 0. Smalltalk vm statistics jitCacheFlushes > 0}'}).
	self assert: (run output trimBoth endsWith: '#(0 true true)')
! !
