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
sitting in front of a ChatGPT or Claude subscription you already pay for. Prompts and commands are
plain files under `~/.config/holster/`, so you can keep them in git. Built as a
stable replacement for Raycast AI custom commands.

<div align="center">

<img src="assets/demo.gif" width="820" alt="Selecting a sentence in TextEdit, pressing the hotkey, and the Grammar Teacher command streaming corrections into a floating window">

</div>

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
3. Set up a provider (next section), then select some text anywhere and press ⌘⇧G.

## AI providers

Holster needs one OpenAI-compatible endpoint behind your commands. Pick the one
that matches what you already have.

### Ollama: free, and the quickest to get running

Cloud models run on Ollama's machines, so a 31B model answers at full speed on a
Mac that could never hold it in memory.

```sh
brew install ollama          # or grab the app from https://ollama.com/download
brew services start ollama   # skip this if you installed the app instead
ollama signin                # free ollama.com account; cloud models need it
ollama pull gemma4:31b-cloud
```

The example config already points an `ollama` provider at
`http://127.0.0.1:11434/v1`, and it needs no API key. Open Settings, pick your
command, set Provider to `ollama` and Model to `gemma4:31b-cloud`. The example
command ships on `cliproxy`, so it keeps failing until you switch it.

The free tier covers light use, with limits that reset per session and per week
([pricing](https://ollama.com/pricing)). To skip the account and the limits, pull
a local model instead: `ollama pull gemma4:12b` weighs about 7 GB and runs
entirely on your Mac.

### CLIProxyAPI: your ChatGPT or Claude subscription, no API key

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) signs in to a
subscription you already pay for and serves it on an OpenAI-compatible port.
Nothing is billed per token.

```sh
brew install cliproxyapi
cliproxyapi --codex-login    # ChatGPT Plus/Pro, opens a browser
cliproxyapi --claude-login   # Claude Pro/Max
brew services start cliproxyapi
```

The proxy listens on 8317, which is where the example config's `cliproxy`
provider already points, and it takes an empty API key.

This setup has more moving parts than the other two, so the easiest route is to
delegate it: hand this README and <https://help.router-for.me/> to Claude Code or
another coding agent and ask it to finish the setup. It can install the binary,
walk you through the OAuth login, and write the provider into `config.yaml`.

### OpenCode Go and Gemini API keys

Settings ships presets for `opencode-go` and `gemini`, both on fixed base URLs.
Paste a key into the command editor and it lands in the Keychain rather than in
`config.yaml`. Anything else OpenAI-compatible, OpenRouter for instance, goes
under the `custom` preset with its own base URL. Saving writes the provider into
`providers:` for you.

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

### Commands in Settings

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
