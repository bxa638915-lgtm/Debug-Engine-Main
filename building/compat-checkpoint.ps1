param(
	[ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
	[string]$Name = 'CNE-compat-master-checkpoint-05',
	[ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
	[string]$Suffix = (Get-Date -Format 'yyyyMMdd-HHmmss'),
	[string]$Validation = 'Compatibility tests and Windows engine build passed.'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workspaceRoot = Split-Path -Parent $projectRoot
$backupRoot = Join-Path $workspaceRoot 'backups'
$checkpointName = "$Name-$Suffix"
$checkpointRoot = Join-Path $backupRoot $checkpointName

$files = @(
	'project.xml',
	'building/libs.xml',
	'building/compat-test.ps1',
	'building/compat-checkpoint.ps1',
	'building/compat-restore.ps1',
	'source/cne/compat/ScriptAdapterRegistry.hx',
	'source/cne/compat/LuaCallbackScope.hx',
	'source/cne/compat/PsychHookMap.hx',
	'source/cne/compat/ScriptCapabilities.hx',
	'source/funkin/backend/scripting/Script.hx',
	'source/funkin/backend/scripting/ScriptAdapterManager.hx',
	'source/funkin/backend/scripting/LuaScript.hx',
	'tests/ScriptAdapterRegistryTest.hx',
	'tests/ScriptCapabilitiesTest.hx',
	'tests/PsychHookMapTest.hx',
	'tests/LuaRuntimeTest.hx',
	'docs/compatibility/COMPATIBILITY-API.md',
	'docs/compatibility/COMPATIBILITY-MATRIX.md',
	'docs/compatibility/COMPATIBILITY-ROADMAP.md',
	'docs/compatibility/COMPATIBILITY-AUDIT.md',
	'docs/compatibility/examples/psych-basic.lua'
)

$gameplayLogs = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'export\compat-tests') -Filter 'gameplay-lua-*.stdout.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
if ($gameplayLogs.Count -gt 0) {
	$gameplayRelativePath = 'export/compat-tests/' + $gameplayLogs[0].Name
	$files += $gameplayRelativePath
	$stderrName = [System.IO.Path]::ChangeExtension($gameplayLogs[0].Name, '.stderr.log')
	if (Test-Path -LiteralPath (Join-Path $gameplayLogs[0].DirectoryName $stderrName) -PathType Leaf) {
		$files += 'export/compat-tests/' + $stderrName
	}
}
foreach ($buildLog in @('export/compat-tests/windows-engine-build.log', 'export/compat-tests/lua-runtime-build.log')) {
	if (Test-Path -LiteralPath (Join-Path $projectRoot ($buildLog -replace '/', '\')) -PathType Leaf) {
		$files += $buildLog
	}
}

foreach ($relativePath in $files) {
	$sourcePath = Join-Path $projectRoot ($relativePath -replace '/', '\')
	if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
		throw "Checkpoint source file is missing: $relativePath"
	}
}
if (Test-Path -LiteralPath $checkpointRoot) {
	throw "Checkpoint destination already exists: $checkpointRoot"
}

New-Item -ItemType Directory -Path (Join-Path $checkpointRoot 'files') -Force | Out-Null
$manifestFiles = @()
foreach ($relativePath in $files) {
	$normalizedPath = $relativePath.Replace('\', '/')
	$sourcePath = Join-Path $projectRoot ($normalizedPath -replace '/', '\')
	$destinationPath = Join-Path (Join-Path $checkpointRoot 'files') ($normalizedPath -replace '/', '\')
	$destinationDirectory = Split-Path -Parent $destinationPath
	New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
	Copy-Item -LiteralPath $sourcePath -Destination $destinationPath

	$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
	$copiedHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
	if ($sourceHash -ne $copiedHash) {
		throw "SHA-256 verification failed for $normalizedPath"
	}
	$manifestFiles += [pscustomobject]@{
		path = $normalizedPath
		length = (Get-Item -LiteralPath $sourcePath).Length
		sha256 = $sourceHash
	}
}

$manifest = [pscustomobject]@{
	schemaVersion = 1
	checkpoint = $checkpointName
	createdUtc = (Get-Date).ToUniversalTime().ToString('o')
	sourceRoot = $projectRoot
	validation = $Validation
	fileCount = $manifestFiles.Count
	files = $manifestFiles
}
$manifestPath = Join-Path $checkpointRoot 'checkpoint-manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$restoreInstructions = @"
Checkpoint: $checkpointName
Created (UTC): $($manifest.createdUtc)
Validation: $Validation
Files: $($manifestFiles.Count), each verified with SHA-256.

To restore into a separate review folder from the engine root:
  .\building\compat-restore.ps1 -CheckpointPath "$checkpointRoot" -Destination "<new-empty-folder>"

The restore tool refuses to overwrite the engine tree and verifies the manifest before copying.
Review the restored files before applying any of them to the working engine.
"@
$restoreInstructions | Set-Content -LiteralPath (Join-Path $checkpointRoot 'RESTORE.txt') -Encoding UTF8

Write-Host "Checkpoint created and verified: $checkpointRoot"
Write-Host "Files: $($manifestFiles.Count); SHA-256: PASS"
