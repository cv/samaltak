TestCase subclass: #TOMLReaderTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Kernel'!

TOMLReaderTest comment: 'Tests for TOMLReader: tables, dotted keys, strings, numbers, booleans, arrays, comments, arrays of tables, and syntax errors.'!

!TOMLReaderTest methodsFor: 'tests'!
testOmarchyShellSections
	| doc |
	doc := TOMLReader parse: '# Omarchy shell surfaces
[bar]
background       = "#FFFCF0"
background-alpha = 1.0
scale-with-font  = true
size-horizontal  = 26

[popups]
border = "hyprland.active-border"  # a reference
'.
	self assert: ((doc at: 'bar') at: 'background') equals: '#FFFCF0'.
	self assert: ((doc at: 'bar') at: 'background-alpha') equals: 1.0.
	self assert: ((doc at: 'bar') at: 'scale-with-font') equals: true.
	self assert: ((doc at: 'bar') at: 'size-horizontal') equals: 26.
	self assert: ((doc at: 'popups') at: 'border') equals: 'hyprland.active-border'
!
testTopLevelAndDottedKeys
	| doc |
	doc := TOMLReader parse: 'mode = "light"
a.b.c = 1
[x.y]
z = false
'.
	self assert: (doc at: 'mode') equals: 'light'.
	self assert: (((doc at: 'a') at: 'b') at: 'c') equals: 1.
	self assert: (((doc at: 'x') at: 'y') at: 'z') equals: false
!
testStringsAndNumbers
	| doc |
	doc := TOMLReader parse: 'a = "tab\there \"q\" \u00e9"
b = ''C:\raw''
c = -42
d = 1_000
e = 0xff
f = 2.5e1
"quoted key" = 3
'.
	self assert: (doc at: 'a') equals: 'tab', (String with: Character tab), 'here "q" ', (String with: (Character value: 16rE9)).
	self assert: (doc at: 'b') equals: 'C:\raw'.
	self assert: (doc at: 'c') equals: -42.
	self assert: (doc at: 'd') equals: 1000.
	self assert: (doc at: 'e') equals: 255.
	self assert: (doc at: 'f') equals: 25.0.
	self assert: (doc at: 'quoted key') equals: 3
!
testArrays
	| doc |
	doc := TOMLReader parse: 'list = [1, "two", [3]]
multi = [
  "a",  # first
  "b",
]
[[city]]
name = "London"
[[city]]
name = "Tokyo"
'.
	self assert: (doc at: 'list') equals: #(1 'two' #(3)).
	self assert: (doc at: 'multi') equals: #('a' 'b').
	self assert: ((doc at: 'city') collect: [:each | each at: 'name']) equals: #('London' 'Tokyo')
!
testSyntaxErrorsNameTheLine
	| error |
	error := [TOMLReader parse: 'a = 1
b = "open
'. nil] on: Error do: [:e | e return: e messageText].
	self assert: (error includesSubstring: 'line 2').
	self should: [TOMLReader parse: 'a = 1 2'] raise: Error.
	self should: [TOMLReader parse: '[a'] raise: Error
! !
