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

## Building on Windows

### Prerequisites

- [Rust](https://rustup.rs/) with the `x86_64-pc-windows-msvc` toolchain.
- Visual Studio C++ Build Tools with x64 C++ tools and a Windows SDK.
- Python 3.
- GNU Make, available as `make` or `mingw32-make`. The Makefile is not compatible
	with Microsoft's `nmake`.

The supplied Makefile targets Windows x64 with MSVC. Linux and macOS builds are
not configured by this Makefile.

### Building the Rust Bridge

`bed-reader` 1.1.1 requires Python at build time even when building this C++ bridge.
If Python is installed but is not on `PATH`, select it explicitly in PowerShell:

```powershell
$env:PYO3_PYTHON = py -c "import sys; print(sys.executable)"
cargo build --release
```

Alternatively, set `PYO3_PYTHON` to the full path of your Python executable.
The resulting static library is `target/release/bed_reader_bridge.lib`.
The generated C++ header is `target/cxxbridge/bed_reader_bridge/src/lib.rs.h`.

### Building the C++ Demo

The Makefile locates Visual Studio C++ Build Tools using `vswhere` and initializes
the x64 compiler environment automatically. From a regular PowerShell terminal
at the project root, with `PYO3_PYTHON` configured as above:

```powershell
make -C bed-reader-cpp
```

The Makefile uses GNU Make (`make` or `mingw32-make`), not `nmake`, but compiles
with the Microsoft `cl` compiler. It builds the Rust library for
`x86_64-pc-windows-msvc` at
`target/x86_64-pc-windows-msvc/release/bed_reader_bridge.lib`.

This builds `bed-reader-cpp/demo.exe`. Pass the BED filename when running it:

```powershell
.\bed-reader-cpp\demo.exe "C:\data\my_genotypes.bed"
```

Keep the corresponding `.bim` and `.fam` files beside the BED file.
The header is included directly from
Cargo's generated directory; no manual copying is needed.

To remove the demo executable:

```powershell
make -C bed-reader-cpp clean
```

### Installing Headers and Libraries Locally

To build the Rust bridge and copy its artifacts into the C++ directory:

```powershell
make -C bed-reader-cpp install
```

This creates or updates:

- `bed-reader-cpp/include/bed_reader_bridge.h`
- `bed-reader-cpp/libs/x86_64-pc-windows-msvc/bed_reader_bridge.lib`

This is local staging, not a system-wide installation. For another C++ application,
add `bed-reader-cpp/include` to its include search path and link the staged library
along with the Windows system libraries listed in `bed-reader-cpp/Makefile`.
Use a compatible MSVC runtime configuration; the demo uses `/MD`.

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
build.rs                   CXX bridge generation and compilation
src/lib.rs                 Bridge declarations and Rust implementation
bed-reader-cpp/
  demo.cpp                 Command-line C++ example
  Makefile                 Windows x64 MSVC build and install targets
  include/                 Locally staged header (make install)
  libs/                    Locally staged static library (make install)
target/
  cxxbridge/               Generated C++ headers
  release/                 Default-target Rust release artifacts
  x86_64-pc-windows-msvc/
	release/               Explicit MSVC-target release artifacts
```

## Acknowledgments

This project builds on [bed-reader](https://github.com/fastlmm/bed-reader),
developed by the FaST-LMM team. Their Rust engine provides the underlying PLINK
file handling and multi-threaded reading capabilities.

## Licensing

The upstream bed-reader library is licensed under Apache-2.0. That does not
automatically establish a license for this wrapper; consult the applicable
project and dependency license terms when redistributing it.
