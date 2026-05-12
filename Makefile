APP_NAME = i3Chat
BUNDLE_NAME = $(APP_NAME).app
BUILD_DIR = build
SRC_DIR = .

# Compiler and flags
CC = clang
OBJCFLAGS = -fobjc-arc -std=c11 -g -O2
FRAMEWORKS = -framework Cocoa -framework Foundation -framework AppKit -framework QuartzCore
INCLUDES = -I$(SRC_DIR) -I$(SRC_DIR)/IRCClient -I$(SRC_DIR)/Storage -I$(SRC_DIR)/UI

# Architecture flags
ARCH_X86 = x86_64
ARCH_ARM = arm64

# ============================================================
# Third-party Libraries Directory
# ============================================================
THIRD_PARTY_DIR = third-party

# ============================================================
# SQLite3 Static Library Configuration
# ============================================================
SQLITE_VERSION = 3510200
SQLITE_YEAR = 2026
SQLITE_DIR = $(THIRD_PARTY_DIR)/sqlite
SQLITE_SRC = $(SQLITE_DIR)/sqlite3.c
SQLITE_HDR = $(SQLITE_DIR)/sqlite3.h
SQLITE_LIB_X86 = $(SQLITE_DIR)/libsqlite3-x86_64.a
SQLITE_LIB_ARM = $(SQLITE_DIR)/libsqlite3-arm64.a
SQLITE_LIB_UNIVERSAL = $(SQLITE_DIR)/libsqlite3-universal.a
SQLITE_URL = https://www.sqlite.org/$(SQLITE_YEAR)/sqlite-amalgamation-$(SQLITE_VERSION).zip

# Source files
SOURCES = main.m \
          IRCClient/IRCConfig.m \
          IRCClient/IRCClient.m \
          Storage/StorageConstants.m \
          Storage/MessageStorage.m \
          Storage/ServerHistoryStorage.m \
          UI/AppDelegate.m \
          UI/MainWindowController.m \
          UI/LoginWindowController.m \
          UI/ChatViewController.m \
          UI/ChatViewController+UI.m \
          UI/ChatViewController+Channel.m \
          UI/ChatViewController+Message.m \
          UI/ChatViewController+IRC.m \
          UI/ChatViewController+DataSource.m \
          UI/ChatViewController+Menu.m \
          UI/ChatViewController+Input.m \
          UI/ChatViewController+Favorites.m \
          UI/ChannelBuffer.m \
          UI/ChannelListWindowController.m \
          UI/LinksListWindowController.m \
          UI/WhoisWindowController.m \
          UI/HistoryWindowController.m \
          UI/SettingsWindowController.m \
          UI/LocalizationManager.m

OBJECTS = $(SOURCES:.m=.o)

# Default target - build for current architecture with static sqlite3
all: $(SQLITE_LIB_UNIVERSAL) $(BUILD_DIR)/$(BUNDLE_NAME)

