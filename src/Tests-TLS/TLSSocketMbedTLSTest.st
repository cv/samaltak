TLSSocketTest subclass: #TLSSocketMbedTLSTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-TLS'!

TLSSocketMbedTLSTest comment: 'I am TLSSocketTest with the VM''s TLS engine forced (TLSSocket engine: #mbedtls), as UEFI uses it: its handshake too never blocks the VM, times out, is cancelled by terminating the connecting Process, and fails against servers that do not speak TLS, leaving no handle open.'!

!TLSSocketMbedTLSTest methodsFor: 'running'!
setUp
	super setUp.
	self replace: #engine of: TLSSocket with: #mbedtls
! !

!TLSSocketMbedTLSTest methodsFor: 'tests'!
testConnectionIsMbedTLS
	"A stalled server: the error comes from the engine's handshake."
	self acceptSilently.
	self should: [TLSSocket connectTo: '127.0.0.1' port: listener localPort timeout: 300] raise: RemoteError withExceptionDo: [:e |
		self assert: (e messageText endsWith: ': TLS handshake: timed out')]
!
testEngineIsAvailable
	self assert: MbedTLSConnection isAvailable
! !
