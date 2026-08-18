APP_NAME = Holster
BUILD_DIR = build

.PHONY: app install test run clean

app:
	./scripts/bundle.sh

install: app
	@killall "$(APP_NAME)" 2>/dev/null || true
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(BUILD_DIR)/$(APP_NAME).app" /Applications/
	open "/Applications/$(APP_NAME).app"

test:
	swift test

run:
	swift run $(APP_NAME)

clean:
	rm -rf .build $(BUILD_DIR)
