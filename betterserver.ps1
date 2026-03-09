# ============================================================
#  FileServe — PowerShell HTTP File Server
#  Save this file as UTF-8 (with or without BOM) to preserve
#  any emoji/Unicode characters in the output.
# ============================================================

param(
    [string]$Path         = (Get-Location).Path,
    [int]$Port            = 8080,
    [string]$Title        = "FileServe",
    [switch]$AllowUpload,
    [switch]$ShowHidden,
    [switch]$LogRequests,
    [switch]$OpenBrowser,
    [string]$Auth         = "",
    [int]$MaxUploadMB     = 100
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

#region ── Startup Checks ────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  ERROR  Requires administrator privileges. Run as Administrator." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Host "  ERROR  Path not found: $Path" -ForegroundColor Red
    exit 1
}
$rootPath = (Resolve-Path -Path $Path).Path
#endregion

#region ── Auth Setup ────────────────────────────────────────
$useAuth      = $false
$authExpected = ""
if ($Auth -ne "") {
    $parts = $Auth -split ":", 2
    if ($parts.Count -eq 2) {
        $useAuth      = $true
        $authExpected = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Auth))
    } else {
        Write-Host "  WARN   Auth must be 'user:password'. Auth disabled." -ForegroundColor Yellow
    }
}
#endregion

#region ── MIME Types ────────────────────────────────────────
$mimeTypes = @{
    ".html"=  "text/html; charset=utf-8";  ".htm"=  "text/html; charset=utf-8"
    ".css"=   "text/css; charset=utf-8";   ".js"=   "application/javascript; charset=utf-8"
    ".json"=  "application/json";          ".xml"=  "application/xml"
    ".txt"=   "text/plain; charset=utf-8"; ".md"=   "text/plain; charset=utf-8"
    ".csv"=   "text/csv; charset=utf-8";   ".log"=  "text/plain; charset=utf-8"
    ".png"=   "image/png";                 ".jpg"=  "image/jpeg"; ".jpeg"= "image/jpeg"
    ".gif"=   "image/gif";                 ".svg"=  "image/svg+xml"; ".webp"= "image/webp"
    ".ico"=   "image/x-icon";             ".bmp"=  "image/bmp"
    ".mp4"=   "video/mp4";                ".webm"= "video/webm"; ".avi"= "video/x-msvideo"
    ".mp3"=   "audio/mpeg";               ".wav"=  "audio/wav"; ".ogg"= "audio/ogg"; ".flac"= "audio/flac"
    ".pdf"=   "application/pdf"
    ".zip"=   "application/zip";          ".gz"=   "application/gzip"; ".tar"= "application/x-tar"
    ".7z"=    "application/x-7z-compressed"; ".rar"= "application/x-rar-compressed"
    ".woff"=  "font/woff";                ".woff2"= "font/woff2"; ".ttf"= "font/ttf"
    ".ps1"=   "text/plain; charset=utf-8"; ".py"=  "text/plain; charset=utf-8"
    ".sh"=    "text/plain; charset=utf-8"; ".bat"= "text/plain; charset=utf-8"
    ".go"=    "text/plain; charset=utf-8"; ".rs"=  "text/plain; charset=utf-8"
    ".ts"=    "text/plain; charset=utf-8"; ".jsx"= "text/plain; charset=utf-8"
    ".java"=  "text/plain; charset=utf-8"; ".c"=   "text/plain; charset=utf-8"
    ".cpp"=   "text/plain; charset=utf-8"; ".cs"=  "text/plain; charset=utf-8"
    ".rb"=    "text/plain; charset=utf-8"; ".php"= "text/plain; charset=utf-8"
    ".sql"=   "text/plain; charset=utf-8"; ".yaml"="text/plain; charset=utf-8"
    ".yml"=   "text/plain; charset=utf-8"; ".toml"="text/plain; charset=utf-8"
    ".ini"=   "text/plain; charset=utf-8"; ".conf"="text/plain; charset=utf-8"
}
#endregion

#region ── Helper Functions ──────────────────────────────────

