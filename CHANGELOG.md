# Changelog

All notable changes to WhisperKiller are documented in this file.

## [Unreleased]

## [4.0.3] - 2026-10-06

### Fixed
- **Capsule visibility**: Fade the recording capsule in and out, continue from its current opacity when a transition reverses, and remove the panel only after it has faded away.
- **Accessibility helper**: Show the drag-and-drop card without activating the application or bringing its other windows above System Settings.

---

## [4.0.2] - 2026-10-05

### Fixed
- **Global hotkeys**: Remove interception when accessibility access is revoked, replace old registrations on restart, discard queued callbacks after stopping, and leave input unfiltered when macOS disables a stalled tap.
- **Recording errors**: Keep full transcription diagnostics in History, show a short recovery message in the capsule, and constrain error text to one line so a long engine log cannot expand the overlay across the screen.
- **Whisper model access**: Copy legacy models into the current application-support cache during local installation, preserve existing models, stop immediately when a model is unreadable, and identify model-open failures without displaying the CLI initialization log.

---

## [4.0.1] - 2026-10-05

### Added
- **Cloud providers and model selection**: Keep OpenAI as the default, allow an OpenAI-compatible API endpoint with its own key, and combine dynamic model menus with manual IDs for transcription, refinement and AI Chat.
- **Parakeet Ultra**: Add a separate Core ML model option while preserving saved TDT v3 choices and caches.
- **History storage management**: Show local storage usage for recorded audio, Meet downloads, text and models. Delete audio while keeping transcripts, remove downloaded Meet files, or delete all history with explicit consequences and confirmation. Imported originals and models are preserved.

### Changed
- **Engine updates**: Upgrade FluidAudio to 0.17.5 and the managed MLX Qwen3-ASR runtime to 0.4.4. Use GPT-6 Luna for new cloud text configurations and Qwen3.5 4B for new Ollama configurations; preserve saved model choices. Update the standalone Python download to 3.12.15 and use the current whisper.cpp Homebrew formula.
- **Cloud API compatibility**: Send `languages[]` to OpenAI GPT Transcribe, retain manual model choices when catalogs change, and omit cost estimates for unknown models or custom providers.
- **Cloud settings**: Keep provider and API key controls visible when AI refinement is disabled so its checkbox stays in place and AI Chat remains configurable.
- **Capsule motion**: Give recording and processing transitions a gentle spring with continuous velocity, a stable center and readable text; stop motion when hidden and respect Reduce Motion.
- **History and menu layout**: Use lighter borderless history cards, a scrolling statistics summary, sticky search with a fading scroll edge and an entry menu for editing, export and deletion. Center window titles independently of the right-side actions across History, Settings, File Transcription, Meet and AI Chat. Remove the history entry counter, clarify the Settings menu button, and group menu actions by workflow and app maintenance, with Quit last.

### Fixed
- **Storage cleanup during imports**: Wait for active Meet and Drive downloads before allowing cleanup, and prevent imports from starting while cleanup runs, so downloaded files reach the transcription queue.
- **Settings window**: Route system and app-menu entry points to the same window controller, preserving the header, resizing and close/reopen behavior.
- **Local Whisper transcription**: Read CLI capability output while the process runs to prevent newer whisper.cpp versions from hanging before transcription starts.
- **Recording overlay**: Clip progress to the capsule, fit the panel to its content, reduce the shadow and keep microphone quality changes from shifting the recording controls.
- **Development launcher**: Reuse an existing watcher when running `make dev` again and reopen a closed dev app without starting another build or watcher.

---

## [3.58] - 2026-09-22

### Fixed
- **Release synchronization**: Prepare the version and changelog together, publish the same notes on GitHub, and include them in the application. Installed apps show notes for their own version instead of unreleased changes.

---

## [3.57] - 2026-09-22

### Changed
- **AI Chat controls**: Harmonize transcript, picker, and suggestion buttons, use matching circular voice/send controls with quieter disabled states, and show model selection only when an API key is configured. Expanding a voice transcript keeps its text before its date without repeating the preview.

---

## [3.56] - 2026-09-22

