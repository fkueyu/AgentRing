.PHONY: test daemon app install-daemon install-app firmware clean

test:
	npm test

daemon:
	npm start

app:
	./macos/build.sh

install-daemon:
	node scripts/install-daemon.mjs

install-app:
	node scripts/install-app.mjs

firmware:
	arduino-cli compile --fqbn "esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app" firmware/esp32/agentring_ring

clean:
	rm -rf dist macos/.build
