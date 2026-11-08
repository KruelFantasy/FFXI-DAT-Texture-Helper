using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Diagnostics;

public static class DatTextureComparisonV2
{
    sealed class IdInfo {
        public string Hex, Name, Suffix;
        public long Original, Custom, Effective;
        public List<string> OriginalSamples = new List<string>();
        public List<string> CustomSamples = new List<string>();
    }
    sealed class CustomFile {
        public string Path;
        public bool Complete, OriginalSeen, OriginalComplete;
        public HashSet<string> Ids = new HashSet<string>(StringComparer.Ordinal);
        public HashSet<string> OriginalIds = new HashSet<string>(StringComparer.Ordinal);
    }
    sealed class Row {
        public string File, Hex, Offset;
        public long Bytes;
        public byte Format;
    }
    sealed class Stats {
        public long Files, Errors, Textures, Excluded, EnumerationErrors;
    }
    static Dictionary<string, IdInfo> ids;
    static Dictionary<string, CustomFile> customFiles;
    static List<Row> customRows;
    static Regex canonical = new Regex(@"^ROM(?:[0-9]+)?/[0-9]+/[0-9]+\.dat$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    static string Csv(string s) { return "\"" + (s ?? "").Replace("\"", "\"\"") + "\""; }
    static void Write(StreamWriter w, params object[] cells) {
        for (int i=0; i<cells.Length; i++) {
            if(i>0) w.Write(','); w.Write(Csv(Convert.ToString(cells[i], System.Globalization.CultureInfo.InvariantCulture)));
        }
        w.WriteLine();
    }
    static StreamWriter Writer(string folder, string name, params object[] headers) {
        StreamWriter w = new StreamWriter(Path.Combine(folder,name), false, new UTF8Encoding(true));
        Write(w,headers); return w;
    }
    static string Display(byte[] b, int at, int n) {
        StringBuilder s=new StringBuilder();
        for(int i=at;i<at+n;i++) {
            if(b[i]>=32 && b[i]<=126) s.Append((char)b[i]); else s.Append("\\x"+b[i].ToString("X2"));
        }
        return s.ToString();
    }
    static void Sample(List<string> list,string path) { if(list.Count<6 && !list.Contains(path)) list.Add(path); }
    static string Root(string p) { return Path.GetFullPath(p).TrimEnd(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar); }
    static string Relative(string root,string path) { return path.Substring(root.Length).TrimStart(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar).Replace('\\','/'); }
    static Stats Scan(string root, bool custom, string output, StreamWriter errors, StreamWriter excluded) {
        Stats stats=new Stats(); Stack<string> dirs=new Stack<string>(); dirs.Push(root);
        Stopwatch clock=Stopwatch.StartNew();
        using(StreamWriter all=Writer(output,custom?"Custom-textures.csv":"Original-textures.csv","File","ChunkOffset","ChunkBytes","FormatByte","TextureID","IDHex","SuffixHex","EightSpaceSuffix","OriginalFileReplaced")) {
            while(dirs.Count>0) {
                string dir=dirs.Pop(); string[] children;
                try { children=Directory.GetDirectories(dir); }
                catch(Exception ex) { stats.EnumerationErrors++; Write(errors,custom?"Custom":"Original",Relative(root,dir),"Directory enumeration",ex.Message.Replace(root,"<root>")); children=new string[0]; }
                foreach(string child in children) {
                    try {
                        if((File.GetAttributes(child)&FileAttributes.ReparsePoint)!=0) {Write(excluded,custom?"Custom":"Original",Relative(root,child),"Reparse-point directory skipped");stats.Excluded++;}
                        else dirs.Push(child);
                    } catch(Exception ex) {stats.EnumerationErrors++; Write(errors,custom?"Custom":"Original",Relative(root,child),"Directory attributes",ex.Message.Replace(root,"<root>"));}
                }
                string[] files;
                try { files=Directory.GetFiles(dir,"*.dat"); }
                catch(Exception ex) {stats.EnumerationErrors++;Write(errors,custom?"Custom":"Original",Relative(root,dir),"File enumeration",ex.Message.Replace(root,"<root>"));continue;}
                Array.Sort(files,StringComparer.OrdinalIgnoreCase);
                foreach(string path in files) {
                    string rel=Relative(root,path);
                    if(!canonical.IsMatch(rel)) {stats.Excluded++;Write(excluded,custom?"Custom":"Original",rel,"Outside ROM[number]/number/number.DAT path; not included in texture comparison");continue;}
                    stats.Files++;
                    CustomFile cf=null;
                    if(custom) {cf=new CustomFile();cf.Path=rel;customFiles.Add(rel,cf);}
                    else if(customFiles.TryGetValue(rel,out cf)) cf.OriginalSeen=true;
                    try {
                        using(FileStream stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read,4096,FileOptions.RandomAccess)) {
                            byte[] header=new byte[33];long offset=0;
                            if(stream.Length==0) throw new InvalidDataException("Empty file: no supported chunk structure");
                            while(offset<stream.Length) {
                                if(stream.Length-offset<16) throw new InvalidDataException("Incomplete chunk header at 0x"+offset.ToString("X"));
                                stream.Position=offset;int want=(int)Math.Min(33,stream.Length-offset), got=0;
                                while(got<want) {int n=stream.Read(header,got,want-got);if(n==0)throw new EndOfStreamException();got+=n;}
                                uint word=BitConverter.ToUInt32(header,4);long length=((word>>7)&0x7ffff)*16L;uint kind=word&127;
                                if(length<16 || length>stream.Length-offset) throw new InvalidDataException("Unsupported or invalid chunk layout at 0x"+offset.ToString("X"));
                                if(kind==32) {
                                    if(length<33) throw new InvalidDataException("Short texture chunk at 0x"+offset.ToString("X"));
                                    string hex=BitConverter.ToString(header,17,16).Replace("-","");
                                    IdInfo info;
                                    if(!ids.TryGetValue(hex,out info)) {info=new IdInfo();info.Hex=hex;info.Name=Display(header,17,16);info.Suffix=hex.Substring(16,16);ids.Add(hex,info);}
                                    if(custom) {
                                        info.Custom++;info.Effective++;Sample(info.CustomSamples,rel);cf.Ids.Add(hex);
                                        customRows.Add(new Row { File=rel,Hex=hex,Offset="0x"+offset.ToString("X"),Bytes=length,Format=header[16] });
                                    } else {
                                        info.Original++;Sample(info.OriginalSamples,rel);
                                        if(cf==null) info.Effective++; else cf.OriginalIds.Add(hex);
                                    }
                                    stats.Textures++;
                                    Write(all,rel,"0x"+offset.ToString("X"),length,header[16],info.Name,hex,info.Suffix,info.Suffix=="2020202020202020",!custom&&cf!=null);
                                }
                                offset+=length;
                            }
                        }
                        if(cf!=null) {if(custom)cf.Complete=true;else cf.OriginalComplete=true;}
                    } catch(Exception ex) {
                        stats.Errors++;Write(errors,custom?"Custom":"Original",rel,"File read/parse (partial rows may exist)",ex.Message.Replace(root,"<root>"));
                    }
                    if(clock.ElapsedMilliseconds>2000) {
                        Console.WriteLine((custom?"Custom":"Original")+": "+stats.Files+" DATs examined; "+stats.Textures+" texture entries; "+stats.Errors+" incomplete files. "+rel);clock.Restart();
                    }
                }
            }
        }
        return stats;
    }
    public static void Run(string originalRoot,string customRoot,string output) {
        string original=Root(originalRoot),custom=Root(customRoot);
        if(String.Equals(original,custom,StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Select different original and custom folders.");
        if(!Directory.Exists(original)||!Directory.Exists(custom)) throw new DirectoryNotFoundException("Selected folder does not exist.");
        if(!Directory.Exists(Path.Combine(original,"ROM"))||!Directory.Exists(Path.Combine(custom,"ROM"))) throw new ArgumentException("Choose each parent folder containing ROM, not ROM itself. If using multiple XIPivot packs, scan each pack separately.");
        Directory.CreateDirectory(output);
        ids=new Dictionary<string,IdInfo>(StringComparer.Ordinal);
        customFiles=new Dictionary<string,CustomFile>(StringComparer.OrdinalIgnoreCase);
        customRows=new List<Row>();
        Stats cs,os;
        using(StreamWriter errors=Writer(output,"Incomplete-files.csv","Collection","File","Stage","Details"))
        using(StreamWriter excluded=Writer(output,"Excluded-paths.csv","Collection","Path","Reason")) {
            Console.WriteLine("Scanning custom DATs first...");cs=Scan(custom,true,output,errors,excluded);
            Console.WriteLine("Scanning original DATs. Non-model DAT formats may be reported as unsupported; this does not mean they are damaged.");os=Scan(original,false,output,errors,excluded);
        }
        if(cs.Files==0||os.Files==0) throw new InvalidOperationException("No canonical DAT files found in one collection. Partial reports were kept; check selected folders.");
        Dictionary<string,List<IdInfo>> suffixes=new Dictionary<string,List<IdInfo>>(StringComparer.Ordinal);
        List<string> sorted=new List<string>(ids.Keys);sorted.Sort(StringComparer.Ordinal);
        foreach(string hex in sorted) {
            IdInfo info=ids[hex];List<IdInfo> group;
            if(!suffixes.TryGetValue(info.Suffix,out group)) {group=new List<IdInfo>();suffixes.Add(info.Suffix,group);}group.Add(info);
        }
        long blank=0,newGlobal=0,changedNames=0;
        using(StreamWriter summary=Writer(output,"Texture-ID-summary.csv","TextureID","IDHex","SuffixHex","OriginalOccurrences","CustomOccurrences","EffectiveOccurrences","OriginalSampleFiles_MAX6","CustomSampleFiles_MAX6")) {
            foreach(string hex in sorted) {IdInfo t=ids[hex];Write(summary,t.Name,t.Hex,t.Suffix,t.Original,t.Custom,t.Effective,String.Join(" | ",t.OriginalSamples.ToArray()),String.Join(" | ",t.CustomSamples.ToArray()));}
        }
        using(StreamWriter candidates=Writer(output,"Custom-comparison.csv","File","ChunkOffset","TextureID","IDHex","SuffixHex","EightSpaceSuffix","OriginalSamePathStatus","PresentInOriginalSamePath","NewNameInThisReplacement","AbsentFromParsedOriginalCollection","OtherOriginalIDsWithSameSuffix","OtherEffectiveIDsWithSameSuffix","CustomFileComplete"))
        using(StreamWriter blanks=Writer(output,"Blank-suffix-candidates.csv","File","ChunkOffset","TextureID","IDHex","PresentInOriginalSamePath","OriginalSamePathStatus","OriginalOccurrences","CustomOccurrences","Interpretation")) {
            foreach(Row row in customRows) {
                IdInfo t=ids[row.Hex];CustomFile cf=customFiles[row.File];bool same=cf.OriginalIds.Contains(t.Hex);
                string status=!cf.OriginalSeen?"Not found":cf.OriginalComplete?"Fully parsed":"Incomplete";
                string introduced= !cf.OriginalSeen||!cf.OriginalComplete||!cf.Complete?"Unknown":same?"No":"Yes";
                int otherOriginal=0,otherEffective=0;
                foreach(IdInfo other in suffixes[t.Suffix]) {if(other.Hex!=t.Hex) {if(other.Original>0)otherOriginal++;if(other.Effective>0)otherEffective++;}}
                bool isBlank=t.Suffix=="2020202020202020";
                Write(candidates,row.File,row.Offset,t.Name,t.Hex,t.Suffix,isBlank,status,same,introduced,t.Original==0,otherOriginal,otherEffective,cf.Complete);
                if(isBlank) {blank++;Write(blanks,row.File,row.Offset,t.Name,t.Hex,same,status,t.Original,t.Custom,"Potential blank-material fallback match; NOT a confirmed crash cause");}
                if(t.Original==0)newGlobal++;
                if(introduced=="Yes")changedNames++;
            }
        }
        using(StreamWriter matches=Writer(output,"Custom-to-original-suffix-matches.csv","CustomTextureID","CustomIDHex","OriginalTextureID","OriginalIDHex","SameFullID","OriginalOccurrences","OriginalSampleFiles_MAX6")) {
            foreach(string hex in sorted) {
                IdInfo c=ids[hex];if(c.Custom==0)continue;
                foreach(IdInfo o in suffixes[c.Suffix]) if(o.Original>0) Write(matches,c.Name,c.Hex,o.Name,o.Hex,c.Hex==o.Hex,o.Original,String.Join(" | ",o.OriginalSamples.ToArray()));
            }
        }
        using(StreamWriter coverage=Writer(output,"Replacement-coverage.csv","CustomFile","CustomFullyParsed","OriginalSamePathFound","OriginalSamePathFullyParsed","CustomDistinctIDs","OriginalDistinctIDs")) {
            List<string> paths=new List<string>(customFiles.Keys);paths.Sort(StringComparer.OrdinalIgnoreCase);
            foreach(string path in paths) {CustomFile c=customFiles[path];Write(coverage,path,c.Complete,c.OriginalSeen,c.OriginalComplete,c.Ids.Count,c.OriginalIds.Count);}
        }
        string limitations="\r\nInterpretation and limits:\r\n"+
            "All findings are candidates, not confirmed crash causes. Repeated names can be intentional.\r\n"+
            "Eight-space suffixes can match the investigated blank-material fallback even without an identical full name elsewhere.\r\n"+
            "Only type-0x20 texture definitions in supported chunk layouts are inventoried. Model material references, encoded models, and runtime flags/scopes/lifetimes are NOT analyzed.\r\n"+
            "AbsentFromParsedOriginalCollection means absent among readable texture definitions, NOT guaranteed absent from the game.\r\n"+
            "Effective occurrences approximate original files minus replaced paths plus the selected custom pack. They do not represent textures simultaneously loaded at runtime.\r\n"+
            "Other XIPivot packs, pack priority, original files modified on disk, and partial/unsupported files can change conclusions.\r\n"+
            "Only ROM[number]/number/number.DAT paths are compared. Backup/nested paths and reparse directories are excluded and listed.\r\n"+
            "An incomplete parse does not establish corruption. Partial texture rows remain in inventories.\r\n"+
            "Paths in reports are relative. Original/custom sample lists are capped at six; full inventories contain every observed occurrence.\r\n"+
            "No source DAT was written or renamed.\r\n";
        string text="DAT TEXTURE COMPARISON v2\r\n"+
            "Custom DATs examined: "+cs.Files+"\r\nCustom texture entries: "+cs.Textures+"\r\nCustom incomplete files: "+cs.Errors+"\r\n"+
            "Original DATs examined: "+os.Files+"\r\nOriginal texture entries: "+os.Textures+"\r\nOriginal incomplete files: "+os.Errors+"\r\n"+
            "Directory access/enumeration errors: "+(cs.EnumerationErrors+os.EnumerationErrors)+"\r\nExcluded paths/directories: "+(cs.Excluded+os.Excluded)+"\r\n"+
            "Custom blank-suffix texture occurrences: "+blank+"\r\nCustom occurrences absent from parsed original texture inventory: "+newGlobal+"\r\nCustom occurrences with IDs absent from fully parsed original same-path DAT: "+changedNames+"\r\n"+limitations;
        File.WriteAllText(Path.Combine(output,"Summary.txt"),text,new UTF8Encoding(true));
        Console.WriteLine(text);
    }
}
