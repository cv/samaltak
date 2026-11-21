# Cryptography

`System-Crypto` (layer 0) is cryptography in Smalltalk, for the TLS 1.3 client where the VM has no OpenSSL (UEFI, docs/uefi.md): hashes, MACs, key derivation, authenticated encryption; the public-key half (X25519, RSA and ECDSA signatures) is its own part of the same package. Tests: `Tests-Crypto`, against the standards' own vectors.

## API

- **Hashes** (`CryptoHash`): `SHA256`, `SHA384`, `SHA512`. `SHA256 hash: bytes` → a ByteArray; incremental `SHA256 new update: bytes; update: more; digest`; `digest` finishes a copy, so the hash goes on (a TLS transcript's running hash), and `copy` forks it. Class side `digestSize` and `blockSize` (bytes). A String is hashed as its UTF-8.
- **HMAC** (RFC 2104): `HMAC hash: SHA256 key: k message: m`, or incremental `(HMAC hash: SHA256 key: k) update: m; digest`.
- **HKDF** (RFC 5869): `HKDF hash: SHA256 extract: salt ikm: ikm` → the PRK, `HKDF hash: SHA256 expand: prk info: info length: n` (n at most 255 blocks).
- **AEAD**: `(ChaCha20Poly1305 key: k) encrypt: plaintext nonce: n aad: a` → the ciphertext with the 16-byte tag appended; `decrypt:nonce:aad:` → the plaintext, or `CryptoError` if the tag does not verify (checked in constant time before anything is decrypted). Class side `keySize`, `nonceSize`, `tagSize`.
- **Primitives under the AEAD**: `ChaCha20 key: k nonce: n counter: c` (`xor:`, `xor:from:to:into:at:`, `nextBlock`), `Poly1305 key: k message: m` (incremental as HMAC).
- **Errors**: `CryptoError` (an Error): a tag that does not verify, keys and nonces of the wrong size, a ChaCha20 counter that wraps, HKDF beyond its limit.
- **Bytes**: `ByteArray>>constantTimeEquals:` compares MACs and tags in time that depends on their sizes only; `ByteArray fromHex:` reads test vectors.

## How

Everything is SmallInteger arithmetic, no LargeInteger in any loop: SmallIntegers have 63 bits (signed, docs/implementation.md), and the JIT's optimizing tier (docs/jit.md) compiles `bitAnd: bitOr: bitXor: bitShift: + * at: at:put:` on them inline, with the working words in temps.

- SHA-256 and ChaCha20 work on 32-bit words. A 32-bit word shifted left by up to 30 bits still is a SmallInteger, so a rotation is a shift right ored (or xored) with a shift left masked to 32 bits; SHA-256 xors the three left shifts of Σ0 and Σ1 first and masks once, and masks sums of up to five words once. ChaCha20's twenty rounds are unrolled over sixteen temps; its key stream is xored a 32-bit word at a time (`uint32At:`, little-endian as ChaCha20).
- SHA-512's 64-bit words do not fit: each is two 32-bit halves, a rotation by n < 32 takes each half's top bits from the other half (by n ≥ 32 they swap first), and a sum carries the low halves' bits above 32 into the high one.
- Poly1305's accumulator and r are five 26-bit limbs (poly1305-donna's 32-bit layout): a product of limbs is below 2^56 and a sum of five below 2^60. The final reduction modulo 2^130 - 5 picks h or h - p by masks, not by a branch.
- Nothing here is hardened against timing beyond the tag comparison and Poly1305's last step: the JIT may branch where the source does not.

## Performance

4 MB at once, `--jit opt` (the default), hosted on arm64 (an NVIDIA GB10, Linux): SHA-256 50 MB/s (79 ms), SHA-512 27 MB/s (149 ms), ChaCha20-Poly1305 68 MB/s encrypting (59 ms; ChaCha20 49 ms, Poly1305 7 ms of it) and decrypting; 1000 TLS-sized records of 100 bytes in 7 ms.

