# Floop's REAPER Scripts

This repository contains a collection of JSFX and Lua scripts for **REAPER**, focused on audio processing and workflow enhancement.

All tools are released as free and open-source software.

---

## Contents

All scripts are located in the `floops-tool/` directory.

Each tool is contained in its own folder and typically includes:
- the script file (`.jsfx` or `.lua`)
- a dedicated `README.md` with usage and details

---

## Installation

### Automatic Installation (Recommended via ReaPack)

1. Open **ReaPack** inside REAPER.
2. Go to **Extensions > ReaPack > Import Repositories...**
3. Paste the following URL:
   ```
   https://github.com/floop-s/floops-reaper-scripts/raw/main/index.xml
   ```
4. Double-click the newly added repository to browse and install the scripts.

### Manual Installation

1. Download the repository  
   - Clone the repository or download it as a ZIP file.

2. Locate the REAPER resource path  
   - Open REAPER  
   - Go to **Options → Show REAPER resource path in explorer/finder**

3. Install the scripts  
   - **Lua scripts**:  
     Copy the `.lua` files into the `Scripts` folder inside the REAPER resource path.
   - **JSFX scripts**:  
     Copy the `.jsfx` files into the `Effects` folder inside the REAPER resource path.

4. Refresh REAPER  
   - For Lua scripts:  
     Open the **Actions List** (press `?`) and use  
     **New Action → Load ReaScript...**
   - For JSFX:  
     Open the FX Browser and press **F5** to rescan effects.

Refer to each tool’s README for specific instructions.

---

## Compatibility

- **Operating System:**  
  Primarily developed and tested on **Windows**.

- **macOS / Linux:**  
  Not personally tested. Feedback is welcome, but compatibility and stability are not guaranteed.

---

## Support and Expectations

These scripts are provided **as-is**.

- No guaranteed support is provided.
- Issues and feedback are welcome, but responses may be limited.
- Scripts are tested only on systems I have direct access to.

This project is maintained in my spare time.

---

## License

All scripts in this repository are released under the **GNU General Public License v3.0**.

See the `LICENSE` file for full license details.

