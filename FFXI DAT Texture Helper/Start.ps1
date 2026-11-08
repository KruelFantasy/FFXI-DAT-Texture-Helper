$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'UI-Common.ps1')
function Layout-ToolHome($Form){
 $c=$Form.Tag;if($c.Busy){return};$c.Busy=$true
 try{
  $s=Get-ToolScale $Form;$p=[int](18*$s);$gap=[int](9*$s)
  $scroll=if($c.Panel.VerticalScroll.Visible){[int](20*$s)}else{0}
  $w=[Math]::Max(160,$c.Panel.ClientSize.Width-2*$p-$scroll)
  $y=$p;$h=Get-ToolTextHeight $c.Warning.Text $c.Warning.Font $w $Form
  $c.Warning.SetBounds($p,$y,$w,$h);$y+=$h+$gap
  foreach($button in $c.Buttons){$button.SetBounds($p,$y,$w,([int](42*$s)));$y+=[int](42*$s)+$gap}
  $y+=[int](7*$s)
  $h=Get-ToolTextHeight $c.Help.Text $c.Help.Font $w $Form
  $c.Help.SetBounds($p,$y,$w,$h);$y+=$h+$p
  $c.ContentHeight=$y;$c.Panel.AutoScrollMinSize=New-Object Drawing.Size(0,$y)
 }finally{$c.Busy=$false}
}
function Show-Home([bool]$HasScan){
 $form=New-ToolForm 'FFXI DAT Texture Helper 2.4' 960 760
 $panel=New-Object Windows.Forms.Panel;$panel.Dock='Fill';$panel.AutoScroll=$true
 $warning=New-Object Windows.Forms.Label;$warning.AutoSize=$false
 $warning.Text='Recommended: Patch only the recommended files. Advanced optional matches are for users who understand why a particular texture needs changing.'
 $help=New-Object Windows.Forms.Label;$help.AutoSize=$false
 $help.Text=@'
Set your FF11 directory where your ROM folders are at.
Then set your XIPivot DAT folder.
Let the tool scan and compare them.
It will then open the DATs list.
It will identify custom DATs with supported texture-name conflict patterns.
Click "Create recommended copies" to create fixed versions of those DATs.
Patched ROM folders appear beside Start.cmd. Reports are reused. Installed DATs are never overwritten.
Copy and overwrite the DATs in your XIPivot folder with the fixed ROM folder.
Do not choose any of the hidden optional textures if you do not know what you are doing.
'@
 $buttons=New-Object 'System.Collections.Generic.List[System.Windows.Forms.Button]'
 foreach($spec in @(@('Scan folders, then assess automatically','scan'),@('Continue with this session''s latest scan','continue'),@('Load an older report and supply DATs','assess'),@('Restore original copies from a fix package','restore'))){
  $button=New-Object Windows.Forms.Button;$button.Text=$spec[0];$button.Tag=$spec[1]
  if($spec[1] -eq 'continue'){$button.Enabled=$HasScan}
  $button.Add_Click({param($sender,$e) $f=$sender.FindForm();$f.Tag.Action=$sender.Tag;$f.DialogResult='OK'})
  $buttons.Add($button);[void]$panel.Controls.Add($button)
 }
 [void]$panel.Controls.Add($warning);[void]$panel.Controls.Add($help);[void]$form.Controls.Add($panel)
 $form.Tag=[pscustomobject]@{Panel=$panel;Warning=$warning;Help=$help;Buttons=$buttons;Busy=$false;ContentHeight=0;Action=$null}
 $form.Add_Resize({param($sender,$e) Layout-ToolHome $sender})
 $panel.Add_SizeChanged({param($sender,$e) $f=$sender.FindForm();if($f -and $f.Tag){Layout-ToolHome $f}})
 $form.Add_Shown({param($sender,$e)
  Layout-ToolHome $sender
  $area=[Windows.Forms.Screen]::FromControl($sender).WorkingArea;$s=Get-ToolScale $sender
  $frame=$sender.Height-$sender.ClientSize.Height
  $sender.Height=[int][Math]::Min(($sender.Tag.ContentHeight+$frame),($area.Height-24*$s))
  Center-ToolForm $sender;Layout-ToolHome $sender
 })
 Layout-ToolHome $form
 try{if($form.ShowDialog() -eq 'OK'){return $form.Tag.Action};return $null}finally{$form.Dispose()}
}
$lastScan=$null
while($true){
 $action=Show-Home ($null -ne $lastScan)
 if(-not $action){break}
 switch($action){
  'scan' {
   $newScan=& (Join-Path $PSScriptRoot 'Compare-DATs.ps1') -PassThru
   if($newScan){$lastScan=$newScan;& (Join-Path $PSScriptRoot 'Assess-Files.ps1') -ReportPath $lastScan.ReportPath -CustomRoot $lastScan.CustomRoot -OriginalRoot $lastScan.OriginalRoot}
  }
  'continue' {& (Join-Path $PSScriptRoot 'Assess-Files.ps1') -ReportPath $lastScan.ReportPath -CustomRoot $lastScan.CustomRoot -OriginalRoot $lastScan.OriginalRoot}
  'assess' {& (Join-Path $PSScriptRoot 'Assess-Files.ps1')}
  'restore' {& (Join-Path $PSScriptRoot 'Restore-Copies.ps1')}
 }
}
