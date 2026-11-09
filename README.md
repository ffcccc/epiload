# epiload

`bed-reader-cpp` is the C++ interface in this repository for reading PLINK `.bed`
genetic variant datasets. It wraps the Rust
[bed-reader](https://github.com/fastlmm/bed-reader) engine using
[`cxx`](https://cxx.rs/) to provide a type-checked boundary between Rust and C++.

## Overview

The goal is to make the Rust engine, also used by bed-reader's Python interface,
available to existing C++ genomic analysis pipelines.

- **Performance:** Uses bed-reader's multi-threaded reading and `ndarray` support.
- **Safety:** Uses `cxx` types and ownership conventions rather than a handwritten
	raw-pointer interface.
- **Interoperability:** Exposes a small C++ API for opening datasets, querying
	sample and variant counts, and reading genotypes as floating-point values.

The current bridge exposes reading only. Although the upstream engine supports
writing, write operations are not yet exposed by this wrapper. Reading all
genotypes materializes the full matrix in memory.

## Future R Integration

A future goal is to provide an R extension using `Rcpp` around this C++ interface.
No R bindings are currently included. Consumers must use compatible compiler,
architecture, and runtime settings; the bridge does not promise a stable C++ ABI
across toolchains.

## Building

GNU Make is the reference build interface; Microsoft's `nmake` is not supported.
Only native x64 builds are supported. Cross-compilation and macOS are not configured.

| Setting | Windows | Linux (including WSL) |
| --- | --- | --- |
| Rust target | `x86_64-pc-windows-msvc` | `x86_64-unknown-linux-gnu` |
| Recipe shell | `cmd.exe` from `COMSPEC`, `/D /S /C` | `/bin/bash`, `-eu -o pipefail -c` |
| Bootstrap Python | `py` | `python3` |
| Python environment | `.venv` | `.venv-linux` |
| C/C++ toolchain | MSVC `cl`, Windows SDK | `gcc` and `g++`, glibc development files |
| Rust library | `bed_reader_bridge.lib` | `libbed_reader_bridge.a` |
| Demo | `build/<target>/demo.exe` | `build/<target>/demo` |

### Prerequisites

Both platforms require x64 Python 3.12+ with `venv` and pip, Rust installed through
[rustup](https://rustup.rs/), and GNU Make. `setup` installs PyYAML into the local
environment. `bed-reader` requires Python at Rust build time; Make exports
`PYO3_PYTHON` automatically, defaulting to the selected environment's interpreter.
An existing environment variable or Make command-line assignment can override it.

On Windows, install native Windows GNU Make (tested with the WinGet package
`ezwinports.make`) and Visual Studio C++ Build Tools with x64 C++ tools and a
Windows SDK. Make discovers Build Tools through `vswhere` and initializes
`VsDevCmd.bat` for both Cargo and the demo compiler. Use the MSVC Rust toolchain:

```text
rustup toolchain install stable-x86_64-pc-windows-msvc
rustup default stable-x86_64-pc-windows-msvc
rustup target add x86_64-pc-windows-msvc
```

On Linux, install Bash, GNU Make, GCC/G++, development headers, and Python's venv
support using your distribution's packages. Install Rust's native GNU toolchain:

```bash
rustup toolchain install stable-x86_64-unknown-linux-gnu
rustup default stable-x86_64-unknown-linux-gnu
rustup target add x86_64-unknown-linux-gnu
```

### Shells and VS Code

The Makefile uses GNU Make syntax, while recipes use the explicitly selected host
shell shown above. The terminal launching Make does not choose the recipe shell.
PowerShell, CMD, and Git Bash can launch the same native Windows Make executable;
Git Bash does not select Linux or MinGW/GCC builds. MSYS/Cygwin Make is not the
supported Windows Make distribution. WSL is Linux: use Linux Python, Rust, and GCC
inside WSL, not the Windows executables. Never share a venv across the two hosts.

Open the folder locally on Windows or through VS Code Remote WSL on Linux.
`.vscode/tasks.json` invokes Make as a process from the project root, avoiding
terminal-specific command quoting. It provides setup, doctor, build, dependency,
test, and install tasks. GNU Make must be on the VS Code process's `PATH`.

### Build Commands

Run these commands from the project root on either platform:

```text
make setup
make doctor
make
make test
make install
```

`make` fetches manifest dependencies and builds the demo. `make rust` builds only
the Rust library, using `Cargo.lock`. `make test` checks the fetcher without
network downloads. The demo uses Cargo's generated header directly, so no prior
`install` is needed. For a dataset smoke test, supply a BED path with its matching
`.bim` and `.fam` files beside it:

```text
make smoke SMOKE_BED="path/to/study.bed"
```

The default smoke path is `data/bed-sample-files/small.bed`; sample data is not
tracked in this repository. Demo invocation examples:

```powershell
.\build\x86_64-pc-windows-msvc\demo.exe "C:\data\study.bed"
```

```bash
./build/x86_64-unknown-linux-gnu/demo /data/study.bed
```

`make clean` removes the current platform's demo/object directory, not Cargo's
cache, installed packages, or Python environment. Use `make clean-deps` to remove
fetched dependencies. Tool variables such as `BOOTSTRAP_PYTHON`, `PYTHON`, `CC`,
`CXX`, `CARGO`, and `RUSTUP` can be overridden on Make's command line. For example:

```text
make setup BOOTSTRAP_PYTHON=python3.12
```

`BOOTSTRAP_PYTHON` is a command that may include arguments; quote an executable
path containing spaces inside that command. `PYTHON` is an executable path only.
`RUST_TARGET` defaults to the host's supported target; incompatible overrides fail
immediately. Separate checkouts are recommended for simultaneous Windows/WSL
builds, since generated headers and the dependency staging directory are shared.

### External Dependencies

`deps.yaml` retains its existing platform keys, `windows-x86_64` and
`linux-x86_64`. Each dependency needs a version and a release asset URL with a
bare SHA-256 checksum for each supported platform. ZIP and TAR archives are
supported; `.7z` is not. Dependencies are extracted under
`3rdparty/<name>/<version>/`. Empty manifests are valid. A `.ready` marker skips
installed dependencies only when its platform also matches the requested host.

```text
make deps
make deps-force
make deps DEPS_MANIFEST=other-deps.yaml DEPS_ROOT=other-deps
```

`FETCHER` can also be overridden to select another compatible script. `deps-force`
redownloads and replaces installed versions. There are currently no active
external entries in this project's manifest; Cargo handles Rust dependencies.

### Installing and Packaging

`make install` builds the Rust bridge, stages its artifacts, and creates a ZIP
using Python's standard library; PowerShell and external archivers are not required.
The archive `bed-reader-cpp/bed-reader-cpp_<target>.zip` contains:

```text
include/bed_reader_bridge.h
libs/<target>/<platform-specific Rust static library>
```

This is local staging, not a system-wide installation. Consumers add the staged
`include` directory to their search path and link the library plus its native
system libraries. Windows system libraries are listed in the Makefile; the demo
uses `/MD`. Linux builds extract native link flags from Rust's
`--print native-static-libs` output into `build/<target>/native-libs.rsp` and pass
that response file after the Rust library when linking with G++. Use compatible
compiler, runtime, glibc, and C++ ABI settings when distributing binaries.

## Usage Example

After running the `install` target, an application using the staged header can use:

```cpp
#include "bed_reader_bridge.h"
#include <exception>
#include <iostream>

int main(int argc, char* argv[]) {
	if (argc != 2) {
		std::cerr << "Usage: " << argv[0] << " <filename.bed>\n";
		return 1;
	}

	try {
		auto bed = new_bed(argv[1]);
		std::cout << "Samples (IID): " << bed->get_iid_count() << '\n';
		std::cout << "Variants (SID): " << bed->get_sid_count() << '\n';

		auto genotypes = bed->read_all_genotypes();
		std::cout << "Read " << genotypes.size() << " genotype values.\n";
	} catch (const std::exception& error) {
		std::cerr << "Error: " << error.what() << '\n';
		return 1;
	}
	return 0;
}
```

`new_bed` returns a `rust::Box<BedWrapper>`, and `read_all_genotypes` returns a
`rust::Vec<float>`, not a `std::vector<float>`. Rust errors returned through the
bridge become C++ exceptions. The repository's demo includes the header directly
from Cargo's generated directory instead of requiring the install step.

## Project Structure

```text
Cargo.toml                 Rust package and dependencies
Makefile                   Native Windows/MSVC and Linux/GCC builds
build.rs                   CXX bridge generation and compilation
src/lib.rs                 Bridge declarations and Rust implementation
scripts/                   Dependency fetcher and its regression tests
.vscode/tasks.json         Process-based Make tasks
build/<target>/            Demo, object files, Linux native link flags
bed-reader-cpp/
  demo.cpp                 Command-line C++ example
  include/                 Locally staged header (make install)
  libs/                    Locally staged static library (make install)
target/
  cxxbridge/               Generated C++ headers
  release/                 Default-target Rust release artifacts
	<target>/release/        Explicit-target Rust release artifacts
```

## Acknowledgments

This project builds on [bed-reader](https://github.com/fastlmm/bed-reader),
developed by the FaST-LMM team. Their Rust engine provides the underlying PLINK
file handling and multi-threaded reading capabilities.

## Licensing

The upstream bed-reader library is licensed under Apache-2.0. That does not
automatically establish a license for this wrapper; consult the applicable
project and dependency license terms when redistributing it.
