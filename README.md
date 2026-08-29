# Holster

A macOS menu bar app that runs your prompt templates on selected text via any
OpenAI-compatible endpoint (CLIProxyAPI, Ollama, OpenAI, ...). Built as a
stable replacement for Raycast AI custom commands.

Select text in any app, press your hotkey, and the LLM result appears in a
floating markdown popup. Press ⌘↩ to copy the corrected sentence and close.

- One global hotkey per command
- Prompts and commands are plain files under `~/.config/holster/`
  (git-friendly, hot-reloaded), also editable in the built-in settings UI
- Streaming markdown rendering with GFM tables
- Smart copy: extracts the corrected sentence, not the whole response
- Optional text-to-speech (OpenAI-compatible `/audio/speech`, falls back to
  the built-in macOS voice)
- Headless CLI mode for scripting and testing
- Native Swift, no Electron; a single small binary

## Build and install

Requires Xcode (Swift 6+). No Xcode project — everything builds with SPM.

```sh
make app       # build Holster.app into ./build.noindex
make install   # copy to /Applications and launch
make test      # unit tests
```

Signing: `scripts/bundle.sh` picks up your "Apple Development" certificate
automatically if you have one, and falls back to ad-hoc signing otherwise.
With ad-hoc signing macOS forgets the Accessibility grant after every
rebuild, so a stable certificate is worth it.

## First run

1. Launch the app; a text icon appears in the menu bar.
2. `~/.config/holster/` is created with an example config and a grammar
   check prompt.
3. Select some text anywhere and press ⌘⇧G. The first run asks for
   Accessibility permission (needed to read the selection via a synthetic
   ⌘C); grant it in System Settings → Privacy & Security → Accessibility,
   then try the hotkey again.

## Configuration

Everything lives in `~/.config/holster/`. Edit the files directly or use
the Settings window (menu bar icon → Settings…) — both stay in sync because
the files are the single source of truth and the app watches them.
Note: a GUI save re-serializes `config.yaml`, so YAML comments are lost.

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
    fallback_provider: ollama   # used when the provider fails before any output
    fallback_model: qwen3:8b    # omit to reuse the primary model
```

The packaged app stores API keys entered in Settings in macOS Keychain, not in
`config.yaml`. When it first opens an existing config, it also migrates any
plaintext provider or TTS API keys to Keychain and removes them from the file.
Development executables launched with `swift run` keep using `api_key` from
YAML; the packaged app uses Keychain in both menu-bar and headless CLI modes.

The Settings window always offers `opencode-go` (OpenCode Go, fixed base URL)
and `custom` (free-form base URL) as providers and writes them to `providers:`
on save.

Prompt files support two placeholders: `{selection}` (the captured selection)
and `{clipboard}` (current clipboard contents).

## Popup keys

| Key | Action |
| --- | --- |
| ⌘↩ | Copy the corrected sentence (smart copy) and close |
| ⇧⌘↩ | Copy the full response |
| ⌘S | Speak the corrected sentence |
| ⌘R | Retry (after an error) |
| Esc | Close |

## CLI mode

Runs the same pipeline without GUI or permissions — useful for testing
prompts and providers:

```sh
Holster --list
Holster --run "Grammar Teacher" --text "It seem wrong."
echo "It seem wrong." | Holster --run "Grammar Teacher"
```

`--config <dir>` points at an alternative config directory, `--no-stream`
disables SSE.

## Notes

- `provider: edge` uses Microsoft Edge's free read-aloud voices over a
  WebSocket — no API key, but it's an unofficial endpoint that may change; on
  any failure Holster falls back to the built-in macOS voice.
- TTS through CLIProxyAPI does not work (`/v1/audio/speech` is not proxied
  for subscription auth); point `tts.base_url` directly at a provider with a
  real API key, or use `provider: edge` / the macOS voice instead.
- The built-in macOS voice (no provider, no base_url) honors `tts.voice` (a
  name like `Ava` or a full identifier). Premium voices are a manual download:
  System Settings → Accessibility → Spoken Content → System voice → Manage
  Voices… → English (US). If the voice isn't installed, it falls back to the
  default en-US voice.
- The app restores your clipboard after capturing the selection and marks the
  restore transient so clipboard managers don't record a duplicate.
- Settings → General → Theme picks System (default), Light or Dark. It is stored
  in UserDefaults, not `config.yaml`. A result window that is already open keeps
  the old theme until the next run.

## License

MIT