function ConvertTo-HtmlEncoded([string]$s) {
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

function Get-MimeType([string]$ext) {
    $ext = $ext.ToLower()
    if ($script:mimeTypes.ContainsKey($ext)) { return $script:mimeTypes[$ext] }
    return "application/octet-stream"
}

function Format-FileSize([long]$bytes) {
    if ($bytes -lt 1KB)  { return "$bytes B" }
    if ($bytes -lt 1MB)  { return "{0:N1} KB" -f ($bytes / 1KB) }
    if ($bytes -lt 1GB)  { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N2} GB" -f ($bytes / 1GB)
}

function Get-FileIcon($item) {
    if ($item.PSIsContainer) { return "&#128194;" } # 📂
    switch ($item.Extension.ToLower()) {
        { $_ -in @(".png",".jpg",".jpeg",".gif",".svg",".webp",".bmp",".ico") } { return "&#128247;" } # 🖼
        { $_ -in @(".mp4",".avi",".mov",".mkv",".webm",".flv") }               { return "&#127909;" } # 🎬
        { $_ -in @(".mp3",".wav",".ogg",".flac",".aac",".m4a") }               { return "&#127925;" } # 🎵
        { $_ -in @(".zip",".gz",".tar",".7z",".rar",".bz2") }                  { return "&#128230;" } # 📦
        { $_ -in @(".pdf") }                                                     { return "&#128213;" } # 📕
        { $_ -in @(".doc",".docx") }                                            { return "&#128196;" } # 📄
        { $_ -in @(".xls",".xlsx",".csv") }                                     { return "&#128202;" } # 📊
        { $_ -in @(".ppt",".pptx") }                                            { return "&#128202;" }
        { $_ -in @(".html",".htm",".css") }                                     { return "&#127758;" } # 🌐
        { $_ -in @(".js",".ts",".jsx",".vue") }                                 { return "&#9889;"   } # ⚡
        { $_ -in @(".py",".rb",".go",".rs",".java",".c",".cpp",".cs",".php") } { return "&#9881;"   } # ⚙
        { $_ -in @(".ps1",".sh",".bat",".cmd") }                               { return "&#128187;"  } # 💻
        { $_ -in @(".json",".xml",".yaml",".yml",".toml",".ini",".conf") }     { return "&#128295;"  } # 🔧
        { $_ -in @(".exe",".dll",".msi") }                                      { return "&#9881;"   }
        default                                                                  { return "&#128196;" } # 📄
    }
}

function Send-Response($response, [int]$status, [string]$contentType, [byte[]]$body) {
    $response.StatusCode      = $status
    $response.ContentType     = $contentType
    $response.ContentLength64 = $body.Length
    $response.OutputStream.Write($body, 0, $body.Length)
    $response.OutputStream.Close()
}

function Send-Html($response, [string]$html, [int]$status = 200) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
    Send-Response $response $status "text/html; charset=utf-8" $bytes
}

function Get-BreadcrumbHtml([string]$reqPath) {
    $html = "<a href='/'>~</a>"
    if ($reqPath -eq '' -or $reqPath -eq '.') { return $html }
    $parts = $reqPath.TrimStart('/').TrimEnd('/') -split '/'
    $acc = ""
    foreach ($part in $parts) {
        if ($part -eq '') { continue }
        $acc += "/$part"
        $enc  = ConvertTo-HtmlEncoded $part
        $html += "<span class='sep'> / </span><a href='${acc}/'>$enc</a>"
    }
    return $html
}

