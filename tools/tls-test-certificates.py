#!/usr/bin/env python3
"""Generate the certificates X509CertificateTest and TrustStoreTest parse: src/Tests-TLS/TLSTestCertificates.st.

usage: tools/tls-test-certificates.py [OUTPUT]   (needs python3-cryptography)

A test root and intermediate (P-256, P-384, ECDSA), an RSA hierarchy (RSA-2048; sha512WithRSAEncryption,
sha384WithRSAEncryption, RSASSA-PSS), a cross-signed root, and leaves that break one rule each: expired, not yet
valid, wrong issuer, a non-CA issuer, a path length exceeded, an issuer without keyCertSign, a client-only leaf, an
unknown critical extension. Validity periods are fixed (the tests validate in 2025); keys are new on every run.
"""
import base64, datetime, ipaddress, sys
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID, ObjectIdentifier
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa, padding

output = sys.argv[1] if len(sys.argv) > 1 else 'src/Tests-TLS/TLSTestCertificates.st'

def t(y, m=1, d=1):
    return datetime.datetime(y, m, d, tzinfo=datetime.timezone.utc)

def name(cn):
    return x509.Name([x509.NameAttribute(NameOID.COUNTRY_NAME, 'US'), x509.NameAttribute(NameOID.ORGANIZATION_NAME, 'Samaltak Test'),
                      x509.NameAttribute(NameOID.COMMON_NAME, cn)])

def ku(sign=False, cert=False):
    return x509.KeyUsage(digital_signature=sign, content_commitment=False, key_encipherment=False, data_encipherment=False,
                         key_agreement=False, key_cert_sign=cert, crl_sign=cert, encipher_only=False, decipher_only=False)

serial = [1000]
def cert(subject, key, issuer, issuer_key, ca, path_len=None, start=t(2020), end=t(2040), names=None, ips=None,
         key_usage=None, eku=None, extra=None, hash_alg=hashes.SHA256(), pss=False):
    serial[0] += 1
    b = (x509.CertificateBuilder().subject_name(name(subject)).issuer_name(name(issuer)).public_key(key.public_key())
         .serial_number(serial[0]).not_valid_before(start).not_valid_after(end))
    b = b.add_extension(x509.BasicConstraints(ca=ca, path_length=path_len), critical=True)
    b = b.add_extension(key_usage if key_usage is not None else (ku(cert=True) if ca else ku(sign=True)), critical=True)
    if eku is not None:
        b = b.add_extension(x509.ExtendedKeyUsage(eku), critical=False)
    if names or ips:
        alt = [x509.DNSName(n) for n in (names or [])] + [x509.IPAddress(ipaddress.ip_address(i)) for i in (ips or [])]
        b = b.add_extension(x509.SubjectAlternativeName(alt), critical=False)
    b = b.add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
    for ext, critical in (extra or []):
        b = b.add_extension(ext, critical=critical)
    if pss:
        return b.sign(issuer_key, hash_alg, rsa_padding=padding.PSS(mgf=padding.MGF1(hash_alg), salt_length=hash_alg.digest_size))
    return b.sign(issuer_key, hash_alg)

p256 = lambda: ec.generate_private_key(ec.SECP256R1())
p384 = lambda: ec.generate_private_key(ec.SECP384R1())
rsa2048 = lambda: rsa.generate_private_key(public_exponent=65537, key_size=2048)
server = [ExtendedKeyUsageOID.SERVER_AUTH]

