# Live Translator settings contract

## User Story

As a WhisperKiller user, I want Live Translator to stay out of my recording workflow until I explicitly enable it, so that an optional translation tool never adds inactive controls or starts work unexpectedly.

## Scope

- In scope: the Live Translator settings pane, its persisted enabled state, its hotkey and runtime lifecycle, and every Live Translator control in the menu-bar popover.
- Out of scope: translation quality, language/model inventory, subtitle overlay design, and the standalone GigaAM transcription experiment.

## Surface contract

- User job: opt into Live Translator, configure it, and start or stop microphone translation.
- Primary object: the persisted `liveTranslatorEnabled` preference.
- First action: a labeled system switch inside the same settings-card structure used by the other settings panes.
- Information placement: the enable switch is always visible; start/stop is visible only when enabled; language, engine, and advanced controls progressively reveal below it.
- Stable anatomy: pane title, enable card, configuration sections, and one advanced disclosure. The disabled pane must remain intentional rather than collapse into empty space.

```text
Disabled                         Enabled
┌ Live Translator               ┌ Live Translator
│                               │
│ Enable Live Translator  [off] │ Enable Live Translator   [on]
└                               │ Microphone translation  [Start]
                                │
                                │ Languages
                                │ Translation Engine
                                │ Advanced
                                └

Menu-bar popover                Menu-bar popover
No translation controls         Compact translation control
No translation command          Start/Stop translation command
```

## State and lifecycle

| State | Settings pane | Menu-bar popover | Hotkey/runtime |
| --- | --- | --- | --- |
| First launch / missing stored key | Disabled card | No controls | Not registered; cannot start |
| Enabled | Configuration and start/stop visible | Compact control and command visible | Hotkey registered; runtime may start |
| Disabled after use | Configuration and start/stop hidden | No controls | Runtime stops; hotkey unregisters |
| Relaunch | Restores the persisted state | Matches the persisted state | Matches the persisted state |

Default, hover, focus, and active appearance remain system-owned through SwiftUI controls. Loading, error, and success are unchanged because this change does not alter the translator runtime feedback surface.

## Acceptance Criteria

- A new or missing `liveTranslatorEnabled` preference resolves to `false`.
- The disabled pane shows one clearly labeled enable switch and no start action or configuration fields; no “Experimental” label describes Live Translator.
- Enabling the switch persists the preference and reveals the start action, configuration sections, menu command, compact menu-bar control, and hotkey.
- Disabling the switch persists the preference, stops an active translator, unregisters its hotkey, and removes every Live Translator control from the menu-bar popover.
- Must not rename or remove the separate GigaAM experimental transcription engine or change translation behavior, models, languages, permissions, or overlay content.

## References

- Existing project settings anatomy: `SettingsView`, `SWSectionHeader`, and `SWCard`.
- Apple SwiftUI `Toggle`: the visible label describes the state being switched.
- Apple HIG disclosure controls: advanced details stay hidden until relevant.

## Stabilization critique

- Keep: the existing pane, sidebar destination, configuration order, and single Advanced disclosure; they already match the user job and avoid a navigation change.
- Rework: move enablement out of the decorative header and into a labeled settings card; keep the pane useful while disabled.
- Merge: place start/stop in the enable card instead of maintaining a separate prominent header action.
- Remove: the empty disabled-state spacer and every menu-bar control that bypasses `liveTranslatorEnabled`.
- Keep: existing SwiftUI controls, semantic `SW` tokens, language/model sources, and runtime owner.
- Reject: replacing the pane with a new `Form` or raw `GroupBox` hierarchy. Those containers are system-appropriate in isolation, but the strongest local alternative is the existing section-card anatomy used by adjacent WhisperKiller settings; reusing it preserves navigation rhythm and shared tokens.
- Not applicable: new imagery, motion, responsive breakpoints, loading output, and error copy. None owns the reported defect.
- Resolved decision: `liveTranslatorEnabled` remains the single profile-level owner; UI visibility alone is insufficient, so the runtime start boundary also rejects the disabled state.

## Verification

- Primary falsifier: run the canonical `make dev` app and replay `off → on → off` across Settings and the menu-bar popover.
- Nearest negative case: while enabled, configuration, start/stop, compact menu control, and menu command remain available.
- Persistence check: relaunch the dev app after the final disabled state and confirm the switch and menu remain disabled.
- Source checks: targeted default-value test plus a debug build.
- Escalate to broader verification if runtime keeps running after disable, persisted state changes on relaunch, or the rendered app disagrees with the current source.
