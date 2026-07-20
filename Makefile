# Ren TUI
# Build with vendored librns. Requires odin on PATH.

ODIN        ?= odin
ROOT        := $(CURDIR)
PREFIX      ?= /usr/local
DESTDIR     ?=
BINDIR      := $(PREFIX)/bin
MANDIR      := $(PREFIX)/share/man/man1
LIBDIR      := $(PREFIX)/lib/ren-tui

LIBC        ?= auto
ifeq ($(LIBC),auto)
LIBC := $(shell $(ROOT)/ci/scripts/detect-libc.sh)
endif

VENDOR_RNS  := $(ROOT)/vendor/librns
RPATH        ?= $(ROOT)/bin
ifeq ($(LIBC),musl)
VENDOR_LIB  := $(VENDOR_RNS)/lib-musl
LIBRNS      := $(VENDOR_LIB)/librns.a
LINKER_FLAGS := -extra-linker-flags:"-L$(VENDOR_LIB) -lpthread -lm"
else
VENDOR_LIB  := $(VENDOR_RNS)/lib
LIBRNS      := $(VENDOR_LIB)/librns.so
LINKER_FLAGS := -extra-linker-flags:"-L$(VENDOR_LIB) -Wl,-rpath,$(RPATH)"
endif
VENDOR_ODIN := $(VENDOR_RNS)/odin
BIN_LIBRNS  := bin/librns.so

RNS_ROOT    ?=
LIVE_SECS   ?= 30

REMOTE_GITHUB ?= git@github.com:Quad4-Software/Ren-TUI.git
REMOTE_RNS    ?= rns://06a54b505bb67b25ef3f8097e8001edc/public/ren-tui

COLLECTION   := -collection:ren=$(ROOT)/ren -collection:rns=$(VENDOR_ODIN)
OUT          := bin/ren-tui
LISTEN       := bin/ren-listen

GIT_COMMIT    ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD_DATE    ?= $(shell date -u +%Y-%m-%dT%H:%MZ 2>/dev/null || echo unknown)
VERSION_DEFINES := -define:REN_GIT_COMMIT=$(GIT_COMMIT) -define:REN_BUILD_DATE=$(BUILD_DATE)

ODIN_TEST_ENV := LIBRARY_PATH="$(VENDOR_LIB):$${LIBRARY_PATH:-}" LD_LIBRARY_PATH="$(ROOT)/bin:$${LD_LIBRARY_PATH:-}"
ODIN_TEST_FLAGS := -collection:ren=$(ROOT)/ren -collection:rns=$(VENDOR_ODIN) $(LINKER_FLAGS) $(VERSION_DEFINES)
ODIN_TEST_SERIAL_FLAGS := $(ODIN_TEST_FLAGS) -define:ODIN_TEST_THREADS=1

.PHONY: all clean install uninstall test \
	test-smoke test-unit test-property test-fuzz test-acceptance \
	test-e2e test-cross-terminal test-mutation test-race test-chaos test-interop \
	test-oracle test-blackbox \
	test-live run listen vendor-librns vendor-librns-musl remotes help man check dist cross bench \
	package package-deb package-rpm package-arch package-nix

all: $(OUT) $(LISTEN)

# Cross / multi-OS build. Example: make cross TARGET=windows-amd64 RNS_ROOT=../Reticulum-Go
TARGET ?=
cross:
	@test -n "$(TARGET)" || (echo "usage: make cross TARGET=linux-arm64|windows-amd64|..." >&2; exit 2)
	TARGET="$(TARGET)" RNS_ROOT="$(RNS_ROOT)" sh $(ROOT)/ci/scripts/build-target.sh


dist: $(OUT) $(LISTEN)
ifeq ($(LIBC),musl)
	@true
else
	patchelf --set-rpath '$$ORIGIN' $(OUT) $(LISTEN)
endif

