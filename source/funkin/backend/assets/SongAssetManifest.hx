package funkin.backend.assets;

import funkin.backend.chart.ChartData;
import funkin.backend.utils.XMLUtil;
import funkin.game.Character;
import funkin.game.Stage;
import haxe.xml.Access;

using StringTools;

enum abstract SongAssetKind(String) from String to String {
	var IMAGE = "image";
	var AUDIO = "audio";
	var VIDEO = "video";
}

typedef SongAssetEntry = {
	var path:String;
	var kind:SongAssetKind;
	var required:Bool;
	var stream:Null<Bool>;
	var ?sizeBytes:Float;
}

/** Static, side-effect-free list of resources used when a chart first enters gameplay. */
class SongAssetManifest {
	public var entries:Array<SongAssetEntry> = [];
	public var duplicateCount:Int = 0;
	public var hasVideo:Bool = false;
	public var totalVideoBytes:Float = 0;

	public function new() {}

	public static function build(request:SongLoadRequest, chart:ChartData):SongAssetManifest {
		var manifest = new SongAssetManifest();
		var seen:Map<String, SongAssetEntry> = [];

		function add(path:String, kind:SongAssetKind, required:Bool, stream:Null<Bool>):Void {
			if (path == null || path.trim() == "") return;
			var key = path.toLowerCase();
			if (seen.exists(key)) {
				manifest.duplicateCount++;
				return;
			}
			var bytes:Float = 0;
			#if sys
			try {
				var local = openfl.utils.Assets.getPath(path);
				if (local != null && sys.FileSystem.exists(local)) {
					bytes = sys.FileSystem.stat(local).size;
				}
			} catch (e:Dynamic) {}
			#end
			if (kind == VIDEO) {
				manifest.hasVideo = true;
				manifest.totalVideoBytes += bytes;
			}
			var entry:SongAssetEntry = {path: path, kind: kind, required: required, stream: stream, sizeBytes: bytes};
			seen.set(key, entry);
			manifest.entries.push(entry);
		}

		if (chart == null || chart.meta == null) return manifest;

		var songName = chart.meta.name != null && chart.meta.name != "" ? chart.meta.name : request.songName;
		var instSuffix = chart.meta.instSuffix == null ? "" : chart.meta.instSuffix;
		var instPath = Paths.inst(songName, request.difficulty, instSuffix);
		add(instPath, AUDIO, true, null);

		if (chart.meta.needsVoices != false) {
			var vocalsSuffix = chart.meta.vocalsSuffix == null ? "" : chart.meta.vocalsSuffix;
			var voicesPath = Paths.voices(songName, request.difficulty, vocalsSuffix);
			if (Assets.exists(voicesPath)) add(voicesPath, AUDIO, false, Options.streamedVocals);
		}
		// StrumLine independently loads any non-empty per-line prefix, even when the global vocal flag is false.
		if (chart.strumLines != null) for (line in chart.strumLines) {
			if (line == null || line.vocalsSuffix == null || line.vocalsSuffix == "") continue;
			var lineVoicesPath = Paths.voices(songName, request.difficulty, line.vocalsSuffix);
			if (Assets.exists(lineVoicesPath)) add(lineVoicesPath, AUDIO, false, Options.streamedVocals);
		}

		var stageName = chart.stage;
		if (stageName == null || stageName.trim() == "") stageName = Flags.DEFAULT_STAGE;
		var stageXML = Stage.getStageXML(stageName);
		if (stageXML != null) {
			var parentFolder = stageXML.getAtt("folder").getDefault("");
			if (parentFolder != "" && !parentFolder.endsWith("/")) parentFolder += "/";
			for (node in selectedStageNodes(stageXML)) {
				if ((node.name != "sprite" && node.name != "spr" && node.name != "sparrow") || !node.has.sprite || !node.has.name) continue;
				for (sheetPath in XMLUtil.getSpriteSheetPathsFromXML(node, node.getAtt("name"), parentFolder))
					add(Paths.image(sheetPath, null, true), IMAGE, false, null);
			}
		}

		if (chart.strumLines != null) for (line in chart.strumLines) {
			if (line == null || line.characters == null) continue;
			for (characterName in line.characters) {
				if (characterName == null || characterName == "") continue;
				var characterXML:Access = Character.getXMLFromCharName(characterName);
				if (characterXML == null) continue;
				for (sheetPath in XMLUtil.getSpriteSheetPathsFromXML(characterXML, characterName, "characters/"))
					add(Paths.image(sheetPath, null, true), IMAGE, false, null);
			}
		}

		function checkAndAddVideo(videoName:String):Void {
			if (videoName == null) return;
			var clean = StringTools.trim(videoName);
			if (clean.length == 0) return;
			if (StringTools.endsWith(clean.toLowerCase(), ".mp4"))
				clean = clean.substr(0, clean.length - 4);

			var vidPath = Paths.video(clean);
			if (openfl.utils.Assets.exists(vidPath)) {
				add(vidPath, VIDEO, false, null);
			} else {
				var direct = Paths.file('videos/$clean.mp4');
				if (openfl.utils.Assets.exists(direct)) {
					add(direct, VIDEO, false, null);
				}
			}
		}

		if (chart.events != null) {
			for (event in chart.events) {
				if (event == null || event.name == null) continue;
				var evName = StringTools.trim(event.name).toLowerCase();
				if (evName == "play video" || evName == "playvideo" || evName == "startvideo" || evName == "video cutscene" || evName == "video") {
					if (event.params != null && event.params.length > 0) {
						checkAndAddVideo(Std.string(event.params[0]));
					}
				}
				if (evName == "change character" && event.params != null && event.params.length >= 2) {
					var p0 = StringTools.trim(Std.string(event.params[0]));
					var p1 = StringTools.trim(Std.string(event.params[1]));
					var charName:String = p1;
					var p0Lower = p0.toLowerCase();
					if (p0Lower != "dad" && p0Lower != "0" && p0Lower != "opponent"
						&& p0Lower != "boyfriend" && p0Lower != "bf" && p0Lower != "1" && p0Lower != "player"
						&& p0Lower != "girlfriend" && p0Lower != "gf" && p0Lower != "2") {
						charName = p0;
					}
					if (charName != null && charName.length > 0) {
						var characterXML:Access = Character.getXMLFromCharName(charName);
						if (characterXML != null) {
							for (sheetPath in XMLUtil.getSpriteSheetPathsFromXML(characterXML, charName, "characters/"))
								add(Paths.image(sheetPath, null, true), IMAGE, false, null);
						}
					}
				}
			}
		}

		var songPath = Paths.formatToSongPath(songName);
		var scriptDirs:Array<String> = ['data/$songPath/', 'songs/$songPath/'];
		if (chart.meta.name != null && chart.meta.name != songPath) {
			scriptDirs.push('data/${chart.meta.name}/');
			scriptDirs.push('songs/${chart.meta.name}/');
		}

		var videoEReg:EReg = ~/startVideo\s*\(\s*['"]([^'"]+)['"]/i;
		for (dir in scriptDirs) {
			for (file in Paths.getFolderContent(dir, true)) {
				var ext = haxe.io.Path.extension(file).toLowerCase();
				if (ext == "lua" || ext == "hx") {
					var scriptPath = Paths.script(file);
					if (openfl.utils.Assets.exists(scriptPath)) {
						var txt = openfl.utils.Assets.getText(scriptPath);
						if (txt != null) {
							var scanTxt = txt;
							while (videoEReg.match(scanTxt)) {
								var matchedVid = videoEReg.matched(1);
								checkAndAddVideo(matchedVid);
								scanTxt = videoEReg.matchedRight();
							}
						}
					}
				}
			}
		}

		if (openfl.utils.Assets.exists(Paths.video(songPath))) checkAndAddVideo(songPath);
		if (openfl.utils.Assets.exists(Paths.video(songName))) checkAndAddVideo(songName);

		return manifest;
	}

	static function selectedStageNodes(stageXML:Access):Array<Access> {
		var selected:Array<Access> = [];
		for (node in stageXML.elements) {
			if (node.name == "high-memory") {
				if (!Options.lowMemoryMode) for (child in node.elements) selected.push(child);
			} else if (node.name == "low-memory") {
				if (Options.lowMemoryMode) for (child in node.elements) selected.push(child);
			} else {
				selected.push(node);
			}
		}
		return selected;
	}
}
