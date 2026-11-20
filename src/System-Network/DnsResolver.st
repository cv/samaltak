Object subclass: #DnsResolver
	instanceVariableNames: 'stack lookups'
	classVariableNames: ''
	package: 'System-Network'!

DnsResolver comment: 'The DNS resolver of a NetworkStack, over UDP: A records, from the servers DHCP gave, each lookup (DnsLookup) from a port of its own with an id of its own. A query unanswered is sent again, to the next server, after 1, 2, then 4 s, six times; a lookup waits 30 s for an address (DHCP) first. An answer without addresses but with a CNAME is followed, eight times at most. A dotted address answers itself, and so does localhost (127.0.0.1).'!

!DnsResolver class methodsFor: 'instance creation'!
on: aStack
	^self new setStack: aStack
! !

!DnsResolver methodsFor: 'lookups'!
setStack: aStack
	stack := aStack.
	lookups := OrderedCollection new
!
lookup: hostName
	"A lookup of hostName, started."
	| l |
	l := DnsLookup new setName: hostName.
	((NetworkStack addressFrom: hostName) ifNil: [hostName = 'localhost' ifTrue: [16r7F000001]]) ifNotNil: [:a |
		l answer: a.
		^l finish].
	(hostName isEmpty or: [hostName size > 253]) ifTrue: [^l fail: 'not a host name'].
	l port: stack freeUdpPort; id: (stack random nextInt: 16rFFFF); expires: stack now + 30000.
	lookups add: l.
	self step: l.
	^l
!
free: aLookup
	lookups remove: aLookup ifAbsent: []
!
tick
	lookups isEmpty ifFalse: [lookups copy do: [:each | self step: each]]
