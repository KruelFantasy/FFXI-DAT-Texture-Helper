Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if(-not ('DatHelperDpi' -as [type])){
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DatHelperDpi {
 [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
 [DllImport("shcore.dll")] static extern int SetProcessDpiAwareness(int awareness);
 public static void Initialize(){try{if(SetProcessDpiAwarenessContext(new IntPtr(-4)))return;}catch{}try{SetProcessDpiAwareness(2);}catch{}}
}
'@
 [DatHelperDpi]::Initialize()
 [Windows.Forms.Application]::EnableVisualStyles()
}
function Get-ToolScale($Form){
 $g=$Form.CreateGraphics()
 try{return [Math]::Max(1.0,[double]$g.DpiX/96.0)}finally{$g.Dispose()}
}
function Get-ToolTextHeight([string]$Text,$Font,[int]$Width,$Context=$null){
 $flags=[Windows.Forms.TextFormatFlags]::WordBreak -bor [Windows.Forms.TextFormatFlags]::TextBoxControl -bor [Windows.Forms.TextFormatFlags]::NoPrefix -bor [Windows.Forms.TextFormatFlags]::NoPadding
 $size=New-Object Drawing.Size([Math]::Max(80,$Width),32767)
 if($Context){
  $g=$Context.CreateGraphics()
  try{return [Windows.Forms.TextRenderer]::MeasureText($g,$Text,$Font,$size,$flags).Height+4}finally{$g.Dispose()}
 }
 return [Windows.Forms.TextRenderer]::MeasureText($Text,$Font,$size,$flags).Height+4
}
function Center-ToolForm($Form){
 $area=[Windows.Forms.Screen]::FromControl($Form).WorkingArea
 $margin=[int](12*(Get-ToolScale $Form))
 $Form.Width=[Math]::Min($Form.Width,[Math]::Max(300,$area.Width-2*$margin))
 $Form.Height=[Math]::Min($Form.Height,[Math]::Max(240,$area.Height-2*$margin))
 $Form.Location=New-Object Drawing.Point(($area.Left+[int](($area.Width-$Form.Width)/2)),($area.Top+[int](($area.Height-$Form.Height)/2)))
}
function New-ToolForm([string]$Title,[int]$Width,[int]$Height){
 $form=New-Object Windows.Forms.Form
 $form.Text=$Title;$form.StartPosition='Manual';$form.AutoScaleMode='None'
 $form.Font=New-Object Drawing.Font('Segoe UI',9)
 $area=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
 $form.Location=New-Object Drawing.Point(($area.Left+20),($area.Top+20))
 $scale=Get-ToolScale $form
 $form.Size=New-Object Drawing.Size(([int][Math]::Min($Width*$scale,$area.Width-24*$scale)),([int][Math]::Min($Height*$scale,$area.Height-24*$scale)))
 $form.MinimumSize=New-Object Drawing.Size(([int][Math]::Min(580*$scale,$area.Width-24*$scale)),([int][Math]::Min(400*$scale,$area.Height-24*$scale)))
 Center-ToolForm $form
 return $form
}
function Set-ToolFolderRoot($Form,[string]$Path){
 if(-not [IO.Directory]::Exists($Path)){$Form.Tag.Note.Text='That folder does not exist. Paste a complete folder path.';return}
 $full=[IO.Path]::GetFullPath($Path)
 $Form.Tag.Tree.Nodes.Clear()
 $node=New-Object Windows.Forms.TreeNode($full);$node.Tag=$full
 [void]$node.Nodes.Add((New-Object Windows.Forms.TreeNode('Loading...')))
 [void]$Form.Tag.Tree.Nodes.Add($node);$node.Expand();$Form.Tag.Tree.SelectedNode=$node
 $Form.Tag.Path.Text=$full;$Form.Tag.Note.Text='Select a folder in the tree, or paste a complete path, then click Use this folder.'
}
function Layout-ToolFolder($Form){
 $c=$Form.Tag;$s=Get-ToolScale $Form;$p=[int](14*$s);$gap=[int](8*$s)
 $w=[Math]::Max(100,$Form.ClientSize.Width-2*$p);$h=$Form.ClientSize.Height
 $titleH=Get-ToolTextHeight $c.Description.Text $c.Description.Font $w $Form
 $c.Description.SetBounds($p,$p,$w,$titleH)
 $y=$p+$titleH+$gap;$bh=[int](32*$s);$navH=[int](34*$s)
 $c.Path.SetBounds($p,$y,[Math]::Max(80,$w-105*$s),$bh)
 $c.Go.SetBounds(([int]($p+$w-98*$s)),$y,([int](98*$s)),$bh)
 $y+=$bh+$gap
 $bw=[int](90*$s)
 $c.Up.SetBounds($p,$y,$bw,$bh);$c.Desktop.SetBounds(($p+$bw+$gap),$y,$bw,$bh);$c.Drives.SetBounds(($p+2*($bw+$gap)),$y,$bw,$bh)
 $y+=$bh+$gap
 $footerY=[Math]::Max(($y+65*$s),($h-$p-$bh))
 $c.Use.SetBounds(([int]($p+$w-244*$s)),([int]$footerY),([int](145*$s)),$bh)
 $c.Cancel.SetBounds(([int]($p+$w-91*$s)),([int]$footerY),([int](91*$s)),$bh)
 $noteH=Get-ToolTextHeight $c.Note.Text $c.Note.Font $w $Form
 $noteY=[int]($footerY-$gap-$noteH)
 $c.Note.SetBounds($p,$noteY,$w,$noteH)
 $c.Tree.SetBounds($p,$y,$w,[Math]::Max(35,($noteY-$gap-$y)))
}
function Select-ToolFolder([string]$Description){
 $form=New-ToolForm 'Choose folder' 820 640
 $tree=New-Object Windows.Forms.TreeView;$tree.HideSelection=$false
 $descriptionLabel=New-Object Windows.Forms.Label;$descriptionLabel.Text=$Description;$descriptionLabel.AutoSize=$false
 $path=New-Object Windows.Forms.TextBox
 $note=New-Object Windows.Forms.Label;$note.AutoSize=$false
 $go=New-Object Windows.Forms.Button;$go.Text='Open path'
 $up=New-Object Windows.Forms.Button;$up.Text='Up'
 $desktop=New-Object Windows.Forms.Button;$desktop.Text='Desktop'
 $drives=New-Object Windows.Forms.Button;$drives.Text='Drives'
 $use=New-Object Windows.Forms.Button;$use.Text='Use this folder'
 $cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancel';$cancel.DialogResult='Cancel'
 $form.Tag=[pscustomobject]@{Tree=$tree;Description=$descriptionLabel;Path=$path;Note=$note;Go=$go;Up=$up;Desktop=$desktop;Drives=$drives;Use=$use;Cancel=$cancel;Selected=$null}
 foreach($control in @($descriptionLabel,$path,$go,$up,$desktop,$drives,$tree,$note,$use,$cancel)){[void]$form.Controls.Add($control)}
 $tree.Add_BeforeExpand({param($sender,$e)
  if(-not $e.Node.Tag){return}
  if($e.Node.Nodes.Count -eq 1 -and -not $e.Node.Nodes[0].Tag){
   $e.Node.Nodes.Clear()
   try{
    foreach($dir in @([IO.Directory]::GetDirectories([string]$e.Node.Tag) | Sort-Object)){
     $n=New-Object Windows.Forms.TreeNode([IO.Path]::GetFileName($dir));$n.Tag=$dir
     [void]$n.Nodes.Add((New-Object Windows.Forms.TreeNode('Loading...')));[void]$e.Node.Nodes.Add($n)
    }
   }catch{$sender.FindForm().Tag.Note.Text='Some subfolders could not be listed. You can still paste or select a folder path.'}
  }
 })
 $tree.Add_AfterSelect({param($sender,$e) if($e.Node -and $e.Node.Tag){$sender.FindForm().Tag.Path.Text=[string]$e.Node.Tag}})
 $go.Add_Click({param($sender,$e) $f=$sender.FindForm();Set-ToolFolderRoot $f $f.Tag.Path.Text.Trim().Trim('"');Layout-ToolFolder $f})
 $up.Add_Click({param($sender,$e)
  $f=$sender.FindForm();try{$parent=[IO.Directory]::GetParent($f.Tag.Path.Text);if($parent){Set-ToolFolderRoot $f $parent.FullName}}catch{};Layout-ToolFolder $f
 })
 $desktop.Add_Click({param($sender,$e) $f=$sender.FindForm();Set-ToolFolderRoot $f ([Environment]::GetFolderPath('DesktopDirectory'));Layout-ToolFolder $f})
 $drives.Add_Click({param($sender,$e)
  $f=$sender.FindForm();$f.Tag.Tree.Nodes.Clear()
  foreach($drive in [IO.Directory]::GetLogicalDrives()){
   $n=New-Object Windows.Forms.TreeNode($drive);$n.Tag=$drive;[void]$n.Nodes.Add((New-Object Windows.Forms.TreeNode('Loading...')));[void]$f.Tag.Tree.Nodes.Add($n)
  }
 })
 $use.Add_Click({param($sender,$e)
  $f=$sender.FindForm()
  $entered=$f.Tag.Path.Text.Trim().Trim('"')
  if([IO.Directory]::Exists($entered)){$f.Tag.Selected=[IO.Path]::GetFullPath($entered);$f.DialogResult='OK'}
  else{$f.Tag.Note.Text='Please select an existing folder.';Layout-ToolFolder $f}
 })
 $form.AcceptButton=$use;$form.CancelButton=$cancel
 $form.Add_Resize({param($sender,$e) Layout-ToolFolder $sender})
 $form.Add_Shown({param($sender,$e) Layout-ToolFolder $sender;Center-ToolForm $sender})
 Set-ToolFolderRoot $form ([Environment]::GetFolderPath('DesktopDirectory'))
 Layout-ToolFolder $form
 try{if($form.ShowDialog() -eq 'OK'){return $form.Tag.Selected};return $null}finally{$form.Dispose()}
}
