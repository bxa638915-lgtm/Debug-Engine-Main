param(
	[switch]$BuildEngine,
	[switch]$GameplaySmoke,
	[switch]$SkipNativeLua
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engineBuildLog = Join-Path $projectRoot 'export\compat-tests\windows-engine-build.log'
$luaBuildLog = Join-Path $projectRoot 'export\compat-tests\lua-runtime-build.log'

function Invoke-HaxeTest {
	param(
		[Parameter(Mandatory = $true)][string]$Name,
		[Parameter(Mandatory = $true)][string[]]$Arguments
	)

	Write-Host "== $Name =="
	& haxe @Arguments
	if ($LASTEXITCODE -ne 0) {
		throw "$Name failed with exit code $LASTEXITCODE."
	}
}

if (-not (Get-Command haxe -ErrorAction SilentlyContinue)) {
	throw 'Haxe was not found on PATH. Install Haxe 4.3.7 and Haxelib before running this script.'
}

Push-Location $projectRoot
try {
	Invoke-HaxeTest 'ScriptAdapterRegistryTest' @('-cp', 'source', '-cp', 'tests', '-main', 'ScriptAdapterRegistryTest', '--interp')
	Invoke-HaxeTest 'PsychHookMapTest' @('-cp', 'source', '-cp', 'tests', '-main', 'PsychHookMapTest', '--interp')
	Invoke-HaxeTest 'PsychCallbackResultTest' @('-cp', 'source', '-cp', 'tests', '-main', 'PsychCallbackResultTest', '--interp')
	Invoke-HaxeTest 'PsychDialogueConverterTest' @('-cp', 'source', '-cp', 'tests', '-main', 'PsychDialogueConverterTest', '--interp')
	Invoke-HaxeTest 'PsychLuaObjectRegistryTest' @('-cp', 'source', '-cp', 'tests', '-main', 'PsychLuaObjectRegistryTest', '--interp')
	Invoke-HaxeTest 'PsychLuaPropertyPathTest' @('-cp', 'source', '-cp', 'tests', '-main', 'PsychLuaPropertyPathTest', '--interp')
	Invoke-HaxeTest 'ScriptCapabilitiesTest (without Lua)' @('-cp', 'source', '-cp', 'tests', '-lib', 'hscript-improved', '-main', 'ScriptCapabilitiesTest', '--interp')
	Invoke-HaxeTest 'ScriptCapabilitiesTest (with Lua metadata)' @('-cp', 'source', '-cp', 'tests', '-lib', 'hscript-improved', '-main', 'ScriptCapabilitiesTest', '-D', 'LUA_ALLOWED', '--interp')
	Invoke-HaxeTest 'VSliceParserTest' @('-cp', 'source', '-cp', 'tests', '-main', 'VSliceParserTest', '--interp')
	Invoke-HaxeTest 'VSliceAssetsConfigTest' @('-cp', 'source', '-cp', 'tests', '-main', 'VSliceAssetsConfigTest', '--interp')
	Invoke-HaxeTest 'RuntimeModConverterTest' @('-cp', 'source', '-cp', 'tests', '-main', 'RuntimeModConverterTest', '--interp')

	$tempTestRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ('uce-ui-builder-data-' + [guid]::NewGuid().ToString('N'))))
	$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
	if (-not $tempTestRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "UIBuilderData test path escaped the temporary directory: $tempTestRoot"
	}
	$tempModuleDirectory = Join-Path $tempTestRoot 'funkin\editors\uibuilder'
	New-Item -ItemType Directory -Path $tempModuleDirectory -Force | Out-Null
	try {
		Copy-Item -LiteralPath 'source\funkin\editors\uibuilder\UIBuilderData.hx' -Destination (Join-Path $tempModuleDirectory 'UIBuilderData.hx')
		Invoke-HaxeTest 'UIBuilderDataTest' @('-cp', $tempTestRoot, '-cp', 'tests', '-main', 'UIBuilderDataTest', '--interp')
	}
	finally {
		if (Test-Path -LiteralPath $tempTestRoot -PathType Container) {
			$resolvedTempRoot = (Resolve-Path -LiteralPath $tempTestRoot).Path
			if (-not $resolvedTempRoot.StartsWith($tempBase.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
				throw "Refusing to remove a UIBuilderData test directory outside the temporary root: $resolvedTempRoot"
			}
			Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
		}
	}

	if (-not $SkipNativeLua) {
		$occupiedDrives = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object Name)
		$driveLetter = @('R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z') | Where-Object { $_ -notin $occupiedDrives } | Select-Object -First 1
		if (-not $driveLetter) {
			throw 'No free drive letter is available for hxcpp. The native test needs a path without spaces on Windows.'
		}

		$drive = '{0}:' -f $driveLetter
		$oldHaxelibPath = $env:HAXELIB_PATH
		$aliasCreated = $false
		try {
			& subst $drive $projectRoot
			if ($LASTEXITCODE -ne 0) {
				throw "Could not create the temporary drive alias ($drive)."
			}
			$aliasCreated = $true
			$env:HAXELIB_PATH = Join-Path $drive '.haxelib'
			Push-Location "$drive\"
			try {
				New-Item -ItemType Directory -Path 'export\compat-tests' -Force | Out-Null
				Write-Host '== LuaRuntimeTest (native LuaJIT / Windows x64) =='
				& haxe -cp source -cp tests -lib linc_luajit -main LuaRuntimeTest -cpp 'export/compat-tests/lua-runtime' -D LUA_ALLOWED *> $luaBuildLog
				if ($LASTEXITCODE -ne 0) {
					Get-Content $luaBuildLog -Tail 50
					throw "LuaRuntimeTest compilation failed with exit code $LASTEXITCODE. Full log: $luaBuildLog"
				}

				$luaTestExecutable = Join-Path (Get-Location) 'export\compat-tests\lua-runtime\LuaRuntimeTest.exe'
				if (-not (Test-Path -LiteralPath $luaTestExecutable)) {
					Get-Content $luaBuildLog -Tail 50
					throw "LuaRuntimeTest executable was not created. Full log: $luaBuildLog"
				}
				& $luaTestExecutable
				if ($LASTEXITCODE -ne 0) {
					throw "LuaRuntimeTest failed with exit code $LASTEXITCODE."
				}
			}
			finally {
				Pop-Location
			}
		}
		finally {
			if ($null -eq $oldHaxelibPath) {
				Remove-Item Env:HAXELIB_PATH -ErrorAction SilentlyContinue
			}
			else {
				$env:HAXELIB_PATH = $oldHaxelibPath
			}
			if ($aliasCreated) {
				& subst $drive /d
			}
		}
	}
	else {
		Write-Host '== LuaRuntimeTest skipped =='
	}

	if ($BuildEngine) {
		Write-Host '== Codename Engine Windows release build =='
		& haxelib run lime build windows -release *> $engineBuildLog
		if ($LASTEXITCODE -ne 0) {
			Get-Content $engineBuildLog -Tail 80
			throw "Codename Engine build failed with exit code $LASTEXITCODE. Full log: $engineBuildLog"
		}
		Write-Host "Build passed. Full log: $engineBuildLog"
	}
	if ($GameplaySmoke) {
		$gameDirectory = Join-Path $projectRoot 'export\release\windows\bin'
		$gameExecutable = Join-Path $gameDirectory 'CodenameEngine.exe'
		if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) {
			throw "Gameplay smoke test needs a Windows release build. Run with -BuildEngine first."
		}

		$temporaryMod = Join-Path $gameDirectory 'mods\__codex_compat_smoke__'
		if (Test-Path -LiteralPath $temporaryMod) {
			throw "Refusing to overwrite an existing folder used by the gameplay smoke test: $temporaryMod"
		}

		$scriptFolder = Join-Path $temporaryMod 'songs\bopeebo\scripts'
		$dialogueFolder = Join-Path $temporaryMod 'data\bopeebo'
		$modDataFolder = Join-Path $temporaryMod 'data'
		New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null
		New-Item -ItemType Directory -Path $dialogueFolder -Force | Out-Null
		New-Item -ItemType Directory -Path $modDataFolder -Force | Out-Null
		$smokeScript = @'
