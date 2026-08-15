VERSION := $(shell cat VERSION)
PKG     := dist/HEIC-Converter-$(VERSION).pkg

.PHONY: help check pkg unsigned notarize release clean

help:
	@echo "heic-converter $(VERSION)"
	@echo
	@echo "  make check      Syntax-check every script and validate the XML"
	@echo "  make pkg        Build and sign dist/HEIC-Converter-$(VERSION).pkg"
	@echo "  make unsigned   Build an unsigned .pkg for local testing"
	@echo "  make notarize   Notarize and staple the built .pkg"
	@echo "  make release    check -> pkg -> notarize"
	@echo "  make clean      Remove build/_work and dist"

# Runs anywhere, including CI on Linux — it is only parsing, not packaging.
check:
	@echo "==> Checking zsh syntax"
	@for f in scripts/heic-watch.sh scripts/install.sh scripts/uninstall.sh \
	          scripts/heic-converter packaging/setup-agent.sh \
	          packaging/preinstall packaging/postinstall \
	          build/build-pkg.sh build/notarize.sh Install.command; do \
		zsh -n "$$f" || exit 1; \
		echo "    ok  $$f"; \
	done
	@echo "==> Validating XML"
	@xmllint --noout packaging/distribution.xml && echo "    ok  packaging/distribution.xml"
	@xmllint --noout --html packaging/resources/welcome.html 2>/dev/null \
		&& echo "    ok  packaging/resources/welcome.html"
	@xmllint --noout --html packaging/resources/conclusion.html 2>/dev/null \
		&& echo "    ok  packaging/resources/conclusion.html"

pkg:
	@./build/build-pkg.sh

unsigned:
	@./build/build-pkg.sh --unsigned

notarize:
	@./build/notarize.sh $(PKG)

release: check pkg notarize
	@echo
	@echo "Release ready: $(PKG)"

clean:
	rm -rf build/_work dist
