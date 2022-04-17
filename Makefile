CRYSTAL_BIN ?= $(shell which crystal)
SHARDS_BIN ?= $(shell which shards)
PREFIX ?= /opt/homebrew

build:
	$(SHARDS_BIN) build $(CRFLAGS)
clean:
	rm -f ./bin/crystalline ./bin/crystalline.dwarf
test: build
	$(CRYSTAL_BIN) spec
install: build
	mkdir -p $(PREFIX)/bin
	cp ./bin/crystalline $(PREFIX)/bin
