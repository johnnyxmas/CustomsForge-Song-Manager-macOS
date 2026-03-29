<a href="https://customsforge.com/">
    <img src="https://i.imgur.com/CeqvXYs.png" alt="CF logo" title="CustomsForge" align="right" height="60" />
</a>

CustomsForge Song Manager
======================

A desktop application for managing custom DLC songs in Rocksmith 2014. Built with C#/.NET Framework 4.8, WinForms, x86.

> **Note:** The [original repository](https://github.com/CustomsForge/CustomsForge-Song-Manager) is archived. This fork includes macOS support and Wine compatibility fixes.

Downloads
======================

Pre-built releases are available on the [Releases](https://github.com/johnnyxmas/CustomsForge-Song-Manager-macOS/releases) page:

* **Windows** — `CFSMSetup.exe` (Inno Setup installer)
* **macOS** — `CustomsForge.Song.Manager.app.zip` (Wine Crossover wrapper)

You can also download the latest Windows installer from [CustomsForge](https://ignition4.customsforge.com/tools/cfsm#downloads).

macOS Build Instructions
======================

The macOS version runs the Windows application inside Wine Crossover, packaged as a native `.app` bundle.

### Prerequisites

* macOS 11+ (Apple Silicon or Intel)
* [Homebrew](https://brew.sh)
* Rosetta 2 (Apple Silicon Macs — installed automatically by the script)

### Building

1. Download `CFSMSetup.exe` from [CustomsForge](https://ignition4.customsforge.com/tools/cfsm#downloads) or from this repo's [Releases](https://github.com/johnnyxmas/CustomsForge-Song-Manager-macOS/releases)

2. Run the build script:
   ```bash
   ./build-macos.sh /path/to/CFSMSetup.exe
   ```

3. The script will automatically:
   * Install Wine Crossover, winetricks, innoextract, and Mono via Homebrew
   * Create a Wine prefix at `~/.wine-cfsm` with .NET Framework 4.8
   * Extract the installer and install CFSM into the prefix
   * Patch `RocksmithToolkitLib.dll` for Wine compatibility
   * Create `CustomsForge Song Manager.app` in the current directory

4. Launch by double-clicking the `.app` or:
   ```bash
   open "CustomsForge Song Manager.app"
   ```

### Notes

* The first run takes several minutes due to .NET 4.8 installation (~1.5GB download)
* Subsequent runs of the build script are fast (skips existing Wine prefix)
* Wine Crossover must remain installed for the `.app` to work
* The app auto-detects Mac mode when running under Wine

Windows Build Instructions
======================

* Visual Studio 2010+ (VS2019 recommended), .NET Framework 4.0+
* Open `CustomsForgeSongManager.sln` and build with configuration `Release|x86`
* Maintain backward compatibility with VS2010 and .NET 4.0

Developers
======================
* Project Overview: Unleashed2k
* Developer: LovroM8


Developers (Hiatus or non-active)
======================
* Lead Developer: Cozy1
* Developer: Darjuz
* Developer: DreddFoxx
* Developer: Zerkz
* Associate Developer: ZagatoZee
