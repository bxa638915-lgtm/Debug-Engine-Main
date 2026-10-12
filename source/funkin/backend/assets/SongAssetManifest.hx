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
}

typedef SongAssetEntry = {
	var path:String;
	var kind:SongAssetKind;
	var required:Bool;
	var stream:Null<Bool>;
}

/** Static, side-effect-free list of resources used when a chart first enters gameplay. */
class SongAssetManifest {
	public var entries:Array<SongAssetEntry> = [];
	public var duplicateCount:Int = 0;

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
			var entry:SongAssetEntry = {path: path, kind: kind, required: required, stream: stream};
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
				for (sheetPath in XMLUtil.getSpriteSheetPathsFromXML(characterXML, characterName, ""))
					add(Paths.image(sheetPath, null, true), IMAGE, false, null);
			}
		}

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
