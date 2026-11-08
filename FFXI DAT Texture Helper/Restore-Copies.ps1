$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UI-Common.ps1')
. (Join-Path $PSScriptRoot 'Output-Management.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.IO.Compression.FileSystem
if(-not ('DatTexturePatcherV1' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Patcher.cs')}
$lease=$null
try {
 $lease=Enter-ToolSession
 $dialog=New-Object Windows.Forms.OpenFileDialog
 $dialog.Title='Select changes.json from an extracted patched DAT package';$dialog.Filter='Fix manifest (changes.json)|changes.json'
 if($dialog.ShowDialog() -ne 'OK'){$dialog.Dispose();return}
 $manifestPath=$dialog.FileName;$dialog.Dispose()
 Assert-ExternalInput $manifestPath
 $data=Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
 if($data.Tool -ne 'FFXI DAT Texture Tool' -or $data.Version -notin @(1,2)){throw 'Not a supported fix manifest.'}
 $root=Split-Path -Parent $manifestPath
 $records=New-Object 'System.Collections.Generic.List[DatPatchRecord]'
 foreach($file in $data.Files){
  $r=New-Object DatPatchRecord;$r.File=$file.File;$r.OriginalSha256=$file.OriginalSha256;$r.PatchedSha256=$file.PatchedSha256;$r.FileBytes=$file.FileBytes
  foreach($change in $file.Changes){
   $c=New-Object DatNameChange;$c.OldHex=$change.OldHex;$c.NewHex=$change.NewHex
   foreach($p in $change.DefinitionOffsets){$c.DefinitionOffsets.Add([int]$p)}
   foreach($p in $change.ReferenceOffsets){$c.ReferenceOffsets.Add([int]$p)}
   foreach($field in $change.EncodedReferences){
    $f=New-Object DatEncodedField;$f.BeforeHex=$field.BeforeHex;$f.AfterHex=$field.AfterHex
    foreach($offset in $field.SourceOffsets){$f.SourceOffsets.Add([int]$offset)}
    $c.EncodedReferences.Add($f)
   }
   $r.Changes.Add($c)
  };$records.Add($r)
 }
 if($records.Count -eq 0){throw 'No files in manifest.'}
 $work=Get-ToolWork
 $restored=Join-Path $work 'Restored'
 $restoreInput=Join-Path $work 'Restore-input'
 foreach($r in $records){
  if($r.File -notmatch '(?i)^ROM(?:[0-9]+)?/[0-9]+/[0-9]+\.dat$'){throw 'Unexpected manifest DAT path.'}
  $dest=Join-Path $restoreInput $r.File
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
  Copy-Item -LiteralPath (Join-Path $root $r.File) -Destination $dest
 }
 [DatTexturePatcherV1]::Restore($restoreInput,$restored,$records.ToArray())
 [IO.Compression.ZipFile]::CreateFromDirectory($restored,(Join-Path $work 'Original-DATs.zip'),[IO.Compression.CompressionLevel]::Optimal,$false)
 Move-Item -LiteralPath (Join-Path $work 'Original-DATs.zip') -Destination (Join-Path $restored 'Original-DATs.zip')
 $saved=Join-Path $PSScriptRoot 'Restored-originals'
 Publish-ManagedDirectory $restored $saved 'restored'
 Write-Host "`nRestored original copies: $saved`nNo installed DATs were overwritten." -ForegroundColor Green
} catch {
 Write-Host "Restore stopped: $($_.Exception.Message)" -ForegroundColor Red
 exit 1
} finally {if($lease){try{Clear-ToolWork}finally{$lease.Dispose()}}}
