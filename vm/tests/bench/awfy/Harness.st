"
Adapted from Harness.som and Run.som of Are We Fast Yet (https://github.com/smarr/are-we-fast-yet):
prints CSV lines (benchmark,iteration,microseconds) and the VM statistics delta; no exit.
Platform-specific: AwfyPlatform and ScriptConsole (Samaltak.st, Pharo.st).

Copyright (c) 2011-2016 see AUTHORS.md file

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the 'Software'), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
"!

Object subclass: #Run
	instanceVariableNames: 'total numIterations innerIterations benchmarkSuite name'
	classVariableNames: ''
	package: 'AWFY'!

Object subclass: #Harness
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'AWFY'!

!Run methodsFor: 'benchmarking'!
initialize: aName
	name            := aName.
	benchmarkSuite  := self loadBenchmarkSuite: aName.
	total           := 0.
	numIterations   := 1.
	innerIterations := 1.
!
loadBenchmarkSuite: className
	| cls |
	cls := Smalltalk at: className asSymbol ifAbsent: [nil].
	cls ifNil: [
		self error: 'Failed loading benchmark: ', className ].
	^ cls
!
name: aString
	name := aString
!
benchmarkSuite: aSuite
	benchmarkSuite := aSuite
!
numIterations: anInt
	numIterations := anInt
!
innerIterations: anInt
	innerIterations := anInt
!
runBenchmark
	| bench before |
	bench := benchmarkSuite new.
	before := AwfyPlatform statistics.
	self doRuns: bench.
	ScriptConsole println: '# stats ', name, (AwfyPlatform statisticsSince: before)
!
measure: bench iteration: i
	| startTime endTime runTime |
	startTime := AwfyPlatform microseconds.
	(bench innerBenchmarkLoop: innerIterations) ifFalse: [
		self error: 'Benchmark failed with incorrect result'. ].
	endTime   := AwfyPlatform microseconds.

	runTime := endTime - startTime.
	self printResult: runTime iteration: i.

	total := total + runTime.
!
doRuns: bench
	1 to: numIterations do: [:i |
		self measure: bench iteration: i
	]
!
printResult: runTime iteration: i
	ScriptConsole println: name, ',', i printString, ',', runTime printString
!
printTotal
	ScriptConsole println: '# total ', name, ' ', total printString, ' us'
! !

!Run class methodsFor: 'benchmarking'!
new: aName
	^ self new initialize: aName
! !

!Harness methodsFor: 'benchmarking'!
processArguments: args
	"args: benchmark name, then optionally num-iterations and inner-iterations (Strings)"
	| run |
	run := Run new: (args at: 1).

	args size > 1 ifTrue: [
		run numIterations: (args at: 2) asInteger.
		args size > 2 ifTrue: [
			run innerIterations: (args at: 3) asInteger.
	] ].
	^ run
!
run: args
	| run |
	run := self processArguments: args.

	run runBenchmark.
	run printTotal
! !
