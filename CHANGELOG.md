# Changelog

All notable changes to WhisperKiller are documented in this file.

## [3.50] - 2026-09-10

### Added
- **Text Casing Settings**: Options to format output as `lowercase` (no caps), `UPPERCASE` (CAPS), `Sentence case`, or `Title Case`.
- **Punctuation Controls**: Global toggle to strip all punctuation marks from transcribed speech, with preserved decimal numbers (`3.14`, `10,5`).
- **Selective Punctuation Removal**: Granular controls to selectively remove periods/ellipsis, commas, question/exclamation marks, hyphens/dashes, quotes/brackets, or colons/semicolons.
- **Formatting Preview**: Live interactive preview card in Settings showing real-time formatting output.
- **In-App Changelog**: New dedicated Changelog tab in Settings fetching remote release notes from GitHub with offline caching and rich Markdown rendering.

### Changed
- **Native Interaction UX**: Removed artificial hover scale and brightness shifts from buttons, returning to Apple-standard interaction feedback.
- **Menu Bar Engine Picker**: Simplified engine labels to clean model names (`OpenAI`, `whisper.cpp`, `Parakeet TDT v3`, `Qwen3-ASR MLX`, `GigaAM`), removing redundant text prefixes.
- **Unified Control Plane**: Unified Makefile with single-purpose commands (`make dev`, `make install`, `make test`, `make verify`, `make clean`, `make clean-legacy`, `make uninstall`).

### Fixed
- **Settings Titlebar Overlap**: Added smooth top content dissolve at the toolbar boundary to prevent scrolled content from overlapping the floating title.
- **Menu Top Gap**: Eliminated empty header gap in menu bar dropdowns caused by inline picker section headers.

---

## [3.49] - 2026-09-10

### Performance
- **CI Build Acceleration**: Added SwiftPM dependency caching to GitHub Actions release workflow.

### Fixed
- **Release Automation**: Added automatic retry logic for transient DMG creation failures during deployment.
- **Window Management**: Fixed issue where minimized standalone windows could not be restored from the menu bar.

---

## [3.48] - 2026-09-10

### Added
- **Parakeet Offline Engine**: Integrated NVIDIA Parakeet TDT v3 CoreML offline speech recognition engine optimized for Apple Silicon.

### Changed
- **Window Styling**: Unified window titlebar materials and visual effect backgrounds across standalone views.
- **Settings Layout**: Collapsed duplicate engine headers and tightened control hierarchy.

---

## [3.47] - 2026-09-04

### Added
- **Dynamic Model Catalog**: Enabled automatic discovery and validation of new OpenAI cloud transcription models without code changes.

### Performance
- **Audio Upload Optimization**: Implemented audio track remuxing and bit-rate scaling to shrink cloud upload sizes and reduce latency.

---

## [3.46] - 2026-08-28

### Security & Releases
- **Code Signing Enforcement**: Enforced Developer ID and stable codesigning identity checks across release packaging.
- **Isolated Dev Runtime**: Introduced `make dev` workflow with isolated bundle identity (`com.whisperkiller.app.dev`) and automatic relaunch on source changes.

---

## [3.45] - 2026-08-28

### Changed
- **Live Translator**: Refined live subtitle overlay controls and status indicators in the menu bar.
- **Accessibility**: Preserved Accessibility permissions across standalone window transitions.

---

## [3.44] - 2026-07-24

### Added
- **AI Chat Context Isolation**: Separated attached transcription context from user prompt messages in the AI Chat window.
- **Multi-Generation Models**: Added support for selecting between the three most recent model generations.

---

## [3.43] - 2026-07-24

### Changed
- **File Queue UI**: Simplified completed file cards and moved primary metrics into the card header.
- **Google Meet Cache**: Added reusable downloads cache for Google Meet recordings to prevent duplicate fetches.

---

## [3.40] - 2026-06-26

### Changed
- **Native Alerts**: Switched updater alerts and permission notices to native macOS dialogs.
- **Documentation**: Updated repository presentation and interface screenshots.

---

## [3.35] - 2026-06-08

### Added
- **Configurable Dock Mode**: Support for running in regular Dock mode alongside menu-bar-only mode, with a dedicated Dock-accessible main menu.
- **Microphone Stability**: Hardened microphone startup sequence to prevent audio input binding stalls on launch.

---

## [3.20] - 2026-05-28

### Added
- **Native Speaker Diarization**: Added support for OpenAI native speech-to-text speaker diarization.
- **Progress Pill**: Real-time transcription stage and progress indicator in the floating overlay pill.
- **API Key Masking**: Secure visual masking for stored OpenAI credentials.

---

## [3.10] - 2026-05-21

### Added
- **Floating AI Chat**: Dedicated AI chat window for ad-hoc queries, rewrites, and summaries.
- **Google Meet Import**: Direct calendar-based import of recorded Google Meet sessions with Keychain-backed OAuth authentication.
- **Queue Concurrency Control**: Automatic concurrency limiting and retry backoff for batch cloud transcription jobs.

---

## [3.0.0] - 2026-05-01

### Added
- **WhisperKiller 3.0 Architecture**: Complete architecture rewrite with support for cloud and local transcription backends.
- **Local whisper.cpp Engine**: Dynamic discovery and execution of local GGUF/bin models.
- **AI Post-Processing**: Specialized output modes (Dictation, Email, Code, Notes, User Story) with custom system prompts.
- **Automated Insertion**: Direct keystroke typing (`AutoTyper`) and single-block clipboard insertion into the frontmost macOS application.
- **Profanity Filter**: Configurable profanity filtering with custom wordlist importing.
