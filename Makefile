CXX        := clang++
CXXFLAGS   := -std=c++20 -Wall -Wextra -O2 -Isrc
FRAMEWORKS := -framework Cocoa -framework CoreServices

CORE := src/core/screenshot.cpp src/core/watcher.cpp
HDRS := $(wildcard src/core/*.hpp)

APP         := build/snap.app
LABEL       := dev.snap.shelf
INSTALL_APP := $(HOME)/Applications/snap.app
AGENT       := $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOG         := $(HOME)/Library/Logs/snap.log
GUI         := gui/$(shell id -u)

build/snap: $(CORE) src/app/main.mm $(HDRS) | build
	$(CXX) $(CXXFLAGS) $(CORE) $(FRAMEWORKS) -fobjc-arc src/app/main.mm -o $@

build/test: tests/test_screenshot.cpp src/core/screenshot.cpp $(HDRS) | build
	$(CXX) $(CXXFLAGS) tests/test_screenshot.cpp src/core/screenshot.cpp -o $@

test: build/test
	./build/test

run: build/snap
	./build/snap

$(APP): build/snap resources/Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp resources/Info.plist $(APP)/Contents/Info.plist
	cp build/snap $(APP)/Contents/MacOS/snap
	codesign --force --sign - $(APP)

app: $(APP)

# Copies snap.app to ~/Applications and starts it now and at every login.
install: $(APP)
	mkdir -p $(HOME)/Applications $(HOME)/Library/LaunchAgents
	-launchctl bootout $(GUI)/$(LABEL) 2>/dev/null
	ditto $(APP) $(INSTALL_APP)
	sed -e 's|@APP@|$(INSTALL_APP)/Contents/MacOS/snap|' -e 's|@LOG@|$(LOG)|' resources/launchagent.plist > $(AGENT)
	launchctl bootstrap $(GUI) $(AGENT)
	@echo "snap installed and running. Logs: $(LOG)"

# Stops snap and stops it starting at login. Leaves ~/Applications/snap.app in place.
uninstall:
	-launchctl bootout $(GUI)/$(LABEL)
	rm -f $(AGENT)

build:
	mkdir -p build

.PHONY: test run app install uninstall
