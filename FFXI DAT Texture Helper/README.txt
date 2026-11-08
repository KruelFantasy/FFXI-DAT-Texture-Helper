FFXI DAT TEXTURE HELPER 2.4

WHAT DOES IT DO?
It compares the original Final Fantasy XI DAT files with the custom DAT files
in your XIPivot folder. It looks for texture-name patterns that can let the
game select a texture belonging to the wrong model.

WHY FIX THOSE NAMES?
An unintended texture match can leave a model using a texture after the game
has unloaded it. This can cause incorrect rendering or a crash. Renaming the
texture and its matching model references removes the detected naming overlap.

It is not a fix for every FFXI crash or for general memory growth. Some DAT
formats and external references cannot be fully checked by this tool.

HOW TO USE IT
1. Double-click Start.cmd.
2. Select your original FF11 folder containing ROM, ROM2, etc.
3. Select your custom XIPivot DAT folder containing its ROM folders.
4. Let the tool scan and compare. It opens the DAT list automatically, using
   the folders you just selected; you do not need to select them again.
5. Click Create recommended copies.
6. Back up your custom DATs.
7. Copy the generated ROM folders (beside Start.cmd) into your XIPivot DAT
   folder, merge the folders, and overwrite the corresponding custom DATs.
8. Reload XIPivot in game and zone, or load the game if you haven't started it.

The helper creates copies. It does not overwrite your installed files for you.
Never copy the output into the original game installation.

RECOMMENDED VERSUS OPTIONAL
Recommended entries have a supported custom texture-name conflict pattern and
validated local model references. A particular file version or hash is NOT
required. Different texture compression or unrelated model changes do not by
themselves make an entry optional. The current file must match its scan report.
An unsupported reference/layout is shown as Needs investigation, not patched.

RECOMMENDED: Patch only the recommended files.
Advanced: Optional texture matches is hidden initially and unchecked. These are
broader overlaps that can be intentional. Only choose them if you understand
why the specific texture needs changing. Otherwise, leave them unchecked.
Each entry shows its DAT path, for example ROM\163\24.DAT.

WHY SOME OPTIONAL BOXES ARE DISABLED
The scanner can find names in more DAT formats than the patcher understands.
Patching now supports the validated character-model, particle, sprite and
encoded mesh layouts found in the supplied samples. Repeated local definitions
of one ID are renamed together, preserving their shared name. Unknown layouts
still remain disabled; this is not evidence that those textures are faulty.
For encoded meshes the tool reads decoding tables from your FFXiMain.dll as
DATA ONLY. It never loads or edits the DLL. The original folder selected during
scanning is reused. With an older report, it may ask for that folder once when
encoded references need checking. Unrecognized tables leave those rows disabled.

To help investigate them, click Export unsupported samples in the assessment
window. It collects one representative custom DAT per reported reason (up to
three distinct DATs), plus original counterparts when the original scan folder
is known. Send Reports/Unsupported/Unsupported-samples.zip. No DATs are patched
and nothing is uploaded automatically. You can load your existing report and
custom folder; another full scan is not needed just to export these samples.

Column header heights now recalculate for font size, DPI and column width. You
should not need to drag them taller after every restart.

WHAT CHANGES INSIDE A FIXED DAT?
Only the selected 16-byte texture names and their supported matching model
references. Texture pixels, compression, geometry and animations are not
re-encoded. The tool checks that all other bytes remain unchanged.
Hashes are used to detect files changing during processing and verify output
and undo; they do not decide which naming patterns are recommended.

WHERE ARE THE FILES?
ROM, ROM2, etc.       Fixed copies directly beside Start.cmd.
Patched-DATs.zip      The same copies packaged with details and undo information.
changes.json         Information needed to recreate the originals.
Previous-output      One previous patched output, replaced on the next success.
Reports              The latest scan and assessment; these locations are reused.
Restored-originals   Recreated originals, if you use Restore.

No growing collection of dated assessment folders is created. Temporary files
are cleaned. Manually edited/unrecognized generated output is preserved rather
than silently deleted. Old folders from earlier tool versions are not removed.

HOW TO UNDO
Keep your own backup. Alternatively choose Restore and select changes.json
beside the matching fixed ROM folders. The tool verifies them and creates
original copies under Restored-originals. Install those copies manually with
the game closed. It never overwrites your installed files automatically.

DISPLAY AND FOLDER SELECTION
Windows sizing is based on the current display scale and usable screen area.
Text wraps; small screens can scroll the main instructions. Folder selection
is centered and resizable, with a path field and buttons outside the scrolling
folder tree. You can paste a full path or browse using Desktop/Drives/Up.
Designed for 100%, 125%, 150%, 175% and 200% scaling.

REQUIREMENTS
Windows 11 with built-in Windows PowerShell/.NET. No Python, Visual Studio
installation, or administrator rights needed. No network calls or uploads.

For scan coverage and exact technical limits see TECHNICAL-NOTES.txt.
For what was actually tested see VALIDATION.txt.
