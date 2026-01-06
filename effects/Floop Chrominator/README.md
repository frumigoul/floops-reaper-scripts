# Floop Chrominator

**Stereo Analog Saturator for Reaper.**

*   **Author**: © 2025-2026 Flora Tarantino (Floop's Reaper Script)
*   **Version**: 1.1.0
*   **Website**: [www.floratarantino.com](https://www.floratarantino.com)

## Description

**Floop Chrominator** is a JSFX effect for REAPER that emulates stereo "analog" saturation with five selectable modes (Soft, Even, Clip, Warm, Odd). It adds warmth, presence, and character to tracks and buses, from subtle color to heavier drive, featuring oversampling, filters, tilt EQ, auto‑gain, and smooth parameter transitions.

## Key Features

*   **Five Saturation Modes**: Soft, Even, Clip, Warm, Odd.
*   **Oversampling**: 1x, 2x, 4x with FIR anti-aliasing (HQ 17-tap).
*   **Filters**: Low Cut and High Cut with selectable slope (Gentle/Sharp).
*   **Head Bump**: Low-frequency reinforcement near the cutoff.
*   **Tilt EQ**: Balances lows and highs after saturation.
*   **Auto-Gain**: Matches loudness between dry and wet signals.
*   **Smooth Transitions**: Glide and crossfade on control changes to prevent clicks.
*   **DPI-Aware UI**: Scales buttons, knobs, and labels with window size/DPI.

## Requirements

*   **REAPER v7.00** or later.
*   Tested on Windows 10/11 and Linux (Pop!_OS).
*   Should work on macOS (standard JSFX code), but not explicitly tested.

## Installation

1.  **Open REAPER**.
2.  Go to **Options > Show REAPER resource path...**.
3.  Enter the **Effects** folder.
4.  Copy the `Floop Chrominator.jsfx` file into this folder.
5.  **Restart REAPER** (recommended) or press "F5" in the FX Browser.
6.  In the FX Browser, search for "Floop Chrominator" and load it on a track.

## Usage

1.  Add **Floop Chrominator** to a track or bus.
2.  Select a **Mode**:
    *   **Soft**: Gentle knee and smooth response.
    *   **Even**: Even-harmonic bias with rounding.
    *   **Clip**: Controlled hard-clip with cubic compression.
    *   **Warm**: Warm response with quadratic component.
    *   **Odd**: Odd-harmonic emphasis with subtle low-frequency conditioning.
3.  Adjust **Core Controls**:
    *   **Drive**: Saturation amount (0–10).
    *   **Tone (Tilt)**: Balance lows/highs (-1 to +1).
    *   **Mix**: Parallel blend (0–100%).
    *   **Output**: Final level (-24 to +24 dB).
4.  **Fine-tune**:
    *   **Punish**: +20 dB boost before waveshaper.
    *   **Bump**: Emphasize low-cut region.
    *   **Oversampling**: Enable for high drive settings to reduce aliasing.

## Troubleshooting

*   **No loudness change with Auto-Gain**: Auto-Gain needs a signal to detect RMS. It estimates weighted RMS on inputs/outputs and applies smoothed correction.
*   **Clicks when changing modes**: The script uses crossfades to prevent this, but extreme CPU load might cause dropouts.
*   **High CPU usage**: "HQ" Oversampling is intensive; use standard oversampling or disable it for real-time monitoring if needed.

## Changelog

### v1.1.0

*   Bug fixes and improvements.
*   Oversampling options: 1x, 2x, 4x with FIR anti-aliasing (HQ 17-tap).

### v1.0.0
* Initial release.
* Current release with scalable UI and 5 saturation modes.

## Support

*   **Website**: [www.floratarantino.com](https://www.floratarantino.com)
*   **Instagram**: [@fdlightproject](https://www.instagram.com/fdlightproject/)

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.
See the `LICENSE` file in the main repository for details.
