TLSSocketTest subclass: #TLSSocketSmalltalkTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

TLSSocketSmalltalkTest comment: 'I am TLSSocketTest with the Smalltalk TLS forced (TLSSocket useSmalltalkTLS: true): its handshake too never blocks the VM, times out, is cancelled by terminating the connecting Process, and fails against servers that do not speak TLS, leaving no handle open.'!

!TLSSocketSmalltalkTest methodsFor: 'running'!
setUp
	super setUp.
	self replace: #useSmalltalkTLS of: TLSSocket with: true
! !

!TLSSocketSmalltalkTest methodsFor: 'tests'!
testConnectionIsSmalltalk
	"A stalled server: the error comes from the Smalltalk handshake."
	self acceptSilently.
	self should: [TLSSocket connectTo: '127.0.0.1' port: listener localPort timeout: 300] raise: RemoteError withExceptionDo: [:e |
		self assert: (e messageText endsWith: ': TLS handshake: timed out')]
! !