root_key, inter_key, leaf_key = p256(), p384(), p256()
certs = {}
certs['root'] = cert('Samaltak Test Root', root_key, 'Samaltak Test Root', root_key, True)
certs['intermediate'] = cert('Samaltak Test Intermediate', inter_key, 'Samaltak Test Root', root_key, True, path_len=0, end=t(2039), eku=server)
leaf_args = dict(names=['test.example.com', '*.wild.example.com'], ips=['10.0.2.2'], eku=server, hash_alg=hashes.SHA384())
certs['leaf'] = cert('test.example.com', leaf_key, 'Samaltak Test Intermediate', inter_key, False, start=t(2024), end=t(2034), **leaf_args)
certs['expiredLeaf'] = cert('test.example.com', leaf_key, 'Samaltak Test Intermediate', inter_key, False, start=t(2020), end=t(2021), **leaf_args)
certs['futureLeaf'] = cert('test.example.com', leaf_key, 'Samaltak Test Intermediate', inter_key, False, start=t(2030), end=t(2034), **leaf_args)
other_key = p256()
certs['otherRoot'] = cert('Samaltak Test Root', other_key, 'Samaltak Test Root', other_key, True)
certs['otherLeaf'] = cert('test.example.com', leaf_key, 'Samaltak Test Root', other_key, False, start=t(2024), end=t(2034), **leaf_args)
ee_key = p256()
certs['endEntityIssuer'] = cert('Samaltak Test End Entity', ee_key, 'Samaltak Test Root', root_key, False, eku=server, names=['ee.example.com'])
certs['leafOfEndEntity'] = cert('test.example.com', leaf_key, 'Samaltak Test End Entity', ee_key, False, start=t(2024), end=t(2034), **leaf_args)
inter2_key = p256()
certs['intermediate2'] = cert('Samaltak Test Intermediate 2', inter2_key, 'Samaltak Test Intermediate', inter_key, True, hash_alg=hashes.SHA384())
certs['leafOfIntermediate2'] = cert('test.example.com', leaf_key, 'Samaltak Test Intermediate 2', inter2_key, False, start=t(2024), end=t(2034), **leaf_args)
nosign_key = p256()
certs['noCertSignIssuer'] = cert('Samaltak Test No Cert Sign', nosign_key, 'Samaltak Test Root', root_key, True, key_usage=ku(sign=True))
certs['leafOfNoCertSign'] = cert('test.example.com', leaf_key, 'Samaltak Test No Cert Sign', nosign_key, False, start=t(2024), end=t(2034), **leaf_args)
certs['clientLeaf'] = cert('test.example.com', leaf_key, 'Samaltak Test Intermediate', inter_key, False, start=t(2024), end=t(2034),
                           names=['test.example.com'], eku=[ExtendedKeyUsageOID.CLIENT_AUTH], hash_alg=hashes.SHA384())
certs['criticalLeaf'] = cert('test.example.com', leaf_key, 'Samaltak Test Intermediate', inter_key, False, start=t(2024), end=t(2034),
                             extra=[(x509.UnrecognizedExtension(ObjectIdentifier('1.3.6.1.4.1.55555.1'), b'\x05\x00'), True)], **leaf_args)
cross_key = p256()
certs['crossRoot'] = cert('Samaltak Cross Root', cross_key, 'Samaltak Cross Root', cross_key, True)
certs['crossRootByRoot'] = cert('Samaltak Cross Root', cross_key, 'Samaltak Test Root', root_key, True, end=t(2039))
certs['crossLeaf'] = cert('cross.example.com', leaf_key, 'Samaltak Cross Root', cross_key, False, start=t(2024), end=t(2034), names=['cross.example.com'], eku=server)
rsa_root, rsa_inter, rsa_leaf = rsa2048(), rsa2048(), rsa2048()
certs['rsaRoot'] = cert('Samaltak RSA Root', rsa_root, 'Samaltak RSA Root', rsa_root, True, hash_alg=hashes.SHA512())
certs['rsaIntermediate'] = cert('Samaltak RSA Intermediate', rsa_inter, 'Samaltak RSA Root', rsa_root, True, hash_alg=hashes.SHA384(), eku=server)
certs['rsaLeaf'] = cert('rsa.example.com', rsa_leaf, 'Samaltak RSA Intermediate', rsa_inter, False, start=t(2024), end=t(2034),
                        names=['rsa.example.com'], eku=server, pss=True)

def st_string(s):
    return "'" + s.replace("'", "''") + "'"

lines = ["Object subclass: #TLSTestCertificates", "\tinstanceVariableNames: ''", "\tclassVariableNames: ''", "\tpackage: 'Tests-TLS'!", "",
         "TLSTestCertificates comment: " + st_string('I am generated by tools/tls-test-certificates.py: certificates for X509CertificateTest and TrustStoreTest, '
         'each a class method answering its DER (TLSTestCertificates named: #leaf). Do not edit me, regenerate me.') + "!", "",
         "!TLSTestCertificates class methodsFor: 'accessing'!",
         "named: aSymbol", '\t"The DER of the certificate aSymbol."', "\t^Base64 decode: (self perform: aSymbol)", "! !", "",
         "!TLSTestCertificates class methodsFor: 'certificates'!"]
methods = []
for key in certs:
    der = certs[key].public_bytes(serialization.Encoding.DER)
    b64 = base64.b64encode(der).decode()
    methods.append(key + "\n\t^" + st_string(b64))
lines.append("\n!\n".join(methods))
lines.append("! !")
open(output, 'w', newline='\n').write('\n'.join(lines) + '\n')
print('%s: %d certificates' % (output, len(certs)))