function Get-DirectoryPage([string]$reqPath, [string]$fullPath) {
    $gcArgs = @{ Path = $fullPath; ErrorAction = 'SilentlyContinue' }
    if ($script:ShowHidden) { $gcArgs['Force'] = $true }
    $allItems    = Get-ChildItem @gcArgs
    $folders     = @($allItems | Where-Object { $_.PSIsContainer } | Sort-Object Name)
    $files       = @($allItems | Where-Object { -not $_.PSIsContainer } | Sort-Object Name)
    $folderCount = $folders.Count
    $fileCount   = $files.Count
    $totalBytes  = ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if ($null -eq $totalBytes) { $totalBytes = 0 }
    $totalSize   = Format-FileSize $totalBytes
    $breadcrumb  = Get-BreadcrumbHtml $reqPath
    $displayPath = if ($reqPath -eq '' -or $reqPath -eq '.') { "/" } else { "/$reqPath/" }

    $sb = [System.Text.StringBuilder]::new()

    # Parent directory link
    if ($reqPath -ne '' -and $reqPath -ne '.') {
        $parent     = Split-Path ($reqPath.TrimEnd('/')) -Parent
        $parentHref = if ($parent -and $parent -ne '.') { "/$parent/" } else { "/" }
        $null = $sb.Append("<a class=`"file-item`" href=`"$parentHref`" data-name=`"..`" data-type=`"folder`" data-size=`"0`" data-date=`"0`">")
        $null = $sb.Append("<span class=`"file-icon`">&#8592;</span>")
        $null = $sb.Append("<span class=`"file-name folder-name`">..</span>")
        $null = $sb.Append("<span class=`"file-date`">&#8212;</span>")
        $null = $sb.Append("<span class=`"file-size`">&#8212;</span></a>")
    }

    foreach ($f in $folders) {
        $name    = $f.Name
        $enc     = ConvertTo-HtmlEncoded $name
        $href    = if ($reqPath -eq '' -or $reqPath -eq '.') { "/$name/" } else { "/$reqPath/$name/" }
        $icon    = Get-FileIcon $f
        $dateSrt = $f.LastWriteTime.ToString("yyyy-MM-dd")
        $dateFmt = $f.LastWriteTime.ToString("MMM dd, yyyy")
        $null = $sb.Append("<a class=`"file-item`" href=`"$href`" data-name=`"$($name.ToLower())`" data-type=`"folder`" data-size=`"0`" data-date=`"$dateSrt`">")
        $null = $sb.Append("<span class=`"file-icon`">$icon</span>")
        $null = $sb.Append("<span class=`"file-name folder-name`">$enc</span>")
        $null = $sb.Append("<span class=`"file-date`">$dateFmt</span>")
        $null = $sb.Append("<span class=`"file-size`">&#8212;</span></a>")
    }

    foreach ($f in $files) {
        $name    = $f.Name
        $enc     = ConvertTo-HtmlEncoded $name
        $href    = if ($reqPath -eq '' -or $reqPath -eq '.') { "/$name" } else { "/$reqPath/$name" }
        $icon    = Get-FileIcon $f
        $dateSrt = $f.LastWriteTime.ToString("yyyy-MM-dd")
        $dateFmt = $f.LastWriteTime.ToString("MMM dd, yyyy")
        $sizeStr = Format-FileSize $f.Length
        $extEnc  = ConvertTo-HtmlEncoded $f.Extension
        $baseEnc = ConvertTo-HtmlEncoded $f.BaseName
        $extHtml = if ($f.Extension) { "<span class=`"ext`">$extEnc</span>" } else { "" }
        $null = $sb.Append("<a class=`"file-item`" href=`"$href`" data-name=`"$($name.ToLower())`" data-type=`"file`" data-size=`"$($f.Length)`" data-date=`"$dateSrt`">")
        $null = $sb.Append("<span class=`"file-icon`">$icon</span>")
        $null = $sb.Append("<span class=`"file-name`">$baseEnc$extHtml</span>")
        $null = $sb.Append("<span class=`"file-date`">$dateFmt</span>")
        $null = $sb.Append("<span class=`"file-size`">$sizeStr</span></a>")
    }

    if ($sb.Length -eq 0) {
        $null = $sb.Append('<div class="empty"><div class="empty-ico">&#127756;</div><h3>EMPTY DIRECTORY</h3></div>')
    }

    # Upload parts
    $uploadButton = ""
    $uploadZone   = ""
    $uploadJs     = ""
    if ($script:AllowUpload) {
        $uploadButton = '<button class="btn btn-primary" onclick="toggleUpload()">Upload</button>'
        $uploadZone = @'
<div class="upload-zone" id="uploadZone" style="display:none" onclick="document.getElementById('fileInput').click()">
  <div class="upload-icon">&#128228;</div>
  <h3>Drop Files to Upload</h3>
  <p>Click anywhere here, or drag &amp; drop files</p>
  <div class="upload-progress" id="uploadProgress">
    <div class="upload-bar" id="uploadBar"></div>
  </div>
  <input type="file" id="fileInput" style="display:none" multiple onchange="uploadFiles(this.files)">
</div>
'@
        $uploadJs = @'
function toggleUpload(){var z=document.getElementById('uploadZone');z.style.display=z.style.display==='none'?'block':'none';}
var zone=document.getElementById('uploadZone');
if(zone){
  zone.addEventListener('dragover',function(e){e.preventDefault();e.stopPropagation();zone.classList.add('drag-over');});
  zone.addEventListener('dragleave',function(e){e.stopPropagation();zone.classList.remove('drag-over');});
  zone.addEventListener('drop',function(e){e.preventDefault();e.stopPropagation();zone.classList.remove('drag-over');uploadFiles(e.dataTransfer.files);});
}
async function uploadFiles(files){
  var progress=document.getElementById('uploadProgress');
  var bar=document.getElementById('uploadBar');
  progress.style.display='block';
  for(var i=0;i<files.length;i++){
    var file=files[i];
    bar.style.width=((i/files.length)*100)+'%';
    try{
      var resp=await fetch('?upload='+encodeURIComponent(file.name),{method:'POST',body:file,headers:{'Content-Type':'application/octet-stream'}});
      if(!resp.ok)throw new Error('fail');
    }catch(e){alert('Upload failed: '+file.name);}
  }
  bar.style.width='100%';
  setTimeout(function(){location.reload();},500);
}
'@
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $portStr   = $script:Port.ToString()

    $page = Get-HtmlTemplate
    $page = $page.Replace('__SERVER_TITLE__',  (ConvertTo-HtmlEncoded $script:Title))
    $page = $page.Replace('__PORT__',           $portStr)
    $page = $page.Replace('__DISPLAY_PATH__',  (ConvertTo-HtmlEncoded $displayPath))
    $page = $page.Replace('__BREADCRUMB__',     $breadcrumb)
    $page = $page.Replace('__FOLDER_COUNT__',   $folderCount.ToString())
    $page = $page.Replace('__FILE_COUNT__',     $fileCount.ToString())
    $page = $page.Replace('__TOTAL_SIZE__',     $totalSize)
    $page = $page.Replace('__UPLOAD_BUTTON__',  $uploadButton)
    $page = $page.Replace('__FILE_ITEMS__',     $sb.ToString())
    $page = $page.Replace('__UPLOAD_ZONE__',    $uploadZone)
    $page = $page.Replace('__UPLOAD_JS__',      $uploadJs)
    $page = $page.Replace('__TIMESTAMP__',      $timestamp)
    return $page
}

# ── HTML Templates ────────────────────────────────────────────────────────────

function Get-HtmlTemplate {
return @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>__SERVER_TITLE__ &middot; __DISPLAY_PATH__</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600&family=DM+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#0c0c0c;
  --surface:#141414;
  --surface-hover:#1a1a1a;
  --border:#222;
  --border-hover:#333;
  --text:#e8e8e8;
  --muted:#555;
  --muted2:#3a3a3a;
  --accent:#fff;
  --folder:#888;
  --green:#3a9;
  --fs:16px;
}
*{margin:0;padding:0;box-sizing:border-box}
html{font-size:var(--fs);scroll-behavior:smooth}
body{
  background:var(--bg);color:var(--text);
  font-family:'DM Sans',sans-serif;font-weight:400;
  min-height:100vh;line-height:1.5;
}
/* ── Layout ── */
.page{max-width:900px;margin:0 auto;padding:0 32px 100px}
/* ── Header ── */
header{
  border-bottom:1px solid var(--border);
  position:sticky;top:0;z-index:50;
  background:rgba(12,12,12,0.92);
  backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);
}
.hdr{
  max-width:900px;margin:0 auto;
  display:flex;align-items:center;justify-content:space-between;
  padding:18px 32px;
}
.logo{
  display:flex;align-items:center;gap:10px;
  text-decoration:none;color:var(--text);
}
.logo-mark{
  width:28px;height:28px;border-radius:6px;
  background:var(--text);
  display:grid;place-items:center;
  flex-shrink:0;
}
.logo-mark svg{display:block}
.logo-name{
  font-size:0.9rem;font-weight:600;
  letter-spacing:-0.01em;
}
.hdr-meta{
  display:flex;align-items:center;gap:6px;
  font-family:'DM Mono',monospace;font-size:0.72rem;
  color:var(--muted);
}
.live-dot{
  width:5px;height:5px;border-radius:50%;
  background:var(--green);flex-shrink:0;
  animation:blink 3s ease infinite;
}
@keyframes blink{0%,100%{opacity:1}60%{opacity:0.2}}
/* ── Breadcrumb ── */
.crumb{
  padding:28px 0 0;margin-bottom:24px;
  display:flex;align-items:center;gap:0;
  font-family:'DM Mono',monospace;font-size:0.78rem;
  flex-wrap:wrap;row-gap:4px;
}
.crumb a{color:var(--muted);text-decoration:none;padding:2px 4px;border-radius:3px;transition:color 0.12s}
.crumb a:hover{color:var(--text)}
.crumb .sep{color:var(--muted2);padding:0 1px}
.crumb .cur{color:var(--text);padding:2px 4px}
/* ── Toolbar ── */
.toolbar{
  display:flex;align-items:center;gap:10px;margin-bottom:20px;
}
.search-wrap{flex:1;position:relative}
.search-ico{
  position:absolute;left:14px;top:50%;transform:translateY(-50%);
  color:var(--muted);font-size:0.85rem;pointer-events:none;line-height:1;
}
.search{
  width:100%;background:var(--surface);
  border:1px solid var(--border);border-radius:8px;
  padding:12px 14px 12px 38px;
  color:var(--text);font-family:'DM Sans',sans-serif;font-size:0.9rem;
  outline:none;transition:border-color 0.15s;
}
.search:focus{border-color:var(--border-hover)}
.search::placeholder{color:var(--muted)}
.sort{
  background:var(--surface);border:1px solid var(--border);border-radius:8px;
  padding:12px 14px;color:var(--text);
  font-family:'DM Sans',sans-serif;font-size:0.85rem;
  cursor:pointer;outline:none;transition:border-color 0.15s;
  -webkit-appearance:none;appearance:none;
  padding-right:30px;
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath d='M1 1l4 4 4-4' stroke='%23555' stroke-width='1.5' fill='none' stroke-linecap='round'/%3E%3C/svg%3E");
  background-repeat:no-repeat;background-position:right 12px center;
}
.sort:focus{border-color:var(--border-hover)}
.btn{
  padding:12px 18px;border-radius:8px;border:1px solid var(--border);
  cursor:pointer;font-family:'DM Sans',sans-serif;font-weight:500;font-size:0.85rem;
  display:flex;align-items:center;gap:6px;white-space:nowrap;
  transition:border-color 0.15s,background 0.15s;
  background:var(--surface);color:var(--text);
}
.btn:hover{border-color:var(--border-hover);background:var(--surface-hover)}
.btn-primary{background:var(--text);color:var(--bg);border-color:var(--text)}
.btn-primary:hover{background:#ddd;border-color:#ddd}
/* ── Stats strip ── */
.stats{
  display:flex;align-items:center;gap:24px;
  padding-bottom:16px;margin-bottom:8px;
  border-bottom:1px solid var(--border);
}
.stat{font-size:0.8rem;color:var(--muted);display:flex;align-items:baseline;gap:5px}
.stat-n{color:var(--text);font-family:'DM Mono',monospace;font-size:0.82rem}
/* ── Column header ── */
.lhdr{
  display:grid;grid-template-columns:1.6rem 1fr 130px 88px;
  align-items:center;gap:16px;
  padding:10px 16px;
  font-size:0.7rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;
  color:var(--muted);
}
.lhdr span:nth-child(3),.lhdr span:nth-child(4){text-align:right}
/* ── File list ── */
.file-list{display:flex;flex-direction:column}
.file-item{
  display:grid;grid-template-columns:1.6rem 1fr 130px 88px;
  align-items:center;gap:16px;
  padding:13px 16px;
  border-radius:8px;
  text-decoration:none;color:var(--text);
  transition:background 0.1s;
  opacity:0;animation:fadein 0.25s ease forwards;
  border-bottom:1px solid transparent;
}
.file-item:hover{background:var(--surface)}
@keyframes fadein{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}
.file-icon{font-size:1rem;line-height:1;text-align:center}
.file-name{
  font-size:0.95rem;font-weight:400;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
}
.file-name .ext{
  font-family:'DM Mono',monospace;font-size:0.75rem;
  color:var(--muted);margin-left:1px;
}
.folder-name{font-weight:500}
.file-date{
  font-family:'DM Mono',monospace;font-size:0.73rem;
  color:var(--muted);text-align:right;white-space:nowrap;
}
.file-size{
  font-family:'DM Mono',monospace;font-size:0.78rem;
  color:var(--muted);text-align:right;white-space:nowrap;
}
.dash{color:var(--muted2)}
/* ── Empty ── */
.empty{
  text-align:center;padding:80px 40px;
  color:var(--muted);font-size:0.9rem;
}
.empty-icon{font-size:2rem;display:block;margin-bottom:14px;opacity:0.3}
/* ── Upload zone ── */
.upload-zone{
  margin-top:28px;border:1px dashed var(--border);border-radius:10px;
  padding:48px 40px;text-align:center;cursor:pointer;
  transition:border-color 0.15s,background 0.15s;
}
.upload-zone:hover,.upload-zone.drag-over{
  border-color:var(--border-hover);background:var(--surface);
}
.upload-icon{font-size:1.6rem;display:block;margin-bottom:14px;opacity:0.4}
.upload-zone h3{font-size:0.9rem;font-weight:500;margin-bottom:6px;color:var(--text)}
.upload-zone p{font-size:0.8rem;color:var(--muted)}
.upload-progress{margin-top:20px;height:2px;background:var(--border);border-radius:1px;overflow:hidden;display:none}
.upload-bar{height:100%;background:var(--text);width:0%;transition:width 0.25s}
/* ── Footer ── */
footer{
  border-top:1px solid var(--border);
  max-width:900px;margin:0 auto;
  padding:20px 32px;
  display:flex;align-items:center;justify-content:space-between;
  font-size:0.72rem;color:var(--muted);
  font-family:'DM Mono',monospace;
}
/* ── Scrollbar ── */
::-webkit-scrollbar{width:4px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:var(--border);border-radius:2px}
::-webkit-scrollbar-thumb:hover{background:var(--muted2)}
/* ── Responsive ── */
@media(max-width:600px){
  .lhdr,.file-item{grid-template-columns:1.4rem 1fr 80px}
  .file-date,.lhdr span:nth-child(3){display:none}
  .page,.hdr{padding-left:20px;padding-right:20px}
}
</style>
</head>
<body>

<header>
  <div class="hdr">
    <a class="logo" href="/">
      <div class="logo-mark">
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" xmlns="http://www.w3.org/2000/svg">
          <rect x="1" y="1" width="5" height="5" rx="1" fill="#0c0c0c"/>
          <rect x="8" y="1" width="5" height="5" rx="1" fill="#0c0c0c"/>
          <rect x="1" y="8" width="5" height="5" rx="1" fill="#0c0c0c"/>
          <rect x="8" y="8" width="5" height="5" rx="1" fill="#0c0c0c"/>
        </svg>
      </div>
      <span class="logo-name">__SERVER_TITLE__</span>
    </a>
    <div class="hdr-meta">
      <div class="live-dot"></div>
      <span>localhost:__PORT__</span>
    </div>
  </div>
</header>

<div class="page">
  <nav class="crumb">__BREADCRUMB__</nav>

  <div class="toolbar">
    <div class="search-wrap">
      <span class="search-ico">&#9906;</span>
      <input type="text" class="search" id="searchInput" placeholder="Filter files&hellip;" oninput="filterFiles()">
    </div>
    <select class="sort" id="sortSel" onchange="sortFiles()">
      <option value="name-asc">Name &uarr;</option>
      <option value="name-desc">Name &darr;</option>
      <option value="size-desc">Size &darr;</option>
      <option value="size-asc">Size &uarr;</option>
      <option value="date-desc">Date &darr;</option>
      <option value="date-asc">Date &uarr;</option>
    </select>
    __UPLOAD_BUTTON__
  </div>

  <div class="stats">
    <div class="stat"><span class="stat-n">__FOLDER_COUNT__</span> folders</div>
    <div class="stat"><span class="stat-n" id="fileCount" data-total="__FILE_COUNT__">__FILE_COUNT__</span> files</div>
    <div class="stat"><span class="stat-n">__TOTAL_SIZE__</span> total</div>
  </div>

  <div class="lhdr">
    <span></span>
    <span>Name</span>
    <span>Modified</span>
    <span>Size</span>
  </div>

  <div class="file-list" id="fileList">
    __FILE_ITEMS__
  </div>

  __UPLOAD_ZONE__
</div>

<footer>
  <span>__SERVER_TITLE__ &mdash; PowerShell File Server</span>
  <span>__TIMESTAMP__</span>
</footer>

<script>
var allItems=Array.from(document.querySelectorAll('.file-item'));
allItems.forEach(function(el,i){el.style.animationDelay=(i*0.022)+'s'});

function filterFiles(){
  var q=document.getElementById('searchInput').value.toLowerCase();
  var vis=0;
  allItems.forEach(function(el){
    var show=!q||((el.dataset.name||'').includes(q));
    el.style.display=show?'':'none';
    if(show)vis++;
  });
  var fc=document.getElementById('fileCount');
  fc.textContent=q?(vis+' match'+(vis!==1?'es':'')):fc.dataset.total;
}

function sortFiles(){
  var sort=document.getElementById('sortSel').value;
  var list=document.getElementById('fileList');
  var items=Array.from(list.querySelectorAll('.file-item'));
  items.sort(function(a,b){
    var aF=a.dataset.type==='folder',bF=b.dataset.type==='folder';
    if(aF!==bF)return aF?-1:1;
    var p=sort.split('-'),f=p[0],d=p[1];
    var av=a.dataset[f]||'',bv=b.dataset[f]||'';
    if(f==='size'){av=parseFloat(av)||0;bv=parseFloat(bv)||0;}
    var c=av<bv?-1:av>bv?1:0;
    return d==='asc'?c:-c;
  });
  items.forEach(function(i){list.appendChild(i)});
}
__UPLOAD_JS__
</script>
</body>
</html>
'@
}

function Get-ErrorPage([int]$code, [string]$message) {
    $tmpl = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>__CODE__</title>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500&family=DM+Mono&display=swap" rel="stylesheet">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{
  background:#0c0c0c;color:#e8e8e8;
  font-family:'DM Sans',sans-serif;
  min-height:100vh;display:flex;flex-direction:column;
  align-items:center;justify-content:center;text-align:center;gap:12px;
}
.code{font-family:'DM Mono',monospace;font-size:5rem;font-weight:400;color:#2a2a2a;line-height:1;margin-bottom:4px}
.msg{font-size:1rem;font-weight:500;color:#888;margin-bottom:24px}
a{
  color:#e8e8e8;font-size:0.85rem;text-decoration:none;
  border-bottom:1px solid #333;padding-bottom:2px;
  transition:border-color 0.12s;
}
a:hover{border-color:#666}
</style>
</head>
<body>
  <div class="code">__CODE__</div>
  <div class="msg">__MESSAGE__</div>
  <a href="/">&#8592; Back to root</a>
</body>
</html>
'@
    $tmpl.Replace('__CODE__', $code.ToString()).Replace('__MESSAGE__', (ConvertTo-HtmlEncoded $message))
}

#endregion

#region ── Main ──────────────────────────────────────────────

$uploadStatus  = if ($AllowUpload)   { "Enabled"  } else { "Disabled" }
$uploadColor   = if ($AllowUpload)   { "Green"    } else { "DarkGray" }
$hiddenStatus  = if ($ShowHidden)    { "Enabled"  } else { "Disabled" }
$hiddenColor   = if ($ShowHidden)    { "Green"    } else { "DarkGray" }
$authStatus    = if ($useAuth)       { "Enabled"  } else { "Disabled" }
$authColor     = if ($useAuth)       { "Green"    } else { "DarkGray" }
$logStatus     = if ($LogRequests)   { "Enabled"  } else { "Disabled" }
$logColor      = if ($LogRequests)   { "Green"    } else { "DarkGray" }

Write-Host ""
Write-Host "  ⚡  $Title" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  URL        : " -NoNewline -ForegroundColor DarkGray; Write-Host "http://localhost:$Port/" -ForegroundColor White
Write-Host "  Root Path  : " -NoNewline -ForegroundColor DarkGray; Write-Host $rootPath -ForegroundColor White
Write-Host "  Upload     : " -NoNewline -ForegroundColor DarkGray; Write-Host $uploadStatus -ForegroundColor $uploadColor
Write-Host "  Hidden     : " -NoNewline -ForegroundColor DarkGray; Write-Host $hiddenStatus -ForegroundColor $hiddenColor
Write-Host "  Auth       : " -NoNewline -ForegroundColor DarkGray; Write-Host $authStatus   -ForegroundColor $authColor
Write-Host "  Logging    : " -NoNewline -ForegroundColor DarkGray; Write-Host $logStatus    -ForegroundColor $logColor
Write-Host "  Max Upload : " -NoNewline -ForegroundColor DarkGray; Write-Host "${MaxUploadMB} MB" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Press Ctrl+C to stop" -ForegroundColor DarkGray
Write-Host ""

if ($OpenBrowser) {
    Start-Process "http://localhost:$Port/"
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://*:$Port/")

try {
    $listener.Start()
    Write-Host "  Server running." -ForegroundColor Green

    while ($listener.IsListening) {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        # ── Auth check ──────────────────────────────────────
        if ($useAuth) {
            $authHdr = $request.Headers["Authorization"]
            $ok = $authHdr -and $authHdr.StartsWith("Basic ") -and ($authHdr.Substring(6) -eq $authExpected)
            if (-not $ok) {
                $response.StatusCode = 401
                $response.Headers.Add("WWW-Authenticate", "Basic realm=`"$Title`"")
                $b = [System.Text.Encoding]::UTF8.GetBytes("401 Unauthorized")
                $response.ContentLength64 = $b.Length
                $response.OutputStream.Write($b, 0, $b.Length)
                $response.OutputStream.Close()
                continue
            }
        }

        $method  = $request.HttpMethod
        $rawPath = $request.Url.AbsolutePath.TrimStart('/').TrimEnd('/')
        if ($rawPath -eq '') { $rawPath = '.' }

        # ── Logging ─────────────────────────────────────────
        if ($LogRequests) {
            $ts = (Get-Date).ToString("HH:mm:ss")
            $ip = $request.RemoteEndPoint.Address
            Write-Host "  [$ts] $ip $method $($request.Url.AbsolutePath)" -ForegroundColor DarkGray
        }

        # ── Path resolution & security ───────────────────────
        $fullPath    = Join-Path $rootPath $rawPath
        $resolvedObj = Resolve-Path -Path $fullPath -ErrorAction SilentlyContinue
        $resolved    = if ($resolvedObj) { $resolvedObj.Path } else { $null }

        if (-not $resolved -or -not $resolved.StartsWith($rootPath)) {
            Send-Html $response (Get-ErrorPage 403 "Access Denied") 403
            continue
        }

        # ── Upload (POST) ────────────────────────────────────
        if ($method -eq "POST" -and $AllowUpload) {
            $uploadName = $request.QueryString["upload"]
            if ($uploadName -and $uploadName -notmatch '[/\\:<>"|?*]') {
                $targetDir  = if (Test-Path $resolved -PathType Container) { $resolved } else { Split-Path $resolved }
                $targetFile = Join-Path $targetDir $uploadName
                try {
                    $maxBytes = [long]$MaxUploadMB * 1MB
                    if ($request.ContentLength64 -gt $maxBytes) {
                        $b = [System.Text.Encoding]::UTF8.GetBytes('{"ok":false,"error":"File exceeds size limit"}')
                        Send-Response $response 413 "application/json" $b
                    } else {
                        $fs = [System.IO.File]::Create($targetFile)
                        $request.InputStream.CopyTo($fs)
                        $fs.Close()
                        $b = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true}')
                        Send-Response $response 200 "application/json" $b
                        if ($LogRequests) { Write-Host "  [UPLOAD] $uploadName -> $targetDir" -ForegroundColor Green }
                    }
                } catch {
                    $b = [System.Text.Encoding]::UTF8.GetBytes('{"ok":false,"error":"Upload failed"}')
                    Send-Response $response 500 "application/json" $b
                }
            } else {
                Send-Html $response (Get-ErrorPage 400 "Bad Request") 400
            }
            continue
        }

        # ── Serve file ───────────────────────────────────────
        if (Test-Path $resolved -PathType Leaf) {
            $ext  = [System.IO.Path]::GetExtension($resolved)
            $mime = Get-MimeType $ext
            try {
                $bytes = [System.IO.File]::ReadAllBytes($resolved)
                Send-Response $response 200 $mime $bytes
            } catch {
                Send-Html $response (Get-ErrorPage 500 "Internal Server Error") 500
            }

        # ── Directory listing ────────────────────────────────
        } elseif (Test-Path $resolved -PathType Container) {
            $html = Get-DirectoryPage $rawPath $resolved
            Send-Html $response $html

        } else {
            Send-Html $response (Get-ErrorPage 404 "Not Found") 404
        }
    }
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
} finally {
    if ($listener.IsListening) { $listener.Stop() }
    $listener.Dispose()
    Write-Host ""
    Write-Host "  Server stopped." -ForegroundColor Yellow
    Write-Host ""
}

#endregion