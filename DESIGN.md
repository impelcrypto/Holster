# Holster Design System

## 1. Atmosphere & Identity

Holster is a compact native macOS utility with the quiet density of a system
preferences pane. Its signature is warm amber hardware-inspired accents over
layered neutral surfaces, reflecting the brass and leather app icon. The
optional Western style shifts the same layout to brass, saddle leather and
parchment without changing the information hierarchy.

## 2. Color

Colors are defined in `HolsterTheme` and adapt to light and dark appearances.

| Role | Swift token | Usage |
| --- | --- | --- |
| Accent | `HolsterTheme.accent` | Icons and selected controls |
| Accent deep | `HolsterTheme.accentDeep` | Window tint and focus color |
| Accent gradient | `HolsterTheme.accentGradient` | Primary actions and selection pills |
| Window | `HolsterTheme.windowBackground` | Detail backgrounds (parchment in Western) |
| Card | `HolsterTheme.card` | Grouped settings |
| Inset | `HolsterTheme.inset` | Fields, editors, segmented controls |
| Hairline | `HolsterTheme.hairline` | Dividers and subtle outlines |
| Banner warn/success | `HolsterTheme.bannerWarningBackground` / `bannerSuccessBackground` | Status banner wash |
| Overline | `HolsterTheme.overline` | Section headers (brass in Western) |

Style switching lives beside the light/dark mode in Appearance:
`VisualStyle` (`standard`/`western`, UserDefaults `visualStyle`). Tokens are
computed from `VisualStyle.stored` so `@AppStorage(VisualStyle.storageKey)`
re-renders pick up the change; `AppearancePreference` still owns
`NSApp.appearance` only.

Semantic text and status colors use SwiftUI system colors so they continue to
track macOS accessibility and appearance settings.

## 3. Typography

Use the macOS system font throughout and the system monospaced design for
hotkeys, URLs, API keys, and editable prompt text. Existing sizes form the
scale: 20 pt titles; 13 pt rows; 12-12.5 pt controls; 11-11.5 pt metadata and
section labels; 10-10.5 pt compact sidebar metadata.

## 4. Spacing & Layout

Spacing follows a roughly 4 pt base rhythm. Settings detail content is capped
at 680 pt with 24 pt page padding. Reusable rows are at least 44 pt high and
use 14 pt horizontal and 9 pt vertical padding. The navigation split view owns
window-level layout and detail screens own their scrolling.

## 5. Components

### SettingsCard

- Structure: zero-spacing vertical stack on the card surface.
- States: content owns control states; the container remains static.
- Layout: groups related settings with 12 pt continuous corners (14 pt in Western).

### SettingRow and RowDivider

- Structure: left label, flexible space, trailing control; inset divider.
- States: controls retain native hover, keyboard, focus, and disabled behavior.
- Layout: one readable horizontal row with a 44 pt minimum target height.

### SettingsSection

- Structure: uppercase overline, optional note, then section content.
- Layout: vertical stack with an 8 pt gap.

### InsetFieldChrome

- Structure: plain native field on the inset surface.
- States: default and focused; focus uses the accent outline.
- Accessibility: native text-field keyboard and accessibility behavior remains intact.

### CredentialStatus

- Structure: a compact icon-and-label row directly below the credential field, with an optional trailing removal action.
- States: checking uses a progress indicator and secondary text; connected uses a system-green checkmark; failed uses a system-orange warning and retry action.
- Content: status copy must distinguish secure storage from a verified provider connection and must never reproduce any credential characters.
- Accessibility: pair every semantic color with an SF Symbol and explicit text; destructive removal requires confirmation.

### SegmentedPicker

- Structure: native buttons inside an inset capsule.
- States: default, selected, pressed, focus, and disabled through SwiftUI.
- Motion: selection changes use a 150 ms ease-out transition.

### AccentButtonStyle and GhostButtonStyle

- Variants: filled primary action and translucent secondary action.
- States: default, hover, pressed, and disabled.
- Motion: hover feedback uses a 120 ms ease-out transition.

### StatusBanner

- Structure: tinted wash with icon tile, bold title, secondary message and optional trailing action.
- States: warning (peach) and success (mint); never encode meaning by color alone — icon plus text always present.
- Layout: 16 pt padding, card-radius corners, hairline outline.

### GettingStartedView

- Structure: status banner, large title, `SetupProgressBar` (required steps only, optional step excluded) and a `SettingsCard` of `StepStatusIcon` rows.
- Content: mirrors General's System Health state (Accessibility, config/commands) without duplicating its controls.

## 6. Motion & Interaction

Motion is brief and communicates state. Hover and focus feedback uses 120-150
ms ease-out animation; larger state transitions remain native SwiftUI. Avoid
decorative motion. Native keyboard navigation and reduced-motion behavior take
precedence.

## 7. Depth & Surface

Use a mixed tonal-shift and hairline strategy: window, card, and inset tokens
create the primary hierarchy, while low-contrast one-point outlines clarify
control boundaries. Do not add shadows or new materials for ordinary settings.

## 8. Accessibility Constraints & Accepted Debt

- Preserve native macOS controls, keyboard navigation, focus handling, and
  appearance-aware semantic colors.
- Keep interactive rows at least 44 pt high and do not encode meaning by color alone.
- Provider and model names must remain readable at the settings window's 760 pt minimum width.

No accepted design debt is introduced by the Gemini provider preset.
