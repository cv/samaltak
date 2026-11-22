AgentTool subclass: #RunTestsTool
	instanceVariableNames: 'timeout limit'
	classVariableNames: ''
	package: 'System-Agent'!

RunTestsTool comment: 'I am the run-tests tool: the call''s arguments are {"names": ["FooTest", "Tests-Agent"]}, test classes or packages of them (as TestCase runNamed:). I run them in a fresh Process (''agent run-tests'', the priority of a do-it); the turn waits for it at most timeout seconds (default 300), then terminates it and reports what ran.

The output is the TestResult''s id and summary, e.g. ''o4 a TestResult(9 run, 8 passed, 1 failed, 0 errors)'', then a line per failure (FAIL, its message) and error (ERROR, the exception and the top of its stack), cut to limit characters (default 10,000). A name that is neither a test class nor a package of test classes answers an error. My item is a #tests item: its text the equivalent Smalltalk, its object the TestResult.'!

!RunTestsTool methodsFor: 'initialization'!
initialize
	timeout := 300.
	limit := 10000
! !

!RunTestsTool methodsFor: 'accessing'!
name
	^'run-tests'
!
timeout
	"Seconds the tests may run."
	^timeout
!
timeout: seconds
	timeout := seconds
!
limit
	"The most characters the output shows."
	^limit ifNil: [10000]
!
limit: characters
	limit := characters
!
spec
	^Dictionary new
		at: 'type' put: 'function';
		at: 'name' put: self name;
		at: 'description' put: 'Run test classes in this image, e.g. {"names": ["FooTest"]}, or every test class of a package ("Tests-Agent"). Answers the id of the TestResult (failures and errors: TestCase -> message Associations) and its summary, then each failure with its message and each error with the top of its stack. Run the tests a change concerns, never the whole suite. Stops after 300 s.';
		at: 'strict' put: false;
		at: 'parameters' put: (Dictionary new
			at: 'type' put: 'object';
			at: 'properties' put: (Dictionary new
				at: 'names' put: (Dictionary new
					at: 'type' put: 'array';
					at: 'items' put: (Dictionary new at: 'type' put: 'string'; yourself);
					at: 'description' put: 'Test class names or package names';
					yourself);
				yourself);
			at: 'required' put: #('names');
			at: 'additionalProperties' put: false;
			yourself);
		yourself
! !

!RunTestsTool methodsFor: 'running'!
namesIn: aCallDictionary
	"The names argument (Strings), or nil."
	| arguments names |
	arguments := [JSON parse: (aCallDictionary at: 'arguments' ifAbsent: ['{}'])] on: Error do: [:e | e return: nil].
	arguments isDictionary ifFalse: [^nil].
	names := arguments at: 'names' ifAbsent: [nil].
	names isString ifTrue: [^Array with: names].
	((names isKindOf: SequenceableCollection) and: [names allSatisfy: [:each | each isString]]) ifFalse: [^nil].
	^names asArray
!
classesNamed: names
	"The test classes named in names and those of the packages named in names, as TestCase runNamed: runs them."
	^(TestCase allTestClasses select: [:c |
		(names includes: c name asString) or: [names includes: c packageName]]) asArray
!
sourceFor: names
	"The Smalltalk that does what I do, shown as the item's text."
	^'TestCase runNamed: ', names asArray printString
!
run: aCallDictionary in: anAgentConversation
	| names classes unknown item |
	names := (self namesIn: aCallDictionary) ifNil: [#()].
	item := AgentItem call: aCallDictionary kind: #tests text: (self sourceFor: names).
	anAgentConversation add: item.
	classes := self classesNamed: names.
	unknown := names reject: [:each | classes anySatisfy: [:c | c name asString = each or: [c packageName = each]]].
	names isEmpty
		ifTrue: [item failed: true; output: 'error: no names: give test classes or packages, e.g. {"names": ["FooTest"]}']
		ifFalse: [
			unknown isEmpty
				ifTrue: [self run: classes for: item in: anAgentConversation]
				ifFalse: [item failed: true; output: (self describeUnknown: unknown)]].
	anAgentConversation changed.
	^item result
!
describeUnknown: names
	^String new: 100 streamContents: [:s |
		s nextPutAll: 'error: no test class or package of test classes named '.
		names do: [:each | s nextPutAll: each] separatedBy: [s nextPutAll: ', ']]
!
run: classes for: anAgentItem in: anAgentConversation
	"Run classes in a new Process and wait for it; give anAgentItem the TestResult and its output. That Process ends with the wait, also when the waiting Process is terminated."
	| result done process timedOut |
	result := TestResult new.
	done := Semaphore new.
	timedOut := false.
	[process := [[result runClasses: classes] ensure: [done signal]] newProcess.
	 process priority: Processor userSchedulingPriority; name: 'agent run-tests'.
	 process resume.
	 timedOut := done waitTimeoutMSecs: (timeout * 1000) rounded]
		ensure: [process isNil ifFalse: [process terminate]].
	anAgentItem object: result; objectId: (anAgentConversation idFor: result).
	anAgentItem output: (self output: result id: anAgentItem objectId timedOut: timedOut)
!
output: aTestResult id: anId timedOut: aBoolean
	"anId and aTestResult's summary, then its failures and errors, cut to limit characters."
	| text max |
	text := String new: 400 streamContents: [:s |
		s nextPutAll: anId; space; print: aTestResult.
		aBoolean ifTrue: [s nextPutAll: ' (stopped after '; print: timeout; nextPutAll: ' s; the rest did not run)'].
		aTestResult failures do: [:each |
			s nextPut: Character lf; nextPutAll: 'FAIL '; print: each key; nextPutAll: ': '; nextPutAll: (each value ifNil: ['']) asString].
		aTestResult errors do: [:each |
			s nextPut: Character lf; nextPutAll: 'ERROR '; print: each key; nextPutAll: ': '; nextPutAll: (each value ifNil: ['']) asString]].
	max := self limit.
	text size <= max ifTrue: [^text].
	^(text copyFrom: 1 to: max), '... [cut: ', text size printString, ' characters in all; ', anId, ' failures and ', anId, ' errors hold every one]'
! !
