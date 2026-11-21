Object subclass: #X509Name
	instanceVariableNames: 'der attributes'
	classVariableNames: ''
	package: 'System-TLS'!

X509Name comment: 'I am an X.501 distinguished name as X.509 certificates hold it (an issuer, a subject): a sequence of relative distinguished names, kept as encoded (der) and as attributes, an Array of {oid. value} in order (value a String, or the encoded element for a value that is not a string). Two names are equal when their encodings are, as RFC 5280''s path building mostly finds them (CAs copy the issuer''s subject byte for byte).

	name commonName.	"''Amazon Root CA 1'', nil if none"
	name printString.	"''CN=Amazon Root CA 1, O=Amazon, C=US'' (most significant last)"'!

!X509Name methodsFor: 'accessing'!
der
	^der
!
attributes
	^attributes
!
valueOf: oidString
	"The first value of the attribute oidString, nil if none."
	attributes do: [:each | (each at: 1) = oidString ifTrue: [^each at: 2]].
	^nil
!
commonName
	^self valueOf: '2.5.4.3'
!
organization
	^self valueOf: '2.5.4.10'
! !

!X509Name methodsFor: 'comparing'!
= anObject
	^self class == anObject class and: [der = anObject der]
!
hash
	^der hash
! !

!X509Name methodsFor: 'printing'!
printOn: aStream
	attributes reverse
		do: [:each |
			aStream nextPutAll: (self class shortNameOf: (each at: 1)); nextPut: $=.
			(each at: 2) isString
				ifTrue: [aStream nextPutAll: (each at: 2)]
				ifFalse: [aStream nextPut: $#; nextPutAll: (each at: 2) hex]]
		separatedBy: [aStream nextPutAll: ', ']
! !

!X509Name methodsFor: 'private'!
setDer: bytes
	| outer rdn atv oid value |
	der := bytes.
	attributes := OrderedCollection new.
	outer := (Asn1Der on: bytes) readSequence.
	[outer atEnd] whileFalse: [
		rdn := outer readSet.
		rdn atEnd ifTrue: [^TLSError signal: 'X.509: empty relative distinguished name'].
		[rdn atEnd] whileFalse: [
			atv := rdn readSequence.
			oid := atv readOid.
			value := (#(12 18 19 20 22 26 28 30) includes: atv peekTag)
				ifTrue: [atv readString]
				ifFalse: [atv readElementBytes].
			atv expectEnd.
			attributes add: {oid. value}]].
	attributes := attributes asArray
! !

!X509Name class methodsFor: 'instance creation'!
fromDer: bytes
	"The name encoded in bytes (a whole Name element). TLSError if it is not one."
	^self new setDer: bytes
! !

!X509Name class methodsFor: 'printing'!
shortNameOf: oidString
	#('2.5.4.3' 'CN' '2.5.4.6' 'C' '2.5.4.7' 'L' '2.5.4.8' 'ST' '2.5.4.10' 'O' '2.5.4.11' 'OU' '2.5.4.5' 'serialNumber' '2.5.4.97' 'organizationIdentifier' '1.2.840.113549.1.9.1' 'emailAddress' '0.9.2342.19200300.100.1.25' 'DC')
		pairsDo: [:oid :short | oid = oidString ifTrue: [^short]].
	^oidString
! !
