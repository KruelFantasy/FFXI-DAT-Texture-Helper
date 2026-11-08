param([string]$OriginalRoot,[string]$CustomRoot,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UI-Common.ps1')
. (Join-Path $PSScriptRoot 'Output-Management.ps1')
Add-Type -AssemblyName System.Windows.Forms
function Choose-Folder([string]$Description){return (Select-ToolFolder $Description)}
$lease=$null
try {
 $lease=Enter-ToolSession
 if(-not $OriginalRoot){$OriginalRoot=Choose-Folder 'FIRST: original FINAL FANTASY XI folder containing ROM, ROM2, etc.'}
 if(-not $OriginalRoot){return}
 if(-not $CustomRoot){$CustomRoot=Choose-Folder 'SECOND: custom XIPivot pack folder containing ROM, ROM2, etc.'}
 if(-not $CustomRoot){return}
 Assert-ExternalInput $OriginalRoot;Assert-ExternalInput $CustomRoot
 $work=Get-ToolWork
 $out=Join-Path $work 'Scan'
 if(-not ('DatTextureComparisonV2' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'Scanner.cs')}
 [DatTextureComparisonV2]::Run($OriginalRoot,$CustomRoot,$out)
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=Join-Path $work 'DAT-Comparison.zip'
 [IO.Compression.ZipFile]::CreateFromDirectory($out,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
 Move-Item -LiteralPath $zip -Destination (Join-Path $out 'DAT-Comparison.zip')
 $saved=Join-Path (Join-Path $PSScriptRoot 'Reports') 'Comparison'
 Publish-ManagedDirectory $out $saved 'comparison'
 Write-Host "`nFinished. Latest comparison:`n$(Join-Path $saved 'DAT-Comparison.zip')" -ForegroundColor Green
 if(-not $PassThru){[void][Windows.Forms.MessageBox]::Show("Scan complete.`r`n$(Join-Path $saved 'DAT-Comparison.zip')`r`nThis location is reused on the next successful scan.",'Finished','OK','Information')}
 if($PassThru){return [pscustomobject]@{ReportPath=(Join-Path $saved 'DAT-Comparison.zip');OriginalRoot=$OriginalRoot;CustomRoot=$CustomRoot}}
} catch {
 Write-Host "Scan stopped: $($_.Exception.Message)" -ForegroundColor Red
 [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Scan stopped','OK','Warning')
 exit 1
} finally {if($lease){try{Clear-ToolWork}finally{$lease.Dispose()}}}
