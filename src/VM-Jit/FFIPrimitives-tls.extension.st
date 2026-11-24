!FFIPrimitives methodsFor: 'tls engine exports'!
nativeTlsSeed: bytes length: bytesLen
	<function>
	<approvedFFI: 700 symbol: 'core_tls_seed' arguments: #(8) result: 3>
	<var: #bytes type: 'const uint8_t *'>
	<var: #bytesLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls seed: bytes length: bytesLen
!
nativeTlsSetTime: seconds
	<function>
	<approvedFFI: 701 symbol: 'core_tls_set_time' arguments: #(3) result: 3>
	<var: #seconds type: 'int64_t'>
	<returns: 'int64_t'>
	^nativeTls setTime: seconds
!
nativeTlsStoreNew
	<function>
	<approvedFFI: 702 symbol: 'core_tls_store_new' arguments: #() result: 3>
	<returns: 'int64_t'>
	^nativeTls storeNew
!
nativeTlsStoreAdd: storeId der: der length: derLen
	<function>
	<approvedFFI: 703 symbol: 'core_tls_store_add' arguments: #(3 8) result: 3>
	<var: #storeId type: 'int64_t'>
	<var: #der type: 'const uint8_t *'>
	<var: #derLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls storeAdd: storeId der: der length: derLen
!
nativeTlsStoreFree: storeId
	<function>
	<approvedFFI: 704 symbol: 'core_tls_store_free' arguments: #(3) result: 3>
	<var: #storeId type: 'int64_t'>
	<returns: 'int64_t'>
	^nativeTls storeFree: storeId
!
nativeTlsOpen: storeId host: host length: hostLen
	<function>
	<approvedFFI: 705 symbol: 'core_tls_new' arguments: #(3 8) result: 3>
	<var: #storeId type: 'int64_t'>
	<var: #host type: 'const uint8_t *'>
	<var: #hostLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls open: storeId host: host length: hostLen
!
nativeTlsHandshake: h in: in length: inLen out: out length: outLen
	<function>
	<approvedFFI: 706 symbol: 'core_tls_handshake' arguments: #(3 8 9) result: 3>
	<var: #h type: 'int64_t'>
	<var: #in type: 'const uint8_t *'>
	<var: #inLen type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #outLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls handshake: h in: in length: inLen out: out length: outLen
!
nativeTlsRead: h into: plain length: plainLen in: in length: inLen
	<function>
	<approvedFFI: 707 symbol: 'core_tls_read' arguments: #(3 9 8) result: 3>
	<var: #h type: 'int64_t'>
	<var: #plain type: 'uint8_t *'>
	<var: #plainLen type: 'uint64_t'>
	<var: #in type: 'const uint8_t *'>
	<var: #inLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls read: h into: plain length: plainLen in: in length: inLen
!
nativeTlsWrite: h bytes: plain length: plainLen out: out length: outLen
	<function>
	<approvedFFI: 708 symbol: 'core_tls_write' arguments: #(3 8 9) result: 3>
	<var: #h type: 'int64_t'>
	<var: #plain type: 'const uint8_t *'>
	<var: #plainLen type: 'uint64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #outLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls write: h bytes: plain length: plainLen out: out length: outLen
!
nativeTlsTake: h out: out length: outLen
	<function>
	<approvedFFI: 709 symbol: 'core_tls_take' arguments: #(3 9) result: 3>
	<var: #h type: 'int64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #outLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls take: h out: out length: outLen
!
nativeTlsClose: h out: out length: outLen
	<function>
	<approvedFFI: 710 symbol: 'core_tls_close' arguments: #(3 9) result: 3>
	<var: #h type: 'int64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #outLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls close: h out: out length: outLen
!
nativeTlsInfo: h what: what into: out length: outLen
	<function>
	<approvedFFI: 711 symbol: 'core_tls_info' arguments: #(3 3 9) result: 3>
	<var: #h type: 'int64_t'>
	<var: #what type: 'int64_t'>
	<var: #out type: 'uint8_t *'>
	<var: #outLen type: 'uint64_t'>
	<returns: 'int64_t'>
	^nativeTls info: h what: what into: out length: outLen
!
nativeTlsRelease: h
	<function>
	<approvedFFI: 712 symbol: 'core_tls_free' arguments: #(3) result: 3>
	<var: #h type: 'int64_t'>
	<returns: 'int64_t'>
	^nativeTls release: h
! !
