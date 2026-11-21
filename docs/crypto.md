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
