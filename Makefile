.PHONY: all help dev test build verify install release-prepare clean clean-legacy uninstall

# Default target: release verification
all: verify

help:
	@echo "WhisperKiller Unified Control System"
	@echo "  make dev          - Run local debug app in .build/dev-runtime with auto-rebuild (isolated from /Applications)"
	@echo "  make test         - Run test suite"
	@echo "  make verify       - Run test suite and verify production release build"
	@echo "  make install      - Verify, package, sign, install to /Applications, and launch"
	@echo "  make release-prepare - Finalize Unreleased and synchronize the next version (no publish)"
	@echo "  make clean        - Clean local build artifacts (.build, dist, staging)"
	@echo "  make clean-legacy - Safely remove empty obsolete Application Support folders (WhisperFlow, WhisperFree)"
	@echo "  make uninstall    - Full cleanup of app and local settings via scripts/uninstall.sh"

# Persistent local debug app with incremental rebuild + relaunch
dev:
	@bash scripts/dev.command

# Run test suite
test:
	@echo "🧪 Running tests..."
	@python3 scripts/release.py check
	@python3 -m unittest discover -s scripts/tests -p 'test_release.py'
	@swift test --disable-keychain --disable-netrc

# Maintainer preparation only; commit/review and publication remain separate actions.
release-prepare:
	@python3 scripts/release.py prepare --remote origin

# Reinstall app locally (verify + build + sign + move to /Applications + launch)
install: verify
	@bash scripts/deploy.command

# Verify release build used for GitHub Releases
verify: test
	@echo "🔍 Verifying release build..."
	@bash scripts/swift_build_with_progress.sh swift build -c release --disable-keychain --disable-netrc
	@echo "✅ Release build succeeded"

# Clean local build artifacts
clean:
	@echo "🧹 Cleaning local build artifacts..."
	@swift package clean 2>/dev/null || true
	@rm -rf .build dist .build-local 2>/dev/null || true
	@echo "✅ Build artifacts cleaned."

# Remove empty legacy folders from older project names
clean-legacy:
	@echo "🧹 Checking legacy Application Support folders..."
	@rm -rf "$$HOME/Library/Application Support/WhisperFlow" "$$HOME/Library/Application Support/WhisperFree" 2>/dev/null || true
	@echo "✅ Obsolete WhisperFlow/WhisperFree folders removed (WhisperKiller preserved)."

# Complete uninstallation of local app and data
uninstall:
	@bash scripts/uninstall.sh
