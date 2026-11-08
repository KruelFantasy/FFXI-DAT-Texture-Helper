# All generated locations are fixed. Source game/XIPivot folders are never cleaned.
$script:DatToolRoot=$PSScriptRoot
function Get-ToolWork {
 $path=Join-Path $script:DatToolRoot '_Work'
 if((Test-Path -LiteralPath $path) -and (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'The workspace is a link or junction; it was not touched.'}
 if(Test-Path -LiteralPath (Join-Path $path 'Publish-in-progress.txt')){throw 'An output move was interrupted. _Work was preserved for recovery; do not delete it.'}
 if(Test-Path -LiteralPath $path){
  $marker=Join-Path $path '.dat-helper-work'
  if(-not (Test-Path -LiteralPath $marker)){throw 'An existing _Work folder is not owned by this helper. Move it elsewhere first.'}
  if((Get-Content -LiteralPath $marker -Raw).Trim() -ne 'FFXI DAT Helper workspace v1'){throw 'Unrecognized workspace marker.'}
  Remove-Item -LiteralPath $path -Recurse -Force
 }
 New-Item -ItemType Directory -Path $path | Out-Null
 'FFXI DAT Helper workspace v1' | Set-Content -LiteralPath (Join-Path $path '.dat-helper-work') -Encoding ASCII
 return $path
}
function Assert-ExternalInput([string]$Path) {
 $work=([IO.Path]::GetFullPath((Join-Path $script:DatToolRoot '_Work'))).TrimEnd('\')+'\'
 $inputPath=[IO.Path]::GetFullPath($Path)
 if($inputPath.StartsWith($work,[StringComparison]::OrdinalIgnoreCase)){throw 'Choose an input outside the temporary _Work folder.'}
}
function Assert-NoReparse([string]$Path) {
 if(Test-Path -LiteralPath $Path){
  if(([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Generated output contains a junction or link: $Path"}
  foreach($entry in @(Get-ChildItem -LiteralPath $Path -Recurse -Force)){
   if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Generated output contains a junction or link: $($entry.FullName)"}
  }
 }
}
function New-DirectoryState([string]$Path,[string]$Purpose) {
 $files=@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | ForEach-Object {
  [pscustomobject]@{Path=$_.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\').Replace('\','/');Hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
 })
 [ordered]@{Tool='FFXI DAT Helper';Purpose=$Purpose;Files=$files} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Path '.dat-helper-output.json') -Encoding UTF8
}
function Assert-ManagedDirectory([string]$Path,[string]$Purpose) {
 if(-not (Test-Path -LiteralPath $Path)){return}
 Assert-NoReparse $Path
 $stateFile=Join-Path $Path '.dat-helper-output.json'
 if(-not (Test-Path -LiteralPath $stateFile)){throw "Existing output folder is not recognized as helper-owned: $Path"}
 $s=Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json
 if($s.Tool -ne 'FFXI DAT Helper' -or $s.Purpose -ne $Purpose){throw "Unrecognized output marker: $Path"}
 $expected=@{}
 foreach($r in $s.Files){
  if($r.Path -match '(^|[/\\])\.\.([/\\]|$)' -or [IO.Path]::IsPathRooted($r.Path)){throw 'Invalid saved output path.'}
  $expected[$r.Path.Replace('\','/')]=$r.Hash
 }
 $actual=@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Where-Object {$_.FullName -ne $stateFile})
 if($actual.Count -ne $expected.Count){throw "Extra or missing files in generated output; it was kept: $Path"}
 foreach($f in $actual){
  $rel=$f.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\').Replace('\','/')
  if(-not $expected.ContainsKey($rel) -or (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -ne $expected[$rel]){throw "Generated output was edited; it was kept: $Path"}
 }
}
function Publish-ManagedDirectory([string]$Stage,[string]$Destination,[string]$Purpose) {
 New-DirectoryState $Stage $Purpose
 Assert-ManagedDirectory $Destination $Purpose
 $old=Join-Path (Join-Path $script:DatToolRoot '_Work') ('Old-'+$Purpose)
 if(Test-Path -LiteralPath $old){throw 'Previous temporary move has not been cleared.'}
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Destination))
 $journal=Join-Path (Join-Path $script:DatToolRoot '_Work') 'Publish-in-progress.txt'
 "Updating $Purpose; stage=$Stage; destination=$Destination; old=$old" | Set-Content -LiteralPath $journal
 $movedOld=$false;$movedNew=$false
 try {
  if(Test-Path -LiteralPath $Destination){Move-Item -LiteralPath $Destination -Destination $old;$movedOld=$true}
  Move-Item -LiteralPath $Stage -Destination $Destination;$movedNew=$true
 } catch {
  if($movedNew){Move-Item -LiteralPath $Destination -Destination $Stage}
  if($movedOld){Move-Item -LiteralPath $old -Destination $Destination}
  Remove-Item -LiteralPath $journal -Force
  throw
 }
 if($movedOld){Remove-Item -LiteralPath $old -Recurse -Force}
 Remove-Item -LiteralPath $journal -Force
}
function Get-RootOutputState([string]$Base) {
 $file=Join-Path $Base 'Output-state.json'
 if(-not (Test-Path -LiteralPath $file)){return $null}
 $state=Get-Content -Raw -LiteralPath $file | ConvertFrom-Json
 if($state.Tool -ne 'FFXI DAT Helper root output' -or $state.Version -ne 1){throw 'Unrecognized root output state.'}
 $expected=@{}
 foreach($r in $state.Files){
  if($r.Path -notmatch '(?i)^(ROM[0-9]*/[0-9]+/[0-9]+\.dat|changes\.json|Patched-DATs\.zip)$'){throw 'Invalid saved root output path.'}
  if($expected.ContainsKey($r.Path)){throw 'Duplicate saved output path.'}
  $expected[$r.Path]=$r.Hash
  $p=Join-Path $Base $r.Path
  if(-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $r.Hash){throw "Existing generated output was edited or removed; it was kept: $p"}
 }
 foreach($rootName in $state.Roots){
  if($rootName -notmatch '(?i)^ROM[0-9]*$'){throw 'Invalid saved ROM root.'}
  $rootPath=Join-Path $Base $rootName;Assert-NoReparse $rootPath
  foreach($f in @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force)){
   $rel=$f.FullName.Substring($Base.TrimEnd('\').Length).TrimStart('\').Replace('\','/')
   if(-not $expected.ContainsKey($rel)){throw "Extra files in generated ROM output; it was kept: $($f.FullName)"}
  }
 }
 return $state
}
function Publish-RootPatched([string]$Stage) {
 $root=$script:DatToolRoot
 $roots=@(Get-ChildItem -LiteralPath $Stage -Directory | Where-Object {$_.Name -match '(?i)^ROM[0-9]*$'} | ForEach-Object {$_.Name})
 if($roots.Count -eq 0){throw 'No patched ROM folders to publish.'}
 $items=@($roots)+@('changes.json','Patched-DATs.zip')
 $records=@()
 foreach($r in $roots){foreach($f in @(Get-ChildItem -LiteralPath (Join-Path $Stage $r) -Recurse -File)){$records += [pscustomobject]@{Path=$f.FullName.Substring($Stage.TrimEnd('\').Length).TrimStart('\').Replace('\','/');Hash=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash}}}
 foreach($name in @('changes.json','Patched-DATs.zip')){$records += [pscustomobject]@{Path=$name;Hash=(Get-FileHash -LiteralPath (Join-Path $Stage $name) -Algorithm SHA256).Hash}}
 [ordered]@{Tool='FFXI DAT Helper root output';Version=1;Roots=$roots;Files=$records} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Stage 'Output-state.json') -Encoding UTF8
 $current=Get-RootOutputState $root
 $previous=Join-Path $root 'Previous-output'
 $previousState=Get-RootOutputState $previous
 if((Test-Path -LiteralPath $previous) -and -not $previousState){throw 'Previous-output exists but is not helper-owned. It was kept.'}
 if($previousState){
  $allowed=@($previousState.Roots)+@('changes.json','Patched-DATs.zip','Output-state.json')
  foreach($e in @(Get-ChildItem -LiteralPath $previous -Force)){if($allowed -notcontains $e.Name){throw 'Untracked files in Previous-output; it was kept.'}}
 }
 $oldItems=if($current){@($current.Roots)+@('changes.json','Patched-DATs.zip','Output-state.json')}else{@()}
 foreach($name in $items+@('Output-state.json')){
  if((Test-Path -LiteralPath (Join-Path $root $name)) -and $oldItems -notcontains $name){throw "Existing $name is not managed output. Move it elsewhere before creating copies."}
 }
 $work=Join-Path $root '_Work';$oldPrevious=Join-Path $work 'Old-previous'
 $journal=Join-Path $work 'Publish-in-progress.txt'
 'Moving current patched output to Previous-output and publishing the new generation.' | Set-Content -LiteralPath $journal
 $savedPrevious=$false;$createdPrevious=$false;$movedOld=New-Object 'System.Collections.Generic.List[string]';$movedNew=New-Object 'System.Collections.Generic.List[string]'
 try {
  if(Test-Path -LiteralPath $previous){Move-Item -LiteralPath $previous -Destination $oldPrevious;$savedPrevious=$true}
  if($oldItems.Count -gt 0){
   New-Item -ItemType Directory -Path $previous | Out-Null;$createdPrevious=$true
   foreach($name in $oldItems){Move-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $previous $name);$movedOld.Add($name)}
  }
  foreach($name in $items+@('Output-state.json')){Move-Item -LiteralPath (Join-Path $Stage $name) -Destination (Join-Path $root $name);$movedNew.Add($name)}
 } catch {
  foreach($name in $movedNew){Move-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $Stage $name)}
  foreach($name in $movedOld){Move-Item -LiteralPath (Join-Path $previous $name) -Destination (Join-Path $root $name)}
  if($createdPrevious -and (Test-Path -LiteralPath $previous)){[IO.Directory]::Delete($previous,$false)}
  if($savedPrevious){Move-Item -LiteralPath $oldPrevious -Destination $previous}
  Remove-Item -LiteralPath $journal -Force
  throw
 }
 if($savedPrevious){Remove-Item -LiteralPath $oldPrevious -Recurse -Force}
 Remove-Item -LiteralPath $journal -Force
}
function Enter-ToolSession {
 try {return [IO.File]::Open((Join-Path $script:DatToolRoot '.Session.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
 catch {throw 'Another copy of the helper is running. Close that operation first.'}
}
function Clear-ToolWork {
 $path=Join-Path $script:DatToolRoot '_Work'
 if((Test-Path -LiteralPath $path) -and (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'The workspace is a link or junction; it was not touched.'}
 if(Test-Path -LiteralPath (Join-Path $path 'Publish-in-progress.txt')){return}
 if(Test-Path -LiteralPath (Join-Path $path '.dat-helper-work')){
  if((Get-Content -Raw -LiteralPath (Join-Path $path '.dat-helper-work')).Trim() -ne 'FFXI DAT Helper workspace v1'){return}
  foreach($item in @(Get-ChildItem -LiteralPath $path -Force | Where-Object {$_.Name -ne '.dat-helper-work'})){Remove-Item -LiteralPath $item.FullName -Recurse -Force}
 }
}
