"Build a seed image with the current ImageBuilder: boot/build-image.sh runs this in boot/seed.image with @SRC@ (the source tree) and @OUT@ (the image to write) filled in. It files in the builder's current sources first, so a seed that predates them still builds with them."
| builderSources say |
say := [:aString | Smalltalk vm stderrWrite: aString , (String with: Character lf)].
[builderSources := #('src/Kernel-Objects/VMConstants.st' 'src/VM-Lowtalk' 'src/VM-Core' 'src/VM-Platform' 'src/VM-Translator' 'src/VM-ImageBuilder').
 (builderSources select: [:each | File exists: each]) do: [:each |
	(File isDirectory: each)
		ifTrue: [
			| files |
			files := (Directory fileNames: each) select: [:f | f endsWith: '.st'].
			(files reject: [:f | f endsWith: '.extension.st']) , (files select: [:f | f endsWith: '.extension.st']) do: [:f | Compiler fileIn: each , '/' , f]]
		ifFalse: [Compiler fileIn: each]].
 VMConstants initialize.
 (Smalltalk allClasses select: [:c | (#('VM-Lowtalk' 'VM-Core' 'VM-Platform' 'VM-Translator' 'VM-ImageBuilder') includes: c packageName) and: [c class includesSelector: #initialize]])
	do: [:c | c initialize].
 say value: (ImageBuilder buildFrom: '@SRC@' to: '@OUT@').
 Smalltalk quit: 0]
	on: Error
	do: [:e |
		say value: (e messageText isString ifTrue: [e messageText] ifFalse: [e printString]).
		Smalltalk quit: 1]
