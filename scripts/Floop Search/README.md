# Floop Search

**Track Navigation System for REAPER.**

*   **Author**: © 2026 Flora Tarantino (Floop's Reaper Script)      
*   **Version**: 1.0
*   **Website**: [www.floratarantino.com](https://www.floratarantino.com)

## Description

**Floop Search** is a Lua script for REAPER that brings a search bar for rapid track navigation, selection, and previewing.
It features a sleek, floating, animated interface that stays out of your way until you need it.
Designed for speed and keyboard-centric workflows, it allows you to find any track by name or track number without touching the mouse.

## Key Features

*   **Modern Search UI**: Floating search bar that animates and expands to show results.
*   **Fast Search**: Instantly filter tracks by Name or Track Number.
*   **Keyboard Navigation**: Full control using Arrow keys, Enter, and Esc.
*   **Preview Solo**: Temporarily solo tracks while navigating results to quickly audition content (Hold ALT).
*   **State Restoration**: Automatically restores original track selection, solo states, and colors upon exit.
*   **Visual Feedback**: Matches highlight colors (red) for clear visibility during navigation.
*   **Auto-Focus**: Smart window focus handling for immediate typing.

## Requirements

*   **REAPER v7.5x** or later.
*   **ReaImGui**: Installed via ReaPack.

## Compatibility

*   **Windows**: Fully supported (Tested).
*   **macOS**: Fully supported (Standard ReaImGui/Lua).
*   **Linux**: Fully supported (Standard ReaImGui/Lua).

> **Note**: This script relies on **ReaImGui**, which is cross-platform. As long as ReaImGui is installed and working on your system, this script will function correctly.

## Installation

1.  **Install ReaImGui**:
    *   Go to **Extensions > ReaPack > Browse Packages**.
    *   Search for and install `ReaImGui`.
    *   Restart REAPER.
2.  **Install the Script**:
    *   Copy `Floop Search.lua` to your REAPER Scripts folder.
3.  **Load the Action**:
    *   Open Actions List (`?`).
    *   Load `Floop Search.lua`.
    *   (Recommended) Assign a **Global + Text** shortcut (e.g., `Ctrl+Space`) to launch/toggle while typing.

## Usage

1.  **Launch** the script.
2.  **Type** to search:
    *   Part of a name (e.g., "Voc", "Kick").
    *   Track number (e.g., "12").
3.  **Navigate**:
    *   **UP / DOWN**: Move through results.
    *   **ALT (Hold)**: Preview Solo the highlighted track.
4.  **Confirm**:
    *   **ENTER**: Select track, scroll to view, expand parents, and close script.
5.  **Cancel**:
    *   **ESC**: Close without changes (restores previous state).

## Troubleshooting

*   **"ReaImGui API not found"**: Install ReaImGui via ReaPack.
*   **Shortcut not working**: Ensure Scope is "Global + Text".

## Changelog

### v1.0 (2026-01-06)
*   Initial release.
*   Basic track search functionality.
*   Track selection and previewing.
*   Animated floating UI.
*   Debounced search for smooth performance.


## Support

*   **Website**: [www.floratarantino.com](https://www.floratarantino.com)
*   **Instagram**: [@fdlightproject](https://www.instagram.com/fdlightproject/)

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.