help:
	@printf '%s\n' \
		'Targets:' \
		'  all            build ren-tui and ren-listen (default)' \
		'  run            build and run ren-tui' \
		'  listen         build and run ren-listen' \
		'  test           run all test suites' \
		'  test-oracle    expected prop wire/config oracles' \
		'  test-blackbox  public-surface prop/config checks' \
		'  bench          timed micron/conversations/UI benches' \
		'  install        install binaries, librns, and man pages to PREFIX' \
		'  uninstall      remove installed files' \
		'  man            show man page sources under man/' \
		'  remotes        configure origin fetch=GitHub, push=GitHub+RNS' \
		'  vendor-librns  refresh vendored glibc librns.so (RNS_ROOT=...)' \
		'  vendor-librns-musl  rebuild vendor/librns/lib-musl/librns.a (needs go+musl)' \
		'  cross          build for TARGET= (uses ci/scripts/build-target.sh)' \
		'  clean          remove bin/' \
		'  dist           build then set RUNPATH to $$ORIGIN (needs patchelf)' \
		'  package        build deb rpm and Arch pkg.tar.zst into dist/pkg' \
		'  package-deb    build .deb (needs dpkg-deb)' \
		'  package-rpm    build .rpm (needs rpmbuild)' \
		'  package-arch   build .pkg.tar.zst (needs tar+zstd)' \
		'  package-nix    build with nix (needs nix, flake.nix)' \
		'' \
		'Variables: PREFIX=$(PREFIX) DESTDIR=$(DESTDIR) LIVE_SECS=$(LIVE_SECS) LIBC=$(LIBC) TARGET= RNS_ROOT='

$(BIN_LIBRNS): $(LIBRNS)
ifeq ($(LIBC),musl)
	mkdir -p bin
else
	mkdir -p bin
	cp -f $(LIBRNS) $(BIN_LIBRNS)
endif

$(OUT): cmd/ren-tui/main.odin $(shell find ren -name '*.odin' 2>/dev/null) $(BIN_LIBRNS)
	mkdir -p bin
	LIBRARY_PATH="$(VENDOR_LIB):$${LIBRARY_PATH:-}" \
	$(ODIN) build cmd/ren-tui -out:$(OUT) $(COLLECTION) $(LINKER_FLAGS) $(VERSION_DEFINES)

$(LISTEN): cmd/ren-listen/main.odin $(shell find ren -name '*.odin' 2>/dev/null) $(BIN_LIBRNS)
	mkdir -p bin
	LIBRARY_PATH="$(VENDOR_LIB):$${LIBRARY_PATH:-}" \
	$(ODIN) build cmd/ren-listen -out:$(LISTEN) $(COLLECTION) $(LINKER_FLAGS) $(VERSION_DEFINES)

