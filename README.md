<p align="center">
  <img src="Sources/WhisperFree/Resources/Banner.png" alt="WhisperFree" width="800">
</p>

<p align="center">
  <a href="#english">English</a> • <a href="#russian">Русский</a>
</p>

---

<a id="english"></a>

## English

### WhisperFree

Open-source macOS menu bar app for voice dictation, file transcription, summaries, and AI cleanup.

Current release: **3.0**.

No subscription is required. If you use cloud transcription or cloud AI cleanup, usage is billed to your own OpenAI account.

The repository is named **WhisperFree**. In the current builds, the macOS app bundle and UI are still labeled **WhisperKiller**, so you may see both names in the app, scripts, and releases.

### What the app can do right now

- **Menu bar dictation** with a configurable global shortcut. Default shortcut: `⌥ Space`.
- **Three recording styles**: Hold to Record, Toggle, and Push to Talk.
- **Two transcription engines**:
  - Local via `whisper.cpp`
  - Cloud via OpenAI Whisper API
- **AI cleanup modes** after transcription:
  - Raw
  - Dictation
  - Email
  - Code
  - Notes
  - Custom modes with your own prompt
- **Automatic insertion into the active app**:
  - paste as one block
  - type character-by-character
  - optional auto-Enter
- **Floating recording overlay** during capture and processing.
- **Speaker diarization** for interviews and meetings.
- **File transcription window** with:
  - drag-and-drop queue
  - audio and video file support
  - per-file start/end range
  - progress states
  - cloud-only cost estimates tied to the actual run
  - cancel/remove/clear flow
- **Auto summary for imported files** with sections for topics, speaker threads, decisions, action items, and open questions.
- **History window** with:
  - search
  - copy processed text, raw text, or summary
  - quick rename/edit
  - playback of saved recordings when available
  - Finder reveal for stored audio
  - usage stats such as total words, average WPM, and estimated time saved
- **Live Translator** for microphone and system audio translation.
- **Model management inside the app** for local Whisper models:
  - Tiny
  - Base
  - Small
  - Medium
  - Large v3 Turbo
  - Large v3
- **Setup wizard** for first launch, permissions, engine choice, and dependency guidance.
- **Accessibility helper panel** for dragging the app into macOS Privacy & Security.
- **GitHub release updater** built into the app.

### 3.0 highlights

- Native macOS UI sweep across menu bar, file transcription, history, settings, onboarding, and overlays.
- Cloud/local file transcription preserves engine, model, language, and cost provenance for completed jobs.
- Local transcription uses explicit language/auto-language settings and sanitizes common ASR filler artifacts.
- Long summaries are chunked before final synthesis.
- Recording enters the active state only after Accessibility and Microphone permissions are valid and the audio engine starts.

### Engines and dependencies

- **Local transcription**:
  - requires `whisper.cpp` (`brew install whisper-cpp`)
  - uses downloadable Whisper model files inside the app
  - works offline once installed
- **Cloud transcription**:
  - requires an OpenAI API key
  - uses OpenAI Whisper API
- **AI cleanup modes and diarization**:
  - require an OpenAI API key
- **Auto summaries**:
  - can use OpenAI when a key is available
  - can fall back to Ollama when local follow-up is configured

### Language support

- The current UI exposes **17 selectable languages plus Auto-detect**:
  - English
  - Russian
  - Spanish
  - French
  - German
  - Italian
  - Portuguese
  - Japanese
  - Korean
  - Chinese
  - Arabic
  - Hindi
  - Turkish
  - Polish
  - Dutch
  - Swedish
  - Ukrainian

### System requirements

- **macOS**: 14.0 or newer
- **Official install/build scripts** target **Apple Silicon (`arm64`)**
- **RAM**:
  - 8 GB minimum for basic usage
  - 16 GB+ recommended for larger local models

### Permissions

- **Accessibility** is required for global hotkeys and text insertion into other apps.
- **Microphone** is required for voice dictation.

### Installation