function onCreate()
    debugPrint("CNE_LUA_SMOKE:onCreate")
    if setTimeBarColors("FFFFFF", "000000") then
        debugPrint("CNE_LUA_SMOKE:timeBar")
    end
    if achievementExists("compat_smoke") then
        debugPrint("CNE_LUA_SMOKE:psychAchievementApi")
    end
    if getTranslationPhrase("compatibility_missing_phrase", "Psych phrase fallback") == "Psych phrase fallback" then
        debugPrint("CNE_LUA_SMOKE:psychTranslationApi")
    end
    if getTranslationPhrase("compatibility phrase") == "Translated from Psych" then
        debugPrint("CNE_LUA_SMOKE:psychLangFile")
    end
    callOnScripts("cneDispatchContinue")
    callOnScripts("cneDispatchStop")
end

function onUpdate(elapsed)
    if not __smoke_update_seen then
        __smoke_update_seen = true
        debugPrint("CNE_LUA_SMOKE:onUpdate")
        setPropertyFromGroup("strumLineNotes", 0, "direction", 0)
        if noteTweenDirection("compat-direction", 0, 90, 0.1) then
            debugPrint("CNE_LUA_SMOKE:noteDirection")
        end
    end
    if __smoke_beat_seen and __smoke_miss_seen and not __smoke_dialogue_started then
        __smoke_dialogue_started = true
        if startDialogue("compat-dialogue") then
            debugPrint("CNE_LUA_SMOKE:dialogueJson")
        end
    end
