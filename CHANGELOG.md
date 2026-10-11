# Changelog

## 2.0.1 (2026-10-10)

- **Calmer, physically based icon colors.** The menu bar icon and the percentage readouts (menu and Dynamic Options) now use the white point Night Shift is actually producing, exaggerated 1.45 times so it reads at menu bar size: white at 0%, through cream and peach, to candlelight amber (about 2230 K) at 100%. The old hand-picked palette went from gold to deep red and was far stronger than the real tint.
- **Even steps, no jump at 0%.** Levels are spaced by perceived difference (equal OKLab distances), so 0% to 1% looks like 1% to 2% and like 99% to 100%. The filled icon is now drawn at 0% too (plain white, or black on a light menu bar), so turning the level up from 0% no longer switches glyph and color at once. The outline icon now only means "off".
- Light menu bars get the same hues, darkened (template black to dark amber) with at least 3.8:1 contrast against the bar.
- The optional percentage next to the icon uses the same color.
- NightMode now quits cleanly (finishing any fade and saving) when it receives SIGTERM, for example from `pkill NightMode`.

## 2.0.0 (2026-10-10)

First public release: exact levels with -5 / -1 / +1 / +5 nudges and one-click 0 / 25 / 50 / 75 / 100%, gradual ramps, daily schedules with sunset and sunrise, tint that follows display brightness, recommended presets, global shortcuts, launch at login, and automatic migration from NightMode 1.x.
