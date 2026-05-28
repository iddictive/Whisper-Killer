<p align="center">
  <img src="Sources/WhisperFree/Resources/Banner.png" alt="WhisperFree" width="800">
</p>

<p align="center">
  <a href="#english">English</a> | <a href="#russian">Русский</a>
</p>

---

<a id="english"></a>

## WhisperFree

WhisperFree turns a Mac menu bar shortcut into dictation, file transcription, summaries, and text cleanup.

It can run locally through `whisper.cpp`, use OpenAI Whisper for cloud transcription, or use GigaAM for Russian ASR experiments. Cloud features use your own OpenAI API key; the app itself does not require a subscription.

Current release: **3.0**

## What it does

- Dictate from the menu bar with a global shortcut. Default: `Option + Space`.
- Choose hold-to-record, toggle recording, or push-to-talk.
- Transcribe audio and video files from a drag-and-drop queue.
- Trim file ranges before transcription.
- Insert the result into the active app by paste, typing, or paste-and-enter.
- Clean up transcripts with built-in modes for dictation, email, code, notes, and custom prompts.
- Add speaker diarization and summaries for meetings or interviews when an OpenAI key is available.
- Keep a searchable history with raw text, processed text, summaries, playback, and Finder reveal.
- Translate microphone or system audio through the Live Translator surface.
- Import supported Google Meet recordings from Drive when Google OAuth is configured.

## Engines

| Engine | Use it for | Requirements |
| --- | --- | --- |
| Local Whisper | Offline dictation and file transcription | `brew install whisper-cpp` plus a downloaded Whisper model |
| OpenAI Whisper | Cloud transcription runs | OpenAI API key |
| GigaAM Russian | Experimental Russian ASR | Python runtime and GigaAM packages |
| Ollama follow-up | Local follow-up summaries where configured | Ollama installed locally |

## Languages

The app exposes 17 selectable languages plus auto-detect: English, Russian, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Arabic, Hindi, Turkish, Polish, Dutch, Swedish, and Ukrainian.

## Install

1. Download the latest `.dmg` from [Releases](https://github.com/iddictive/Whisper-Killer/releases).
2. Move the app to `Applications`.
3. Launch it and complete the setup wizard.
4. Grant Accessibility and Microphone permissions.
5. Pick a transcription engine in Settings.

## Build from source

```bash
git clone https://github.com/iddictive/Whisper-Killer.git
cd Whisper-Killer
make install
```

Useful commands:

```bash
make install  # build, install to /Applications, and launch
make verify   # verify release build
```

## Requirements

- macOS 14 or newer
- Apple Silicon for the official install/build scripts
- 8 GB RAM minimum; 16 GB or more is better for larger local models
- Accessibility permission for global shortcuts and text insertion
- Microphone permission for dictation

---

<a id="russian"></a>

## WhisperFree

WhisperFree превращает shortcut в macOS menu bar в диктовку, транскрибацию файлов, саммари и очистку текста.

Приложение может работать локально через `whisper.cpp`, отправлять аудио в OpenAI Whisper или использовать GigaAM для экспериментального русского ASR. Облачные функции работают через ваш OpenAI API key; отдельная подписка на приложение не нужна.

Текущий релиз: **3.0**

## Что умеет приложение

- Диктовка из menu bar по глобальной горячей клавише. По умолчанию: `Option + Space`.
- Режимы hold-to-record, toggle и push-to-talk.
- Транскрибация аудио и видео через drag-and-drop очередь.
- Выбор нужного временного диапазона внутри файла.
- Вставка результата в активное приложение: paste, посимвольный ввод или paste-and-enter.
- Обработка текста режимами для диктовки, email, кода, заметок и своих промптов.
- Диаризация спикеров и саммари для встреч или интервью при наличии OpenAI API key.
- История с поиском, raw/processed текстом, саммари, playback и открытием файла в Finder.
- Live Translator для микрофона и системного аудио.
- Импорт поддерживаемых Google Meet записей из Drive, если настроен Google OAuth.

## Движки

| Движок | Для чего | Требования |
| --- | --- | --- |
| Local Whisper | Офлайн-диктовка и транскрибация файлов | `brew install whisper-cpp` и скачанная Whisper-модель |
| OpenAI Whisper | Облачная транскрибация и более точные прогоны | OpenAI API key |
| GigaAM Russian | Экспериментальный русский ASR | Python runtime и GigaAM packages |
| Ollama follow-up | Локальные follow-up саммари, если настроено | Ollama на машине |

## Языки

В интерфейсе доступно 17 языков плюс auto-detect: English, Russian, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Arabic, Hindi, Turkish, Polish, Dutch, Swedish, Ukrainian.

## Установка

1. Скачайте последнюю `.dmg` сборку в [Releases](https://github.com/iddictive/Whisper-Killer/releases).
2. Перенесите приложение в `Applications`.
3. Запустите приложение и пройдите setup wizard.
4. Дайте доступ к Accessibility и Microphone.
5. Выберите движок транскрибации в Settings.

## Сборка из исходников

```bash
git clone https://github.com/iddictive/Whisper-Killer.git
cd Whisper-Killer
make install
```

Полезные команды:

```bash
make install  # собрать, установить в /Applications и запустить
make verify   # проверить release build
```

## Требования

- macOS 14 или новее
- Apple Silicon для официальных install/build scripts
- 8 GB RAM минимум; 16 GB+ лучше для больших локальных моделей
- Accessibility для hotkeys и вставки текста
- Microphone для диктовки
