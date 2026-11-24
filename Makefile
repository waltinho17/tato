APP      = Tato
BINARY   = touchbar-temp
VERSION  = 2.0.0
SOURCES  = $(shell find Sources/$(BINARY) -name "*.swift")
BUNDLE   = $(APP).app
PKG      = Tato-v$(VERSION).pkg

.PHONY: build app pkg run probe clean

build: $(SOURCES)
	swiftc -O \
		-target arm64-apple-macosx13.0 \
		$(SOURCES) \
		-o "$(BINARY)" \
		-framework AppKit \
		-framework IOKit \
		-framework Foundation \
		-framework SwiftUI \
		-framework UserNotifications \
		-framework ServiceManagement

app: build
	@mkdir -p "$(BUNDLE)/Contents/MacOS"
	@cp "$(BINARY)" "$(BUNDLE)/Contents/MacOS/"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/"
	@mkdir -p "$(BUNDLE)/Contents/Resources"
	@cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/"
	@codesign --force --sign - "$(BUNDLE)"
	@echo "✓  Built: $(BUNDLE)"

pkg: app
	@rm -rf .pkgwork
	@mkdir -p .pkgwork/root/Applications .pkgwork/scripts
	@cp -r "$(BUNDLE)" .pkgwork/root/Applications/
	@printf '#!/bin/bash\nxattr -cr "/Applications/Tato.app"\nexit 0\n' \
		> .pkgwork/scripts/postinstall
	@chmod +x .pkgwork/scripts/postinstall
	@pkgbuild \
		--root .pkgwork/root \
		--scripts .pkgwork/scripts \
		--identifier com.touchbar-temp \
		--version $(VERSION) \
		--install-location / \
		"$(PKG)"
	@rm -rf .pkgwork
	@echo "✓  Built: $(PKG)"

run: app
	@xattr -cr "$(BUNDLE)"
	@open "$(BUNDLE)"

clean:
	@rm -rf "$(BINARY)" "$(BUNDLE)" "$(PKG)" Tato-*.zip
	@echo "✓  Clean"

probe: build
	@./$(BINARY) --probe
