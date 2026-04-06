.PHONY: all help install verify

# Default target: release verification
all: verify

help:
	@echo "WhisperKiller Build System"
	@echo "  make install - Reinstall app to /Applications and launch it"
	@echo "  make verify  - Verify release build for GitHub Releases"

# Reinstall app locally (verify + build + sign + move to /Applications + launch)
install: verify
	@bash scripts/deploy.command

# Verify release build used for GitHub Releases
verify:
	@echo "🔍 Verifying release build..."
	@swift build -c release
	@echo "✅ Release build succeeded"
