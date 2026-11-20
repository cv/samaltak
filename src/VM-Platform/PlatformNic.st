VMPlatformModule subclass: #PlatformNic
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PlatformNic comment: 'A raw network interface: Ethernet frames, for a TCP/IP stack in the image (System-Network) where the VM has no sockets of the OS (UEFI: UefiSnp takes my place). A host has none: every call fails with ''no raw network interface'', and the image uses the socket primitives.

open: fills the MAC address (6 bytes); send:length: sends a whole frame (without its checksum); receive:max: answers the length of the next frame received (0: none, -2: failure); frameSemaphore: signals an external semaphore once when a frame is waiting, re-armed by a receive that finds none; counters: answers {frames received, sent, sends that failed (the transmit queue was full), frames waiting}.'!

!PlatformNic methodsFor: 'interface'!
open: mac
	<function>
	<var: #mac type: 'uint8_t *'>
	<returns: 'bool'>
	common setError: 'no raw network interface'.
	^false
!
send: frame length: n
	<function>
	<var: #frame type: 'const uint8_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'bool'>
	common setError: 'no raw network interface'.
	^false
!
receive: buf max: n
	<function>
	<var: #buf type: 'uint8_t *'>
	<var: #n type: 'int64_t'>
	<returns: 'int64_t'>
	common setError: 'no raw network interface'.
	^-2
!
frameSemaphore: index
	<function>
	<var: #index type: 'int32_t'>
	<returns: 'bool'>
	common setError: 'no raw network interface'.
	^false
!
counters: v
	<function>
	<var: #v type: 'int64_t *'>
	<returns: 'bool'>
	common setError: 'no raw network interface'.
	^false
! !
