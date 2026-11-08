. (Join-Path $PSScriptRoot 'Grid-Headers.ps1')
. (Join-Path $PSScriptRoot 'Export-Samples.ps1')
function Show-Assessment($display,$optional,[int]$ready,[int]$already,[string]$folder,[string]$InputRoot,[string]$OriginalRoot) {
 $form=New-ToolForm 'FFXI DAT Texture Helper 2.4 - assessment' 1240 800
 $scale=Get-ToolScale $form
 $supported=@($optional | Where-Object {$_.CanSelect}).Count
 $layout=New-Object Windows.Forms.TableLayoutPanel
 $layout.Dock='Fill';$layout.ColumnCount=1;$layout.RowCount=5
 [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
 foreach($logical in @(110,0,42,0,65)){$h=[int]($logical*$scale);[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',$h)))}
 $layout.RowStyles[1].SizeType='Percent';$layout.RowStyles[1].Height=100
 $top=New-Object Windows.Forms.Label
 $top.Dock='Fill';$top.Padding=New-Object Windows.Forms.Padding(12)
 $top.Text="RECOMMENDED: Patch only the recommended files.`r`n$ready file(s) passed the naming-pattern and supported-reference checks. This is not proof of an individual crash cause.`r`nAdvanced optional matches are not confirmed problems. Only select them if you understand the naming issue and why that specific texture needs changing. Otherwise, leave them unchecked."
 $top.Font=New-Object Drawing.Font('Segoe UI',10)
 $grid=New-Object Windows.Forms.DataGridView
 $grid.Dock='Fill';$grid.ReadOnly=$true;$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false
 $grid.RowHeadersVisible=$false;$grid.AutoGenerateColumns=$false;$grid.SelectionMode='FullRowSelect'
 $grid.DefaultCellStyle.WrapMode='True';$grid.AutoSizeRowsMode='AllCells'
 $grid.AutoSizeColumnsMode='Fill';$grid.BackgroundColor=[Drawing.Color]::White
 foreach($spec in @(@('Dat','DAT file',32),@('Texture','Texture name',20),@('Status','Result',25),@('Action','What happens',40))){
  $col=New-Object Windows.Forms.DataGridViewTextBoxColumn
  $col.Name=$spec[0];$col.HeaderText=$spec[1];$col.FillWeight=[int]$spec[2];[void]$grid.Columns.Add($col)
 }
 Initialize-ToolGridHeaders $grid
 foreach($row in $display){[void]$grid.Rows.Add([object[]]@($row.Dat,$row.Texture,$row.Status,$row.Action))}
 $toggle=New-Object Windows.Forms.Button
 $toggle.Text="Advanced: Optional texture matches ($($optional.Count); $supported selectable) - Show"
 $toggle.Dock='Fill';$toggle.TextAlign='MiddleLeft'
 $advanced=New-Object Windows.Forms.DataGridView
 $advanced.Dock='Fill';$advanced.Visible=$false;$advanced.AllowUserToAddRows=$false;$advanced.AllowUserToDeleteRows=$false
 $advanced.RowHeadersVisible=$false;$advanced.AutoGenerateColumns=$false;$advanced.AutoSizeColumnsMode='Fill'
 $advanced.DefaultCellStyle.WrapMode='True';$advanced.AutoSizeRowsMode='AllCells'
 $advanced.BackgroundColor=[Drawing.Color]::White
 $check=New-Object Windows.Forms.DataGridViewCheckBoxColumn
 $check.Name='Select';$check.HeaderText='Add';$check.FillWeight=7;[void]$advanced.Columns.Add($check)
 foreach($spec in @(@('Dat','DAT file',30),@('Texture','Texture name',20),@('Reason','Why listed',25),@('Status','Optional rename status',34))){
  $col=New-Object Windows.Forms.DataGridViewTextBoxColumn
  $col.Name=$spec[0];$col.HeaderText=$spec[1];$col.FillWeight=[int]$spec[2];$col.ReadOnly=$true;[void]$advanced.Columns.Add($col)
 }
 Initialize-ToolGridHeaders $advanced
 foreach($item in $optional){
  $i=$advanced.Rows.Add([object[]]@($false,$item.File.Replace('/','\'),$item.Texture,$item.Reason,$item.Status))
  $advanced.Rows[$i].Tag=$item
  if(-not $item.CanSelect){$advanced.Rows[$i].Cells[0].ReadOnly=$true;$advanced.Rows[$i].DefaultCellStyle.ForeColor=[Drawing.Color]::Gray}
 }
 $bottom=New-Object Windows.Forms.FlowLayoutPanel
 $bottom.Dock='Fill';$bottom.Padding=New-Object Windows.Forms.Padding(8)
 $create=New-Object Windows.Forms.Button
 $create.Text='Create recommended copies';$create.AutoSize=$true;$create.Enabled=($ready -gt 0);$create.DialogResult='OK'
 $count=New-Object Windows.Forms.Label;$count.AutoSize=$true;$count.Text='Optional rows selected: 0';$count.Margin=New-Object Windows.Forms.Padding(8,8,8,0)
 $close=New-Object Windows.Forms.Button;$close.Text='Close';$close.AutoSize=$true;$close.DialogResult='Cancel'
 $open=New-Object Windows.Forms.Button;$open.Text='Open assessment folder';$open.AutoSize=$true;$open.Tag=$folder
 $open.Add_Click({param($sender,$eventArgs) Start-Process -FilePath explorer.exe -ArgumentList ('"'+$sender.Tag+'"')})
 $export=New-Object Windows.Forms.Button
 $export.Text='Export unsupported samples';$export.AutoSize=$true
 $export.Enabled=(@($optional | Where-Object {-not $_.CanSelect -and $_.ExpectedSha256}).Count -gt 0)
 $export.Tag=[pscustomobject]@{Items=$optional;Input=$InputRoot;Original=$OriginalRoot}
 $export.Add_Click({param($sender,$e)
  try{
   $zip=Export-ToolUnsupportedSamples $sender.Tag.Items $sender.Tag.Input $sender.Tag.Original
   [void][Windows.Forms.MessageBox]::Show("Sample ZIP created:`r`n$zip`r`nSend this ZIP for format investigation. No DATs were patched or uploaded.",'Samples ready','OK','Information')
  }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Sample export stopped','OK','Warning')}
 })
 $advanced.Tag=[pscustomobject]@{Create=$create;Count=$count;Ready=$ready}
 $advanced.Add_CurrentCellDirtyStateChanged({param($sender,$eventArgs) if($sender.IsCurrentCellDirty){[void]$sender.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)}})
 $advanced.Add_CellValueChanged({param($sender,$eventArgs)
  $n=0;foreach($r in $sender.Rows){if($r.Tag.CanSelect -and $r.Cells[0].Value -eq $true){$n++}}
  $sender.Tag.Count.Text="Optional rows selected: $n"
  $sender.Tag.Create.Enabled=($sender.Tag.Ready -gt 0 -or $n -gt 0)
  $sender.Tag.Create.Text=if($n -gt 0){"Create recommended + optional copies"}else{'Create recommended copies'}
 })
 $toggle.Tag=[pscustomobject]@{Grid=$advanced;Layout=$layout;Count=$optional.Count;Supported=$supported;Scale=$scale}
 $toggle.Add_Click({param($sender,$eventArgs)
  $show=-not $sender.Tag.Grid.Visible;$sender.Tag.Grid.Visible=$show
  $sender.Tag.Layout.RowStyles[3].SizeType=if($show){'Percent'}else{'Absolute'}
  $sender.Tag.Layout.RowStyles[3].Height=if($show){50}else{0}
  $sender.Tag.Layout.RowStyles[1].Height=if($show){50}else{100}
  Resize-ToolGridHeaders $sender.Tag.Grid
  $sender.Text="Advanced: Optional texture matches ($($sender.Tag.Count); $($sender.Tag.Supported) selectable) - "+$(if($show){'Hide'}else{'Show'})
 })
 foreach($c in @($create,$close,$open,$export,$count)){[void]$bottom.Controls.Add($c)}
 [void]$layout.Controls.Add($top,0,0);[void]$layout.Controls.Add($grid,0,1);[void]$layout.Controls.Add($toggle,0,2)
 [void]$layout.Controls.Add($advanced,0,3);[void]$layout.Controls.Add($bottom,0,4);$form.Controls.Add($layout)
 $form.Tag=[pscustomobject]@{Layout=$layout;Top=$top;Bottom=$bottom;MainGrid=$grid;Advanced=$advanced;Scale=$scale}
 $form.Add_Resize({param($sender,$e)
  $c=$sender.Tag;if(-not $c){return}
  $w=[Math]::Max(160,$sender.ClientSize.Width-40*$c.Scale)
  $c.Layout.RowStyles[0].Height=(Get-ToolTextHeight $c.Top.Text $c.Top.Font ([int]$w) $sender)+[int](26*$c.Scale)
  $bh=$c.Bottom.GetPreferredSize((New-Object Drawing.Size($sender.ClientSize.Width,0))).Height
  $c.Layout.RowStyles[4].Height=[Math]::Max([int](55*$c.Scale),$bh+12*$c.Scale)
  Resize-ToolGridHeaders $c.MainGrid;Resize-ToolGridHeaders $c.Advanced
 })
 $form.Add_Shown({param($sender,$e) Center-ToolForm $sender;$c=$sender.Tag;$w=[int][Math]::Max(160,$sender.ClientSize.Width-40*$c.Scale);$c.Layout.RowStyles[0].Height=(Get-ToolTextHeight $c.Top.Text $c.Top.Font $w $sender)+[int](26*$c.Scale);Resize-ToolGridHeaders $c.MainGrid;Resize-ToolGridHeaders $c.Advanced})
 $form.AcceptButton=$create;$form.CancelButton=$close
 try{
  if($form.ShowDialog() -ne 'OK'){return [pscustomobject]@{Create=$false;Optional=@()}}
  [void]$advanced.EndEdit()
  $selected=@($advanced.Rows | Where-Object {$_.Tag.CanSelect -and $_.Cells[0].Value -eq $true} | ForEach-Object {$_.Tag})
  return [pscustomobject]@{Create=$true;Optional=$selected}
 }finally{$form.Dispose()}
}
