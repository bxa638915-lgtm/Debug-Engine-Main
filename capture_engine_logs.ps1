param(
    [string]$Mod = "",
    [string]$Song = "",
    [string]$Difficulty = "",
    [switch]$RebuildFirst = $false,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $RootDir "export\release\windows\bin"
$ExePath = Join-Path $BinDir "CodenameEngine.exe"

if (-not (Test-Path $ExePath)) {
    # Fallback if script is placed directly inside bin/
    $AltExe = Join-Path $RootDir "CodenameEngine.exe"
    if (Test-Path $AltExe) {
        $BinDir = $RootDir
        $ExePath = $AltExe
    } else {
        Write-Host "[ERRO] Executavel nao encontrado em: $ExePath" -ForegroundColor Red
        exit 1
    }
}

if ($RebuildFirst) {
    Write-Host "[DBE CAPTURE] Compilando a engine (lime build windows -release)..." -ForegroundColor Cyan
    Push-Location $RootDir
    & lime build windows -release
    Pop-Location
}

$LogsDir = Join-Path $RootDir "logs"
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$FullLogFile = Join-Path $LogsDir "dbe_console_full.log"
$TimestampedLogFile = Join-Path $LogsDir "dbe_console_$Timestamp.log"
$ErrorsLogFile = Join-Path $LogsDir "dbe_console_errors.log"
$SummaryFile = Join-Path $LogsDir "dbe_diagnostic_summary.txt"

# Build argument list for maximum verbosity and clean console output
$EngineArgs = New-Object System.Collections.Generic.List[string]
$EngineArgs.Add("-verbose")
$EngineArgs.Add("-nocolor")
$EngineArgs.Add("-livereload")

if ($Mod -ne "") {
    $EngineArgs.Add("-mod")
    $EngineArgs.Add("`"$Mod`"")
}
if ($Song -ne "") {
    $EngineArgs.Add("-song")
    $EngineArgs.Add("`"$Song`"")
    if ($Difficulty -ne "") {
        $EngineArgs.Add("`"$Difficulty`"")
    }
}
if ($ExtraArgs) {
    foreach ($a in $ExtraArgs) {
        $EngineArgs.Add($a)
    }
}

$ArgString = ($EngineArgs -join " ")

$Header = @"
================================================================================
  DBE ENGINE CONSOLE & DIAGNOSTIC CAPTURE
================================================================================
  Started At : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff")
  Executable : $ExePath
  WorkingDir : $BinDir
  Arguments  : $ArgString
  Full Log   : $FullLogFile
  Errors Log : $ErrorsLogFile
  Summary    : $SummaryFile
================================================================================
"@

Write-Host $Header -ForegroundColor Cyan
Set-Content -Path $FullLogFile -Value $Header -Encoding UTF8
Set-Content -Path $TimestampedLogFile -Value $Header -Encoding UTF8
Set-Content -Path $ErrorsLogFile -Value $Header -Encoding UTF8

$FullWriter = New-Object System.IO.StreamWriter($FullLogFile, $true, [System.Text.Encoding]::UTF8)
$FullWriter.AutoFlush = $true

$TimeWriter = New-Object System.IO.StreamWriter($TimestampedLogFile, $true, [System.Text.Encoding]::UTF8)
$TimeWriter.AutoFlush = $true

$ErrWriter = New-Object System.IO.StreamWriter($ErrorsLogFile, $true, [System.Text.Encoding]::UTF8)
$ErrWriter.AutoFlush = $true

$AllLines = New-Object System.Collections.Generic.List[string]
$ErrorLines = New-Object System.Collections.Generic.List[string]
$WarningLines = New-Object System.Collections.Generic.List[string]
$ScriptIssues = New-Object System.Collections.Generic.List[string]
$MissingAssets = New-Object System.Collections.Generic.List[string]
$ModCompatLines = New-Object System.Collections.Generic.List[string]

$StartTime = Get-Date

$Psi = New-Object System.Diagnostics.ProcessStartInfo
$Psi.FileName = $ExePath
$Psi.WorkingDirectory = $BinDir
$Psi.Arguments = $ArgString
$Psi.UseShellExecute = $false
$Psi.RedirectStandardOutput = $true
$Psi.RedirectStandardError = $true
$Psi.CreateNoWindow = $false
$Psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$Psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

$Proc = New-Object System.Diagnostics.Process
$Proc.StartInfo = $Psi

function Process-LogLine([string]$RawLine, [string]$StreamTag) {
    if ($null -eq $RawLine) { return }
    # Clean stray carriage returns and ANSI escape sequences that scramble the console
    $Clean = $RawLine -replace "`r", "" -replace "\x1B\[[0-9;]*[a-zA-Z]", ""
    if ([string]::IsNullOrWhiteSpace($Clean)) { return }

    $NowStr = (Get-Date).ToString("HH:mm:ss.fff")
    $Formatted = "[$NowStr][$StreamTag] $Clean"

    $AllLines.Add($Formatted)
    $FullWriter.WriteLine($Formatted)
    $TimeWriter.WriteLine($Formatted)

    $IsErr = ($StreamTag -eq "STDERR") -or ($Clean -match "(?i)(\bERROR\b|\bFAILURE\b|Uncaught|Exception|Null Object Reference|Critical|Stack|Segmentation)")
    $IsWarn = (-not $IsErr) -and ($Clean -match "(?i)(\bWARNING\b|\bWARN\b|deprecated|failed|blocked|incompatible)")
    $IsScript = ($Clean -match "(?i)(\.hx|\.lua|HScript|Lua|interp|CustomClass|importFailed|Unknown variable|Invalid field|PsychLua)")
    $IsAsset = ($Clean -match "(?i)(missing|not found|does not exist|null graphic|failed to load|cannot find|returnSound|getSparrowAtlas)")
    $IsCompat = ($Clean -match "(?i)(Compatibility|RuntimeModConverter|REA|Switching Mod|Loaded mod|psych_source|_dbe_)")

    if ($IsErr) {
        $ErrorLines.Add($Formatted)
        $ErrWriter.WriteLine($Formatted)
        Write-Host $Formatted -ForegroundColor Red
    } elseif ($IsWarn) {
        $WarningLines.Add($Formatted)
        $ErrWriter.WriteLine($Formatted)
        Write-Host $Formatted -ForegroundColor Yellow
    } elseif ($IsCompat) {
        $ModCompatLines.Add($Formatted)
        Write-Host $Formatted -ForegroundColor Cyan
    } else {
        Write-Host $Formatted -ForegroundColor Gray
    }

    if ($IsScript -and ($IsErr -or $IsWarn -or $Clean -match "(?i)(error|warn|fail|null|unknown|cannot)")) {
        $ScriptIssues.Add($Formatted)
    }
    if ($IsAsset -and ($IsErr -or $IsWarn)) {
        $MissingAssets.Add($Formatted)
    }
}

$Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'

# Register async event handlers so neither stdout nor stderr ever deadlocks or drops lines
$OutEvent = Register-ObjectEvent -InputObject $Proc -EventName OutputDataReceived -Action {
    if ($null -ne $EventArgs.Data) {
        $Event.MessageData.Enqueue(@("STDOUT", $EventArgs.Data))
    }
} -MessageData $Queue

$ErrEvent = Register-ObjectEvent -InputObject $Proc -EventName ErrorDataReceived -Action {
    if ($null -ne $EventArgs.Data) {
        $Event.MessageData.Enqueue(@("STDERR", $EventArgs.Data))
    }
} -MessageData $Queue

try {
    [void]$Proc.Start()
    $Proc.BeginOutputReadLine()
    $Proc.BeginErrorReadLine()

    Write-Host "[DBE CAPTURE] Engine iniciada (PID: $($Proc.Id)). Feche o jogo ou pressione Ctrl+C para finalizar e gerar o relatorio." -ForegroundColor Green

    while (-not $Proc.HasExited) {
        $Item = $null
        while ($Queue.TryDequeue([ref]$Item)) {
            Process-LogLine -RawLine $Item[1] -StreamTag $Item[0]
        }
        Start-Sleep -Milliseconds 25
    }

    # Flush remaining lines after exit
    $Proc.WaitForExit(2000) | Out-Null
    $Item = $null
    while ($Queue.TryDequeue([ref]$Item)) {
        Process-LogLine -RawLine $Item[1] -StreamTag $Item[0]
    }
} finally {
    Unregister-Event -SourceIdentifier $OutEvent.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $ErrEvent.Name -ErrorAction SilentlyContinue
    $FullWriter.Close()
    $TimeWriter.Close()
    $ErrWriter.Close()
}

$Duration = (Get-Date) - $StartTime
$ExitCode = $Proc.ExitCode

# If the engine also wrote directly to bin/logs/dbe_console_latest.log, merge any extra lines
$EngineInternalLog = Join-Path $BinDir "logs\dbe_console_latest.log"
if (Test-Path $EngineInternalLog) {
    Copy-Item -Path $EngineInternalLog -Destination (Join-Path $LogsDir "dbe_engine_internal_latest.log") -Force -ErrorAction SilentlyContinue
}
$EngineInternalErrLog = Join-Path $BinDir "logs\dbe_errors_latest.log"
if (Test-Path $EngineInternalErrLog) {
    Copy-Item -Path $EngineInternalErrLog -Destination (Join-Path $LogsDir "dbe_engine_internal_errors.log") -Force -ErrorAction SilentlyContinue
}

# Build comprehensive diagnostic summary
$Summary = New-Object System.Text.StringBuilder
[void]$Summary.AppendLine("================================================================================")
[void]$Summary.AppendLine("  DBE ENGINE DIAGNOSTIC SUMMARY")
[void]$Summary.AppendLine("================================================================================")
[void]$Summary.AppendLine("  Timestamp        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$Summary.AppendLine("  Duration         : $([math]::Round($Duration.TotalSeconds, 2))s")
[void]$Summary.AppendLine("  Exit Code        : $ExitCode")
[void]$Summary.AppendLine("  Total Log Lines  : $($AllLines.Count)")
[void]$Summary.AppendLine("  Errors Detected  : $($ErrorLines.Count)")
[void]$Summary.AppendLine("  Warnings         : $($WarningLines.Count)")
[void]$Summary.AppendLine("  Script Issues    : $($ScriptIssues.Count)")
[void]$Summary.AppendLine("  Missing Assets   : $($MissingAssets.Count)")
[void]$Summary.AppendLine("")

# Check REA Learned Profile status
[void]$Summary.AppendLine("--- [0] REA LEARNED ENGINE PROFILE STATUS ---")
foreach ($profCandidate in @((Join-Path $BinDir "mods\_dbe_rea_learned_profile.json"), (Join-Path $RootDir "mods\_dbe_rea_learned_profile.json"))) {
    if (Test-Path $profCandidate) {
        try {
            $profJson = Get-Content $profCandidate -Raw | ConvertFrom-Json
            [void]$Summary.AppendLine("  Profile Path     : $profCandidate")
            [void]$Summary.AppendLine("  Source EXE       : $($profJson.sourceExecutable)")
            [void]$Summary.AppendLine("  Detected Engine  : $($profJson.detectedEngine) ($($profJson.engineVersion))")
            [void]$Summary.AppendLine("  Psych Lua Profile: $($profJson.psychLuaProfile)")
            [void]$Summary.AppendLine("  Learned Rules    : $($profJson.learnedRulesCount)")
            [void]$Summary.AppendLine("  Learned At       : $($profJson.learnedAt)")
        } catch {}
    }
}
[void]$Summary.AppendLine("")

# Check latest RuntimeModConverter reports in %TEMP%\CodenameEngine\mod-conversions
[void]$Summary.AppendLine("--- [0B] RECENT MOD CONVERSION REPORTS ---")
$ConvCacheDir = Join-Path $env:TEMP "CodenameEngine\mod-conversions"
if (Test-Path $ConvCacheDir) {
    $Reports = Get-ChildItem -Path $ConvCacheDir -Filter "_dbe_conversion_report.json" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 8
    foreach ($rep in $Reports) {
        try {
            $rJson = Get-Content $rep.FullName -Raw | ConvertFrom-Json
            $incompCount = if ($rJson.incompatibilities) { $rJson.incompatibilities.Count } else { 0 }
            $warnCount = if ($rJson.warnings) { $rJson.warnings.Count } else { 0 }
            [void]$Summary.AppendLine("  * Mod Source: $($rJson.source)")
            [void]$Summary.AppendLine("    Format: $($rJson.sourceFormat) -> $($rJson.targetEngine) | Incompatibilities: $incompCount | Warnings: $warnCount")
            if ($incompCount -gt 0) {
                foreach ($inc in $rJson.incompatibilities) {
                    [void]$Summary.AppendLine("      [BLOCKED] $($inc.code): $($inc.message) ($($inc.source))")
                }
            }
        } catch {}
    }
}
[void]$Summary.AppendLine("")

[void]$Summary.AppendLine("--- [1] MOD & REA COMPATIBILITY EVENTS ($($ModCompatLines.Count)) ---")
if ($ModCompatLines.Count -eq 0) {
    [void]$Summary.AppendLine("  (None recorded)")
} else {
    foreach ($l in ($ModCompatLines | Select-Object -Last 60)) { [void]$Summary.AppendLine("  $l") }
}
[void]$Summary.AppendLine("")

[void]$Summary.AppendLine("--- [2] HSCRIPT / LUA SCRIPT ERRORS & WARNINGS ($($ScriptIssues.Count)) ---")
if ($ScriptIssues.Count -eq 0) {
    [void]$Summary.AppendLine("  (None recorded)")
} else {
    foreach ($l in ($ScriptIssues | Select-Object -Last 100)) { [void]$Summary.AppendLine("  $l") }
}
[void]$Summary.AppendLine("")

[void]$Summary.AppendLine("--- [3] MISSING ASSETS / PATH FAILURES ($($MissingAssets.Count)) ---")
if ($MissingAssets.Count -eq 0) {
    [void]$Summary.AppendLine("  (None recorded)")
} else {
    foreach ($l in ($MissingAssets | Select-Object -Last 100)) { [void]$Summary.AppendLine("  $l") }
}
[void]$Summary.AppendLine("")

[void]$Summary.AppendLine("--- [4] ALL ERRORS ($($ErrorLines.Count)) ---")
if ($ErrorLines.Count -eq 0) {
    [void]$Summary.AppendLine("  (None recorded)")
} else {
    foreach ($l in ($ErrorLines | Select-Object -Last 120)) { [void]$Summary.AppendLine("  $l") }
}
[void]$Summary.AppendLine("")

[void]$Summary.AppendLine("--- [5] ALL WARNINGS ($($WarningLines.Count)) ---")
if ($WarningLines.Count -eq 0) {
    [void]$Summary.AppendLine("  (None recorded)")
} else {
    foreach ($l in ($WarningLines | Select-Object -Last 100)) { [void]$Summary.AppendLine("  $l") }
}
[void]$Summary.AppendLine("")

[void]$Summary.AppendLine("--- [6] LAST 60 CONSOLE LINES BEFORE EXIT ---")
foreach ($l in ($AllLines | Select-Object -Last 60)) {
    [void]$Summary.AppendLine("  $l")
}

Set-Content -Path $SummaryFile -Value $Summary.ToString() -Encoding UTF8

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "  CAPTURA FINALIZADA! ARQUIVOS SALVOS EM:" -ForegroundColor Green
Write-Host "  1. Log Completo : $FullLogFile" -ForegroundColor White
Write-Host "  2. So Erros/Warn: $ErrorsLogFile" -ForegroundColor Yellow
Write-Host "  3. Resumo Diag. : $SummaryFile" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Green