## Public-key cryptography

X25519 key agreement, ECDH on P-256 and P-384, and the signature verifications TLS 1.3 and X.509 need: RSA PKCS #1 v1.5 and RSA-PSS, ECDSA on P-256 and P-384. Only verification: a TLS client signs nothing. Certificates are docs/certificates.md.

- **X25519** (RFC 7748): `X25519 newPrivateKey` (32 bytes of `SecureRandom`), `X25519 publicKeyFor: priv`, `X25519 sharedSecret: priv peer: pub` (32-byte ByteArrays, little-endian as the RFC encodes them; CryptoError if the secret is all zeros, a peer key of small order, as TLS 1.3 requires); `X25519 scalar: k u: u` is the bare function.
- **RSA** (RFC 8017): `RsaPublicKey modulus: n exponent: e` (1024 to 8192 bits, else CryptoError); `verifyPkcs1: sig message: m hash: SHA256` (SHA384, SHA512; the DigestInfo is rebuilt and compared byte for byte, its NULL parameters required); `verifyPss: sig message: m hash: SHA256` (MGF1 with the same hash, the salt as long as the hash: TLS 1.3's rsa_pss_rsae_* and rsa_pss_pss_*), `verifyPss:message:hash:saltLength:` for another salt length, or any if nil (certificates give theirs in the algorithm's parameters). The `...digest:` variants take a precomputed digest. A malformed signature is false, never an error.
- **ECDSA** (FIPS 186-4, SEC 1): `EcPublicKey curve: #p256 point: bytes` (or #p384; the uncompressed point 04 || X || Y, CryptoError unless on the curve), `verify: derSignature message: m hash: SHA256` → Boolean: strict DER, r and s in [1, n-1], a longer digest truncated to the order's bits.
- **ECDH** (SEC 1, 3.3.1): `EcPrivateKey newOn: #p256` (or #p384), `publicKeyBytes` (uncompressed: the TLS key share), `sharedSecret: peerBytes` → X of the shared point (CryptoError unless the peer's point is on the curve).

**How.** Integers are the VM's LargeIntegers, whose arithmetic is primitives (32-bit limbs, schoolbook multiplication, Knuth's division), reduced modulo the prime after each product: at these sizes that beats Montgomery or special-prime reduction written in Smalltalk. X25519 is RFC 7748's Montgomery ladder, inverting by Fermat. `EcCurve` holds P-256 and P-384 (a = -3) with points in Jacobian coordinates (doubling dbl-2001-b, general addition, one inversion for the result); ECDSA computes u1·G + u2·Q with Shamir's trick. RSA verification is s^e mod n, square and multiply. **Not constant-time**: the primitives' running time and allocations depend on the values, and the ladder's swaps and the double-and-add are branches. That does not matter for verification (no secrets) and is tolerable for ephemeral key agreement against a network observer; there are no long-term private keys.

**Tests** (`Tests-Crypto`): RFC 7748's vectors (the iterated one to 1000 iterations, the Diffie-Hellman example), and subsets of Project Wycheproof (`WycheproofVectors`, generated by `tools/wycheproof-subset.py` from its JSON files: one test of each flag and comment, at most 30 a file) of x25519, ecdh_secp256r1_ecpoint, ecdsa_secp256r1_sha256, ecdsa_secp384r1_sha384 and _sha256, rsa_signature_2048_sha256, 3072_sha384 and 4096_sha512, rsa_pss_2048_sha256_mgf1_32, 4096_sha384_mgf1_48 and 2048_sha256_mgf1_0. The whole files pass too (3566 tests, the 'acceptable' ones left out), run once through the same calls from a script.

**Performance**, `--jit opt` hosted on arm64 (an NVIDIA GB10, Linux): X25519 0.7 ms; ECDSA verification P-256 1.2 ms, P-384 2.8 ms; RSA-2048 verification PKCS #1 v1.5 0.13 ms, PSS 0.22 ms; RSA-4096 0.5 ms.