### Changed
- **AI Chat transcript workspace**: Search the full history, filter voice recordings and imports, preview and attach multiple transcripts from the composer, and start editable summary, action-item, or takeaway prompts. Compact source chips and transcript previews avoid repeated headings and text. Drafts stay with their chat; responses support inline formatting and copying.
- **AI Chat source context**: Attach full transcripts instead of summaries and retain attached sources throughout longer conversations.
- **Dev runtime stability**: Resolve bundle versions without rewriting watched source metadata, preventing repeated rebuilds when nothing changed.

---

## [3.55] - 2026-09-16

### Added
- **System search**: Find transcripts through Spotlight and access bilingual semantic discovery through App Intents.

### Fixed
- **History controls**: Integrate titlebar controls and correct action-button behavior.

---

## [3.54] - 2026-09-12

### Fixed
- **Update dialogs**: Keep release highlights readable in compact update alerts.

---

## [3.53] - 2026-09-12

### Changed
- **Updater feedback**: Manual update checks now always report their result, while compact update dialogs show up to three concise changelog highlights for the relevant version.
- **Unified warning center**: Accessibility and API-key warnings now share one compact notification area in the main menu.
- **Local transcription fallback**: Missing or invalid OpenAI credentials no longer block mode selection; Cloud stays unavailable while recordings and imported files fall back to the first ready local engine and skip unavailable AI refinement.

---

## [3.52] - 2026-09-12

### Removed
- **GigaAM transcription engine**: Removed the experimental engine, its Python runtime installer, and all related setup, settings, menu-bar, and file-transcription controls.

### Changed
- **Retired engine migration**: Existing settings that selected a retired transcription engine now keep all other preferences and fall back to OpenAI.
- **Shared engine picker**: Settings and Setup Wizard now render their engine choices from one SwiftUI component with surface-specific presentations.

---

## [3.51] - 2026-09-10

### Added
- **OpenAI API Key Validation & Real-Time Mode Locking**: Real-time detection of invalid, expired, or revoked OpenAI API keys. When an API key fails validation or returns HTTP 401, dependent AI modes are automatically locked with warning banners and tooltips, preventing failed dictation attempts.
- **In-Wizard Model Management**: Direct downloads, progress bars, and status checks for Parakeet TDT v3, Qwen3-ASR (Fast/Quality), and GigaAM directly within the Setup Wizard.

### Changed
- **Setup Wizard Modernization**: Redesigned Setup Wizard with native macOS glass translucency, centered engine selection with live readiness indicators, and a clean, spacious final slide featuring a GitHub star callout and hotkey guide.
- **Parakeet Auto-Readiness**: Automatically marked complete Parakeet models as ready without requiring manual verification on every app launch.

### Fixed
- **Bundled Changelog Synchronization**: Bundled `CHANGELOG.md` into the application resources, ensuring the installed version's release notes are immediately accessible offline without displaying stale cached changelogs.

---

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

## [3.0] - 2026-05-01

### Changed
- **Interface refresh**: Rework the menu bar, file queue, history, settings and setup wizard; separate file-processing jobs from the file queue view.

### Fixed
- **Transcript cleanup**: Share subtitle-credit and repetition filtering across local transcription, cloud transcription and summaries.
- **Recording and insertion**: Check microphone and Accessibility permissions before recording and release modifier keys after inserting text.

---

## [2.0.72] - 2026-04-29

### Added
- **Local engine setup**: Install `whisper.cpp` through Homebrew from the app's dependency setup flow.

---

## [2.0.71] - 2026-04-15

### Fixed
- **Menu bar sizing**: Remove the fixed minimum popover height to avoid empty space below the controls.

---

## [2.0.70] - 2026-04-15

### Changed
- **Local transcription controls**: Improve `whisper.cpp` execution and add cancellation during transcription and AI processing.

---

## [2.0.69] - 2026-04-06

### Fixed
- **Menu bar layout**: Resize the popover to fit its current content.

---

## [2.0.68] - 2026-04-06

### Added
- **Built-in profanity dictionaries**: Bundle English and Russian wordlists alongside the existing filters and custom dictionaries.

