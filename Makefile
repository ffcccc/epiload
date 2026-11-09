.DEFAULT_GOAL := all

ifeq ($(OS),Windows_NT)
	override SHELL := $(COMSPEC)
	override .SHELLFLAGS := /D /S /C
	HOST_TARGET := x86_64-pc-windows-msvc
	VENV ?= .venv
	BOOTSTRAP_PYTHON ?= py
	PYTHON ?= $(VENV)/Scripts/python.exe
	export MSYS_NO_PATHCONV := 1
	export MSYS2_ARG_CONV_EXCL := *
else
	override SHELL := /bin/bash
	override .SHELLFLAGS := -eu -o pipefail -c
	ifneq ($(shell uname -s),Linux)
		$(error Only native Windows/MSVC and Linux/GCC builds are supported)
	endif
	HOST_TARGET := x86_64-unknown-linux-gnu
	ifneq ($(shell uname -m),x86_64)
		$(error Only x86_64 Linux hosts are supported)
	endif
	VENV ?= .venv-linux
	BOOTSTRAP_PYTHON ?= python3
	PYTHON ?= $(VENV)/bin/python
endif

RUST_TARGET ?= $(HOST_TARGET)
ifneq ($(RUST_TARGET),$(HOST_TARGET))
	$(error Target $(RUST_TARGET) is not supported on this host; expected $(HOST_TARGET))
endif
export PYO3_PYTHON ?= $(abspath $(PYTHON))
DEPS_MANIFEST ?= deps.yaml
DEPS_ROOT ?= 3rdparty
FETCHER ?= scripts/fetch_deps.py
CARGO ?= cargo
RUSTUP ?= rustup
BUILD_DIR := build/$(RUST_TARGET)
RUST_DIR := target/$(RUST_TARGET)/release
BRIDGE_HEADER := target/cxxbridge/bed_reader_bridge/src/lib.rs.h
STAGE_DIR := bed-reader-cpp
PACKAGE := $(STAGE_DIR)/bed-reader-cpp_$(RUST_TARGET).zip
SMOKE_BED ?= data/bed-sample-files/small.bed