end

function onBeatHit(beat)
    if beat == 0 then
        __smoke_beat_seen = true
        debugPrint("CNE_LUA_SMOKE:onBeatHit")
    end
end

function noteMiss(id, direction, noteType, isSustainNote)
    if not __smoke_miss_seen then
        __smoke_miss_seen = true
        debugPrint("CNE_LUA_SMOKE:noteMiss:" .. tostring(id) .. ":" .. tostring(direction))
    end
end
'@
		$smokeScriptPath = Join-Path $scriptFolder 'compat-smoke.lua'
		Set-Content -LiteralPath $smokeScriptPath -Value $smokeScript -Encoding UTF8
		$dispatchLua = @'
function cneDispatchContinue()
    debugPrint("CNE_LUA_SMOKE:dispatchLuaContinue")
    return Function_Continue
end

function cneDispatchStop()
    debugPrint("CNE_LUA_SMOKE:dispatchLuaStop")
    return Function_StopLua
end
'@
		Set-Content -LiteralPath (Join-Path $scriptFolder 'compat-dispatch.lua') -Value $dispatchLua -Encoding UTF8
		$dispatchHScript = @'
function cneDispatchContinue() {
    trace("CNE_LUA_SMOKE:dispatchHScriptContinue");
}

function cneDispatchStop() {
    trace("CNE_LUA_SMOKE:dispatchHScriptShouldSkip");
}
'@
		Set-Content -LiteralPath (Join-Path $scriptFolder 'compat-dispatch.hx') -Value $dispatchHScript -Encoding UTF8
		$dialoguePath = Join-Path $dialogueFolder 'compat-dialogue.json'
		[System.IO.File]::WriteAllText($dialoguePath, '{"dialogue":[{"portrait":"bf","expression":"normal","text":"Psych JSON dialogue smoke","boxState":"normal","speed":0.03}]}', [System.Text.UTF8Encoding]::new($false))
		$achievementPath = Join-Path $modDataFolder 'achievements.json'
		[System.IO.File]::WriteAllText($achievementPath, '[{"save":"compat_smoke","name":"Compatibility smoke","description":"Lua API check"}]', [System.Text.UTF8Encoding]::new($false))
		$languagePath = Join-Path $modDataFolder 'en.lang'
		[System.IO.File]::WriteAllLines($languagePath, [string[]]@('Compatibility smoke', 'compatibility_phrase: "Translated from Psych"', 'images/alphabet: "compat_smoke_alphabet"'), [System.Text.UTF8Encoding]::new($false))

		$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
		$stdout = Join-Path $projectRoot "export\compat-tests\gameplay-lua-$stamp.stdout.log"
		$stderr = Join-Path $projectRoot "export\compat-tests\gameplay-lua-$stamp.stderr.log"
		$process = $null
		try {
			Write-Host '== Lua mod gameplay smoke test (Bopeebo) =='
			$process = Start-Process -FilePath $gameExecutable -WorkingDirectory $gameDirectory -ArgumentList '-modfolder mods/ -mod __codex_compat_smoke__ -song bopeebo normal' -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
			Wait-Process -Id $process.Id -Timeout 25 -ErrorAction SilentlyContinue
			$process.Refresh()
			if (-not $process.HasExited) {
				$runningProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)"
				if (-not $runningProcess -or -not [string]::Equals($runningProcess.ExecutablePath, $gameExecutable, [System.StringComparison]::OrdinalIgnoreCase)) {
					throw 'Refusing to close a process that is not the engine started by this smoke test.'
				}
				Stop-Process -Id $process.Id -Force
			}

			$logText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
			foreach ($marker in @('CNE_LUA_SMOKE:onCreate', 'CNE_LUA_SMOKE:timeBar', 'CNE_LUA_SMOKE:psychAchievementApi', 'CNE_LUA_SMOKE:psychTranslationApi', 'CNE_LUA_SMOKE:psychLangFile', 'CNE_LUA_SMOKE:dispatchLuaContinue', 'CNE_LUA_SMOKE:dispatchHScriptContinue', 'CNE_LUA_SMOKE:dispatchLuaStop', 'CNE_LUA_SMOKE:onUpdate', 'CNE_LUA_SMOKE:noteDirection', 'CNE_LUA_SMOKE:onBeatHit', 'CNE_LUA_SMOKE:noteMiss:', 'CNE_LUA_SMOKE:dialogueJson')) {
				if ($logText -notmatch [regex]::Escape($marker)) {
					Get-Content -LiteralPath $stdout -Tail 80 -ErrorAction SilentlyContinue
					Get-Content -LiteralPath $stderr -Tail 40 -ErrorAction SilentlyContinue
					throw "Gameplay smoke test did not observe callback marker '$marker'. See $stdout"
				}
			}
			if ($logText -match 'CNE_LUA_SMOKE:dispatchHScriptShouldSkip') {
				throw "callOnScripts did not honor Function_StopLua. See $stdout"
			}
			if ($logText.IndexOf('CNE_LUA_SMOKE:dispatchLuaContinue') -gt $logText.IndexOf('CNE_LUA_SMOKE:dispatchHScriptContinue')) {
				throw "callOnScripts did not dispatch Lua before HScript. See $stdout"
			}
			if ($logText -match 'Lua load error:|Lua API callback failed:|Lua callback .* failed:|Invalid field:|The object does not have the property|Error while loading dialogue') {
				throw "Gameplay smoke test reported a Lua error. See $stdout"
			}
			Write-Host "Gameplay smoke passed: Lua callbacks, time bar colors, note direction, and Psych JSON dialogue. Log: $stdout"
		}
		finally {
			if ($process) {
				$runningProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)" -ErrorAction SilentlyContinue
				if ($runningProcess -and [string]::Equals($runningProcess.ExecutablePath, $gameExecutable, [System.StringComparison]::OrdinalIgnoreCase)) {
					Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
				}
			}
			$resolvedTemporaryMod = [System.IO.Path]::GetFullPath($temporaryMod).TrimEnd('\')
			$expectedModsFolder = [System.IO.Path]::GetFullPath((Join-Path $gameDirectory 'mods')).TrimEnd('\')
			if ($resolvedTemporaryMod.StartsWith("$expectedModsFolder\", [System.StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTemporaryMod) -eq '__codex_compat_smoke__') {
				Remove-Item -LiteralPath $resolvedTemporaryMod -Recurse -Force
			}
		}
	}

	Write-Host 'Compatibility tests passed.'
}
finally {
	Pop-Location
}
