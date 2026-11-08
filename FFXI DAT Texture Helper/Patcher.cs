using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

public sealed class DatOptionalSelection { public string File, IDHex, ExpectedSha256; public bool Advanced; }
public sealed class DatInspection { public string File, IDHex, Sha256, Reason; public bool CanPatch; public int References; }
public sealed class DatDefinition {
 public string File, IDHex;
 public long Offset, ChunkBytes;
 public int Format;
}
public sealed class DatPatchRecord {
 public string File, OriginalSha256, PatchedSha256;
 public long FileBytes;
 public bool IncludesOptional;
 public List<DatNameChange> Changes=new List<DatNameChange>();
}
public sealed class DatEncodedField { public List<int> SourceOffsets=new List<int>(); public string BeforeHex,AfterHex; }
public sealed class DatNameChange {
 public List<DatEncodedField> EncodedReferences=new List<DatEncodedField>();
 public string OldHex, NewHex, OldName, NewName;
 public List<int> DefinitionOffsets=new List<int>();
 public List<int> ReferenceOffsets=new List<int>();
}
public sealed class DatPatchResult {
 public List<DatPatchRecord> Files=new List<DatPatchRecord>();
 public List<string> MissingFiles=new List<string>();
}
public static class DatTexturePatcherV1 {
 sealed class Chunk {public int Start, End, Type;}
 static void Require(bool ok,string message){if(!ok)throw new InvalidDataException(message);}
 static string Hex(byte[] b,int at,int n){return BitConverter.ToString(b,at,n).Replace("-","");}
 static byte[] Unhex(string s){Require(s!=null && Regex.IsMatch(s,@"\A[0-9a-fA-F]{32}\z"),"Invalid 16-byte ID");byte[] b=new byte[16];for(int i=0;i<16;i++)b[i]=Convert.ToByte(s.Substring(i*2,2),16);return b;}
 static bool Equal(byte[] a,byte[] b){if(a.Length!=b.Length)return false;for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;return true;}
 static bool Match(byte[] b,int at,byte[] needle){if(at<0 || at+needle.Length>b.Length)return false;for(int i=0;i<needle.Length;i++)if(b[at+i]!=needle[i])return false;return true;}
 static string Hash(byte[] b){using(SHA256 s=SHA256.Create())return BitConverter.ToString(s.ComputeHash(b)).Replace("-","").ToLowerInvariant();}
 static string Name(byte[] b){StringBuilder s=new StringBuilder();foreach(byte c in b)if(c>=32&&c<=126)s.Append((char)c);else s.Append("\\x"+c.ToString("X2"));return s.ToString();}
 static List<Chunk> Parse(byte[] b){
  List<Chunk> result=new List<Chunk>();long p=0;Require(b.Length>0,"Empty DAT");
  while(p<b.Length){Require(p+16<=b.Length,"Incomplete DAT chunk header");uint w=BitConverter.ToUInt32(b,(int)p+4);long n=((w>>7)&0x7ffff)*16L;Require(n>=16 && p+n<=b.Length,"Unsupported DAT chunk layout at 0x"+p.ToString("X"));result.Add(new Chunk{Start=(int)p,End=(int)(p+n),Type=(int)(w&127)});p+=n;}
  return result;
 }
 static string SafePath(string root,string rel){
  Require(rel!=null && Regex.IsMatch(rel,@"\AROM(?:[0-9]+)?/[0-9]+/[0-9]+\.dat\z",RegexOptions.IgnoreCase),"Expected ROM[number]/number/number.DAT path: "+rel);
  string basePath=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar)+Path.DirectorySeparatorChar;
  string path=Path.GetFullPath(Path.Combine(basePath,rel.Replace('/',Path.DirectorySeparatorChar)));
  Require(path.StartsWith(basePath,StringComparison.OrdinalIgnoreCase),"Path outside supplied folder");return path;
 }
 static bool Within(string child,string parent){return child.StartsWith(parent.TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)||String.Equals(child,parent,StringComparison.OrdinalIgnoreCase);}
 static byte[] Key1,Key2;
 public static void ConfigureGame(string folder){
  Key1=null;Key2=null;if(String.IsNullOrEmpty(folder))return;
  byte[] b=File.ReadAllBytes(Path.Combine(folder,"FFXiMain.dll"));
  Key1=Table(b,new byte[]{0xE2,0xE5,0x06,0xA9});Key2=Table(b,new byte[]{0xB8,0xC5,0xF7,0x84});
 }
 static byte[] Table(byte[] b,byte[] signature){int found=-1;for(int i=0x30000;i+256<=b.Length;i++)if(Match(b,i,signature)){Require(found<0,"Ambiguous game decoding table");found=i;}Require(found>=0,"Game decoding tables not recognized");byte[] r=new byte[256];Array.Copy(b,found,r,0,256);return r;}
 sealed class Mesh {public Chunk Chunk;public byte[] Plain;public int[] Map;public HashSet<int> Fields=new HashSet<int>();}
 static Mesh Decode(byte[] source,Chunk c){
  byte[] a=new byte[c.End-c.Start];Array.Copy(source,c.Start,a,0,a.Length);int[] map=new int[a.Length];for(int i=0;i<map.Length;i++)map[i]=i;
  Require(a.Length>=84,"Short MMB header");int mode=a[19];bool legacy=a[16]==77&&a[17]==77&&a[18]==66&&mode<=4;
  if(!legacy){
   Require(mode==5,"Unsupported MMB encoding version");Require(Key1!=null&&Key2!=null,"Choose the original game folder to validate encoded mesh references");
   int size=(int)(BitConverter.ToUInt32(a,16)&0xFFFFFF);Require(size>=8&&size<=a.Length-16,"Invalid encoded MMB size");int length=size-8;long state=Key1[a[21]^0xF0];
   for(int i=0;i<length;i++){int mask=((int)state&255)*257;state+=2L*i+1;a[24+i]^=(byte)(mask>>(int)(state&7));state+=2L*i+2;}
   if(a[22]==255&&a[23]==255){long k=a[21]^0xF0;state=Key2[(int)k];int half=(length&~15)/2;for(int i=0;i<half;i+=8){if((state&1)!=0)for(int j=0;j<8;j++){int x=24+i+j,y=24+half+i+j;byte t=a[x];a[x]=a[y];a[y]=t;int m=map[x];map[x]=map[y];map[y]=m;}k+=9;state+=k;}}
  }
  Mesh mesh=new Mesh{Chunk=c,Plain=a,Map=map};
  uint count0=BitConverter.ToUInt32(a,48);if(count0==0)return mesh;
  uint off=BitConverter.ToUInt32(a,76),count=BitConverter.ToUInt32(a,80);Require(off>=36&&off<a.Length-48&&count>0&&count<=4096,"Unsupported MMB material layout");
  long cursor=48L+off;int stride=(a[20]&2)!=0?48:36;
  for(uint m=0;m<count;m++){
   Require(cursor+20<=a.Length,"Truncated MMB material");int at=(int)cursor;
   for(int j=0;j<16;j++)Require(a[at+j]==0||(a[at+j]>=32&&a[at+j]<=126),"Invalid MMB material name");mesh.Fields.Add(at);
   int nv=BitConverter.ToUInt16(a,at+16);Require(nv>0,"Empty MMB vertex run");long indices=cursor+20L+nv*stride;Require(indices+4<=a.Length,"Truncated MMB vertices");int ni=BitConverter.ToUInt16(a,(int)indices);Require(ni>0&&indices+4L+ni*2<=a.Length,"Truncated MMB indices");for(int j=0;j<ni;j++)Require(BitConverter.ToUInt16(a,(int)indices+4+j*2)<nv,"MMB index outside vertex run");cursor=(indices+4L+ni*2+3)&~3L;
  }return mesh;
 }
 sealed class Binding {public List<int> Definitions=new List<int>(),References=new List<int>();public List<KeyValuePair<Mesh,int>> Encoded=new List<KeyValuePair<Mesh,int>>();}
 static Binding Bind(byte[] b,List<Chunk> chunks,byte[] id){
  Binding r=new Binding();
  foreach(Chunk c in chunks){
   if(c.Type==32){if(Match(b,c.Start+17,id))r.Definitions.Add(c.Start+17);continue;}
   if(c.Type==46){Mesh mesh=Decode(b,c);for(int at=16;at+16<=mesh.Plain.Length;at++)if(Match(mesh.Plain,at,id)){Require(mesh.Fields.Contains(at),"Unrecognized decoded MMB reference; no patch offered");r.Encoded.Add(new KeyValuePair<Mesh,int>(mesh,at));at+=15;}continue;}
   HashSet<int> fields=new HashSet<int>();
   if(c.Type==31){
    Require(c.End-c.Start>=24,"Short particle mesh");int marker=BitConverter.ToUInt16(b,c.Start+16)&15;Require(marker==5||marker==6,"Unsupported particle mesh marker");int mat=b[c.Start+20],total=mat+b[c.Start+21],slots=total%4==0?total:total+3-total%4;int start=c.Start+24+2*slots;long end=start+mat*16L+BitConverter.ToUInt16(b,c.Start+22)*108L;Require(end<=c.End,"Truncated particle materials or vertices");for(int j=0;j<mat;j++)fields.Add(start+j*16);
   }
   if(c.Type==33){Require(c.End-c.Start>=40,"Short sprite mesh");int cards=BitConverter.ToUInt16(b,c.Start+18);Require(cards>0&&c.Start+40L+cards*148L<=c.End,"Truncated sprite cards");fields.Add(c.Start+24);}
   for(int at=c.Start+16;at+16<=c.End;at++)if(Match(b,at,id)){
    bool known=fields.Contains(at)||(c.Type==42&&at>=c.Start+20&&b[at-4]==0&&b[at-3]==0&&b[at-2]==0&&b[at-1]==128);
    Require(known,"Unrecognized reference; no patch offered");r.References.Add(at);at+=15;
   }
  }
  Require(r.Definitions.Count>0,"Selected ID has no local definition");Require(r.References.Count+r.Encoded.Count>0,"No supported internal model reference found");return r;
 }
 public static DatInspection[] InspectFile(string suppliedRoot,string file,DatDefinition[] inventory,string[] candidateIDs){
  List<DatInspection> result=new List<DatInspection>();
  byte[] before=null;List<Chunk> chunks=null;string fileHash=null,error=null;
  try{
   before=File.ReadAllBytes(SafePath(suppliedRoot,file));fileHash=Hash(before);chunks=Parse(before);

   Dictionary<long,DatDefinition> expected=new Dictionary<long,DatDefinition>();
   foreach(DatDefinition d in inventory){Require(String.Equals(d.File,file,StringComparison.OrdinalIgnoreCase),"Inventory file mismatch");Require(!expected.ContainsKey(d.Offset),"Duplicate report offset");expected.Add(d.Offset,d);}
   int actual=0;
   foreach(Chunk c in chunks)if(c.Type==32){
    actual++;Require(c.End-c.Start>=33,"Short texture definition");DatDefinition d;
    Require(expected.TryGetValue(c.Start,out d)&&String.Equals(d.IDHex,Hex(before,c.Start+17,16),StringComparison.OrdinalIgnoreCase)&&d.ChunkBytes==c.End-c.Start&&d.Format==before[c.Start+16],"Texture headers differ from scan; run a fresh comparison");
   }
   Require(actual==inventory.Length,"Texture count differs from scan; run a fresh comparison");
  }catch(Exception ex){error=ex.Message;}
  foreach(string hex in candidateIDs){
   DatInspection item=new DatInspection{File=file,IDHex=hex,Sha256=fileHash};result.Add(item);
   if(error!=null){item.Reason=error;continue;}
   try{
    Binding binding=Bind(before,chunks,Unhex(hex));item.CanPatch=true;item.References=binding.References.Count+binding.Encoded.Count;item.Reason="Local definitions and supported internal references validated";
   }catch(Exception ex){item.Reason=ex.Message;}
  }
  return result.ToArray();
 }
 public static DatPatchResult PatchSelections(string suppliedRoot,string outputRoot,DatDefinition[] inventory,DatOptionalSelection[] selected,string[] occupiedIDs){
  string input=Path.GetFullPath(suppliedRoot),output=Path.GetFullPath(outputRoot);
  Require(!Within(output,input) && !Within(input,output),"Output and supplied DAT folders must be separate, not nested");
  Require(!Directory.Exists(output),"Output already exists; use a new output folder");
  HashSet<string> advancedFiles=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  Dictionary<string,string> selectedHashes=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
  Dictionary<string,HashSet<string>> choices=new Dictionary<string,HashSet<string>>(StringComparer.OrdinalIgnoreCase);
  foreach(DatOptionalSelection selection in selected){
   SafePath(input,selection.File);if(selection.Advanced)advancedFiles.Add(selection.File);HashSet<string> set;
   if(!choices.TryGetValue(selection.File,out set)){set=new HashSet<string>(StringComparer.Ordinal);choices.Add(selection.File,set);}
   set.Add(Hex(Unhex(selection.IDHex),0,16));
   Require(!String.IsNullOrEmpty(selection.ExpectedSha256),"Missing assessment hash");
   if(selectedHashes.ContainsKey(selection.File))Require(selectedHashes[selection.File]==selection.ExpectedSha256,"Conflicting assessment hashes");else selectedHashes.Add(selection.File,selection.ExpectedSha256);
  }
  Require(choices.Count>0,"No texture rows selected");
  HashSet<string> usedIDs=new HashSet<string>(StringComparer.Ordinal),usedSuffixes=new HashSet<string>(StringComparer.Ordinal);
  foreach(string id in occupiedIDs){string hex=Hex(Unhex(id),0,16);usedIDs.Add(hex);usedSuffixes.Add(hex.Substring(16));}
  Dictionary<string,List<DatDefinition>> files=new Dictionary<string,List<DatDefinition>>(StringComparer.OrdinalIgnoreCase);
  foreach(DatDefinition row in inventory){
   if(!choices.ContainsKey(row.File))continue;
   SafePath(input,row.File);row.IDHex=Hex(Unhex(row.IDHex),0,16);
   List<DatDefinition> f;if(!files.TryGetValue(row.File,out f)){f=new List<DatDefinition>();files.Add(row.File,f);}f.Add(row);
  }
  List<string> paths=new List<string>(files.Keys);paths.Sort(StringComparer.OrdinalIgnoreCase);
  DatPatchResult result=new DatPatchResult();Directory.CreateDirectory(output);
  foreach(string rel in paths){
   HashSet<string> selectedSet=choices[rel];
   List<DatDefinition> reported=files[rel];bool wanted=false;foreach(DatDefinition d in reported)if(selectedSet.Contains(d.IDHex))wanted=true;if(!wanted)continue;
   string source=SafePath(input,rel);
   Require(File.Exists(source),"Selected DAT was not supplied: "+rel);
   byte[] before=File.ReadAllBytes(source);Require(Hash(before)==selectedHashes[rel],"DAT changed since assessment: "+rel);List<Chunk> chunks=Parse(before);

   Dictionary<long,DatDefinition> expected=new Dictionary<long,DatDefinition>();foreach(DatDefinition d in reported){Require(!expected.ContainsKey(d.Offset),"Duplicate report definition: "+rel);expected.Add(d.Offset,d);}
   int actual=0;
   Dictionary<string,List<int>> definitions=new Dictionary<string,List<int>>(StringComparer.Ordinal);
   foreach(Chunk c in chunks)if(c.Type==32){
    Require(c.End-c.Start>=33,"Short texture chunk: "+rel);actual++;
    string id=Hex(before,c.Start+17,16);DatDefinition d;
    Require(expected.TryGetValue(c.Start,out d) && d.IDHex==id && d.ChunkBytes==c.End-c.Start && d.Format==before[c.Start+16],"DAT texture headers differ from the report: "+rel+". Run a new comparison first.");
    if(selectedSet.Contains(id)){List<int> ds;if(!definitions.TryGetValue(id,out ds)){ds=new List<int>();definitions.Add(id,ds);}ds.Add(c.Start+17);}
   }
   Require(actual==reported.Count,"DAT texture inventory differs from report: "+rel);
   Require(definitions.Count==selectedSet.Count,"A selected texture is absent from this file: "+rel);
   byte[] after=(byte[])before.Clone();DatPatchRecord record=new DatPatchRecord{IncludesOptional=advancedFiles.Contains(rel),File=rel,FileBytes=before.Length,OriginalSha256=Hash(before)};
   List<string> keys=new List<string>(definitions.Keys);keys.Sort(StringComparer.Ordinal);
   foreach(string oldHex in keys){

    byte[] old=Unhex(oldHex),replacement=null;string newHex=null;
    for(int attempt=0;attempt<1000;attempt++){
     byte[] random=new byte[8];using(RandomNumberGenerator rng=RandomNumberGenerator.Create())rng.GetBytes(random);
     string randomHex=BitConverter.ToString(random).Replace("-","");
     // Both halves are 8 printable bytes. The final 8 bytes carry 28 random bits.
     replacement=Encoding.ASCII.GetBytes("LB"+randomHex.Substring(0,6)+"T"+randomHex.Substring(6,7));newHex=Hex(replacement,0,16);
     if(!usedIDs.Contains(newHex)&&!usedSuffixes.Contains(newHex.Substring(16)))break;
     replacement=null;
    }
    Require(replacement!=null,"Could not allocate an unused suffix");usedIDs.Add(newHex);usedSuffixes.Add(newHex.Substring(16));
    DatNameChange change=new DatNameChange{OldHex=oldHex,NewHex=newHex,OldName=Name(old),NewName=Name(replacement)};
    Binding binding=Bind(before,chunks,old);
    foreach(int p in binding.Definitions){Require(Match(after,p,old),"Overlapping definitions");Array.Copy(replacement,0,after,p,16);change.DefinitionOffsets.Add(p);}
    foreach(int p in binding.References){Require(Match(after,p,old),"Overlapping references");Array.Copy(replacement,0,after,p,16);change.ReferenceOffsets.Add(p);}
    foreach(KeyValuePair<Mesh,int> entry in binding.Encoded){
     Mesh mesh=entry.Key;int at=entry.Value;DatEncodedField field=new DatEncodedField();byte[] rawOld=new byte[16],rawNew=new byte[16];
     for(int j=0;j<16;j++){int p=mesh.Chunk.Start+mesh.Map[at+j];Require(after[p]==before[p],"Overlapping encoded reference edits");rawOld[j]=before[p];rawNew[j]=(byte)(before[p]^old[j]^replacement[j]);after[p]=rawNew[j];field.SourceOffsets.Add(p);}
     field.BeforeHex=Hex(rawOld,0,16);field.AfterHex=Hex(rawNew,0,16);change.EncodedReferences.Add(field);
    }
    record.Changes.Add(change);
   }
   // Reversing only recorded ID edits must reproduce EVERY original byte.
   byte[] reversed=(byte[])after.Clone();
   foreach(DatNameChange c in record.Changes){
    byte[] old=Unhex(c.OldHex),n=Unhex(c.NewHex);
    foreach(int p in c.DefinitionOffsets){Require(Match(after,p,n),"Definition mismatch");Array.Copy(old,0,reversed,p,16);}
    foreach(int p in c.ReferenceOffsets){Require(Match(after,p,n),"Reference mismatch");Array.Copy(old,0,reversed,p,16);}
    foreach(DatEncodedField f in c.EncodedReferences){byte[] a=Unhex(f.AfterHex),o=Unhex(f.BeforeHex);Require(f.SourceOffsets.Count==16,"Invalid encoded undo record");for(int j=0;j<16;j++){int p=f.SourceOffsets[j];Require(after[p]==a[j],"Encoded reference mismatch");reversed[p]=o[j];}}
   }
   Require(Equal(before,reversed),"Byte preservation verification failed");Parse(after);
   foreach(Chunk chunk in chunks)if(chunk.Type==46){Mesh original=Decode(before,chunk),modified=Decode(after,chunk);byte[] expectedPlain=(byte[])original.Plain.Clone();foreach(DatNameChange change in record.Changes){byte[] oldID=Unhex(change.OldHex),newID=Unhex(change.NewHex);foreach(int at in original.Fields)if(Match(original.Plain,at,oldID))Array.Copy(newID,0,expectedPlain,at,16);}Require(Equal(expectedPlain,modified.Plain),"Decoded mesh preservation verification failed");}
   record.PatchedSha256=Hash(after);
   string dest=SafePath(output,rel);Directory.CreateDirectory(Path.GetDirectoryName(dest));File.WriteAllBytes(dest,after);
   Require(Hash(File.ReadAllBytes(dest))==record.PatchedSha256,"Written file verification failed");result.Files.Add(record);
   Console.WriteLine("Patched copy: "+rel+" ("+record.Changes.Count+" texture IDs)");
  }
  Require(result.Files.Count==choices.Count,"Selection file list does not match report");
  Require(result.Files.Count>0,"No matching DATs supplied. Choose the folder CONTAINING ROM, not ROM itself.");
  return result;
 }
 public static void Restore(string patchedRoot,string outputRoot,DatPatchRecord[] records){
  string input=Path.GetFullPath(patchedRoot),output=Path.GetFullPath(outputRoot);
  Require(!Within(output,input)&&!Within(input,output),"Restore output must be separate from supplied folders");Require(!Directory.Exists(output),"Restore output already exists");Directory.CreateDirectory(output);
  foreach(DatPatchRecord record in records){
   string path=SafePath(input,record.File);byte[] b=File.ReadAllBytes(path);Require(Hash(b)==record.PatchedSha256,"Patched file has changed; refusing restore: "+record.File);
   foreach(DatNameChange c in record.Changes){
    byte[] old=Unhex(c.OldHex),n=Unhex(c.NewHex);
    foreach(int p in c.DefinitionOffsets){Require(Match(b,p,n),"Restore definition mismatch");Array.Copy(old,0,b,p,16);}
    foreach(int p in c.ReferenceOffsets){Require(Match(b,p,n),"Restore reference mismatch");Array.Copy(old,0,b,p,16);}
    foreach(DatEncodedField f in c.EncodedReferences){byte[] a=Unhex(f.AfterHex),o=Unhex(f.BeforeHex);Require(f.SourceOffsets.Count==16,"Invalid encoded undo record");for(int j=0;j<16;j++){int p=f.SourceOffsets[j];Require(p>=0&&p<b.Length&&b[p]==a[j],"Restore encoded reference mismatch");b[p]=o[j];}}
   }
   Require(Hash(b)==record.OriginalSha256,"Restored source hash mismatch: "+record.File);string dest=SafePath(output,record.File);Directory.CreateDirectory(Path.GetDirectoryName(dest));File.WriteAllBytes(dest,b);
  }
 }
}
