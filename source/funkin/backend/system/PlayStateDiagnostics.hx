package funkin.backend.system;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.text.FlxText.FlxTextAlign;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.util.FlxColor;
import dbe.diagnostics.ScriptTimingProfiler;
import funkin.backend.chart.ChartData.ChartEvent;
import funkin.backend.assets.SongLoadReport;
import funkin.backend.assets.SongLoader;
import funkin.backend.scripting.HScript;
import funkin.game.PlayState;
import haxe.ds.ObjectMap;
import haxe.io.Path;
import openfl.filesystem.File;
#if sys
import sys.FileSystem;
import sys.io.File as SysFile;
#end

using StringTools;

/**
	A manual, read-only snapshot of gameplay objects for diagnosing black screens
	and camera/rendering problems that are easy to miss in the console.
**/
class PlayStateDiagnostics
{
	static inline var MAX_OBJECTS:Int = 900;
	static inline var MAX_CAMERA_EVENTS:Int = 32;
	static inline var MAX_CAMERA_FILTER_NAMES:Int = 16;

	static var trackedGame:PlayState;
	static var recentCameraEvents:Array<String> = [];
	static var noticeOwner:PlayState;
	static var notice:FlxText;

	/** Save a report to application storage and show its path in the game. */
	public static function capture(game:PlayState, reason:String = "manual snapshot"):String
	{
		if (game == null) return "No active PlayState.";
		ensureTrackedGame(game);

		#if sys
		try {
			var directory = File.applicationStorageDirectory.nativePath;
			if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);

			var baseName = 'dbe-playstate-diagnostic-${DateTools.format(Date.now(), "%Y%m%d-%H%M%S")}';
			var outputPath = Path.join([directory, '$baseName.txt']);
			var suffix = 1;
			while (FileSystem.exists(outputPath)) {
				outputPath = Path.join([directory, '$baseName-$suffix.txt']);
				suffix++;
			}

			SysFile.saveContent(outputPath, buildReport(game, outputPath, reason));
			showNotice(game, 'Relatório salvo em:\n$outputPath');
			return outputPath;
		} catch (error:Dynamic) {
			var message = 'Não foi possível salvar o relatório:\n${Std.string(error)}';
			showNotice(game, message);
			return message;
		}
		#else
		var message = "Este diagnóstico precisa de uma build desktop com acesso a arquivos.";
		showNotice(game, message);
		return message;
		#end
	}

	/** Keep a short history of camera chart events already removed from the queue. */
	public static function recordCameraEvent(game:PlayState, event:ChartEvent, songPosition:Float):Void
	{
		if (game == null || event == null || event.name == null || !event.name.toLowerCase().contains("camera")) return;
		ensureTrackedGame(game);

		var params = event.params == null ? "<null>" : Std.string(event.params);
		recentCameraEvents.push('songPosition=${formatFloat(songPosition)}ms event="${event.name}" params=$params');
		while (recentCameraEvents.length > MAX_CAMERA_EVENTS) recentCameraEvents.shift();
	}

	/** Release static references before PlayState destroys its display members. */
	public static function clear(game:PlayState):Void
	{
		if (noticeOwner == game) {
			notice = null;
			noticeOwner = null;
		}
		if (trackedGame == game) {
			trackedGame = null;
			recentCameraEvents = [];
		}
	}

	static function ensureTrackedGame(game:PlayState):Void
	{
		if (trackedGame != game) {
			trackedGame = game;
			recentCameraEvents = [];
		}
	}

	static function showNotice(game:PlayState, message:String):Void
	{
		if (notice != null && noticeOwner == game) {
			notice.text = message;
			return;
		}

		if (notice != null && noticeOwner != null && noticeOwner.members != null)
			noticeOwner.remove(notice, true);

		notice = new FlxText(16, 16, FlxG.width - 32, message, 14);
		notice.setFormat(null, 14, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		notice.scrollFactor.set(0, 0);
		var displayCamera = game.camHUD != null ? game.camHUD : game.camGame;
		if (displayCamera != null) notice.cameras = [displayCamera];
		noticeOwner = game;
		game.add(notice);
	}

	static function buildReport(game:PlayState, outputPath:String, reason:String):String
	{
		var lines:Array<String> = [];
		var counts:DiagnosticCounts = {
			nodes: 0,
			sprites: 0,
			hidden: 0,
			zeroAlpha: 0,
			noGraphic: 0,
			offscreen: 0,
			fullScreenCandidates: 0,
			truncated: false
		};
		var seen = new ObjectMap<Dynamic, Bool>();
		var camera = game.camGame != null ? game.camGame : FlxG.camera;

		lines.push("DBE PLAYSTATE / CAMERA DIAGNOSTIC");
		lines.push('Captured: ${Date.now().toString()}');
		lines.push('captureReason=${oneLine(reason)}');
		lines.push('Report: $outputPath');
		#if sys
		lines.push('Working directory: ${safe(Sys.getCwd())}');
		#else
		lines.push("Working directory: unavailable on this target");
		#end
		lines.push("");

		var songName = PlayState.SONG != null && PlayState.SONG.meta != null ? PlayState.SONG.meta.name : "<null>";
		lines.push("=== GAME STATE ===");
		lines.push('song=$songName difficulty=${PlayState.difficulty} variation=${safe(PlayState.variation)}');
		lines.push('songPosition=${formatFloat(Conductor.songPosition)}ms generatedMusic=${game.generatedMusic} startingSong=${safe(Reflect.field(game, "startingSong"))}');
		lines.push('inCutscene=${game.inCutscene} chartingMode=${PlayState.chartingMode}');
		lines.push('cameraSpeed=${formatFloat(game.cameraSpeed)} forcedPosition=${game.isCameraOnForcedPos} curCameraTarget=${game.curCameraTarget}');
		lines.push('screen=${FlxG.width}x${FlxG.height}');
		if (FlxG.worldBounds != null)
			lines.push('worldBounds=${formatFloat(FlxG.worldBounds.x)},${formatFloat(FlxG.worldBounds.y)} ${formatFloat(FlxG.worldBounds.width)}x${formatFloat(FlxG.worldBounds.height)}');
		lines.push("");

		lines.push("=== PLAYSTATE CAMERAS ===");
		appendCamera(lines, "camGame", game.camGame);
		appendCamera(lines, "camHUD", game.camHUD);
		appendCamera(lines, "camOther", game.camOther);
		lines.push('camFollow=${describeObject(game.camFollow)}');
		lines.push('camFollowPos=${describeObject(game.camFollowPos)}');
		if (camera != null && game.camFollow != null) {
			var zoom = camera.zoom > 0 ? camera.zoom : 1;
			var centerX = camera.scroll.x + camera.width / zoom * 0.5;
			var centerY = camera.scroll.y + camera.height / zoom * 0.5;
			var deltaX = game.camFollow.x - centerX;
			var deltaY = game.camFollow.y - centerY;
			lines.push('cameraCenter=${formatFloat(centerX)},${formatFloat(centerY)} targetDelta=${formatFloat(deltaX)},${formatFloat(deltaY)}');
			if (!game.isCameraOnForcedPos && (Math.abs(deltaX) > camera.width * 2 || Math.abs(deltaY) > camera.height * 2))
				lines.push("FINDING: camera is far from camFollow; it may be looking outside the stage.");
		}
		if (camera == null) {
			lines.push("FINDING: camGame is null.");
		} else {
			if (!camera.visible || !camera.exists) lines.push("FINDING: camGame is hidden or does not exist.");
			if (!camera.followEnabled) lines.push("FINDING: camGame follow is disabled.");
			if (camera.zoom <= 0) lines.push("FINDING: camGame zoom is zero or negative.");
			if (camera.target != game.camFollow) lines.push('FINDING: camGame target is ${describeObject(camera.target)}, not camFollow.');
		}
		if (game.isCameraOnForcedPos) lines.push("NOTE: a Camera Follow Pos event or script is holding the camera at a forced position.");
		lines.push("");

		lines.push("=== CAMERA MANAGER ===");
		if (FlxG.cameras != null && FlxG.cameras.list != null) {
			lines.push('registeredCameras=${FlxG.cameras.list.length}');
			for (i in 0...FlxG.cameras.list.length)
				appendCamera(lines, 'manager[$i]', FlxG.cameras.list[i]);
		} else lines.push("FlxG.cameras or its camera list is null.");
		lines.push("");

		lines.push("=== STAGE ===");
		if (game.stage == null) {
			lines.push("FINDING: PlayState.stage is null.");
		} else {
			lines.push('stageFile=${safe(game.stage.stageFile)} stageName=${safe(game.stage.stageName)}');
			lines.push('stagePath=${safe(game.stage.stagePath)} stageXMLLoaded=${game.stage.stageXML != null}');
			var stageSpriteNames:Array<String> = [];
			for (name in game.stage.stageSprites.keys()) stageSpriteNames.push(name);
			stageSpriteNames.sort(function(a, b) return Reflect.compare(a, b));
			lines.push('stageSprites=${stageSpriteNames.length}');
			if (game.stage.stageXML == null) lines.push("FINDING: stage XML did not load or convert.");
			if (stageSpriteNames.length == 0) lines.push("FINDING: stage has no registered sprites.");
			for (name in stageSpriteNames) {
				var sprite = game.stage.stageSprites.get(name);
				var rootIndex = game.members == null ? -1 : game.members.indexOf(sprite);
				walkObject(lines, counts, seen, sprite, 'stageSprite[$name] rootIndex=$rootIndex', camera, 1);
			}
		}
		lines.push("");

		lines.push("=== CHARACTERS ===");
		if (game.strumLines != null && game.strumLines.members != null) {
			for (i in 0...game.strumLines.members.length) {
				var line = game.strumLines.members[i];
				if (line == null) continue;
				lines.push('strumLine[$i] visible=${line.visible} exists=${line.exists} characters=${line.characters == null ? 0 : line.characters.length}');
				if (line.characters != null) for (j in 0...line.characters.length) {
					var character = line.characters[j];
					if (character == null) {
						lines.push('  character[$j]=null');
						continue;
					}
					var animName = character.getAnimName();
					lines.push('  character[$j] id=${safe(character.curCharacter)} animation=${safe(animName)}');
					walkObject(lines, counts, seen, character, 'character[$i][$j]', camera, 2);
				}
			}
		}
		lines.push("");

		lines.push("=== RECENT CAMERA EVENTS ===");
		if (recentCameraEvents.length == 0) lines.push("No camera chart events recorded in this PlayState yet.");
		else for (entry in recentCameraEvents) lines.push(entry);
		lines.push("=== UPCOMING CAMERA EVENTS ===");
		var upcomingCount = 0;
		for (event in game.events) {
			if (event == null || event.name == null || !event.name.toLowerCase().contains("camera")) continue;
			lines.push('time=${formatFloat(event.time)}ms name="${event.name}" params=${event.params == null ? "<null>" : Std.string(event.params)}');
			if (++upcomingCount >= 40) break;
		}
		if (upcomingCount == 0) lines.push("No pending camera events found in the queue.");
		lines.push("");

		lines.push("=== LOADED SCRIPTS ===");
		var scriptEntries = game.scripts == null ? null : game.scripts.scripts;
		if (scriptEntries == null) {
			lines.push(game.scripts == null ? "PlayState ScriptPack is null." : "PlayState ScriptPack scripts array is null.");
			lines.push("HScript runHaxeCode cache instances=0 hits=0 misses=0");
			lines.push("No HScript instances found; ScriptPack contents are unavailable.");
		} else {
			var scriptTypeCounts = new haxe.ds.StringMap<Int>();
			var activeScriptTypeCounts = new haxe.ds.StringMap<Int>();
			var scriptTotal = 0;
			var activeScriptTotal = 0;
			var nullScriptEntries = 0;
			var hscriptCount = 0;
			var hscriptCacheHits = 0;
			var hscriptCacheMisses = 0;
			for (script in scriptEntries) {
				if (script == null) {
					nullScriptEntries++;
					continue;
				}
				scriptTotal++;
				var scriptClass = Type.getClass(script);
				var scriptType = scriptClass == null ? "<unknown>" : Type.getClassName(scriptClass);
				if (scriptType == null) scriptType = "<unknown>";
				var typeTotal = scriptTypeCounts.get(scriptType);
				scriptTypeCounts.set(scriptType, (typeTotal == null ? 0 : typeTotal) + 1);
				if (script.active) {
					activeScriptTotal++;
					var typeActive = activeScriptTypeCounts.get(scriptType);
					activeScriptTypeCounts.set(scriptType, (typeActive == null ? 0 : typeActive) + 1);
				}
				if (Std.isOfType(script, HScript)) {
					var hscript:HScript = cast script;
					hscriptCount++;
					hscriptCacheHits += hscript.runHaxeCodeCacheHits;
					hscriptCacheMisses += hscript.runHaxeCodeCacheMisses;
				}
			}

			lines.push('PlayState ScriptPack total=$scriptTotal active=$activeScriptTotal nullEntries=$nullScriptEntries');
			var scriptTypes:Array<String> = [];
			for (scriptType in scriptTypeCounts.keys()) scriptTypes.push(scriptType);
			scriptTypes.sort(function(a, b) return Reflect.compare(a, b));
			for (scriptType in scriptTypes) {
				var typeTotal = scriptTypeCounts.get(scriptType);
				var typeActive = activeScriptTypeCounts.get(scriptType);
				lines.push('  $scriptType total=${typeTotal == null ? 0 : typeTotal} active=${typeActive == null ? 0 : typeActive}');
			}
			lines.push('HScript runHaxeCode cache instances=$hscriptCount hits=$hscriptCacheHits misses=$hscriptCacheMisses');
			if (hscriptCount == 0) lines.push("No HScript instances in the PlayState ScriptPack.");
			for (script in scriptEntries) {
				if (script == null) lines.push("active=<unknown> name=<null> path=<null>");
				else lines.push('active=${script.active} name=${safe(script.fileName)} path=${safe(script.path)}');
			}
		}
		lines.push("");
		for (line in ScriptTimingProfiler.reportLines()) lines.push(line);
		lines.push("");

		appendSongLoaderReport(lines);

		lines.push("=== RENDER TREE ===");
		if (game.members != null) for (i in 0...game.members.length)
			walkObject(lines, counts, seen, game.members[i], 'state[$i]', camera, 0);
		lines.push('SUMMARY nodes=${counts.nodes} sprites=${counts.sprites} hiddenOrMissing=${counts.hidden} zeroAlpha=${counts.zeroAlpha} noGraphic=${counts.noGraphic} likelyOffscreen=${counts.offscreen} fullScreenCandidates=${counts.fullScreenCandidates} truncated=${counts.truncated}');
		lines.push("NOTE: estimateRGBA8Bytes is width × height × 4 theoretical backing-image size; it is not process-memory or GPU-memory measurement.");
		if (counts.hidden > 0) lines.push("NOTE: hiddenOrMissing includes intentionally inactive helper objects; inspect the listed entries before treating them as errors.");
		if (counts.offscreen > 0) lines.push("NOTE: likelyOffscreen is heuristic; parallax and decorative sprites can intentionally be outside the current camera.");
		if (counts.fullScreenCandidates > 0) lines.push("NOTE: full-screen candidates can be normal backgrounds; use rootIndex and draw order to identify an overlay above the stage.");

		return lines.join("\n") + "\n";
	}

	static function appendSongLoaderReport(lines:Array<String>):Void {
		lines.push("=== SONG LOADER ===");
		var report:SongLoadReport = SongLoader.lastReport;
		if (report == null) {
			lines.push("No song load report available.");
			lines.push("");
			return;
		}

		lines.push('status=${oneLine(report.status)} generation=${report.generation}');
		if (report.request != null) {
			var request = report.request;
			var variation = request.variation == null ? "<none>" : oneLine(request.variation);
			lines.push('song=${oneLine(request.songName)} difficulty=${oneLine(request.difficulty)} variation=$variation origin=${oneLine(request.origin)}');
		}
		lines.push('totalMs=${formatFloat(report.totalMs)} assetsLoaded=${report.assetsLoaded} resources=${report.bitmapResources + report.audioResources} duplicates=${report.duplicateCount}');
		lines.push('bitmapCacheHits=${report.bitmapCacheHits} bitmapCacheMisses=${report.bitmapCacheMisses} audioCacheHits=${report.audioCacheHits} audioCacheMisses=${report.audioCacheMisses}');

		var phases:Array<String> = [];
		for (phase in report.phaseMs.keys()) phases.push(phase);
		phases.sort(function(a, b) return Reflect.compare(a, b));
		for (phase in phases) lines.push('phaseMs[$phase]=${formatFloat(report.phaseMs.get(phase))}');

		lines.push("dynamicScriptAndShaderAssets=not collected");
		var failureLimit = 64;
		var failureCount = report.failures == null ? 0 : report.failures.length;
		var printed = failureCount < failureLimit ? failureCount : failureLimit;
		for (i in 0...printed) {
			var failure = report.failures[i];
			if (failure == null) continue;
			lines.push('failure[$i] phase=${oneLine(failure.phase)} path=${oneLine(failure.path)} message=${oneLine(failure.message)}');
		}
		if (failureCount > printed) lines.push('failuresOmitted=${failureCount - printed} totalFailures=$failureCount');
		if (failureCount == 0) lines.push("failures=0");
		lines.push("");
	}

	static function oneLine(value:Dynamic):String {
		if (value == null) return "<null>";
		return Std.string(value).replace("\r", "\\r").replace("\n", "\\n");
	}

	static function appendCamera(lines:Array<String>, label:String, camera:FlxCamera):Void
	{
		if (camera == null) {
			lines.push('$label=<null>');
			return;
		}
		var alpha = Reflect.field(camera, "alpha");
		var bgColor = Reflect.field(camera, "bgColor");
		var target = camera.target == null ? "<null>" : describeObject(camera.target);
		var filterSummary:String;
		if (camera.filters == null) {
			filterSummary = 'filtersEnabled=${camera.filtersEnabled} filterCount=<unknown> filterClasses=<null>';
		} else if (camera.filters.length == 0) {
			filterSummary = 'filtersEnabled=${camera.filtersEnabled} filterCount=0 filterClasses=<none>';
		} else {
			var filterNames:Array<String> = [];
			var printedFilterCount = camera.filters.length < MAX_CAMERA_FILTER_NAMES ? camera.filters.length : MAX_CAMERA_FILTER_NAMES;
			for (i in 0...printedFilterCount) {
				var filter = camera.filters[i];
				if (filter == null) {
					filterNames.push("<null>");
				} else {
					var filterClass = Type.getClass(filter);
					var filterName = filterClass == null ? null : Type.getClassName(filterClass);
					filterNames.push(filterName == null ? "<unknown>" : filterName);
				}
			}
			if (camera.filters.length > printedFilterCount) filterNames.push("...");
			filterSummary = 'filtersEnabled=${camera.filtersEnabled} filterCount=${camera.filters.length} filterClasses=[${filterNames.join(", ")}]';
		}
		lines.push('$label id=${camera.ID} exists=${camera.exists} visible=${camera.visible} alpha=${safe(alpha)} viewport=${formatFloat(camera.x)},${formatFloat(camera.y)} ${formatFloat(camera.width)}x${formatFloat(camera.height)} zoom=${formatFloat(camera.zoom)} scroll=${formatFloat(camera.scroll.x)},${formatFloat(camera.scroll.y)} followEnabled=${camera.followEnabled} followLerp=${formatFloat(camera.followLerp)} target=$target bgColor=${safe(bgColor)} $filterSummary');
	}

	static function walkObject(lines:Array<String>, counts:DiagnosticCounts, seen:ObjectMap<Dynamic, Bool>, value:Dynamic, label:String, camera:FlxCamera, depth:Int):Void
	{
		if (value == null || !Std.isOfType(value, FlxBasic)) return;
		if (seen.exists(value)) return;
		seen.set(value, true);
		if (counts.nodes >= MAX_OBJECTS) {
			counts.truncated = true;
			return;
		}
		counts.nodes++;

		var basic:FlxBasic = cast value;
		var classType = Type.getClass(value);
		var className = classType == null ? "<unknown>" : Type.getClassName(classType);
		var customName = Reflect.field(value, "name");
		var indent = "";
		for (_ in 0...depth) indent += "  ";
		var entry = '$indent$label $className#${basic.ID} exists=${basic.exists} active=${basic.active} visible=${basic.visible}';
		if (customName != null) entry += ' name=${safe(customName)}';

		if (!basic.exists || !basic.visible) counts.hidden++;
		if (Std.isOfType(value, FlxObject)) {
			var object:FlxObject = cast value;
			entry += ' xy=${formatFloat(object.x)},${formatFloat(object.y)} size=${formatFloat(object.width)}x${formatFloat(object.height)} scrollFactor=${formatFloat(object.scrollFactor.x)},${formatFloat(object.scrollFactor.y)}';
		}

		if (Std.isOfType(value, FlxSprite)) {
			var sprite:FlxSprite = cast value;
			counts.sprites++;
			entry += ' alpha=${formatFloat(sprite.alpha)} color=0x${StringTools.hex(sprite.color, 6)}';
			if (sprite.alpha <= 0.001) counts.zeroAlpha++;
			var graphic:Dynamic = Reflect.field(sprite, "graphic");
			if (graphic == null) {
				counts.noGraphic++;
				entry += " graphic=<null> graphicDimensions=<unknown> estimateRGBA8Bytes=<unknown>";
			} else {
				var graphicWidth:Dynamic = Reflect.field(graphic, "width");
				var graphicHeight:Dynamic = Reflect.field(graphic, "height");
				entry += ' graphic=${safe(Reflect.field(graphic, "key"))}';
				if (Std.isOfType(graphicWidth, Int) && Std.isOfType(graphicHeight, Int)) {
					var width:Int = cast graphicWidth;
					var height:Int = cast graphicHeight;
					if (width > 0 && height > 0) {
						var estimateRGBA8Bytes:Float = width * 1.0 * height * 4.0;
						entry += ' graphicDimensions=${width}x$height estimateRGBA8Bytes=${formatByteEstimate(estimateRGBA8Bytes)}';
					} else {
						entry += " graphicDimensions=<unknown> estimateRGBA8Bytes=<unknown>";
					}
				} else {
					entry += " graphicDimensions=<unknown> estimateRGBA8Bytes=<unknown>";
				}
			}
			entry += ' cameras=${cameraList(sprite.cameras)}';

			if (camera != null && sprite.alpha > 0.001 && sprite.exists && sprite.visible) {
				var zoom = camera.zoom > 0 ? camera.zoom : 1;
				var viewWidth = camera.width / zoom;
				var viewHeight = camera.height / zoom;
				if (sprite.scrollFactor.x >= 0.95 && sprite.scrollFactor.y >= 0.95 && sprite.width > 0 && sprite.height > 0
					&& (sprite.x + sprite.width < camera.scroll.x || sprite.x > camera.scroll.x + viewWidth || sprite.y + sprite.height < camera.scroll.y || sprite.y > camera.scroll.y + viewHeight)) {
					counts.offscreen++;
					entry += " [LIKELY OUTSIDE camGame VIEW]";
				}
				if (sprite.scrollFactor.x <= 0.05 && sprite.scrollFactor.y <= 0.05 && sprite.width >= FlxG.width * 0.8 && sprite.height >= FlxG.height * 0.8) {
					counts.fullScreenCandidates++;
					entry += " [FULL-SCREEN OVERLAY CANDIDATE]";
				}
			}
		}
		lines.push(entry);

		var members:Dynamic = Reflect.field(value, "members");
		if (Std.isOfType(members, Array)) {
			var children:Array<Dynamic> = cast members;
			for (i in 0...children.length)
				walkObject(lines, counts, seen, children[i], '$label.members[$i]', camera, depth + 1);
		}
	}

	static function cameraList(cameras:Array<FlxCamera>):String
	{
		if (cameras == null) return "default-cameras";
		if (cameras.length == 0) return "<empty>";
		var ids:Array<String> = [];
		for (camera in cameras) ids.push(camera == null ? "<null>" : Std.string(camera.ID));
		return ids.join(",");
	}

	static function describeObject(value:Dynamic):String
	{
		if (value == null) return "<null>";
		var classType = Type.getClass(value);
		var typeName = classType == null ? Std.string(Type.typeof(value)) : Type.getClassName(classType);
		var id = Reflect.field(value, "ID");
		var name = Reflect.field(value, "name");
		return '$typeName${id == null ? "" : "#" + Std.string(id)}${name == null ? "" : "[" + Std.string(name) + "]"}';
	}

	static inline function safe(value:Dynamic):String
		return value == null ? "<null>" : Std.string(value);

	static function formatFloat(value:Float):String
		return Math.isNaN(value) ? "NaN" : Std.string(Math.round(value * 1000) / 1000);

	static function formatByteEstimate(value:Float):String
		return haxe.Int64.toStr(haxe.Int64.fromFloat(value));
}

typedef DiagnosticCounts = {
	var nodes:Int;
	var sprites:Int;
	var hidden:Int;
	var zeroAlpha:Int;
	var noGraphic:Int;
	var offscreen:Int;
	var fullScreenCandidates:Int;
	var truncated:Bool;
}
