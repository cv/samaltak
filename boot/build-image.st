"Build a seed image with the current ImageBuilder: boot/build-image.sh runs this in boot/seed.image with @SRC@ (the source tree), @OUT@ (the image to write) and @PACKAGES@ (a list of the packages to build, e.g. src/runtime.txt; empty: all) filled in. It files in the builder's current sources first (the code generator it compiles with included), so a seed that predates them still builds with them. A file whose superclasses are in a later file is filed in again on the next pass."
| packages files pending failed say |
say := [:aString | Smalltalk vm stderrWrite: aString , (String with: Character lf)].
[packages := #('src/Kernel-Objects/VMConstants.st' 'src/Compiler/Behavior.extension.st' 'src/Compiler/BytecodeEncoder.st' 'src/Compiler/CodeGenerator.st' 'src/VM-Lowtalk' 'src/VM-Core/VMCoreModule.st' 'src/VM-Core' 'src/VM-Jit' 'src/VM-Platform' 'src/VM-Translator' 'src/VM-ImageBuilder').
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
 failed do: [:f | Compiler fileIn: f].
 VMConstants initialize.
 (Smalltalk allClasses select: [:c | (#('VM-Lowtalk' 'VM-Core' 'VM-Jit' 'VM-Platform' 'VM-Translator' 'VM-ImageBuilder') includes: c packageName) and: [c class includesSelector: #initialize]])
	do: [:c | c initialize].
 say value: (ImageBuilder buildFrom: '@SRC@' packages: '@PACKAGES@' to: '@OUT@').
 Smalltalk quit: 0]
	on: Error
	do: [:e |
		say value: (e messageText isString ifTrue: [e messageText] ifFalse: [e printString]).
		say value: (e signalerContext stack first: 10) printString.
		Smalltalk quit: 1]
