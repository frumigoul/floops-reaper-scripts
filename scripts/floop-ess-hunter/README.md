# Floop Ess Hunter

**Taming hiss in a single pass.**



## Overview

**Floop Ess Hunter** analyzes vocal items to detect sibilant sounds ("s", "sh", "ch") and automatically reduces their level by writing volume envelope points only on detected segments. The analysis is precise and configurable, aiming to preserve natural dynamics in speech and singing.

## Screenshot

<p align="center"> 
 <br> 
 <a href="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-ess-hunter-v1.1.0.png" target="_blank"> 
   <img src="https://raw.githubusercontent.com/floop-s/floops-reaper-scripts/main/assets/floop-ess-hunter-v1.1.0.png" width="450" style="border: 1px solid #27a086ff;" alt="Click to zoom in"> 
 </a> 
 <br> 
 </p>

## Key Features

*   **Multi-band Analysis**: Focuses on the 3.5–9.5 kHz range, plus ZCR (Zero Crossing Rate) detection.
*   **Adaptive Threshold**: Uses band/wide spectral ratio.
*   **Optimized Performance**: Median calculation via Quickselect (O(n)).
*   **Precise Editing**: Writes envelope points only on sibilant segments.
*   **Non-Destructive**: Supports Pre-FX Volume envelope and non-cumulative segment replacement.
*   **Safe Workflow**: Automatic Undo blocks for apply/clear operations.
*   **Visual Preview**: Zoom/pan, ratio overlay, and draggable segment edges with optional hop snapping.
*   **Presets**: Built-in presets for Speech, Soft Singing, Aggressive Singing, plus user presets.

## Requirements

*   **REAPER v7.48** or later.
*   **ReaImGui**: "ReaScript binding for Dear ImGui" installed via ReaPack.

## Installation

The easiest way to install and keep the script updated is via **ReaPack**.

### Method 1: ReaPack (Recommended)

1.  **Install Prerequisites**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for and install:
        *   `ReaScript binding for Dear ImGui`
        *   `SWS/S&M Extension`
    *   **Restart REAPER**.

2.  **Add the Repository**:
    *   Open **Extensions > ReaPack > Import Repositories...**
    *   Copy and paste this URL:
        https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
    *   Click **OK**.

3.  **Install the Script**:
    *   Open **Extensions > ReaPack > Browse Packages**.
    *   Search for `Floop Ess Hunter`.
    *   Right-click > **Install**.
    *   Click **Apply**.

### Method 2: Manual Installation

1.  **Install ReaImGui**:
    *   Go to **Extensions > ReaPack > Browse Packages**.
    *   Search for and install `ReaImGui: ReaScript binding for Dear ImGui`.
    *   Restart REAPER.
2.  **Install the Script**:
    *   Copy the `Floop Ess Hunter` folder (or just the `.lua` file) to your REAPER Scripts folder.
    *   Path: `REAPER > Options > Show REAPER resource path > Scripts`.
3.  **Load the Action**:
    *   Open the **Actions List** (`?`).
    *   Click **New Action > Load ReaScript...**.
    *   Select `Floop Ess Hunter.lua`.

## Quick Start

1.  Select one or more **vocal items** in your project.
2.  Run **Floop Ess Hunter** from the Actions List.
3.  Click **Analyze and apply** to analyze and write envelope points.
4.  Adjust parameters under **Advanced Setting** if needed.
5.  Use **Clear segments on selection** to remove segments.

> **Tip**: You can target the **Pre-FX Volume** envelope (recommended) or the standard **Track Volume** envelope. The script ensures the chosen envelope is visible.

## Parameters (Fine Tuning)

### Analysis
*   **Min Hz / Max Hz**: Frequency range of interest (default 3500–9500 Hz).
*   **Step Hz**: Spacing between band centers (default 1000 Hz).
*   **Q**: Filter quality factor (default 4.0).

### Detection
*   **Window / Hop**: Analysis window and hop size (default 12 / 6 ms).
*   **Min Level (dB)**: Minimum level to consider content (default −45 dB).
*   **ZCR Threshold**: Zero-crossing threshold for fricatives (default 0.12).
*   **Delta IN / OUT**: Hysteresis for on/off (default 0.08 / 0.05).

### Segments
*   **Min Segment**: Minimum segment duration (default 25 ms).
*   **Max Gap**: Fills micro-pauses up to this length (default 18 ms).
*   **Pre / Post Ramp**: Fade-in/out edges (default 8 / 12 ms).
*   **Volume reduction**: Attenuation applied to segments (default 4.0 dB).
*   **Use Pre-FX Volume**: Writes to Pre-FX Volume (default: on).
*   **Replace segments**: Rewrites segments without accumulating edits.

## Troubleshooting

*   **"ReaImGui not found"**: Install via ReaPack and restart REAPER.
*   **Envelope not visible**: The script tries to show it, but you can manually check Track Envelopes.
*   **No segments detected**:
    *   Raise **Min level** (less negative).
    *   Adjust frequency range.
    *   Lower **ZCR Threshold**.
    *   Reduce **Min Segment**.
*   **Performance**: For very long items, analysis might take time. The algorithm is optimized but processes a lot of data.

## Changelog

### v1.1.1 (2026-02-15)
*   **Stability**: Improved envelope visibility when applying from preview and during Live Edit.
*   **Control**: Segment gain handles now support live update when Live Edit is enabled.
*   **Analysis**: Median ratio clamping hardened for extremely sibilant or short clips.

### v1.1.0 (2026-01-08)
*   **New Feature**: Support for split clips and items not starting at timeline zero.
*   **New Feature**: Interactive handles for manual segment resizing.
*   **New Feature**: Per-segment volume adjustment via vertical drag (0–24 dB reduction).
*   **UI**: Improved waveform display alignment for offset items.
*   **Fix**: "Analyze and Apply" logic aligned with take-relative time for accurate envelope placement.
*   **Fix**: Resolved segment edge resizing conflicts with volume drag.

### v1.0.0 (2025-10-31)
*   Initial public release.
*   Sibilance detection pipeline with envelope writing.
*   Quickselect O(n) optimization.
*   Timing correction for playback rates.
*   Undo blocks integration.

## Author

Developed by **Flora Tarantino**  
Project home: [https://www.floratarantino.com/floop-reaper-scripts/](https://www.floratarantino.com/floop-reaper-scripts/)

## License

Licensed under the **GNU General Public License v3.0 (GPL-3.0)**  
See the `LICENSE.txt` file in the main repository for details.
