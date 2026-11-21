#!/bin/sh
# An HTTPS test server for the TLS client (make test-uefi): a test CA and a server certificate (P-256 ECDSA, for localhost,
# 127.0.0.1 and 10.0.2.2, QEMU's host) made in DIR, then openssl s_server -tls1_3 -www on PORT in the background (its pid
# in DIR/pid). The CA's DER, in hex, is DIR/ca.hex: the guest trusts it (TrustStore new add: (ByteArray fromHex: ...)).
# usage: tools/tls-test-server.sh DIR PORT [s_server option...]     stop: kill $(cat DIR/pid)
set -eu
DIR=$1 PORT=$2
shift 2
mkdir -p "$DIR"
cd "$DIR"
key() { openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1" 2>/dev/null; }
key ca.key
openssl req -x509 -key ca.key -out ca.pem -days 2 -subj "/CN=Samaltak Test CA" \
	-addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign 2>/dev/null
key server.key
openssl req -new -key server.key -out server.csr -subj /CN=localhost 2>/dev/null
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1,IP:10.0.2.2\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n' > ext.cnf
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 2 -extfile ext.cnf 2>/dev/null
openssl x509 -in ca.pem -outform DER | od -An -v -tx1 | tr -d ' \n' > ca.hex
openssl s_server -accept "$PORT" -tls1_3 -cert server.pem -key server.key -www "$@" > server.log 2>&1 < /dev/null &
echo $! > pid
i=0
until grep -q ACCEPT server.log; do
	i=$((i + 1))
	[ $i -gt 100 ] && { echo "tls-test-server: s_server did not start: $(cat server.log)" >&2; exit 1; }
	sleep 0.1
done