!
step: l
	"Send l's query if it is time to (again), or give up."
	| t servers round |
	l isDone ifTrue: [^lookups remove: l ifAbsent: []].
	t := stack now.
	stack isConfigured ifFalse: [
		(t >= l expires or: [stack dhcp state == #idle]) ifTrue: [self finish: l error: 'no network address'].
		^self].
	servers := stack nameServers.
	servers isEmpty ifTrue: [^self finish: l error: 'no DNS server'].
	t < l deadline ifTrue: [^self].
	l tries >= 6 ifTrue: [^self finish: l error: 'DNS timed out'].
	(self query: l to: (servers at: l tries \\ servers size + 1)) ifFalse: [^self].
	round := l tries // servers size.
	l deadline: t + (#(1000 2000 4000) at: (round min: 2) + 1).
	l tries: l tries + 1
!
finish: l error: aString
	l fail: aString.
	lookups remove: l ifAbsent: []
!
query: l to: server
	"A query for l's name, type A, recursion desired; false if the name is not one."
	| q f |
	q := WriteStream on: (ByteArray new: 300).
	q nextPutAll: (ByteArray with: l id // 256 with: l id \\ 256); nextPutAll: #[1 0 0 1 0 0 0 0 0 0].
	((l name subStrings: '.') allSatisfy: [:label | label size <= 63]) ifFalse: [
		self finish: l error: 'not a host name'.
		^false].
	(l name subStrings: '.') do: [:label |
		q nextPut: label size; nextPutAll: label asByteArray].
	q nextPutAll: #[0 0 1 0 1].
	q := q contents.
	f := stack newFrame: 8 + q size.
	f replaceFrom: 43 to: 42 + q size with: q startingAt: 1.
	stack sendUdpFrom: l port to: server port: 53 frame: f length: q size.
	^true
!
datagram: f at: start count: n port: port from: src port: sport
	"A datagram to port: the answer to a lookup's query if it is one."
	sport = 53 ifFalse: [^self].
	lookups do: [:each | each port = port ifTrue: [^self answer: each from: f at: start count: n]]
!
answer: l from: f at: start count: n
	| flags rcode o type rdlen cname found stop |
	(n < 12 or: [(f netUint16At: start) ~= l id]) ifTrue: [^self].
	flags := f netUint16At: start + 2.
	(flags bitAnd: 16r8000) = 0 ifTrue: [^self].
	rcode := flags bitAnd: 15.
	rcode = 3 ifTrue: [^self finish: l error: 'no such host'].
	rcode ~= 0 ifTrue: [
		"the next server, at once"
		^l deadline: 0].
	stop := start + n.
	o := start + 12.
	(f netUint16At: start + 4) timesRepeat: [o := (self skipName: f at: o stop: stop) + 4].
	found := false.
	(f netUint16At: start + 6) timesRepeat: [
		o := self skipName: f at: o stop: stop.
		o + 10 <= stop ifTrue: [
			type := f netUint16At: o.
			rdlen := f netUint16At: o + 8.
			o + 10 + rdlen <= stop ifTrue: [
				(type = 1 and: [(f netUint16At: o + 2) = 1 and: [rdlen = 4]]) ifTrue: [
					l answer: (f netUint32At: o + 10).
					found := true].
				type = 5 ifTrue: [cname := self nameIn: f at: o + 10 start: start stop: stop].
				o := o + 10 + rdlen]]].
	found ifTrue: [
		l finish.
		^lookups remove: l ifAbsent: []].
	(cname notNil and: [l follows < 8]) ifTrue: [
		l follow: cname id: (stack random nextInt: 16rFFFF).
		^self step: l].
	self finish: l error: 'no such host'
!
skipName: f at: o stop: stop
	"The offset after the (compressed) name at o."
	| i len |
	i := o.
	[i < stop] whileTrue: [
		len := f at: i.
		len = 0 ifTrue: [^i + 1].
		(len bitAnd: 16rC0) = 16rC0 ifTrue: [^i + 2].
		i := i + 1 + len].
	^stop
!
nameIn: f at: o start: start stop: stop
	"The dotted (compressed) name at o, or nil if it is malformed."
	| i len s jumps |
	i := o.
	s := WriteStream on: (String new: 64).
	jumps := 0.
	[i < stop] whileTrue: [
		len := f at: i.
		len = 0 ifTrue: [^s contents isEmpty ifTrue: [nil] ifFalse: [s contents allButLast]].
		(len bitAnd: 16rC0) = 16rC0
			ifTrue: [
				(i + 1 >= stop or: [jumps > 16]) ifTrue: [^nil].
				jumps := jumps + 1.
				i := start + ((len bitAnd: 16r3F) * 256) + (f at: i + 1)]
			ifFalse: [
				(i + 1 + len > stop or: [s size + len > 253]) ifTrue: [^nil].
				s nextPutAll: (f copyFrom: i + 1 to: i + len) asString; nextPut: $..
				i := i + 1 + len]].
	^nil
! !

Object subclass: #DnsLookup
	instanceVariableNames: 'name port id tries follows deadline expires addresses failure done'
	classVariableNames: ''
	package: 'System-Network'!

DnsLookup comment: 'A lookup of a DnsResolver: the name asked for (a CNAME''s once followed), its UDP port and query id, the queries sent and when to send the next, when to stop waiting for an address; once done, its addresses or its error. It reads (text) as the platform''s lookup sockets do: an address a line, or a line of !! and the error.'!

!DnsLookup methodsFor: 'accessing'!
setName: aString
	name := aString.
	tries := follows := deadline := 0.
	addresses := OrderedCollection new.
	done := false
!
name
	^name
!
port
	^port
!
port: anInteger
	port := anInteger
!
id
	^id
!
id: anInteger
	id := anInteger
!
tries
	^tries
!
tries: anInteger
	tries := anInteger
!
follows
	^follows
!
deadline
	^deadline
!
deadline: milliseconds
	deadline := milliseconds
!
expires
	^expires
!
expires: milliseconds
	expires := milliseconds
!
follow: aName id: anInteger
	name := aName.
	id := anInteger.
	follows := follows + 1.
	tries := deadline := 0
!
answer: anAddress
	addresses add: anAddress
!
finish
	done := true
!
fail: aString
	failure := aString.
	done := true
!
isDone
	^done
!
addresses
	^addresses
!
failure
	^failure
!
text
	"What the lookup reads as."
	^String streamContents: [:s |
		failure isNil
			ifTrue: [addresses do: [:a | s nextPutAll: (NetworkStack dotted: a); nextPut: Character lf]]
			ifFalse: [s nextPut: $!!; nextPutAll: failure; nextPut: Character lf]]
! !