---

## [2.0.67] - 2026-04-05

### Added
- **Custom profanity dictionaries**: Import and manage wordlists in Settings.

---

## [2.0.66] - 2026-03-31

### Fixed
- **Failed recording recovery**: Keep audio from failed transcription attempts in history for later retranscription.

---

## [2.0.65] - 2026-03-29

### Fixed
- **Credentials and recovery**: Improve OpenAI API-key checks, recovery of saved recordings and recording-overlay placement.

---

## [2.0.64] - 2026-03-26

### Fixed
- **Updates and recording tails**: Stabilize application updates and preserve the end of speech when recording stops.

---

## [2.0.63] - 2026-03-26

### Added
- **History retranscription**: Run transcription again from a saved recording.

### Changed
- **Live Translator**: Hide its controls from the interface while retaining the implementation.

---

## [2.0.62] - 2026-03-26

### Added
- **User Story mode**: Turn spoken product requirements into user stories with acceptance criteria.

### Changed
- **Live Translator**: Improve microphone and system-audio translation.

---

## [2.0.61] - 2026-03-25

### Added
- **File summaries**: Automatically summarize imported transcripts and save the summary alongside the text in history.

---

## [2.0.60] - 2026-03-25

### Fixed
- **Speaker diarization**: Route text processing and speaker separation through OpenAI, removing the Perplexity-dependent bypass.

---

## [2.0.59] - 2026-03-09

### Fixed
- **Transcription stability**: Address local transcription hangs, voice-activity detection crashes and setup-wizard defaults.

---

## [2.0.58] - 2026-03-06

### Changed
- **File transcription**: Refine queue cards, range selection and cloud cost estimates; expand local Whisper artifact filtering.

---

## [2.0.57] - 2026-03-06

### Added
- **Time range selection**: Choose the start and end of an audio or video segment with a dual slider.

### Changed
- **App theme**: Switch the interface accent to blue.

---

## [2.0.56] - 2026-03-06

### Changed
- **File queue actions**: Enlarge the start and cancel controls on queue cards.

---

## [2.0.55] - 2026-03-06

### Changed
- **Explicit queue start**: Wait for Start or Start All instead of transcribing files immediately on import; show cloud diarization independently of AI cleanup.

---

## [2.0.54] - 2026-03-06

### Fixed
- **Cloud Whisper artifacts**: Adjust the transcription prompt to suppress subtitle/editor credits and repeated closing phrases.

---

## [2.0.53] - 2026-03-06

### Changed
- **File queue**: Redesign queue cards and improve cloud transcript cleanup.

---

## [2.0.52] - 2026-03-05

### Fixed
- **Recording window focus**: Prevent window jitter when switching applications with Cmd-Tab during recording.

---

## [2.0.51] - 2026-03-05

### Added
- **File transcription queue**: Process audio and video files in the background with progress, engine selection, speaker separation and cancellation.

### Changed
- **Settings and statistics**: Reorganize Settings and exclude file imports from dictation usage statistics.

### Fixed
- **Update persistence**: Preserve saved settings and existing macOS permission grants across updates.

---

## [2.0.35] - 2026-03-04

### Added
- **Experimental Auto-Enter**: Optionally press Enter after inserting a transcription.

---

## [2.0.34] - 2026-03-04

### Changed
- **Updater and recording indicators**: Add GitHub release update checks, refine the recording overlay and offer a monochrome menu bar icon.

---

## [2.0.0] - 2026-03-04

### Added
- **Initial public release as Whisper Free**: Menu bar dictation with configurable hotkeys, local `whisper.cpp` and OpenAI cloud transcription, automatic paste or typing, and transcription history.
- **AI modes**: Dictation, Email, Code and Notes presets with custom prompts and OpenAI or Perplexity text processing.
- **First-run setup and updates**: Permission guidance, local model selection and automatic updates through Sparkle.

---

## [1.0]

### Added
- **Early dictation prototype (early 2026, approximate retrospective)**: Record speech with a global shortcut, transcribe it locally with Whisper and insert the text into the active app.
