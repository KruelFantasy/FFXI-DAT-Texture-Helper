function Update-ToolGridHeaders($Grid){
 if(-not $Grid -or $Grid.IsDisposed -or -not $Grid.IsHandleCreated){return}
 $form=$Grid.FindForm();if(-not $form){return};$scale=Get-ToolScale $form
 $Grid.ColumnHeadersDefaultCellStyle.Font=$Grid.Font
 $Grid.ColumnHeadersDefaultCellStyle.WrapMode='True'
 $height=[int](28*$scale)
 foreach($col in $Grid.Columns){
  if(-not $col.Visible){continue}
  $width=[int][Math]::Max(20,($col.Width-18*$scale))
  $measured=Get-ToolTextHeight $col.HeaderText $Grid.Font $width $form
  $height=[int][Math]::Max($height,($measured+8*$scale))
 }
 $Grid.ColumnHeadersHeightSizeMode='EnableResizing'
 if($Grid.ColumnHeadersHeight -ne $height){$Grid.ColumnHeadersHeight=$height}
}
function Resize-ToolGridHeaders($Grid){
 # Width/resize events can occur inside DataGridView.AdjustFillingColumns.
 # Only enqueue work here; never change header geometry in that call stack.
 if(-not $Grid -or $Grid.IsDisposed -or -not $Grid.IsHandleCreated){return}
 if($Grid.PSObject.Properties['HeaderResizeTimer'] -and $Grid.HeaderResizeTimer){
  $Grid.HeaderResizeTimer.Stop();$Grid.HeaderResizeTimer.Start()
 }
}
function Initialize-ToolGridHeaders($Grid){
 $Grid.ColumnHeadersDefaultCellStyle.WrapMode='True'
 $timer=New-Object Windows.Forms.Timer;$timer.Interval=60;$timer.Tag=$Grid
 Add-Member -InputObject $Grid -MemberType NoteProperty -Name HeaderResizeTimer -Value $timer
 Add-Member -InputObject $Grid -MemberType NoteProperty -Name HeaderRetryCount -Value 0
 $timer.Add_Tick({param($sender,$e)
  $sender.Stop();$g=$sender.Tag
  if(-not $g -or $g.IsDisposed -or -not $g.IsHandleCreated){return}
  try{Update-ToolGridHeaders $g;$g.HeaderRetryCount=0}
  catch{
   # A resize still in flight is retried on a later message-loop tick. No
   # PowerShell exception escapes into a Windows Forms event handler.
   if($_.Exception.ToString() -match 'auto-filled column' -and $g.HeaderRetryCount -lt 5){$g.HeaderRetryCount++;$sender.Start()}
   else{Write-Warning ("Header resize deferred: "+$_.Exception.Message)}
  }
 })
 $Grid.Add_ColumnWidthChanged({param($sender,$e) Resize-ToolGridHeaders $sender})
 $Grid.Add_FontChanged({param($sender,$e) Resize-ToolGridHeaders $sender})
 $Grid.Add_HandleCreated({param($sender,$e) Resize-ToolGridHeaders $sender})
 $Grid.Add_Disposed({param($sender,$e) if($sender.HeaderResizeTimer){$sender.HeaderResizeTimer.Stop();$sender.HeaderResizeTimer.Dispose();$sender.HeaderResizeTimer=$null}})
}
