<div align="center">

<img src="assets/icon.png" width="128" alt="Holster app icon">

# Holster

Run your own prompts on selected text, anywhere in macOS.

[![License](https://img.shields.io/badge/license-MIT-0B347C)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-0B347C)
![Swift](https://img.shields.io/badge/Swift-6-0B347C)

</div>

Select text in any app, press your hotkey, and the answer streams into a
floating markdown window. Press ⌘↩ to copy it and close.

Holster talks to any OpenAI-compatible endpoint, so the model behind a command
can be a local Ollama, OpenAI, Google Gemini, OpenRouter, or a CLIProxyAPI
sitting in front of a subscription you already pay for. Prompts and commands are
plain files under `~/.config/holster/`, so you can keep them in git. Built as a
stable replacement for Raycast AI custom commands.

<!-- TODO: demo GIF of the popup goes here -->

## Features

- One global hotkey per command, recorded in Settings with a duplicate check
- Prompts and commands are plain files: git-friendly, hot-reloaded, and also
  editable from the built-in Settings UI
- Streaming markdown rendering, GFM tables included
- Smart copy pulls out the corrected sentence instead of the whole response
- API keys go to the macOS Keychain, never to `config.yaml`
- A fallback provider takes over when the primary one dies before any output
- Optional text-to-speech: free Edge voices, an OpenAI-compatible
  `/audio/speech`, or the built-in macOS voice
- Your clipboard survives the capture, and the restore is marked transient so
  clipboard managers don't log a duplicate
- Headless CLI mode for scripting and for testing prompts
- Native Swift and SwiftUI. No Electron, one small binary

## Privacy

Holster has no telemetry and no backend. Your selected text goes to the endpoint
you configure and nowhere else. The one exception is `tts.provider: edge`, which
sends whatever you ask it to speak to Microsoft's read-aloud service.

## Install

There is no prebuilt release yet, so build it from source. Everything goes
through SPM and there is no Xcode project to open, but you do need Xcode
installed for Swift 6.

```sh
git clone https://github.com/impelcrypto/Holster.git
cd Holster
make app       # build Holster.app into ./build.noindex
make install   # copy to /Applications and launch
make test      # unit tests
```

`scripts/bundle.sh` signs with your "Apple Development" certificate when you
have one and falls back to ad-hoc signing otherwise. Under ad-hoc signing macOS
forgets the Accessibility grant after every rebuild, so a stable certificate
saves you a trip to System Settings each time.

## First run

1. Launch the app. A text icon appears in the menu bar and the Settings window
   opens on General, where System Health shows the Accessibility permission
   (needed to read the selection via a synthetic ⌘C) and the config status.
2. `~/.config/holster/` is created with an example config and a grammar check
   prompt.
3. Select some text anywhere and press ⌘⇧G.

## Configuration

Everything lives in `~/.config/holster/`. Edit the files directly or use the
Settings window (menu bar icon → Settings…). Both stay in sync because the files
are the single source of truth and the app watches them. One caveat: saving from
the GUI re-serializes `config.yaml`, which drops your YAML comments.

```yaml
# config.yaml
providers:                 # any OpenAI-compatible endpoints
  cliproxy:
    base_url: http://127.0.0.1:8317/v1
    api_key: ""            # only for CLI/dev; the app uses macOS Keychain
  ollama:
    base_url: http://127.0.0.1:11434/v1
  opencode-go:             # https://opencode.ai/docs/go/
    base_url: https://opencode.ai/zen/go/v1
    api_key: ""
  gemini:                  # Google Gemini API
    base_url: https://generativelanguage.googleapis.com/v1beta/openai
    api_key: ""
  custom:                  # e.g. OpenRouter; editable from Settings
    base_url: https://openrouter.ai/api/v1
    api_key: ""

default_provider: cliproxy

tts:                       # provider: edge = free Edge voices, no API key;
  provider: edge           #   base_url = OpenAI-compatible; neither = macOS voice
  voice: en-US-AvaMultilingualNeural

commands:
  - name: Grammar Teacher
    hotkey: cmd+shift+g    # modifiers: cmd, shift, opt, ctrl
    prompt: grammar.md     # file under prompts/, {selection} gets replaced
    provider: cliproxy
    model: gpt-5.6-sol
    reasoning: medium      # low / medium / high; omit to send no reasoning field
                           # (on opencode-go an omitted value falls back to low:
                           #  its models think by default, so "none" never helps)
    copy_on_select: true   # selecting text in the result window copies it
    fallback_provider: ollama   # used when the provider fails before any output
    fallback_model: qwen3:8b    # omit to reuse the primary model
```

Prompt files take two placeholders: `{selection}` for the captured selection and
`{clipboard}` for the current clipboard contents.

### API keys

The packaged app stores keys you enter in Settings in the macOS Keychain rather
than in `config.yaml`. The first time it opens an existing config it also
migrates any plaintext provider or TTS keys into the Keychain and strips them
from the file. Development builds launched with `swift run` keep reading
`api_key` from YAML; the packaged app uses the Keychain in both menu-bar and
headless CLI modes.

### Providers and commands in Settings

Settings always offers `opencode-go` (fixed base URL), `gemini` (fixed
OpenAI-compatible base URL), and `custom` (free-form base URL), and writes them
to `providers:` on save.

Each command gets its own editor: hotkey recording that warns when another
command already claims the combination, a model list pulled from the provider's
`/v1/models` (type the ID when the endpoint has none), an API key check, and a
Test section that runs the draft on a sample sentence before you save.

### Theme

Settings → General → Theme picks System (default), Light, or Dark. It lives in
UserDefaults rather than `config.yaml`.

## Popup shortcuts

| Key | Action |
| --- | --- |
| ⌘↩ | Copy the corrected sentence (smart copy) and close |
| ⇧⌘↩ | Copy the full response |
| ⌘S | Speak the selection, or the whole response when nothing is selected |
| ⌘. | Stop generating (Esc also cancels the stream on close) |
| ⌘R | Retry (after an error) |
| Esc | Close |

## CLI

The same pipeline without the GUI or any permissions, handy for iterating on
prompts and providers:

```sh
Holster --list
Holster --run "Grammar Teacher" --text "It seem wrong."
echo "It seem wrong." | Holster --run "Grammar Teacher"
Holster --help
```

`--config <dir>` points at an alternative config directory and `--no-stream`
disables SSE. Each config directory gets its own Keychain namespace, so API keys
never leak between configs.

## Known limits

- Text-to-speech through CLIProxyAPI does not work, because `/v1/audio/speech`
  is not proxied for subscription auth. Point `tts.base_url` straight at a
  provider with a real API key, or use `provider: edge` or the macOS voice.
- `provider: edge` rides Microsoft Edge's free read-aloud voices over a
  WebSocket. No API key, but it is an unofficial endpoint that may change. On
  any failure Holster drops back to the built-in macOS voice.
- The built-in macOS voice (no provider, no base_url) honors `tts.voice`, either
  a name like `Ava` or a full identifier. Premium voices need a manual download
  from System Settings → Accessibility → Spoken Content → System voice → Manage
  Voices… → English (US). An uninstalled voice falls back to the default en-US one.
- A result window that is already open keeps the old theme until the next run.

## Contributing

Issues and pull requests are welcome. Run `make test` before opening one.

## License

[MIT](LICENSE)
