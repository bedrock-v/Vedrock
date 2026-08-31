# Building Vedrock on Windows (OpenSSL)

Vedrock reaches OpenSSL only through vlib's `crypto.ecdsa` which the
NetherNet/DTLS identity path and the Bedrock encryption handshake both use.
Vedrock declares no OpenSSL symbols of its own, so the setup below is just what
`crypto.ecdsa` needs.

## 1. Install OpenSSL

Any 3.x or 4.x build with development headers works. The default locations
`vlib/crypto/ecdsa` probes for are:

```
C:\Program Files\OpenSSL-Win64\include
C:\Program Files\OpenSSL-Win64\lib\VC\x64\MD
C:\Program Files\OpenSSL\include
C:\Program Files\OpenSSL\lib\VC\x64\MD
```

## 2. Point the compiler at a non default install

If OpenSSL lives anywhere else, set these before building. With GCC/MinGW:

```
set C_INCLUDE_PATH=C:\Program Files\OpenSSL Library\openssl-4.0\include
set LIBRARY_PATH=C:\Program Files\OpenSSL Library\openssl-4.0\lib
```

Then build with GCC explicitly:

```
v -cc gcc -o vedrock.exe .
```

The bundled TCC does not reliably find OpenSSL on Windows; use GCC.

## 3. Runtime DLLs

`libcrypto-*.dll` (and `libssl-*.dll`) must be on `PATH` or beside the
executable at run time. A build that links cleanly can still fail to start
without them.

## Verifying the toolchain in isolation

```v
import crypto.ecdsa

fn main() {
	private_key, public_key := ecdsa.generate_key() or {
		eprintln('generate_key failed: ${err}')
		return
	}
	_ = private_key
	_ = public_key
	println('ecdsa key generated successfully')
}
```

```
v -cc gcc run test_ecdsa.v
```

If this prints `ecdsa key generated successfully`, headers, import library and
DLLs are all in order and any remaining failure is in Vedrock or in the V
compiler rather than in the OpenSSL setup.

## Historical note: the `C.EVP_PKEY` build failure

`server/internal/encryption` used to declare its own OpenSSL EVP/BIO bindings,
because `crypto.ecdsa` keeps its `EVP_PKEY` handle private. That overlapped 20
functions and 6 opaque types with `crypto.ecdsa`.

V keeps both declarations rather than merging them, and `C.EVP_PKEY` existed
twice in the type table. On compilers before `vlang/v@dff6356` (2026-07-28) a
`fn C.x` declaration also resolved globally, last parsed wins, across module
boundaries. So `crypto.ecdsa` could end up calling a declaration whose return
type was the *other* `C.EVP_PKEY`, and failed to compile itself:

```
vlib/crypto/ecdsa/ecdsa.v:649:2: error:
  `&C.EVP_PKEY` doesn't implement method `msg` of interface `IError`
  cannot use `C.EVP_PKEY` as type `!&C.EVP_PKEY` in return argument
```

It reproduced only with a particular module parse order which is why the same
tree built on one machine and not another.

Vedrock no longer declares any OpenSSL symbol, so this can't recur here. Prefer a V build from 2026-07-28 or later.

Thanks to [thekevin1](https://github.com/thekevin1) - Discord @zlhern for reporting the problem.
