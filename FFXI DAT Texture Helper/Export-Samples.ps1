function Export-ToolUnsupportedSamples($Items,[string]$InputRoot,[string]$OriginalRoot){
 $groups=@($Items | Where-Object {-not $_.CanSelect -and $_.ExpectedSha256} | Group-Object Status)
 if($groups.Count -eq 0){throw 'There are no supplied unsupported DATs to export.'}
 # Select one representative per distinct reason, capped at three DATs.
 $chosen=New-Object 'System.Collections.Generic.List[object]'
 $paths=@{}
 foreach($group in @($groups | Sort-Object Name)){
  $representative=$group.Group | Sort-Object File,IDHex | Select-Object -First 1
  if(-not $paths.ContainsKey($representative.File)){$chosen.Add($representative);$paths[$representative.File]=$true}
  if($chosen.Count -ge 3){break}
 }
 $work=Join-Path $PSScriptRoot '_Work'
 $data=Join-Path $work 'Unsupported-data';$stage=Join-Path $work 'Unsupported-export'
 if((Test-Path -LiteralPath $data) -or (Test-Path -LiteralPath $stage)){throw 'A previous sample staging folder is still present. Close and reopen assessment before retrying.'}
 New-Item -ItemType Directory -Path $data | Out-Null
 New-Item -ItemType Directory -Path $stage | Out-Null
 try{
  $details=New-Object 'System.Collections.Generic.List[object]'
  foreach($item in $chosen){
   $rel=$item.File
   if($rel -notmatch '(?i)^ROM(?:[0-9]+)?/[0-9]+/[0-9]+\.dat$'){throw 'Unexpected sample path.'}
   $source=Join-Path $InputRoot $rel
   if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $item.ExpectedSha256){throw "Sample changed since assessment: $rel. Run a fresh assessment."}
   $dest=Join-Path (Join-Path $data 'Custom') $rel
   [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest));Copy-Item -LiteralPath $source -Destination $dest
   if((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $item.ExpectedSha256){throw 'Copied sample hash mismatch.'}
   $hasOriginal=$false
   if($OriginalRoot){
    $original=Join-Path $OriginalRoot $rel
    if(Test-Path -LiteralPath $original -PathType Leaf){
     $destOriginal=Join-Path (Join-Path $data 'Original') $rel
     [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destOriginal));Copy-Item -LiteralPath $original -Destination $destOriginal
     $hasOriginal=$true
    }
   }
   foreach($match in @($Items | Where-Object {$_.File -eq $rel})){
    $details.Add([pscustomobject]@{File=$rel.Replace('/','\');Texture=$match.Texture;IDHex=$match.IDHex;Reason=$match.Status;CustomSHA256=$item.ExpectedSha256;OriginalIncluded=$hasOriginal})
   }
  }
  $details.ToArray() | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $data 'Sample-details.csv')
  @'
UNSUPPORTED DAT FORMAT SAMPLES
These are exact read-only copies, not patched DATs. One representative custom
DAT is selected for each observed refusal reason, up to three distinct files.
Original counterparts are included only when the original scan folder is known.
Sample-details.csv records all reported optional texture IDs in these files.
No game executable, account data or complete XIPivot installation is included.
This ZIP is for offline format investigation. Nothing is uploaded automatically.
'@ | Set-Content -LiteralPath (Join-Path $data 'README.txt') -Encoding UTF8
  $zip=Join-Path $stage 'Unsupported-samples.zip'
  [IO.Compression.ZipFile]::CreateFromDirectory($data,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
  $saved=Join-Path (Join-Path $PSScriptRoot 'Reports') 'Unsupported'
  Publish-ManagedDirectory $stage $saved 'unsupported-samples'
  return (Join-Path $saved 'Unsupported-samples.zip')
 }finally{
  if(Test-Path -LiteralPath $data){Remove-Item -LiteralPath $data -Recurse -Force}
  # An interrupted output publication must retain its stage for recovery.
  if(-not (Test-Path -LiteralPath (Join-Path $work 'Publish-in-progress.txt'))){if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}}
 }
}
