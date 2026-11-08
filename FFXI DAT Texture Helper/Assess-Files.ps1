param([string]$ReportPath,[string]$CustomRoot,[string]$OriginalRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UI-Common.ps1')
. (Join-Path $PSScriptRoot 'Output-Management.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
if(-not ('DatTexturePatcherV1' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Patcher.cs')}
function Pick-File([string]$Title,[string]$Filter) {
 $d=New-Object System.Windows.Forms.OpenFileDialog
 $d.Title=$Title;$d.Filter=$Filter
 try {if($d.ShowDialog() -eq 'OK'){return $d.FileName};return $null} finally {$d.Dispose()}
}
function Pick-Folder([string]$Title){return (Select-ToolFolder $Title)}
function Read-Report([string]$ZipPath,[string]$Destination) {
 New-Item -ItemType Directory -Path $Destination | Out-Null
 $zip=[IO.Compression.ZipFile]::OpenRead($ZipPath)
 try {
  foreach($name in @('Custom-comparison.csv','Custom-textures.csv','Texture-ID-summary.csv','Summary.txt')) {
   $entries=@($zip.Entries | Where-Object {($_.FullName -replace '\\','/').Split('/')[-1] -ceq $name})
   if($entries.Count -ne 1){throw "Expected exactly one $name in a v2 comparison ZIP."}
   [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0],(Join-Path $Destination $name))
  }
 } finally {$zip.Dispose()}
}
. (Join-Path $PSScriptRoot 'Assessment-Window.ps1')
$work=$null;$patched=$null;$lease=$null
try {
 $lease=Enter-ToolSession
 $report=$ReportPath
 if(-not $report){$report=Pick-File 'Select the DAT-Comparison ZIP from the scanner' 'Comparison report (*.zip)|*.zip'}
 if(-not $report){return}
 Assert-ExternalInput $report
 $tempRoot=Get-ToolWork
 $work=Join-Path $tempRoot 'Assessment'
 New-Item -ItemType Directory -Path $work | Out-Null
 $reportDir=Join-Path $work 'report';Read-Report $report $reportDir
 $rows=@(Import-Csv -LiteralPath (Join-Path $reportDir 'Custom-comparison.csv'))
 $inventory=@(Import-Csv -LiteralPath (Join-Path $reportDir 'Custom-textures.csv'))
 $summary=@(Import-Csv -LiteralPath (Join-Path $reportDir 'Texture-ID-summary.csv'))
 if($rows.Count -eq 0 -or $summary.Count -eq 0){throw 'Report has no texture entries.'}
 $inventoryByFile=@{};foreach($group in ($inventory | Group-Object File)){$inventoryByFile[$group.Name]=@($group.Group)}
 $candidateRows=@($rows | Where-Object {
  $_.CustomFileComplete -eq 'True' -and (
   ($_.EightSpaceSuffix -eq 'True' -and $_.AbsentFromParsedOriginalCollection -eq 'True') -or
   ($_.NewNameInThisReplacement -eq 'Yes' -and ([int]$_.OtherOriginalIDsWithSameSuffix -gt 0 -or [int]$_.OtherEffectiveIDsWithSameSuffix -gt 0)) -or
   ($_.AbsentFromParsedOriginalCollection -eq 'True' -and [int]$_.OtherEffectiveIDsWithSameSuffix -gt 0)
  )
 })
 $inputRoot=$CustomRoot
 if(-not $inputRoot){
 $choice=[Windows.Forms.MessageBox]::Show('Are the custom DAT files you want to check in a ZIP? Yes = choose a ZIP. No = choose a folder containing ROM.','Supply custom DATs','YesNoCancel','Question')
 if($choice -eq 'Cancel'){return}
 if($choice -eq 'Yes') {
  $source=Pick-File 'Select your custom DAT ZIP, preserving ROM paths' 'DAT archive (*.zip)|*.zip'
  if(-not $source){return}
  Assert-ExternalInput $source
  $inputRoot=Join-Path $work 'supplied';New-Item -ItemType Directory -Path $inputRoot | Out-Null
  $zip=[IO.Compression.ZipFile]::OpenRead($source)
  try {
   $seen=@{}
   foreach($entry in $zip.Entries){
    $path=$entry.FullName -replace '\\','/'
    if($path -match '(?i)(?:^|/)(ROM(?:[0-9]+)?/[0-9]+/[0-9]+\.dat)$'){
     $rel=$Matches[1];if($seen.ContainsKey($rel)){throw "Duplicate supplied path: $rel"};$seen[$rel]=$true
     $dest=Join-Path $inputRoot $rel;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))
     [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$dest)
    }
   }
   if($seen.Count -eq 0){throw 'No DATs at ROM/number/number.DAT paths found in ZIP.'}
  } finally {$zip.Dispose()}
 } else {
  $inputRoot=Pick-Folder 'Choose your CUSTOM DAT pack folder containing ROM; not the original game installation'
  if(-not $inputRoot){return}
  Assert-ExternalInput $inputRoot
 }
 } else {
  Assert-ExternalInput $inputRoot
  if(-not (Test-Path -LiteralPath $inputRoot -PathType Container)){throw 'The scanned custom folder is no longer available.'}
 }
 $recommended=New-Object 'System.Collections.Generic.List[object]'
 $optional=New-Object 'System.Collections.Generic.List[object]'
 $primary=New-Object 'System.Collections.Generic.List[object]'
 $allRows=New-Object 'System.Collections.Generic.List[object]'
 $missing=New-Object 'System.Collections.Generic.List[string]'
 $blocked=0
 $decoderPrompted=$false
 [DatTexturePatcherV1]::ConfigureGame($null)
 if($OriginalRoot){
  $decoderPrompted=$true
  try{[DatTexturePatcherV1]::ConfigureGame($OriginalRoot)}catch{Write-Warning ('Encoded mesh decoding unavailable: '+$_.Exception.Message)}
 }
 foreach($group in @($candidateRows | Group-Object File | Sort-Object Name)){
  $path=$group.Name
  if($path -notmatch '(?i)^ROM(?:[0-9]+)?/[0-9]+/[0-9]+\.dat$'){throw 'Unexpected report path.'}
  $present=Test-Path -LiteralPath (Join-Path $inputRoot $path) -PathType Leaf
  $definitions=New-Object 'System.Collections.Generic.List[DatDefinition]'
  foreach($row in $inventoryByFile[$path]){
   $d=New-Object DatDefinition;$d.File=$row.File;$d.IDHex=$row.IDHex
   $d.Offset=[Convert]::ToInt64($row.ChunkOffset.Substring(2),16);$d.ChunkBytes=[long]$row.ChunkBytes;$d.Format=[int]$row.FormatByte;$definitions.Add($d)
  }
  $inspections=@{}
  if($present){
   Write-Host "Checking naming pattern and references: $($path.Replace('/','\'))"
   $checked=@([DatTexturePatcherV1]::InspectFile($inputRoot,$path,$definitions.ToArray(),[string[]]@($group.Group.IDHex | Sort-Object -Unique)))
   if(-not $decoderPrompted -and @($checked | Where-Object {$_.Reason -like 'Choose the original game folder*'}).Count -gt 0){
    $decoderPrompted=$true
    $OriginalRoot=Pick-Folder 'Choose the original FFXI game folder containing FFXiMain.dll to check encoded meshes (Cancel leaves these rows unavailable)'
    if($OriginalRoot){
     try{[DatTexturePatcherV1]::ConfigureGame($OriginalRoot)}catch{Write-Warning ('Encoded mesh decoding unavailable: '+$_.Exception.Message)}
     $checked=@([DatTexturePatcherV1]::InspectFile($inputRoot,$path,$definitions.ToArray(),[string[]]@($group.Group.IDHex | Sort-Object -Unique)))
    }
   }
   foreach($item in $checked){$inspections[$item.IDHex]=$item}
  }else{$missing.Add($path)}
  foreach($r in @($group.Group | Group-Object IDHex | ForEach-Object {$_.Group[0]})){
   # Recommendation is based on the name and reference structure, never a list
   # of known names, paths, source hashes, or texture compression sizes.
   $newName=$r.AbsentFromParsedOriginalCollection -eq 'True'
   $blank=$r.EightSpaceSuffix -eq 'True'
   $suffixConflict=([int]$r.OtherOriginalIDsWithSameSuffix -gt 0 -or [int]$r.OtherEffectiveIDsWithSameSuffix -gt 0)
   $pattern=$newName -and ($blank -or $suffixConflict)
   $check=$inspections[$r.IDHex]
   $canPatch=$present -and $check -and $check.CanPatch
   $reason=if($blank){'Custom texture ID ends with eight spaces'}else{'Custom texture ID shares its suffix with a different ID'}
   $friendly=$path.Replace('/','\')
   $entry=[pscustomobject]@{File=$path;IDHex=$r.IDHex;Texture=$r.TextureID.TrimEnd();Reason=$reason;Status='';CanSelect=[bool]$canPatch;ExpectedSha256=$(if($check){$check.Sha256}else{$null})}
   if($pattern){
    if(-not $present){$status='Not supplied';$action='Supply this DAT to validate and create a copy'}
    elseif(-not $canPatch){$status='Needs investigation';$action=$check.Reason;$blocked++}
    else{
     $status='Recommended naming-pattern repair';$action='Local definition and model references validated; create a copy'
     $recommended.Add($entry)
    }
    $primary.Add([pscustomobject]@{Dat=$friendly;Texture=$entry.Texture;Status=$status;Action=$action})
   }else{
    $status=if(-not $present){'Not supplied; provide this DAT first'}elseif(-not $canPatch){$check.Reason}else{'Advanced choice; overlap may be intentional'}
    $optional.Add($entry)
   }
   $entry.Status=$status
   $allRows.Add([pscustomobject]@{Dat=$friendly;Texture=$entry.Texture;IDHex=$r.IDHex;Category=$(if($pattern){'Recommended pattern'}else{'Advanced optional'});Result=$status;Reason=$reason;References=$(if($check){$check.References}else{0})})
  }
 }
 $ready=@($recommended.ToArray().File | Sort-Object -Unique).Count
 $assessmentStage=Join-Path $work 'Assessment-results';New-Item -ItemType Directory -Path $assessmentStage | Out-Null
 $allRows.ToArray() | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $assessmentStage 'Assessment.csv')
 $optional.ToArray() | Select-Object File,Texture,IDHex,Reason,Status,CanSelect | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $assessmentStage 'Optional-matches.csv')
 [IO.File]::WriteAllLines((Join-Path $assessmentStage 'Not-supplied.txt'),$missing.ToArray(),[Text.Encoding]::UTF8)
 $scanSummary=Get-Content -Raw -LiteralPath (Join-Path $reportDir 'Summary.txt')
 @"
FFXI DAT Texture Helper 2.4
Files eligible for recommended naming-pattern repair: $ready
Recommended pattern rows blocked by unsupported or mismatched references: $blocked

Recommendation uses new custom IDs with blank or conflicting suffixes, then
validates the supported local definition and all observed internal references.
No exact source-file hash, file path, texture name, or compression version is
used to decide whether a naming pattern qualifies. Hashes detect a file changing
during processing and verify outputs and reversible edits only.

Recommended is a supported naming-risk mitigation, not proof that each entry
caused a crash. Original/custom scan coverage can be incomplete. Other overlaps
may be intentional and stay in Advanced, unchecked. Unrecognized structures are
blocked. External references, runtime resource flags and lifetimes are not fully
modeled, so this tool does not certify every DAT or every kind of crash.

SOURCE SCAN COVERAGE
$scanSummary
"@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $assessmentStage 'Assessment.txt')
 $assessmentSaved=Join-Path (Join-Path $PSScriptRoot 'Reports') 'Assessment'
 Publish-ManagedDirectory $assessmentStage $assessmentSaved 'assessment'
 $decision=Show-Assessment $primary.ToArray() $optional.ToArray() $ready 0 $assessmentSaved $inputRoot $OriginalRoot
 if(-not $decision.Create){Write-Host "Latest assessment: $assessmentSaved";return}
 $selected=@($decision.Optional)
 $requests=New-Object 'System.Collections.Generic.List[DatOptionalSelection]'
 foreach($entry in $recommended){
  $r=New-Object DatOptionalSelection;$r.File=$entry.File;$r.IDHex=$entry.IDHex;$r.ExpectedSha256=$entry.ExpectedSha256;$r.Advanced=$false;$requests.Add($r)
 }
 foreach($entry in $selected){
  $r=New-Object DatOptionalSelection;$r.File=$entry.File;$r.IDHex=$entry.IDHex;$r.ExpectedSha256=$entry.ExpectedSha256;$r.Advanced=$true;$requests.Add($r)
 }
 if($requests.Count -eq 0){throw 'No supported rows selected.'}
 $definitions=New-Object 'System.Collections.Generic.List[DatDefinition]'
 foreach($row in $inventory){
  $d=New-Object DatDefinition;$d.File=$row.File;$d.IDHex=$row.IDHex
  $d.Offset=[Convert]::ToInt64($row.ChunkOffset.Substring(2),16);$d.ChunkBytes=[long]$row.ChunkBytes;$d.Format=[int]$row.FormatByte;$definitions.Add($d)
 }
 $patched=Join-Path $work 'Patched'
 $result=[DatTexturePatcherV1]::PatchSelections($inputRoot,$patched,$definitions.ToArray(),$requests.ToArray(),[string[]]$summary.IDHex)
 $manifest=[ordered]@{Tool='FFXI DAT Texture Tool';Version=2;RecommendationRule='Custom name plus supported reference structure';OptionalRowsSelected=$selected.Count;ReportSha256=(Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash;Files=$result.Files.ToArray()}
 $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $patched 'changes.json') -Encoding UTF8
 $selected | Select-Object File,Texture,IDHex | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $patched 'Selected-optional.csv')
 foreach($name in @('Assessment.csv','Assessment.txt','Not-supplied.txt')){Copy-Item -LiteralPath (Join-Path $assessmentSaved $name) -Destination $patched}
 @'