man:
	@ls -1 man/*.1

install:
ifeq ($(LIBC),musl)
	$(MAKE) all LIBC=musl
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(MANDIR)
	install -m 755 $(OUT) $(DESTDIR)$(BINDIR)/ren-tui
	install -m 755 $(LISTEN) $(DESTDIR)$(BINDIR)/ren-listen
	install -m 644 man/ren-tui.1 $(DESTDIR)$(MANDIR)/ren-tui.1
	install -m 644 man/ren-listen.1 $(DESTDIR)$(MANDIR)/ren-listen.1
else
	$(MAKE) all RPATH=$(LIBDIR)
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(LIBDIR)
	install -d $(DESTDIR)$(MANDIR)
	install -m 755 $(OUT) $(DESTDIR)$(BINDIR)/ren-tui
	install -m 755 $(LISTEN) $(DESTDIR)$(BINDIR)/ren-listen
	install -m 755 $(BIN_LIBRNS) $(DESTDIR)$(LIBDIR)/librns.so
	install -m 644 man/ren-tui.1 $(DESTDIR)$(MANDIR)/ren-tui.1
	install -m 644 man/ren-listen.1 $(DESTDIR)$(MANDIR)/ren-listen.1
	$(MAKE) all RPATH=$(ROOT)/bin
endif


uninstall:
	rm -f $(DESTDIR)$(BINDIR)/ren-tui
	rm -f $(DESTDIR)$(BINDIR)/ren-listen
	rm -f $(DESTDIR)$(LIBDIR)/librns.so
	rm -f $(DESTDIR)$(MANDIR)/ren-tui.1
	rm -f $(DESTDIR)$(MANDIR)/ren-listen.1
	-rmdir $(DESTDIR)$(LIBDIR) 2>/dev/null || true

check: test

test: test-smoke test-unit test-property test-fuzz test-acceptance \
	test-e2e test-cross-terminal test-mutation test-race test-chaos test-interop \
	test-oracle test-blackbox

test-smoke: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/smoke $(ODIN_TEST_SERIAL_FLAGS)

test-unit: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/unit $(ODIN_TEST_SERIAL_FLAGS)

test-property: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/property $(ODIN_TEST_FLAGS)

test-fuzz: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/fuzz $(ODIN_TEST_FLAGS)

test-acceptance: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/acceptance $(ODIN_TEST_FLAGS)

test-e2e: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/e2e $(ODIN_TEST_SERIAL_FLAGS)

test-cross-terminal: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/cross_terminal $(ODIN_TEST_SERIAL_FLAGS)

test-mutation: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/mutation $(ODIN_TEST_FLAGS)

test-race: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/race $(ODIN_TEST_FLAGS)

test-chaos: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/chaos $(ODIN_TEST_SERIAL_FLAGS)

test-oracle: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/oracle $(ODIN_TEST_FLAGS)

test-blackbox: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/blackbox $(ODIN_TEST_FLAGS)

bench: $(BIN_LIBRNS)
	$(ODIN_TEST_ENV) $(ODIN) test tests/bench $(ODIN_TEST_SERIAL_FLAGS)

package:
	sh $(ROOT)/ci/scripts/package-all.sh

package-deb:
	sh $(ROOT)/ci/scripts/package-deb.sh

package-rpm:
	sh $(ROOT)/ci/scripts/package-rpm.sh

package-arch:
	sh $(ROOT)/ci/scripts/package-arch.sh

package-nix:
	nix build .#ren-tui -L

test-interop:
	python3 tests/interop/python_lxmf_interop.py
	python3 tests/interop/python_nomad_page_interop.py

test-live: $(LISTEN)
	./$(LISTEN) -t $(LIVE_SECS) $${REN_RNS_CONFIG:+-c $$REN_RNS_CONFIG}

run: $(OUT)
	./$(OUT)

listen: $(LISTEN)
	./$(LISTEN) -t $(LIVE_SECS)

remotes:
	@if git remote get-url origin >/dev/null 2>&1; then \
		git remote set-url origin $(REMOTE_GITHUB); \
	else \
		git remote add origin $(REMOTE_GITHUB); \
	fi
	@git remote set-url --push origin $(REMOTE_GITHUB)
	@git remote set-url --add --push origin $(REMOTE_RNS)
	@git remote -v

vendor-librns:
	@test -n "$(RNS_ROOT)" || (echo "usage: make vendor-librns RNS_ROOT=/path/to/Reticulum-Go" >&2; exit 2)
	cd "$(RNS_ROOT)" && task build-librns
	mkdir -p "$(VENDOR_RNS)/lib" "$(VENDOR_RNS)/include" "$(VENDOR_ODIN)/rns" "$(VENDOR_RNS)/lib/linux/amd64"
	cp -f "$(RNS_ROOT)/bin/librns.so" "$(VENDOR_RNS)/lib/librns.so"
	cp -f "$(RNS_ROOT)/bin/librns.so" "$(VENDOR_RNS)/lib/linux/amd64/librns.so"
	cp -f "$(RNS_ROOT)/bin/rns.h" "$(VENDOR_RNS)/include/rns.h"
	cp -a "$(RNS_ROOT)/bindings/odin/rns/." "$(VENDOR_ODIN)/rns/"
	mkdir -p bin
	cp -f "$(VENDOR_RNS)/lib/librns.so" "$(BIN_LIBRNS)"

vendor-librns-musl:
	RNS_ROOT="$(RNS_ROOT)" sh $(ROOT)/ci/scripts/build-librns-musl.sh

clean:
	rm -rf bin