1. Download the latest `.dmg` from [Releases](https://github.com/iddictive/Whisper-Killer/releases).
2. Move the app to `Applications`.
3. Launch it and complete the setup wizard.
4. Grant `Accessibility` and `Microphone` access when prompted.
5. Choose your engine:
   - OpenAI API key for cloud transcription
   - `whisper.cpp` + local model download for offline transcription
   - Ollama if you want local Live Translator / local follow-up AI

### Build from source

```bash
git clone https://github.com/iddictive/Whisper-Killer.git
cd Whisper-Killer
make install
```

Useful commands:

```bash
make install  # reinstall app to /Applications and launch it
make verify   # verify release build
```

---

<a id="russian"></a>

## Русский

### WhisperFree

Open-source приложение для macOS в menu bar: диктовка голосом, транскрибация файлов, саммари и AI-обработка текста.

Текущий релиз: **3.0**.

Подписка не нужна. Если использовать облачную транскрибацию или облачную AI-обработку, расходы идут только по вашему OpenAI-аккаунту.

Репозиторий называется **WhisperFree**, но в текущих сборках само приложение, `.app` bundle и часть интерфейса всё ещё называются **WhisperKiller**. Поэтому в коде, релизах и UI встречаются оба имени.

### Что приложение умеет сейчас

- **Диктовка из menu bar** по настраиваемой глобальной горячей клавише. По умолчанию: `⌥ Space`.
- **Три режима записи**:
  - удержание клавиши
  - toggle-режим
  - push-to-talk
- **Два движка транскрибации**:
  - локально через `whisper.cpp`
  - через OpenAI Whisper API
- **AI-обработка текста после распознавания**:
  - Raw
  - Dictation
  - Email
  - Code
  - Notes
  - пользовательские режимы со своим промптом
- **Автовставка результата в активное приложение**:
  - вставкой одним блоком
  - посимвольной печатью
  - с опциональным авто-`Enter`
- **Плавающий overlay** во время записи и обработки.
- **Диаризация спикеров** для встреч, интервью и разговоров.
- **Отдельное окно транскрибации файлов**, где есть:
  - drag-and-drop очередь
  - поддержка аудио и видео файлов
  - выбор нужного временного диапазона внутри файла
  - статусы прогресса
  - cloud-only оценка стоимости, привязанная к фактическому прогону
  - отмена, удаление и очистка очереди
- **Автосводка для импортированных файлов** с блоками: темы, линии спикеров, решения, действия и открытые вопросы.
- **Окно истории** с возможностями:
  - поиск
  - копирование обработанного текста, сырой расшифровки или сводки
  - быстрое переименование/редактирование
  - проигрывание сохранённых записей, если аудио доступно
  - открытие исходного аудио в Finder
  - статистика: слова, средний WPM, оценка сэкономленного времени
- **Live Translator** для перевода с микрофона и системного аудио.
- **Управление локальными Whisper-моделями прямо в приложении**:
  - Tiny
  - Base
  - Small
  - Medium
  - Large v3 Turbo
  - Large v3
- **Мастер первого запуска** для разрешений, выбора движка и зависимостей.
- **Accessibility helper panel** для перетаскивания приложения в macOS Privacy & Security.
- **Встроенная проверка обновлений** через GitHub Releases.

### Что нового в 3.0

- Нативный macOS UI sweep для menu bar, file transcription, history, settings, onboarding и overlays.
- Cloud/local транскрибация файлов сохраняет engine/model/language/cost provenance у завершенных задач.
- Локальная транскрибация использует явный язык/auto-language и чистит типовые ASR-заглушки.
- Длинные саммари режутся на чанки перед финальным синтезом.
- Запись переходит в активное состояние только после валидных Accessibility/Microphone прав и успешного старта аудио-движка.

### Движки и зависимости

- **Локальная транскрибация**:
  - требует `whisper.cpp` (`brew install whisper-cpp`)
  - использует скачиваемые Whisper-модели внутри приложения
  - после установки работает офлайн
- **Облачная транскрибация**:
  - требует OpenAI API key
  - использует OpenAI Whisper API
- **AI-режимы и диаризация**:
  - требуют OpenAI API key
- **Автосводки**:
  - могут работать через OpenAI при наличии ключа
  - могут использовать Ollama как локальный follow-up движок

### Поддержка языков

- В текущем UI доступны **17 языков плюс Auto-detect**:
  - English
  - Russian
  - Spanish
  - French
  - German
  - Italian
  - Portuguese
  - Japanese
  - Korean
  - Chinese
  - Arabic
  - Hindi
  - Turkish
  - Polish
  - Dutch
  - Swedish
  - Ukrainian

### Системные требования

- **macOS**: 14.0 или новее
- **Официальные install/build scripts** ориентированы на **Apple Silicon (`arm64`)**
- **RAM**:
  - минимум 8 ГБ для базового использования
  - 16 ГБ+ желательно для крупных локальных моделей

### Разрешения

- **Accessibility** нужно для глобальных хоткеев и вставки текста в другие приложения.
- **Microphone** нужен для голосовой диктовки.

### Установка

1. Скачайте актуальный `.dmg` со страницы [Releases](https://github.com/iddictive/Whisper-Killer/releases).
2. Переместите приложение в `Applications`.
3. Запустите приложение и пройдите мастер первого запуска.
4. Выдайте доступ к `Accessibility` и `Microphone`.
5. Выберите нужный режим:
   - OpenAI API key для облачной транскрибации
   - `whisper.cpp` + локальная модель для офлайн-работы
   - Ollama для локального follow-up AI

### Сборка из исходников

```bash
git clone https://github.com/iddictive/Whisper-Killer.git
cd Whisper-Killer
make install
```

Полезные команды:

```bash
make install  # переустановить приложение в /Applications и запустить
make verify   # проверить release-сборку
```

---

MIT License.