Back up your custom DATs and close all FFXI/POL instances. Copy the ROM folders
into the SAME XIPivot pack, never the original game installation. Start fresh
instances and test appearance and normal play.

Recommended entries passed the naming-pattern and supported-reference checks;
they are not proven individual crash causes. IncludesOptional=true identifies
files also changed by explicit advanced choices. Only recorded 16-byte IDs were
edited. Textures, geometry and animations were not re-encoded. Keep changes.json
for restoring exact original copies. Installed files are never overwritten by
the helper. Unselected or unsupported entries remain unresolved.
'@ | Set-Content -LiteralPath (Join-Path $patched 'README.txt') -Encoding UTF8
 $output=Join-Path $work 'Patched-DATs.zip'
 [IO.Compression.ZipFile]::CreateFromDirectory($patched,$output,[IO.Compression.CompressionLevel]::Optimal,$false)
 Move-Item -LiteralPath $output -Destination (Join-Path $patched 'Patched-DATs.zip')
 Publish-RootPatched $patched
 $output=Join-Path $PSScriptRoot 'Patched-DATs.zip'
 Write-Host "Patched ROM folders are beside Start.cmd. ZIP: $output" -ForegroundColor Green
 [void][Windows.Forms.MessageBox]::Show("Created $($result.Files.Count) patched copies.`r`nROM folders are beside Start.cmd.`r`nInstalled DATs were not changed.",'Finished','OK','Information')
} catch {
 Write-Host "Stopped without changing source DATs: $($_.Exception.Message)" -ForegroundColor Red
 [void][Windows.Forms.MessageBox]::Show("No source DATs changed.`r`n$($_.Exception.Message)",'Operation stopped','OK','Warning')
 exit 1
} finally {if($lease){try{Clear-ToolWork}finally{$lease.Dispose()}}}