ifeq ($(OS),Windows_NT)
	ifneq ($(filter default undefined,$(origin CC)),)
		CC := cl
	endif
	ifneq ($(filter default undefined,$(origin CXX)),)
		CXX := cl
	endif
	VSWHERE ?= ${ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe
	VSINSTALL = $(shell "$(VSWHERE)" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
	VSDEVCMD ?= $(VSINSTALL)/Common7/Tools/VsDevCmd.bat
	vsrun = call "$(VSDEVCMD)" -arch=x64 -host_arch=x64 >NUL && $(1)
	RUST_LIB := $(RUST_DIR)/bed_reader_bridge.lib
	DEMO := $(BUILD_DIR)/demo.exe
	CPPFLAGS += /I"target/cxxbridge"
	CXXFLAGS += /nologo /std:c++17 /O2 /W4 /EHsc /MD
	LDLIBS += ws2_32.lib userenv.lib bcrypt.lib ntdll.lib crypt32.lib secur32.lib advapi32.lib ncrypt.lib iphlpapi.lib shell32.lib ole32.lib
else
	ifneq ($(filter default undefined,$(origin CC)),)
		CC := gcc
	endif
	ifneq ($(filter default undefined,$(origin CXX)),)
		CXX := g++
	endif
	RUST_LIB := $(RUST_DIR)/libbed_reader_bridge.a
	DEMO := $(BUILD_DIR)/demo
	CPPFLAGS += -I"target/cxxbridge"
	CXXFLAGS += -std=c++17 -O2 -Wall -Wextra -pthread
endif
export CC CXX

.PHONY: all setup deps deps-force doctor rust clean clean-deps install test smoke

all: deps $(DEMO)

setup:
	$(BOOTSTRAP_PYTHON) -c "import sys; assert sys.version_info >= (3, 10), 'Python 3.10+ is required (3.12+ suggested)'"
	$(BOOTSTRAP_PYTHON) -m venv "$(VENV)"
	"$(PYTHON)" -m pip install "PyYAML>=6,<7"

deps:
	"$(PYTHON)" "$(FETCHER)" --manifest "$(DEPS_MANIFEST)" --root "$(DEPS_ROOT)"

deps-force:
	"$(PYTHON)" "$(FETCHER)" --manifest "$(DEPS_MANIFEST)" --root "$(DEPS_ROOT)" --force

doctor:
	@"$(PYTHON)" --version
	@"$(PYTHON)" -c "import os, pathlib, platform, sys, yaml; assert sys.version_info >= (3, 10); assert platform.machine().lower() in ('amd64', 'x86_64'), 'x64 Python required'; assert pathlib.Path(os.environ['PYO3_PYTHON']).is_file(), 'PYO3_PYTHON does not exist'; print('PyYAML:', yaml.__version__); print('PYO3_PYTHON:', os.environ['PYO3_PYTHON'])"
	@$(MAKE) --version
	@$(CARGO) --version
	@$(RUSTUP) target list --installed
	@"$(PYTHON)" -c "import subprocess; assert '$(RUST_TARGET)' in subprocess.check_output(['$(RUSTUP)', 'target', 'list', '--installed'], text=True).split(), 'Install the target with rustup target add $(RUST_TARGET)'"
ifeq ($(OS),Windows_NT)
	@$(call vsrun,where $(CC) && where $(CXX) && where link)
else
	@$(CC) --version
	@$(CXX) --version
endif

$(BUILD_DIR):
ifeq ($(OS),Windows_NT)
	if not exist "$(subst /,\,$@)" mkdir "$(subst /,\,$@)"
else
	mkdir -p "$@"
endif

rust: | $(BUILD_DIR)
ifeq ($(OS),Windows_NT)
	$(call vsrun,$(CARGO) build --manifest-path Cargo.toml --release --target $(RUST_TARGET) --locked)
else
	$(CARGO) rustc --manifest-path Cargo.toml --release --target $(RUST_TARGET) --locked -- --print native-static-libs 2>&1 | tee "$(BUILD_DIR)/rust.log"
	sed -n 's/^.*native-static-libs: //p' "$(BUILD_DIR)/rust.log" > "$(BUILD_DIR)/native-libs.rsp"
	test -s "$(BUILD_DIR)/native-libs.rsp"
endif

$(DEMO): bed-reader-cpp/demo.cpp rust | $(BUILD_DIR)
ifeq ($(OS),Windows_NT)
	$(call vsrun,$(CXX) $(CPPFLAGS) $(CXXFLAGS) bed-reader-cpp/demo.cpp /Fo:"$(BUILD_DIR)/demo.obj" /Fe:"$@" /link "$(RUST_LIB)" $(LDFLAGS) $(LDLIBS))
else
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) bed-reader-cpp/demo.cpp "$(RUST_LIB)" $(LDFLAGS) $(LDLIBS) @"$(BUILD_DIR)/native-libs.rsp" -o "$@"
endif

install: rust
	"$(PYTHON)" -c "from pathlib import Path; import shutil, zipfile; root=Path('$(STAGE_DIR)'); inc=root/'include'; lib=root/'libs'/'$(RUST_TARGET)'; inc.mkdir(parents=True, exist_ok=True); lib.mkdir(parents=True, exist_ok=True); shutil.copy2('$(BRIDGE_HEADER)', inc/'bed_reader_bridge.h'); shutil.copy2('$(RUST_LIB)', lib); archive=zipfile.ZipFile('$(PACKAGE)', 'w', zipfile.ZIP_DEFLATED); [archive.write(path, path.relative_to(root).as_posix()) for folder in (inc, lib) for path in sorted(folder.rglob('*')) if path.is_file()]; archive.close()"

clean:
ifeq ($(OS),Windows_NT)
	if exist "$(subst /,\,$(BUILD_DIR))" rmdir /S /Q "$(subst /,\,$(BUILD_DIR))"
else
	rm -rf "$(BUILD_DIR)"
endif

clean-deps:
	"$(PYTHON)" -c "from pathlib import Path; import shutil; root=Path('$(DEPS_ROOT)'); shutil.rmtree(root) if root.exists() else None"

test:
	"$(PYTHON)" -m unittest discover -s scripts -p test_fetch_deps.py -v

smoke: all
	"$(DEMO)" "$(SMOKE_BED)"