# Cryptography

`System-Crypto` (layer 0) is cryptography in Smalltalk, for the TLS 1.3 client where the VM has no OpenSSL (UEFI, docs/uefi.md): hashes, MACs, key derivation; the public-key half (X25519, RSA and ECDSA signatures) is its own part of the same package. Tests: `Tests-Crypto`, against the standards' own vectors.

## API

- **Hashes** (`CryptoHash`): `SHA256 hash: bytes` → a ByteArray; incremental `SHA256 new update: bytes; update: more; digest`; `digest` finishes a copy, so the hash goes on (a TLS transcript's running hash), and `copy` forks it. Class side `digestSize` and `blockSize` (bytes). A String is hashed as its UTF-8.
- **HMAC** (RFC 2104): `HMAC hash: SHA256 key: k message: m`, or incremental `(HMAC hash: SHA256 key: k) update: m; digest`.
- **HKDF** (RFC 5869): `HKDF hash: SHA256 extract: salt ikm: ikm` → the PRK, `HKDF hash: SHA256 expand: prk info: info length: n` (n at most 255 blocks).
- **Errors**: `CryptoError` (an Error): a tag that does not verify, sizes out of range.
- **Bytes**: `ByteArray>>constantTimeEquals:` compares MACs and tags in time that depends on their sizes only; `ByteArray fromHex:` reads test vectors.

## How

Everything is SmallInteger arithmetic: SmallIntegers have 63 bits (signed, docs/implementation.md), so a 32-bit word shifted left by up to 30 bits is one, and the JIT's optimizing tier (docs/jit.md) compiles `bitAnd: bitOr: bitXor: bitShift: + at: at:put:` on them inline. SHA-256 keeps its state words in temps and its schedule and round constants in Arrays; a rotation right by n is a shift right ored with the word shifted left by 32 - n and masked to 32 bits, the left shifts of Σ0 and Σ1 xored first and masked once, sums of up to five words masked once.

## Performance

Measured with `--jit opt` (the default) on arm64 (hosted): SHA-256 about 50 MB/s (4 MB in 76 ms).