# Create app bundle (current architecture with static sqlite3)
$(BUILD_DIR)/$(BUNDLE_NAME): $(OBJECTS) Info.plist $(SQLITE_LIB_UNIVERSAL)
	@mkdir -p $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/MacOS
	@mkdir -p $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources
	@cp Info.plist $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/
	@if [ -d Resources ]; then cp -R Resources/* $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/Resources/; fi
	$(CC) $(OBJCFLAGS) $(FRAMEWORKS) -o $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(OBJECTS) $(SQLITE_LIB_UNIVERSAL)
	@chmod +x $(BUILD_DIR)/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME)
	@xattr -cr $(BUILD_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@codesign --force --deep --sign - $(BUILD_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@echo "Build complete: $(BUILD_DIR)/$(BUNDLE_NAME)"

# Compile Objective-C files
%.o: %.m $(SQLITE_SRC)
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) $(INCLUDES) -I$(SQLITE_DIR) -c $< -o $@

# ============================================================
# SQLite3 Static Library Build
# ============================================================

# Download SQLite source
$(SQLITE_SRC):
	@echo "Downloading SQLite $(SQLITE_VERSION) from $(SQLITE_URL)..."
	@mkdir -p $(SQLITE_DIR)
	@curl -f -L -o $(SQLITE_DIR)/sqlite.zip $(SQLITE_URL) || (echo "Error: Failed to download SQLite. Check your network connection." && exit 1)
	@unzip -o $(SQLITE_DIR)/sqlite.zip -d $(SQLITE_DIR) || (echo "Error: Failed to unzip SQLite." && exit 1)
	@mv $(SQLITE_DIR)/sqlite-amalgamation-$(SQLITE_VERSION)/* $(SQLITE_DIR)/
	@rmdir $(SQLITE_DIR)/sqlite-amalgamation-$(SQLITE_VERSION)
	@rm -f $(SQLITE_DIR)/sqlite.zip
	@echo "SQLite source downloaded successfully."

# Build SQLite static library for x86_64
$(SQLITE_LIB_X86): $(SQLITE_SRC)
	@echo "Building SQLite static library for x86_64..."
	$(CC) -arch $(ARCH_X86) -O2 -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS5 -c $(SQLITE_SRC) -o $(SQLITE_DIR)/sqlite3-x86_64.o
	ar rcs $(SQLITE_LIB_X86) $(SQLITE_DIR)/sqlite3-x86_64.o
	@echo "SQLite x86_64 static library built: $(SQLITE_LIB_X86)"

# Build SQLite static library for arm64
$(SQLITE_LIB_ARM): $(SQLITE_SRC)
	@echo "Building SQLite static library for arm64..."
	$(CC) -arch $(ARCH_ARM) -O2 -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS5 -c $(SQLITE_SRC) -o $(SQLITE_DIR)/sqlite3-arm64.o
	ar rcs $(SQLITE_LIB_ARM) $(SQLITE_DIR)/sqlite3-arm64.o
	@echo "SQLite arm64 static library built: $(SQLITE_LIB_ARM)"

# Build SQLite universal static library
$(SQLITE_LIB_UNIVERSAL): $(SQLITE_LIB_X86) $(SQLITE_LIB_ARM)
	@echo "Creating SQLite universal static library..."
	lipo -create $(SQLITE_LIB_X86) $(SQLITE_LIB_ARM) -output $(SQLITE_LIB_UNIVERSAL)
	@echo "SQLite universal static library built: $(SQLITE_LIB_UNIVERSAL)"

# Convenience targets
sqlite-x86: $(SQLITE_LIB_X86)
sqlite-arm: $(SQLITE_LIB_ARM)
sqlite-universal: $(SQLITE_LIB_UNIVERSAL)
sqlite: sqlite-universal

# ============================================================
# Architecture-specific builds
# ============================================================

# Build for x86_64 (Intel)
build-x86: $(SQLITE_LIB_X86)
	@echo "Building for x86_64 (Intel)..."
	@mkdir -p $(BUILD_DIR)/x86_64/$(BUNDLE_NAME)/Contents/MacOS
	@mkdir -p $(BUILD_DIR)/x86_64/$(BUNDLE_NAME)/Contents/Resources
	@cp Info.plist $(BUILD_DIR)/x86_64/$(BUNDLE_NAME)/Contents/
	@if [ -d Resources ]; then cp -R Resources/* $(BUILD_DIR)/x86_64/$(BUNDLE_NAME)/Contents/Resources/; fi
	$(CC) $(OBJCFLAGS) -arch $(ARCH_X86) $(FRAMEWORKS) $(INCLUDES) -I$(SQLITE_DIR) -o $(BUILD_DIR)/x86_64/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(SOURCES) $(SQLITE_LIB_X86)
	@chmod +x $(BUILD_DIR)/x86_64/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME)
	@xattr -cr $(BUILD_DIR)/x86_64/$(BUNDLE_NAME) 2>/dev/null || true
	@codesign --force --deep --sign - $(BUILD_DIR)/x86_64/$(BUNDLE_NAME) 2>/dev/null || true
	@echo "Build complete: $(BUILD_DIR)/x86_64/$(BUNDLE_NAME)"

# Build for arm64 (Apple Silicon M-series)
build-arm: $(SQLITE_LIB_ARM)
	@echo "Building for arm64 (Apple Silicon)..."
	@mkdir -p $(BUILD_DIR)/arm64/$(BUNDLE_NAME)/Contents/MacOS
	@mkdir -p $(BUILD_DIR)/arm64/$(BUNDLE_NAME)/Contents/Resources
	@cp Info.plist $(BUILD_DIR)/arm64/$(BUNDLE_NAME)/Contents/
	@if [ -d Resources ]; then cp -R Resources/* $(BUILD_DIR)/arm64/$(BUNDLE_NAME)/Contents/Resources/; fi
	$(CC) $(OBJCFLAGS) -arch $(ARCH_ARM) $(FRAMEWORKS) $(INCLUDES) -I$(SQLITE_DIR) -o $(BUILD_DIR)/arm64/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) $(SOURCES) $(SQLITE_LIB_ARM)
	@chmod +x $(BUILD_DIR)/arm64/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME)
	@xattr -cr $(BUILD_DIR)/arm64/$(BUNDLE_NAME) 2>/dev/null || true
	@codesign --force --deep --sign - $(BUILD_DIR)/arm64/$(BUNDLE_NAME) 2>/dev/null || true
	@echo "Build complete: $(BUILD_DIR)/arm64/$(BUNDLE_NAME)"

# Build Universal binary (both architectures)
build-universal: build-x86 build-arm
	@echo "Creating Universal binary..."
	@mkdir -p $(BUILD_DIR)/universal/$(BUNDLE_NAME)/Contents/MacOS
	@mkdir -p $(BUILD_DIR)/universal/$(BUNDLE_NAME)/Contents/Resources
	@cp Info.plist $(BUILD_DIR)/universal/$(BUNDLE_NAME)/Contents/
	@if [ -d Resources ]; then cp -R Resources/* $(BUILD_DIR)/universal/$(BUNDLE_NAME)/Contents/Resources/; fi
	@lipo -create \
		$(BUILD_DIR)/x86_64/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) \
		$(BUILD_DIR)/arm64/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME) \
		-output $(BUILD_DIR)/universal/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME)
	@chmod +x $(BUILD_DIR)/universal/$(BUNDLE_NAME)/Contents/MacOS/$(APP_NAME)
	@xattr -cr $(BUILD_DIR)/universal/$(BUNDLE_NAME) 2>/dev/null || true
	@codesign --force --deep --sign - $(BUILD_DIR)/universal/$(BUNDLE_NAME) 2>/dev/null || true
	@echo "Build complete: $(BUILD_DIR)/universal/$(BUNDLE_NAME)"

# ============================================================
# DMG Package Creation
# ============================================================

DMG_TEMP_DIR = $(BUILD_DIR)/dmg_temp

# Create DMG for x86_64
dmg-x86: build-x86
	@echo "Creating DMG for x86_64 (Intel)..."
	@rm -rf $(DMG_TEMP_DIR)
	@mkdir -p $(DMG_TEMP_DIR)
	@cp -R $(BUILD_DIR)/x86_64/$(BUNDLE_NAME) $(DMG_TEMP_DIR)/
	@xattr -cr $(DMG_TEMP_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@codesign --force --deep --sign - $(DMG_TEMP_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@ln -s /Applications $(DMG_TEMP_DIR)/Applications
	@rm -f $(BUILD_DIR)/$(APP_NAME)-x86_64.dmg
	@hdiutil create -volname "$(APP_NAME) (Intel)" -srcfolder $(DMG_TEMP_DIR) -ov -format UDZO $(BUILD_DIR)/$(APP_NAME)-x86_64.dmg
	@rm -rf $(DMG_TEMP_DIR)
	@echo "DMG created: $(BUILD_DIR)/$(APP_NAME)-x86_64.dmg"

# Create DMG for arm64
dmg-arm: build-arm
	@echo "Creating DMG for arm64 (Apple Silicon)..."
	@rm -rf $(DMG_TEMP_DIR)
	@mkdir -p $(DMG_TEMP_DIR)
	@cp -R $(BUILD_DIR)/arm64/$(BUNDLE_NAME) $(DMG_TEMP_DIR)/
	@xattr -cr $(DMG_TEMP_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@codesign --force --deep --sign - $(DMG_TEMP_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@ln -s /Applications $(DMG_TEMP_DIR)/Applications
	@rm -f $(BUILD_DIR)/$(APP_NAME)-arm64.dmg
	@hdiutil create -volname "$(APP_NAME) (Apple Silicon)" -srcfolder $(DMG_TEMP_DIR) -ov -format UDZO $(BUILD_DIR)/$(APP_NAME)-arm64.dmg
	@rm -rf $(DMG_TEMP_DIR)
	@echo "DMG created: $(BUILD_DIR)/$(APP_NAME)-arm64.dmg"

# Create DMG for Universal binary
dmg-universal: build-universal
	@echo "Creating DMG for Universal binary..."
	@rm -rf $(DMG_TEMP_DIR)
	@mkdir -p $(DMG_TEMP_DIR)
	@cp -R $(BUILD_DIR)/universal/$(BUNDLE_NAME) $(DMG_TEMP_DIR)/
	@xattr -cr $(DMG_TEMP_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@codesign --force --deep --sign - $(DMG_TEMP_DIR)/$(BUNDLE_NAME) 2>/dev/null || true
	@ln -s /Applications $(DMG_TEMP_DIR)/Applications
	@rm -f $(BUILD_DIR)/$(APP_NAME)-universal.dmg
	@hdiutil create -volname "$(APP_NAME) (Universal)" -srcfolder $(DMG_TEMP_DIR) -ov -format UDZO $(BUILD_DIR)/$(APP_NAME)-universal.dmg
	@rm -rf $(DMG_TEMP_DIR)
	@echo "DMG created: $(BUILD_DIR)/$(APP_NAME)-universal.dmg"

# Build all DMG packages (x86_64, arm64, and universal)
build: dmg-x86 dmg-arm dmg-universal
	@echo ""
	@echo "============================================================"
	@echo "All DMG packages created successfully!"
	@echo "============================================================"
	@echo "  Intel (x86_64):      $(BUILD_DIR)/$(APP_NAME)-x86_64.dmg"
	@echo "  Apple Silicon (M):   $(BUILD_DIR)/$(APP_NAME)-arm64.dmg"
	@echo "  Universal:           $(BUILD_DIR)/$(APP_NAME)-universal.dmg"
	@echo "============================================================"

# Clean build directory only (keeps third-party libraries)
clean:
	rm -rf $(BUILD_DIR)
	find . -name "*.o" -delete
	@echo "Build directory cleaned. Third-party libraries preserved in $(THIRD_PARTY_DIR)/"

# Clean third-party compiled libraries only (keeps source)
clean-libs:
	rm -f $(SQLITE_LIB_X86) $(SQLITE_LIB_ARM) $(SQLITE_LIB_UNIVERSAL)
	rm -f $(SQLITE_DIR)/*.o
	@echo "Third-party compiled libraries cleaned."

# Full clean including third-party directory
distclean: clean
	rm -rf $(THIRD_PARTY_DIR)
	@echo "Full clean completed (including third-party libraries)."

.PHONY: all clean clean-libs distclean build build-x86 build-arm build-universal dmg-x86 dmg-arm dmg-universal sqlite sqlite-x86 sqlite-arm sqlite-universal
