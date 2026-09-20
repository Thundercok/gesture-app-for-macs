.PHONY: build install run stop clean

APP_NAME := GestureFlow
APP_BUNDLE := $(APP_NAME).app
INSTALL_DIR := /Applications

build:
	@swift build -c release
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp .build/arm64-apple-macosx/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@codesign --force --deep --sign "GestureFlow Developer" --identifier com.user.GestureFlow $(APP_BUNDLE) 2>/dev/null || codesign --force --deep --sign - --identifier com.user.GestureFlow $(APP_BUNDLE)
	@echo "✓ $(APP_BUNDLE) built and signed"

install: build
	@rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "✓ Installed to $(INSTALL_DIR)/$(APP_BUNDLE)"

run: install
	@pkill -f $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	@open $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "🚀 GestureFlow launched!"

stop:
	@pkill -f $(APP_NAME) 2>/dev/null && echo "✓ Stopped" || echo "Not running"

clean:
	@rm -rf .build $(APP_BUNDLE)
	@echo "✓ Cleaned"
