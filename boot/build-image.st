"File in the current builder before building an image. The final three VM arguments are the source directory, output file and package list (empty: all)."
| args packages files pending failed say |
say := [:aString | Smalltalk vm stderrWrite: aString , (String with: Character lf)].
[args := Smalltalk vm arguments.
 packages := #('src/Kernel-Objects/VMConstants.st' 'src/System-Support/FFIError.st' 'src/System-Support/FFIBinding.st' 'src/System-Support/FFI.st' 'src/Compiler/Behavior.extension.st' 'src/Compiler/BytecodeEncoder.st' 'src/Compiler/CodeGenerator.st' 'src/VM-Lowtalk' 'src/VM-Core/VMCoreModule.st' 'src/VM-Core' 'src/VM-Jit' 'src/VM-Platform' 'src/VM-Translator' 'src/VM-ImageBuilder').
 files := OrderedCollection new.
 (packages select: [:each | File exists: each]) do: [:each |
	(File isDirectory: each)
		ifTrue: [
			| names |
			names := (Directory fileNames: each) select: [:f | f endsWith: '.st'].
			(names reject: [:f | f endsWith: '.extension.st']) , (names select: [:f | f endsWith: '.extension.st']) do: [:f | files add: each , '/' , f]]
		ifFalse: [files add: each]].
 pending := files.
 [failed := pending select: [:f | [Compiler fileIn: f. false] on: Error do: [:e | e return: true]].
  failed notEmpty and: [failed size < pending size]] whileTrue: [pending := failed].
 failed do: [:f | say value: 'image builder: loading ' , f. Compiler fileIn: f].
 VMConstants initialize.
 (Smalltalk allClasses select: [:c | (#('VM-Lowtalk' 'VM-Core' 'VM-Jit' 'VM-Platform' 'VM-Translator' 'VM-ImageBuilder') includes: c packageName) and: [c class includesSelector: #initialize]])
	do: [:c | c initialize].
 say value: (ImageBuilder buildFrom: (args at: args size - 2) packages: args last to: (args at: args size - 1)).
 Smalltalk quit: 0]
	on: Error
	do: [:e |
		say value: (e messageText isString ifTrue: [e messageText] ifFalse: [e printString]).
		say value: (e signalerContext stack first: 10) printString.
		Smalltalk quit: 1]
