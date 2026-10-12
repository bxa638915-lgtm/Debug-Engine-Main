[CmdletBinding()]
param(
	[switch]$ValidateOnly,
	[switch]$BuildEngine,
	[switch]$BuildHScriptOnly,
	[switch]$GameplaySmoke,
	[string[]]$Profiles = @('0.6.3', '1.0.4'),
	[string[]]$FixtureIds = @(),
	[ValidateRange(15, 180)][int]$TimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $projectRoot 'tests\fixtures\psych-lua\fixture-manifest.json'
$logRoot = Join-Path $projectRoot 'export\compat-tests'
$engineBuildLog = Join-Path $logRoot 'psych-lua-windows-engine-build.log'
$evidenceRunId = [guid]::NewGuid().ToString('N')
$evidencePath = Join-Path $logRoot ("psych-lua-evidence-$evidenceRunId.json")
$evidence = [ordered]@{
	schemaVersion = 1
	runId = $evidenceRunId
	startedAt = [DateTime]::UtcNow.ToString('o')
	builds = @()
	fixtureRuns = @()
}

function Save-EvidenceRecord {
	param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Data)
	$json = ConvertTo-Json -InputObject $Data -Depth 20
	[System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-ProjectRelativePath {
	param([Parameter(Mandatory = $true)][string]$Path)
	$fullPath = [System.IO.Path]::GetFullPath($Path)
	$prefix = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
	if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Evidence path escaped the project root: $fullPath"
	}
	return $fullPath.Substring($prefix.Length).Replace('\', '/')
}

if (-not ($ValidateOnly -or $BuildEngine -or $BuildHScriptOnly -or $GameplaySmoke)) {
	throw 'Choose -ValidateOnly, -BuildEngine, -BuildHScriptOnly, and/or -GameplaySmoke.'
}
if ($ValidateOnly -and ($BuildEngine -or $BuildHScriptOnly -or $GameplaySmoke)) {
	throw '-ValidateOnly cannot be combined with a build or gameplay smoke.'
}
if ($BuildEngine -and $BuildHScriptOnly) {
	throw '-BuildEngine and -BuildHScriptOnly are separate build configurations.'
}
if ($BuildHScriptOnly -and $GameplaySmoke) {
	throw '-BuildHScriptOnly cannot be combined with -GameplaySmoke; the Lua fixtures require the Lua-enabled executable.'
}

function Invoke-ContractValidation {
	$python = Get-Command python -ErrorAction SilentlyContinue
	if (-not $python) {
		throw 'Python 3 was not found on PATH.'
	}

	Push-Location $projectRoot
	try {
		Write-Host '== Psych Lua Python contract tests =='
		& $python.Source -m unittest discover -s tests/psych_contracts -p 'test_*.py'
		if ($LASTEXITCODE -ne 0) {
			throw "Psych Lua contract tests failed with exit code $LASTEXITCODE."
		}

		Write-Host '== Psych Lua contract and fixture manifest validation =='
		& $python.Source tools/psych-compat/verify_contracts.py
		if ($LASTEXITCODE -ne 0) {
			throw "Psych Lua contract validation failed with exit code $LASTEXITCODE."
		}
	}
	finally {
		Pop-Location
	}
}

function Read-FixtureManifest {
	if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
		throw "Psych Lua fixture manifest was not found: $manifestPath"
	}
	try {
		return (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
	}
	catch {
		throw "Could not parse Psych Lua fixture manifest '$manifestPath': $($_.Exception.Message)"
	}
}

function Get-ResolvedFixturePath {
	param([Parameter(Mandatory = $true)]$Fixture)

	$fixtureRoot = Join-Path $projectRoot 'tests\fixtures\psych-lua'
	$fixtureDirectory = if ($Fixture.profile -eq 'unspecified') { 'profile-cases' } else { [string]$Fixture.profile }
	$profileRoot = [System.IO.Path]::GetFullPath((Join-Path $fixtureRoot $fixtureDirectory)).TrimEnd('\')
	$fixturePath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot ([string]$Fixture.scriptPath))).TrimEnd('\')
	$profilePrefix = $profileRoot + [System.IO.Path]::DirectorySeparatorChar
	if (-not $fixturePath.StartsWith($profilePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Fixture path escaped its profile directory: $($Fixture.scriptPath)"
	}
	if ($Fixture.physicalStatus -ne 'present' -or -not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
		throw "Fixture '$($Fixture.id)' is pending or missing: $fixturePath"
	}
	return $fixturePath
}

function Copy-FixtureSupportFiles {
	param(
		[Parameter(Mandatory = $true)]$Fixture,
		[Parameter(Mandatory = $true)][string]$TemporaryMod
	)

	$supportRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'tests\fixtures\psych-lua')).TrimEnd('\')
	$supportPrefix = $supportRoot + [System.IO.Path]::DirectorySeparatorChar
	$supportFiles = @()
	if ($Fixture.supportFiles) { $supportFiles = @($Fixture.supportFiles) }
	foreach ($support in $supportFiles) {
		$sourcePath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot ([string]$support.sourcePath))).TrimEnd('\')
		if (-not $sourcePath.StartsWith($supportPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
			throw "Fixture '$($Fixture.id)' has an invalid or missing support file: $($support.sourcePath)"
		}

		$relativeTarget = [string]$support.modPath
		if ([string]::IsNullOrWhiteSpace($relativeTarget) -or [System.IO.Path]::IsPathRooted($relativeTarget)) {
			throw "Fixture '$($Fixture.id)' has an invalid mod support path: $relativeTarget"
		}
		$targetPath = [System.IO.Path]::GetFullPath((Join-Path $TemporaryMod $relativeTarget)).TrimEnd('\')
		$targetPrefix = [System.IO.Path]::GetFullPath($TemporaryMod).TrimEnd('\') + [System.IO.Path]::DirectorySeparatorChar
		if (-not $targetPath.StartsWith($targetPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
			throw "Fixture '$($Fixture.id)' support path escaped its temporary mod: $relativeTarget"
		}
		$targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
		if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
			New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
		}
		$supportText = [System.IO.File]::ReadAllText($sourcePath)
		$supportText = $supportText.Replace('__DBE_TEMP_MOD__', [System.IO.Path]::GetFileName($TemporaryMod))
		[System.IO.File]::WriteAllText($targetPath, $supportText, [System.Text.UTF8Encoding]::new($false))
	}
}

function Assert-OwnedProcess {
	param(
		[Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
		[Parameter(Mandatory = $true)][string]$ExpectedExecutable
	)

	$runningProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($Process.Id)" -ErrorAction SilentlyContinue
	$resolvedExpected = [System.IO.Path]::GetFullPath($ExpectedExecutable)
	if (-not $runningProcess -or -not [string]::Equals([System.IO.Path]::GetFullPath($runningProcess.ExecutablePath), $resolvedExpected, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw 'Refusing to stop a process that is not the engine executable started by this runner.'
	}
}

Invoke-ContractValidation
$manifest = Read-FixtureManifest
$allFixtures = @($manifest.fixtures)
$pendingCount = @($allFixtures | Where-Object { $_.physicalStatus -ne 'present' }).Count

if ($ValidateOnly) {
	Write-Host "Catalog/manifest validation passed. Gameplay Lua fixtures pending: $pendingCount."
	return
}

if ($BuildHScriptOnly) {
	if (-not (Get-Command haxelib -ErrorAction SilentlyContinue)) {
		throw 'haxelib was not found on PATH; cannot build the HScript-only Windows release engine.'
	}
	New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
	$temporaryProjectName = '.dbe-hscript-only-' + [guid]::NewGuid().ToString('N') + '.xml'
	$temporaryProject = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $temporaryProjectName))
	$rootPrefix = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + [System.IO.Path]::DirectorySeparatorChar
	if (-not $temporaryProject.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or $temporaryProjectName -notmatch '^\.dbe-hscript-only-[0-9a-f]{32}\.xml$') {
		throw "Temporary HScript-only project path is invalid: $temporaryProject"
	}
	if (Test-Path -LiteralPath $temporaryProject) {
		throw "Refusing to overwrite a temporary project: $temporaryProject"
	}
	$temporaryProjectCreated = $false
	$hscriptOnlyLog = Join-Path $logRoot 'psych-lua-windows-hscript-only-build.log'
	try {
		$projectXml = [System.IO.File]::ReadAllText((Join-Path $projectRoot 'project.xml'))
		foreach ($requiredSetting in @('<haxelib name="linc_luajit" if="cpp"/>', '<haxedef name="LUA_ALLOWED" if="cpp"/>', 'file="CodenameEngine"')) {
			if (-not $projectXml.Contains($requiredSetting)) {
				throw "HScript-only build could not find project setting: $requiredSetting"
			}
		}
		$projectXml = $projectXml.Replace('<haxelib name="linc_luajit" if="cpp"/>', '')
		$projectXml = $projectXml.Replace('<haxedef name="LUA_ALLOWED" if="cpp"/>', '')
		$projectXml = $projectXml.Replace('file="CodenameEngine"', 'file="CodenameEngine-HScriptOnly"')
		[System.IO.File]::WriteAllText($temporaryProject, $projectXml, [System.Text.UTF8Encoding]::new($false))
		$temporaryProjectCreated = $true

		Push-Location $projectRoot
		try {
			Write-Host '== Codename Engine Windows release build without LuaJIT =='
			& haxelib run lime build $temporaryProject windows -release *> $hscriptOnlyLog
			$hscriptOnlyExitCode = $LASTEXITCODE
		}
		finally {
			Pop-Location
		}
		if ($hscriptOnlyExitCode -ne 0) {
			Get-Content -LiteralPath $hscriptOnlyLog -Tail 80 -ErrorAction SilentlyContinue
			throw "HScript-only Windows build failed with exit code $hscriptOnlyExitCode. Full log: $hscriptOnlyLog"
		}
		$hscriptOnlyExecutable = Join-Path $projectRoot 'export\release\windows\bin\CodenameEngine-HScriptOnly.exe'
		if (-not (Test-Path -LiteralPath $hscriptOnlyExecutable -PathType Leaf)) {
			throw "HScript-only build returned success without its executable: $hscriptOnlyExecutable"
		}
		$releaseHxml = Join-Path $projectRoot 'export\release\windows\haxe\release.hxml'
		$releaseHxmlText = Get-Content -LiteralPath $releaseHxml -Raw
		if ($releaseHxmlText -match 'LUA_ALLOWED') {
			throw 'HScript-only release HXML unexpectedly defines LUA_ALLOWED.'
		}
		if ((Get-Content -LiteralPath $hscriptOnlyLog -Raw) -match 'lua51\.lib') {
			throw 'HScript-only build unexpectedly linked the LuaJIT library.'
		}

		$evidence.builds += [ordered]@{
			target = 'windows-x64'
			luaEnabled = $false
			status = 'passed'
			completedAt = [DateTime]::UtcNow.ToString('o')
			log = Get-ProjectRelativePath -Path $hscriptOnlyLog
			executable = Get-ProjectRelativePath -Path $hscriptOnlyExecutable
		}
		Save-EvidenceRecord -Path $evidencePath -Data $evidence
		Write-Host "HScript-only Windows build passed. Executable: $hscriptOnlyExecutable; full log: $hscriptOnlyLog"
	}
	finally {
		if ($temporaryProjectCreated -and (Test-Path -LiteralPath $temporaryProject -PathType Leaf)) {
			$resolvedTemporaryProject = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $temporaryProject).Path)
			if ($resolvedTemporaryProject.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.Path]::GetFileName($resolvedTemporaryProject) -eq $temporaryProjectName) {
				[System.IO.File]::Delete($resolvedTemporaryProject)
			}
			else {
				throw "Refusing to remove a path that no longer matches the temporary HScript-only project: $resolvedTemporaryProject"
			}
		}
	}
	if (-not $GameplaySmoke) {
		Write-Host 'HScript-only build completed.'
		return
	}
}

if ($BuildEngine) {
	if (-not (Get-Command haxelib -ErrorAction SilentlyContinue)) {
		throw 'haxelib was not found on PATH; cannot build the Windows release engine.'
	}
	New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
	Push-Location $projectRoot
	try {
		Write-Host '== Codename Engine Windows release build =='
		& haxelib run lime build windows -release *> $engineBuildLog
		if ($LASTEXITCODE -ne 0) {
			Get-Content -LiteralPath $engineBuildLog -Tail 80 -ErrorAction SilentlyContinue
			throw "Windows release build failed with exit code $LASTEXITCODE. Full log: $engineBuildLog"
		}
		$evidence.builds += [ordered]@{
			target = 'windows-x64'
			luaEnabled = $true
			status = 'passed'
			completedAt = [DateTime]::UtcNow.ToString('o')
			log = Get-ProjectRelativePath -Path $engineBuildLog
		}
		Save-EvidenceRecord -Path $evidencePath -Data $evidence
		Write-Host "Windows release build passed. Full log: $engineBuildLog"
	}
	finally {
		Pop-Location
	}
}

if (-not $GameplaySmoke) {
	Write-Host 'Psych Lua validation/build completed.'
	return
}

$supportedProfiles = @('0.6.3', '1.0.4', 'unspecified')
foreach ($profile in $Profiles) {
	if ($profile -notin $supportedProfiles) {
		throw "Unsupported Psych profile '$profile'. Use 0.6.3, 1.0.4, and/or unspecified."
	}
}
if ($Profiles.Count -eq 0) {
	throw 'At least one profile is required for -GameplaySmoke.'
}

$selectedFixtures = @($allFixtures | Where-Object { $Profiles -contains $_.profile })
if ($FixtureIds.Count -gt 0) {
	$unknownIds = @($FixtureIds | Where-Object { $_ -notin @($allFixtures | ForEach-Object { $_.id }) })
	if ($unknownIds.Count -gt 0) {
		throw "Unknown fixture ID(s): $($unknownIds -join ', ')"
	}
	$selectedFixtures = @($selectedFixtures | Where-Object { $FixtureIds -contains $_.id })
	$wrongProfileIds = @($FixtureIds | Where-Object { $_ -notin @($selectedFixtures | ForEach-Object { $_.id }) })
	if ($wrongProfileIds.Count -gt 0) {
		throw "Fixture ID(s) are outside the selected profiles: $($wrongProfileIds -join ', ')"
	}
}
if ($selectedFixtures.Count -eq 0) {
	throw 'No fixture declarations matched the requested profiles and IDs.'
}

$gameDirectory = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'export\release\windows\bin'))
$gameExecutable = Join-Path $gameDirectory 'CodenameEngine.exe'
if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) {
	throw "Gameplay smoke needs the Windows release executable: $gameExecutable. Run with -BuildEngine first."
}
$gameExecutable = (Resolve-Path -LiteralPath $gameExecutable).Path
$modsDirectory = Join-Path $gameDirectory 'mods'
if (Test-Path -LiteralPath $modsDirectory -PathType Leaf) {
	throw "Expected the game mods path to be a directory: $modsDirectory"
}
if (-not (Test-Path -LiteralPath $modsDirectory -PathType Container)) {
	New-Item -ItemType Directory -Path $modsDirectory | Out-Null
}
$modsRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $modsDirectory).Path).TrimEnd('\')
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

foreach ($profileGroup in ($selectedFixtures | Group-Object {
	$configScenario = [string]$_.configScenario
	if ([string]::IsNullOrWhiteSpace($configScenario)) { $configScenario = 'selected' }
	$isolationKey = if ($_.isolation -eq $true) { [string]$_.id } else { 'shared' }
	"$($_.profile)|$configScenario|$isolationKey"
})) {
	$fixtures = @($profileGroup.Group)
	$profile = [string]$fixtures[0].profile
	$configScenario = [string]$fixtures[0].configScenario
	if ([string]::IsNullOrWhiteSpace($configScenario)) { $configScenario = 'selected' }
	$expectedProfile = [string]$fixtures[0].expectedProfile
	if ([string]::IsNullOrWhiteSpace($expectedProfile)) { $expectedProfile = $profile }
	$fixturePaths = @{}
	foreach ($fixture in $fixtures) {
		$fixturePaths[$fixture.id] = Get-ResolvedFixturePath -Fixture $fixture
	}

	$modName = '__dbe_psych_compat_' + [guid]::NewGuid().ToString('N')
	$temporaryMod = [System.IO.Path]::GetFullPath((Join-Path $modsRoot $modName)).TrimEnd('\')
	$expectedModsPrefix = $modsRoot + [System.IO.Path]::DirectorySeparatorChar
	if (-not $temporaryMod.StartsWith($expectedModsPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or [System.IO.Path]::GetFileName($temporaryMod) -ne $modName) {
		throw "Temporary mod path escaped the resolved mods directory: $temporaryMod"
	}
	if (Test-Path -LiteralPath $temporaryMod) {
		throw "Refusing to overwrite an existing temporary mod: $temporaryMod"
	}

	$temporaryModCreated = $false
	$process = $null
	$stdout = Join-Path $logRoot ("psych-lua-$profile-" + [guid]::NewGuid().ToString('N') + '.stdout.log')
	$stderr = [System.IO.Path]::ChangeExtension($stdout, '.stderr.log')
	try {
		New-Item -ItemType Directory -Path $temporaryMod | Out-Null
		$temporaryModCreated = $true
		$scriptFolder = Join-Path $temporaryMod 'songs\bopeebo\scripts'
		$configFolder = Join-Path $temporaryMod 'data\config'
		New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null
		New-Item -ItemType Directory -Path $configFolder -Force | Out-Null

		foreach ($fixture in $fixtures) {
			$destination = Join-Path $scriptFolder ($fixture.id + '.lua')
			$fixtureText = [System.IO.File]::ReadAllText($fixturePaths[$fixture.id])
			$fixtureText = $fixtureText.Replace('__DBE_TEMP_MOD__', $modName)
			[System.IO.File]::WriteAllText($destination, $fixtureText, [System.Text.UTF8Encoding]::new($false))
			Copy-FixtureSupportFiles -Fixture $fixture -TemporaryMod $temporaryMod
		}
		$configPath = Join-Path $configFolder 'dbe-compat.json'
		switch ($configScenario) {
			'selected' {
				if ($profile -notin @('0.6.3', '1.0.4')) { throw "Selected config scenario has invalid profile '$profile'." }
				$config = @{ psychLuaProfile = $profile } | ConvertTo-Json -Compress
				[System.IO.File]::WriteAllText($configPath, $config, [System.Text.UTF8Encoding]::new($false))
			}
			'missing' { }
			'malformed' { [System.IO.File]::WriteAllText($configPath, [string]$fixtures[0].configText, [System.Text.UTF8Encoding]::new($false)) }
			'unsupported' { [System.IO.File]::WriteAllText($configPath, [string]$fixtures[0].configText, [System.Text.UTF8Encoding]::new($false)) }
			default { throw "Unsupported Psych profile config scenario '$configScenario'." }
		}

		$arguments = "-modfolder mods/ -mod $modName -song bopeebo normal"
		Write-Host "== Psych Lua gameplay smoke: $expectedProfile / $configScenario ($($fixtures.Count) fixture(s)) =="
		$process = Start-Process -FilePath $gameExecutable -WorkingDirectory $gameDirectory -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
		Wait-Process -Id $process.Id -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
		$process.Refresh()
		$timedOut = -not $process.HasExited
		if ($timedOut) {
			Assert-OwnedProcess -Process $process -ExpectedExecutable $gameExecutable
			Stop-Process -Id $process.Id -Force
			$process.WaitForExit()
		}
		elseif ($process.ExitCode -ne 0) {
			throw "Engine exited with code $($process.ExitCode). See $stdout and $stderr"
		}

		$stdoutText = if (Test-Path -LiteralPath $stdout -PathType Leaf) { Get-Content -LiteralPath $stdout -Raw } else { '' }
		$stderrText = if (Test-Path -LiteralPath $stderr -PathType Leaf) { Get-Content -LiteralPath $stderr -Raw } else { '' }
		$logText = $stdoutText + "`n" + $stderrText
		$luaErrorPattern = 'DBE_PSYCH_LUA_ERROR:|Lua load error:|Lua API callback failed:|Lua callback .* failed:|Error while loading script'
		if ($logText -match $luaErrorPattern) {
			throw "Gameplay smoke reported a Lua error. See $stdout and $stderr"
		}

		$profileMarker = "DBE_PSYCH_PROFILE:$expectedProfile"
		if (-not $logText.Contains($profileMarker)) {
			throw "Gameplay smoke did not report selected profile marker '$profileMarker'. See $stdout"
		}
		foreach ($fixture in $fixtures) {
			foreach ($marker in @($fixture.expectedMarkers)) {
				if (-not $logText.Contains([string]$marker)) {
					throw "Fixture '$($fixture.id)' did not emit expected marker '$marker'. See $stdout"
				}
			}
			$lastIndex = -1
			foreach ($callbackName in @($fixture.expectedCallbackOrder)) {
				$callbackMarker = "DBE_PSYCH_CALLBACK:$($fixture.id):$callbackName"
				$nextIndex = $logText.IndexOf($callbackMarker, $lastIndex + 1, [System.StringComparison]::Ordinal)
				if ($nextIndex -lt 0) {
					throw "Fixture '$($fixture.id)' did not report callback order marker '$callbackMarker'. See $stdout"
				}
				if ($nextIndex -le $lastIndex) {
					throw "Fixture '$($fixture.id)' callback marker '$callbackMarker' was out of order. See $stdout"
				}
				$lastIndex = $nextIndex
			}
		}
		$evidence.fixtureRuns += [ordered]@{
			profile = $expectedProfile
			platform = 'windows-x64'
			fixtureIds = @($fixtures | ForEach-Object { [string]$_.id })
			status = 'passed'
			completedAt = [DateTime]::UtcNow.ToString('o')
			stdoutLog = Get-ProjectRelativePath -Path $stdout
			stderrLog = Get-ProjectRelativePath -Path $stderr
		}
		Save-EvidenceRecord -Path $evidencePath -Data $evidence
		Write-Host "Gameplay smoke passed for $expectedProfile / $configScenario. Logs: $stdout and $stderr"
	}
	finally {
		if ($process) {
			$process.Refresh()
			if (-not $process.HasExited) {
				Assert-OwnedProcess -Process $process -ExpectedExecutable $gameExecutable
				Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
			}
		}
		if ($temporaryModCreated -and (Test-Path -LiteralPath $temporaryMod -PathType Container)) {
			$resolvedTemporaryMod = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $temporaryMod).Path).TrimEnd('\')
			$allowedName = $modName -match '^__dbe_psych_compat_[0-9a-f]{32}$'
			if ($resolvedTemporaryMod.StartsWith($expectedModsPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.Path]::GetFileName($resolvedTemporaryMod) -eq $modName -and $allowedName) {
				Remove-Item -LiteralPath $resolvedTemporaryMod -Recurse -Force
			}
			else {
				throw "Refusing to remove a path that no longer matches this run's temporary mod: $resolvedTemporaryMod"
			}
		}
	}
}
