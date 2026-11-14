<#
.SYNOPSIS
    Build Virtua Tennis 3 VR for Meta Quest on Windows from your own copy of the game.

.DESCRIPTION
    Native Windows equivalent of scripts/build-quest-from-my-copy.sh (no WSL required).
    Checks required tools, validates your game folder, builds Quest arm64 dependencies
    into ..\deps (via Git Bash + quest/deps.sh), lifts the game ELF and libCg.so to C,
    generates Android GL thunks, and builds quest/VirtuaTennis3VR.apk.

.EXAMPLE
    .\scripts\build-quest-windows.ps1 C:\path\to\disk0
    .\scripts\build-quest-windows.ps1 -Install C:\path\to\disk0
    .\scripts\build-quest-windows.ps1 -Check C:\path\to\disk0
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$GamePath,
    [switch]$Install,
    [switch]$Yes,
    [switch]$Check,
    [switch]$Relift,
    [switch]$AllowDamagedGame,
    [string]$DepsDir
)

$ErrorActionPreference = "Stop"

# Refresh PATH from registry in case winget/installers were just run in this session
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:Path    = (@($machinePath, $userPath, $env:Path) | Where-Object { $_ }) -join ";"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Toolkit = Join-Path $Root "lindberghrecomp"
$Id = "vt3"
$Gen = Join-Path $Root "games\$Id\generated"
$Venv = Join-Path $Root ".venv"

if (-not $DepsDir) {
    $DepsDir = if ($env:DEPS) { $env:DEPS } else { Join-Path (Split-Path $Root -Parent) "deps" }
}
New-Item -ItemType Directory -Force -Path $DepsDir | Out-Null
$DepsDir = (Resolve-Path $DepsDir).Path

function Say([string]$msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok([string]$msg)   { Write-Host "    ok   $msg" -ForegroundColor Green }
function Bad([string]$msg)  { Write-Host "    no   $msg" -ForegroundColor Red }
function Warn([string]$msg) { Write-Host "    !!   $msg" -ForegroundColor Yellow }
function Die([string]$msg)  { Write-Host "`nerror: $msg" -ForegroundColor Red; exit 1 }
function To-Slash([string]$p) { return ($p -replace '\\', '/') }
function To-Msys([string]$p) {
    $s = To-Slash $p
    if ($s -match '^([A-Za-z]):/(.*)$') {
        return "/$($Matches[1].ToLower())/$($Matches[2])"
    }
    return $s
}

if (-not $GamePath) {
    Write-Host "usage: .\scripts\build-quest-windows.ps1 [-Check] [-Install] [-Yes] [-Relift] [-AllowDamagedGame] [-DepsDir <dir>] <path\to\disk0>"
    exit 2
}

# =========================================================================
Say "checking the tools"
$Problems = [System.Collections.Generic.List[string]]::new()
function Need([string]$what, [string]$fix) {
    Bad $what
    $Problems.Add("$what`n        -> $fix")
}

# Git & Git Bash
$GitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($GitCmd) { Ok "git" } else { Need "git" "winget install Git.Git" }

$BashExe = $null
foreach ($candidate in @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)) {
    if (Test-Path $candidate) { $BashExe = $candidate; break }
}
if (-not $BashExe -and $GitCmd) {
    $gitRoot = Split-Path (Split-Path $GitCmd.Source -Parent) -Parent
    $cand = Join-Path $gitRoot "bin\bash.exe"
    if (Test-Path $cand) { $BashExe = $cand }
}
if ($BashExe) { Ok "Git Bash ($BashExe)" } else { Need "Git Bash" "winget install Git.Git" }

# CMake & Ninja
foreach ($tool in @(
    @{ Name = "cmake"; Fix = "winget install Kitware.CMake" },
    @{ Name = "ninja"; Fix = "winget install Ninja-build.Ninja" }
)) {
    if (Get-Command $tool.Name -ErrorAction SilentlyContinue) { Ok $tool.Name }
    else { Need $tool.Name $tool.Fix }
}

