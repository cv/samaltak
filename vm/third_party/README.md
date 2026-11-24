# Vendored C libraries

The VM's C is translated from Lowtalk (vm/gen), except for what is here and its glue in vm/native (built by
vm/native/native.mk, included by vm/Makefile and vm/uefi.mk). Each library is an unchanged copy of a pinned release,
reproducible from its tarball by the script next to it, with the release's license.

| library | release | from | SHA-256 of the tarball | license | what is taken |
| --- | --- | --- | --- | --- | --- |
| mbedtls | 3.6.8 (LTS, supported to March 2027) | https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.8/mbedtls-3.6.8.tar.bz2 | bc54b818e87f49c0b3281dd85d24adaede0e63b4e822e3fbd49c005a38b9595b | Apache-2.0 (mbedtls/LICENSE; the release is dual Apache-2.0 OR GPL-2.0-or-later, taken under Apache-2.0) | include/, library/ (without its CMake and make files), LICENSE |

**mbedTLS** is the VM's TLS engine (vm/native/tls.c; docs/tls.md), hosted and on UEFI. Its configuration is
mbedTLS's default with vm/native/samaltak_mbedtls_config.h applied (a TLS 1.3 and 1.2 client; no files, sockets,
clocks or OS entropy: the image supplies them); on UEFI it is compiled against the few C library headers of
vm/native/uefi-include, its C library VM-UEFI's UefiLibC plus vm/native/uefi_libc.c (string search, snprintf, time,
128-bit division).

To update: change VERSION and SHA256 in vendor-mbedtls.sh (the release's `-sha256sum.txt` has it), run it, and
review the diff (ChangeLog in the release). Track the 3.6 LTS releases for their security fixes; 4.x (PSA only,
TF-PSA-Crypto) before 3.6's end of support.
