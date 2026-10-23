# TimeStamp changelog

## 2.0.0

Rewritten for **World of Warcraft: Midnight** (12.1.5, PTR 12.1.7) and **World of Warcraft: Forever** (1.60.1).

### New: settings panel (Options > AddOns > TimeStamp, or `/ts config`)
While a TimeStamp page is open, a live preview shows exactly what your screenshots will look like. Drag it to move it.

- **TimeStamp**: screenshot key overlay, companion mode, clean shot countdown, position and scale for both the screenshot overlay and the clean card.
- **Appearance**: heading and text fonts (game fonts plus any LibSharedMedia fonts from your other addons), sizes, outline, drop shadow, colors, class-colored name, background style (none, shade, fade, tooltip box) and opacity.
- **Layout**: stacked or compact arrangement, separator, text alignment, line spacing, spacer size, and 14 line slots to choose what goes where. Line details: realm, character title, race, specialization, guild rank, experience, and 10 date/time formats.

### Also new
- Lines for map coordinates and a personal note per character (`/ts note <text>`).
- Countdown before a clean shot (run `/ts` again to cancel).
- Key bindings for both shot types (Keybindings > AddOns).
- Minimap addon-compartment entry: left-click opens settings, right-click takes a clean shot.
- `/ts unlock card` to move the clean card; `/ts reset` resets both positions.

### Improvements
- Your UI is always restored after a clean shot, even if combat starts mid-capture or no screenshot event arrives.
- Safe with Midnight's secret values; a broken line never breaks a screenshot.
- Month and weekday names follow your game language.
- Settings from 1.x carry over (overlay position, companion mode, screenshot key option).