# Python 3.10+
$PyExe = $null
if ($env:PYTHON -and (Test-Path $env:PYTHON)) {
    $PyExe = $env:PYTHON
} else {
    foreach ($cmd in @("python", "python3", "py")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if (-not $found) { continue }
        try {
            & $found.Source -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" 2>$null
            if ($LASTEXITCODE -eq 0) { $PyExe = $found.Source; break }
        } catch {}
    }
}
if ($PyExe) {
    $pyVer = (& $PyExe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')")
    Ok "Python $pyVer ($PyExe)"
} else {
    Need "Python 3.10+" "winget install Python.Python.3.12"
}

# JDK 17+
$JavaExe = Get-Command java -ErrorAction SilentlyContinue
$JavaHome = $env:JAVA_HOME
if (-not $JavaHome -and $JavaExe) {
    $JavaHome = Split-Path (Split-Path $JavaExe.Source -Parent) -Parent
}
if ($JavaHome -and (Test-Path (Join-Path $JavaHome "bin\java.exe"))) {
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $jVerOut = (cmd /c "`"$(Join-Path $JavaHome 'bin\java.exe')`" -version 2>&1" | Select-Object -First 1)
    $ErrorActionPreference = $prevEap
    Ok "JDK ($JavaHome) [$jVerOut]"
} else {
    Need "JDK 17+ (21 recommended)" "winget install Microsoft.OpenJDK.21"
}

# Android SDK & NDK 27/28
$SdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
if (Test-Path $SdkRoot) { Ok "Android SDK ($SdkRoot)" }
else { Need "Android SDK" "Install Android Command Line Tools into $SdkRoot (see README)" }

$NdkDir = $env:ANDROID_NDK
if (-not $NdkDir -and (Test-Path (Join-Path $SdkRoot "ndk"))) {
    $ndks = Get-ChildItem (Join-Path $SdkRoot "ndk") -Directory | Where-Object { $_.Name -match '^(27|28)\.' } | Sort-Object Name -Descending
    if ($ndks) { $NdkDir = $ndks[0].FullName }
}
if ($NdkDir -and (Test-Path (Join-Path $NdkDir "build\cmake\android.toolchain.cmake"))) {
    Ok "Android NDK ($(Split-Path $NdkDir -Leaf))"
} else {
    Need "Android NDK 27 or 28" "sdkmanager `"ndk;27.3.13750724`" `"platforms;android-35`" `"build-tools;35.0.0`" `"platform-tools`""
}

if ($Install) {
    $AdbExe = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $AdbExe -and (Test-Path (Join-Path $SdkRoot "platform-tools\adb.exe"))) {
        $AdbExe = Get-Item (Join-Path $SdkRoot "platform-tools\adb.exe")
    }
    if ($AdbExe) { Ok "adb ($($AdbExe.FullName -replace '^$','adb'))" }
    else { Need "adb (Android platform-tools)" "sdkmanager `"platform-tools`"" }
}

if ($Problems.Count -gt 0) {
    Write-Host ""
    Write-Host "missing tools:" -ForegroundColor Red
    foreach ($p in $Problems) { Write-Host "  * $p" }
    exit 1
}

# =========================================================================
Say "checking the game folder"
if (-not (Test-Path $GamePath)) { Die "$GamePath does not exist" }
$Game = $null
foreach ($cand in @($GamePath, (Join-Path $GamePath "disk0"), (Join-Path $GamePath "extracted\disk0"))) {
    if (Test-Path (Join-Path $cand "vt3_Lindbergh\vt3_Lindbergh_HD")) {
        $Game = (Resolve-Path $cand).Path
        break
    }
}
if (-not $Game) { Die "no vt3_Lindbergh\vt3_Lindbergh_HD in $GamePath (expected Virtua Tennis 3's disk0 folder)" }
Ok "Virtua Tennis 3: $Game"

$ElfPath = Join-Path $Game "vt3_Lindbergh\vt3_Lindbergh_HD"
$ElfExpectedSha = "4bc1ff1735b382f9dd6246656cdeaa3260193283aa494d3e745ad83655d3c9aa"
$ElfSha = (Get-FileHash $ElfPath -Algorithm SHA256).Hash.ToLower()
if ($ElfSha -eq $ElfExpectedSha) {
    Ok "vt3_Lindbergh_HD SHA-256 matches"
} else {
    Die "vt3_Lindbergh_HD has SHA-256 $ElfSha, expected $ElfExpectedSha"
}

$CgPath = Join-Path $Game "lib\libCg.so"
if (-not (Test-Path $CgPath)) { Die "$CgPath is missing (the whole disk0 folder is needed, including lib/)" }
$CgSize = (Get-Item $CgPath).Length
$CgSha = (Get-FileHash $CgPath -Algorithm SHA256).Hash.ToLower()
$CgExpectedSha = "da2f7604a1046e841e4a3e28d63c6a8d80ef9dcae996d6c06cad1b32585c736c"
if ($CgSize -eq 2170374 -and $CgSha -eq $CgExpectedSha) {
    Ok "lib/libCg.so matches (2170374 bytes)"
} else {
    Die "lib/libCg.so ($CgSize bytes, $CgSha) does not match the expected 2170374-byte library ($CgExpectedSha)"
}

# Damaged game check (same checks as games/vt3/game.conf)
$PlayerModels = @{
    "P_M_BLA_game_all01_base_II.efo"  = "e6137acabfe03d7894032b66c40c11324d7a7fcff27d906bec483c5b4e352672"
    "P_M_BLA_game_all_M1_II.efo"      = "42be2284592a1ba6002ca581a125c4141460542d845205a7e66acbff37efe308"
    "P_M_BLA_game_all_M2_II.efo"      = "b4d081a5bc512dd7ad33d8dbff1cebe02c64922c1e94b86c32dc052e23e3248a"
    "P_M_BLA_game_all_M3_II.efo"      = "c7e732be0dec53aba2895961a814a6255ef93b7e2b3296c67cad255e0f4aa274"
    "P_M_BLA_game_all_M4SP_II.efo"    = "f8859ff80d7c75d6782cdd5483cac41464e453f746dc538bb36e911a66fe966d"
    "P_M_BLA_game_all_M4_II.efo"      = "eb39ffbe84c1537daa63e561b040c57e9a2ec63c0f1623c34ec358debebf3ed9"
    "P_M_ANC_game_all01_base_AN.efo"  = "3873d84e46f31af78d36ecac89229790a832a348f991f6d58806447b1b8a4c94"
    "P_M_ANC_game_all01_M1_AN.efo"    = "4d58f18959942881a570ca9e7ad6b76c9f80185c7c6ce0f64815566818d72a0f"
    "P_M_ANC_game_all01_M1SP_AN.efo"  = "544500ac4448b78dc408f64949244ba9c590f0a75a95fb9e9805c0ca6e3f091a"
    "P_M_ANC_game_all01_M2_AN.efo"    = "36758ff496424541f99e4772675dae8364a2c44856b20dfaef83e2191c28e622"
    "P_M_ANC_game_all01_M3_AN.efo"    = "5e866faada7edf256fbfe7df14825ca9d02265a20bd1383d459783559856fea8"
    "P_M_ANC_game_all01_M4_AN.efo"    = "a80025451dc14a719a793c797ae1e12b1b7cb82bcfb6ff8e5181faffab6894e1"
}
$ModelDir = Join-Path $Game "vt3_Lindbergh\resource\model\player"
$Damaged = [System.Collections.Generic.List[string]]::new()
foreach ($kv in $PlayerModels.GetEnumerator()) {
    $mp = Join-Path $ModelDir $kv.Key
    if (-not (Test-Path $mp)) {
        $Damaged.Add("vt3_Lindbergh/resource/model/player/$($kv.Key) (missing)")
    } elseif ((Get-Item $mp).Length -eq 0) {
        $Damaged.Add("vt3_Lindbergh/resource/model/player/$($kv.Key) (empty)")
    } else {
        $msha = (Get-FileHash $mp -Algorithm SHA256).Hash.ToLower()
        if ($msha -ne $kv.Value) {
            $Damaged.Add("vt3_Lindbergh/resource/model/player/$($kv.Key) (damaged)")
        }
    }
}
if ($Damaged.Count -gt 0) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  WARNING: INCOMPLETE GAME TREE - MISSING / DAMAGED .efo PLAYER MODELS  " -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host "  $($Damaged.Count) of 12 checked player model (.efo) files are missing, empty, or damaged:" -ForegroundColor Yellow
    foreach ($d in $Damaged) { Write-Host "    - $d" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "  The game will start and play, but CRASHES during a tournament as soon" -ForegroundColor Yellow
    Write-Host "  as a match needs James Blake (round 2 of Road to the Championship) or" -ForegroundColor Yellow
    Write-Host "  Mario Ancic. Some dumps of vt3.bin are cut short; copy these .efo" -ForegroundColor Yellow
    Write-Host "  files from a complete copy (e.g. Rev. A or Rev. C) into:" -ForegroundColor Yellow
    Write-Host "    $ModelDir" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Red
    Write-Host ""
    if (-not $AllowDamagedGame -and $env:LINDBERGH_ALLOW_DAMAGED_GAME -ne "1") {
        Die "fix the .efo files above or pass -AllowDamagedGame (or set LINDBERGH_ALLOW_DAMAGED_GAME=1)"
    }
    Warn "continuing with damaged .efo files because -AllowDamagedGame / LINDBERGH_ALLOW_DAMAGED_GAME=1 is set"
} else {
    Ok "player models intact"
}

if ($Check) {
    Say "check complete (-Check specified; nothing built)"
    exit 0
}

# =========================================================================
# Ensure debug.keystore exists for Gradle release signing
$Keystore = Join-Path $env:USERPROFILE ".android\debug.keystore"
if (-not (Test-Path $Keystore)) {
    Say "generating Android debug keystore"
    New-Item -ItemType Directory -Force -Path (Split-Path $Keystore -Parent) | Out-Null
    $Keytool = Join-Path $JavaHome "bin\keytool.exe"
    & $Keytool -genkey -v -keystore $Keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "keytool failed" }
    Ok "created $Keystore"
}

# =========================================================================
Say "setting up Python virtual environment"
if (-not (Test-Path (Join-Path $Toolkit "pcrecomp\tools"))) {
    Say "fetching submodules"
    & git -C $Root submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { Die "git submodule update failed" }
}
$Vpy = Join-Path $Venv "Scripts\python.exe"
if (-not (Test-Path $Vpy)) {
    & $PyExe -m venv $Venv
    if ($LASTEXITCODE -ne 0) { Die "python -m venv failed" }
}
& $Vpy -m pip install -q --disable-pip-version-check -r (Join-Path $Root "requirements-dev.txt")
if ($LASTEXITCODE -ne 0) { Die "pip install failed" }
Ok "venv ready"

# =========================================================================
Say "building Quest dependencies in $DepsDir"
$env:ANDROID_SDK_ROOT = To-Slash $SdkRoot
$env:ANDROID_NDK      = To-Slash $NdkDir
$env:DEPS             = To-Slash $DepsDir
$env:JAVA_HOME        = To-Slash $JavaHome
$RootMsys = To-Msys $Root
& $BashExe -c "cd '$RootMsys' && ./quest/deps.sh"
if ($LASTEXITCODE -ne 0) { Die "quest/deps.sh failed" }
Ok "dependencies ready"

# =========================================================================
Say "lifting Virtua Tennis 3 to C"
New-Item -ItemType Directory -Force -Path $Gen | Out-Null

# Compute lift stamp
$pyFiles = Get-ChildItem (Join-Path $Toolkit "tools"), (Join-Path $Toolkit "pcrecomp\tools") -Recurse -Filter "*.py" -File | Sort-Object FullName
$pipFreeze = (& $Vpy -m pip freeze --disable-pip-version-check 2>$null | Select-String -Pattern '^(capstone|pyelftools)==') -join "`n"
$stampInput = @(
    "elf $ElfSha",
    "solib lib/libCg.so $CgSha"
)
foreach ($pf in $pyFiles) {
    $stampInput += (Get-FileHash $pf.FullName -Algorithm SHA256).Hash.ToLower()
}
$stampInput += $pipFreeze
$sha256Obj = [System.Security.Cryptography.SHA256]::Create()
$stampBytes = [System.Text.Encoding]::UTF8.GetBytes(($stampInput -join "`n"))
$Stamp = ([System.BitConverter]::ToString($sha256Obj.ComputeHash($stampBytes)) -replace '-', '').ToLower()

$StampFile = Join-Path $Gen ".lift-stamp"
$HasFuncs = @(Get-ChildItem $Gen -Filter "recomp_funcs_*.c" -ErrorAction SilentlyContinue).Count -gt 0
if (-not $Relift -and $HasFuncs -and (Test-Path $StampFile) -and ((Get-Content $StampFile -Raw).Trim() -eq $Stamp)) {
    Ok "lifted code in games/$Id/generated is current (-Relift to lift again)"
} else {
    if (Test-Path $StampFile) { Remove-Item $StampFile -Force }
    Push-Location $Toolkit
    try {
        & $Vpy -m tools recomp $ElfPath $Gen
        if ($LASTEXITCODE -ne 0) { Die "tools recomp failed" }
        & $Vpy -m tools.recomp.solib $Gen --main-elf $ElfPath $CgPath
        if ($LASTEXITCODE -ne 0) { Die "tools.recomp.solib failed" }
    } finally {
        Pop-Location
    }
    Set-Content -Path $StampFile -Value $Stamp -NoNewline -Encoding Ascii
    Ok "lift complete"
}

Say "generating Android GL thunks"
$LlvmNm = Join-Path $NdkDir "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe"
$ExportsFile = Join-Path $env:TEMP "gl4es.exports"
& $LlvmNm -g --defined-only (Join-Path $DepsDir "gl4es\lib\libGL.a") |
    ForEach-Object { $p = ($_ -split '\s+') | Where-Object { $_ -ne '' }; if ($p.Count -eq 3) { $p[2] } } |
    Sort-Object -Unique |
    Set-Content -Encoding Ascii $ExportsFile

& $Vpy (Join-Path $Toolkit "tools\gen_gl_thunks.py") --exports $ExportsFile `
    (Join-Path $Gen "recomp_imports.h") `
    (Join-Path $DepsDir "gl4es\include\GL\gl.h") `
    (Join-Path $DepsDir "gl4es\include\GL\glext.h") |
    Set-Content -Encoding Ascii (Join-Path $Gen "recomp_gl_thunks_android.c")
if ($LASTEXITCODE -ne 0) { Die "gen_gl_thunks.py failed" }
Set-Content -Encoding Ascii -NoNewline -Path (Join-Path $Gen "vt3_Lindbergh_HD.elf.sha256") -Value $ElfSha
Ok "GL thunks generated"

# =========================================================================
Say "building quest/VirtuaTennis3VR.apk"
& $BashExe -c "cd '$RootMsys' && ./quest/build.sh vt3"
if ($LASTEXITCODE -ne 0) { Die "quest/build.sh vt3 failed" }

$ApkPath = Join-Path $Root "quest\VirtuaTennis3VR.apk"
if (-not (Test-Path $ApkPath)) { Die "build finished without $ApkPath" }
Ok "built $ApkPath ($((Get-Item $ApkPath).Length) bytes)"

# =========================================================================
if ($Install) {
    Say "installing on Meta Quest"
    $adbPath = if ($AdbExe -is [System.Management.Automation.ApplicationInfo]) { $AdbExe.Source } else { $AdbExe.FullName }
    $devs = & $adbPath devices | Select-String '\bdevice$'
    if (-not $devs) { Die "no Quest detected via adb (enable Developer Mode, connect USB, and accept Allow USB debugging)" }
    if (-not $Yes) {
        $ans = Read-Host "Install VirtuaTennis3VR.apk and copy game files to /sdcard/VirtuaTennis3? [y/N]"
        if ($ans -notmatch '^[Yy]') { Die "cancelled" }
    }
    & $adbPath install -r $ApkPath
    if ($LASTEXITCODE -ne 0) { Die "adb install failed" }
    & $adbPath shell mkdir -p /sdcard/VirtuaTennis3
    foreach ($part in @("vt3_Lindbergh", "shader", "lib")) {
        $srcPart = Join-Path $Game $part
        if (Test-Path $srcPart) {
            Write-Host "    pushing $part..."
            & $adbPath push $srcPart /sdcard/VirtuaTennis3/
            if ($LASTEXITCODE -ne 0) { Die "adb push $part failed" }
        }
    }
    Ok "installed and copied game files to /sdcard/VirtuaTennis3"
}
