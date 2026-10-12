# Local Windows compatibility fix

`ech_http` is an unmodified copy of pub.dev version 0.2.1 except for
`src/CMakeLists.txt` and `src/ca_bundle.h.in`.

MSVC rejects the original 188,900-byte CA certificate raw string with error C2026.
The local fix embeds the same file as a byte array and constructs the same
`std::string`. Certificate verification and all certificate contents are preserved.
MSVC also receives `/utf-8` to read upstream headers consistently on Chinese Windows.

`../pubspec_overrides.yaml` selects this local package. The package's MIT license
and dependency licenses are retained. Run `tools/setup_angle.ps1`, `flutter pub get`, then `flutter build windows`
from the project root. The override also survives `flutter clean` and dependency-cache repairs.

The app analyzer excludes this vendored dependency's own development files,
which use a separate package test setup. The native CA embedding change is
verified by compiling a small local C++ probe against `src/ca_bundle.h.in` and
comparing its emitted bytes with `src/cacert.pem` using SHA-256.
