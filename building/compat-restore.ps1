param(
	[Parameter(Mandatory = $true)][string]$CheckpointPath,
	[Parameter(Mandatory = $true)][string]$Destination,
	[string[]]$Files
)

$ErrorActionPreference = 'Stop'
$checkpointRoot = (Resolve-Path -LiteralPath $CheckpointPath).Path
$manifestPath = Join-Path $checkpointRoot 'checkpoint-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or -not $manifest.sourceRoot -or -not $manifest.files) {
	throw "Unsupported or invalid checkpoint manifest: $manifestPath"
}
if ($manifest.fileCount -ne $manifest.files.Count) {
	throw "Checkpoint manifest count mismatch: expected $($manifest.fileCount), found $($manifest.files.Count)."
}

$destinationRoot = [System.IO.Path]::GetFullPath($Destination)
$sourceRoot = [System.IO.Path]::GetFullPath([string]$manifest.sourceRoot).TrimEnd('\')
$checkpointRoot = [System.IO.Path]::GetFullPath($checkpointRoot).TrimEnd('\')
$separator = [System.IO.Path]::DirectorySeparatorChar
if ($destinationRoot.TrimEnd('\') -eq $sourceRoot -or $destinationRoot.StartsWith("$sourceRoot$separator", [System.StringComparison]::OrdinalIgnoreCase)) {
	throw 'Restore destination cannot be the engine root or a folder inside it. Choose a separate review folder.'
}
if ($destinationRoot.TrimEnd('\') -eq $checkpointRoot -or $destinationRoot.StartsWith("$checkpointRoot$separator", [System.StringComparison]::OrdinalIgnoreCase)) {
	throw 'Restore destination cannot be inside the checkpoint.'
}

$checkpointFilesRoot = Join-Path $checkpointRoot 'files'
$checkpointFilesRoot = [System.IO.Path]::GetFullPath($checkpointFilesRoot).TrimEnd('\')
$selected = @($manifest.files)
if ($Files -and $Files.Count -gt 0) {
	$requested = @($Files | ForEach-Object { $_.Replace('\', '/') })
	$selected = @($manifest.files | Where-Object { $_.path -in $requested })
	$missing = @($requested | Where-Object { $_ -notin @($selected | ForEach-Object path) })
	if ($missing.Count -gt 0) {
		throw "These paths are not present in the checkpoint manifest: $($missing -join ', ')"
	}
}

$copyPlan = @()
$seenPaths = @{}
foreach ($entry in $selected) {
	$relativePath = [string]$entry.path
	if ([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath.Split('/') -contains '..' -or $relativePath.Split('\') -contains '..') {
		throw "Unsafe path in checkpoint manifest: $relativePath"
	}
	if ([string]::IsNullOrWhiteSpace($relativePath) -or $seenPaths.ContainsKey($relativePath)) {
		throw "Empty or duplicate path in checkpoint manifest: $relativePath"
	}
	$seenPaths[$relativePath] = $true
	$relativeWindowsPath = $relativePath -replace '/', '\'
	$sourcePath = [System.IO.Path]::GetFullPath((Join-Path $checkpointFilesRoot $relativeWindowsPath))
	if (-not $sourcePath.StartsWith("$checkpointFilesRoot$separator", [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Checkpoint path escapes its files folder: $relativePath"
	}
	if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
		throw "Checkpoint file is missing: $relativePath"
	}
	$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
	if ($sourceHash -ne $entry.sha256) {
		throw "Checkpoint SHA-256 mismatch: $relativePath"
	}
	if ((Get-Item -LiteralPath $sourcePath).Length -ne $entry.length) {
		throw "Checkpoint length mismatch: $relativePath"
	}
	$copyPlan += [pscustomobject]@{
		path = $relativePath
		windowsPath = $relativeWindowsPath
		source = $sourcePath
		hash = [string]$entry.sha256
	}
}

	if (Test-Path -LiteralPath $destinationRoot) {
		$existingItems = @(Get-ChildItem -LiteralPath $destinationRoot -Force)
		if ($existingItems.Count -gt 0) {
			throw "Restore destination must be empty: $destinationRoot"
		}
	}
	else {
		New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
	}

foreach ($item in $copyPlan) {
	$destinationPath = Join-Path $destinationRoot $item.windowsPath
	New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
	Copy-Item -LiteralPath $item.source -Destination $destinationPath
	$restoredHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
	if ($restoredHash -ne $item.hash) {
		throw "Restored SHA-256 mismatch: $($item.path)"
	}
}

Write-Host "Restored $($copyPlan.Count) file(s) to $destinationRoot; SHA-256: PASS"
