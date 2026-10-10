package funkin.editors.uibuilder;

import haxe.Json;

enum abstract UIElementType(String) from String to String {
	var PANEL = "panel";
	var BUTTON = "button";
	var TEXT = "text";
	var PROGRESS_BAR = "progressbar";
	var CHECKBOX = "checkbox";
	var IMAGE = "image";
	var CHARACTER = "character";
	var INPUT_BOX = "inputbox";
}

typedef UIElementData = {
	var ?uid:String;
	var ?parentUid:String;
	var id:String;
	var type:UIElementType;
	var x:Float;
	var y:Float;
	var width:Int;
	var height:Int;
	var text:String; // Label text or Character name (e.g. "bf", "green", "red")
	var fontSize:Int;
	var color:Int; // ARGB / RGB
	var bgColor:Int;
	var borderColor:Int;
	var alpha:Float;
	var camera:String; // "camHUD", "camGame", "camOther"
	var scrollFactorX:Float;
	var scrollFactorY:Float;
	var imagePath:String;
	var alignment:String; // "left", "center", "right"
	var visible:Bool;
	var active:Bool;
	var ?extra:Dynamic; // anim, isPlayer, dance, etc.
}

typedef UIProjectData = {
	var ?schemaVersion:Int;
	var name:String;
	var version:String;
	var canvasWidth:Int;
	var canvasHeight:Int;
	var defaultCamera:String;
	var elements:Array<UIElementData>;
}

class UIBuilderData {
	public static inline var CURRENT_SCHEMA_VERSION:Int = 2;
	public static inline var MAX_CANVAS_DIMENSION:Int = 4096;
	public static inline var MAX_CANVAS_PIXELS:Int = 10000000;
	static var _generatedElementUidCounter:Int = 0;

	public static function createDefaultProject(name:String = "NewUI"):UIProjectData {
		return {
			schemaVersion: CURRENT_SCHEMA_VERSION,
			name: name,
			version: "1.0",
			canvasWidth: 1280,
			canvasHeight: 720,
			defaultCamera: "camHUD",
			elements: []
		};
	}

	public static function setCanvasSize(project:UIProjectData, width:Int, height:Int):Void {
		if (project == null)
			throw new haxe.Exception("Invalid UI project: project data is required.");

		var canvasSize:UIProjectData = cast {canvasWidth: width, canvasHeight: height};
		_validateCanvasDimensions(canvasSize);
		project.canvasWidth = width;
		project.canvasHeight = height;
	}

	public static function getCenteredElementPosition(project:UIProjectData, elementWidth:Int, elementHeight:Int):{x:Float, y:Float} {
		_validateCanvasDimensions(project);
		return {
			x: (project.canvasWidth - elementWidth) * 0.5,
			y: (project.canvasHeight - elementHeight) * 0.5
		};
	}

	/**
	 * Calculates camera scroll that centers a canvas after FlxCamera applies zoom around the viewport center.
	 */
	public static function getCenteredCameraScroll(canvasWidth:Int, canvasHeight:Int, viewportWidth:Int, viewportHeight:Int, zoom:Float, initialZoom:Float):{x:Float, y:Float} {
		if (zoom <= 0 || viewportWidth <= 0 || viewportHeight <= 0)
			throw new haxe.Exception("Camera viewport dimensions and zoom must be positive.");

		return {
			x: canvasWidth * 0.5 - (viewportWidth * 0.5 * (1 + zoom - initialZoom)) / zoom,
			y: canvasHeight * 0.5 - (viewportHeight * 0.5 * (1 + zoom - initialZoom)) / zoom
		};
	}

	/**
	 * Template oficial VS Impostor (NVE) Main Menu pré-carregado no UI Builder.
	 */
	public static function createNVEMainMenuProject():UIProjectData {
		var project:UIProjectData = {
			schemaVersion: CURRENT_SCHEMA_VERSION,
			name: "NVEMainMenu",
			version: "1.0",
			canvasWidth: 1280,
			canvasHeight: 720,
			defaultCamera: "camHUD",
			elements: [
				{
					id: "bgVignette",
					type: IMAGE,
					x: 0,
					y: 0,
					width: 1280,
					height: 720,
					text: "",
					fontSize: 18,
					color: 0xFFFFFFFF,
					bgColor: 0xFF000000,
					borderColor: 0xFF00FFC8,
					alpha: 1.0,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "nve/main/vignette",
					alignment: "left",
					visible: true,
					active: true,
					extra: {}
				},
				{
					id: "charGreen",
					type: CHARACTER,
					x: 60,
					y: 160,
					width: 320,
					height: 480,
					text: "green",
					fontSize: 18,
					color: 0xFFFFFFFF,
					bgColor: 0xFF1A1A2E,
					borderColor: 0xFF00FFC8,
					alpha: 1.0,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "nve/main/greenmenu",
					alignment: "left",
					visible: true,
					active: true,
					extra: {anim: "idle", isPlayer: false, dance: true}
				},
				{
					id: "charRed",
					type: CHARACTER,
					x: 880,
					y: 160,
					width: 320,
					height: 480,
					text: "red",
					fontSize: 18,
					color: 0xFFFFFFFF,
					bgColor: 0xFF1A1A2E,
					borderColor: 0xFF00FFC8,
					alpha: 1.0,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "nve/main/redmenu",
					alignment: "left",
					visible: true,
					active: true,
					extra: {anim: "idle", isPlayer: false, dance: true}
				},
				{
					id: "tabletPanel",
					type: PANEL,
					x: 410,
					y: 110,
					width: 460,
					height: 500,
					text: "TERMINAL DE NAVEGACAO",
					fontSize: 18,
					color: 0xFF00FFC8,
					bgColor: 0xEE0B0B16,
					borderColor: 0xFF00FFC8,
					alpha: 0.95,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "nve/main/tablet",
					alignment: "left",
					visible: true,
					active: true,
					extra: {}
				},
				{
					id: "btnStoryMode",
					type: BUTTON,
					x: 445,
					y: 180,
					width: 390,
					height: 54,
					text: "MODO HISTORIA",
					fontSize: 20,
					color: 0xFFFFFFFF,
					bgColor: 0xFF1A1A35,
					borderColor: 0xFF00FFC8,
					alpha: 1.0,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "",
					alignment: "center",
					visible: true,
					active: true,
					extra: {}
				},
				{
					id: "btnFreeplay",
					type: BUTTON,
					x: 445,
					y: 250,
					width: 390,
					height: 54,
					text: "JOGO LIVRE (FREEPLAY)",
					fontSize: 20,
					color: 0xFFFFFFFF,
					bgColor: 0xFF1A1A35,
					borderColor: 0xFF00FFC8,
					alpha: 1.0,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "",
					alignment: "center",
					visible: true,
					active: true,
					extra: {}
				},
				{
					id: "btnOptions",
					type: BUTTON,
					x: 445,
					y: 320,
					width: 390,
					height: 54,
					text: "OPCOES",
					fontSize: 20,
					color: 0xFFFFFFFF,
					bgColor: 0xFF1A1A35,
					borderColor: 0xFF00FFC8,
					alpha: 1.0,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "",
					alignment: "center",
					visible: true,
					active: true,
					extra: {}
				},
				{
					id: "btnCredits",
					type: BUTTON,
					x: 445,
					y: 390,
					width: 390,
					height: 54,
					text: "CREDITOS",
					fontSize: 20,
					color: 0xFFFFFFFF,
					bgColor: 0xFF1A1A35,
					borderColor: 0xFF00FFC8,
					alpha: 1.0,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "",
					alignment: "center",
					visible: true,
					active: true,
					extra: {}
				},
				{
					id: "txtEngineStatus",
					type: TEXT,
					x: 445,
					y: 470,
					width: 390,
					height: 30,
					text: "VS IMPOSTOR ALTERNATED v4.0",
					fontSize: 14,
					color: 0xFF77FFBB,
					bgColor: 0x00000000,
					borderColor: 0x00000000,
					alpha: 0.9,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "",
					alignment: "center",
					visible: true,
					active: true,
					extra: {}
				},
				{
					id: "loadProgress",
					type: PROGRESS_BAR,
					x: 445,
					y: 520,
					width: 390,
					height: 18,
					text: "SISTEMA PRONTO - 100%",
					fontSize: 12,
					color: 0xFF00FFC8,
					bgColor: 0xFF111122,
					borderColor: 0xFF00FFC8,
					alpha: 1.0,
					camera: "camHUD",
					scrollFactorX: 0,
					scrollFactorY: 0,
					imagePath: "",
					alignment: "center",
					visible: true,
					active: true,
					extra: {}
				}
			]
		};
		_ensureElementUids(project);
		return project;
	}

	public static function createElement(type:UIElementType, id:String, x:Float, y:Float, w:Int = 0, h:Int = 0):UIElementData {
		var el:UIElementData = {
			uid: _generateElementUid(new Map<String, Bool>()),
			id: id,
			type: type,
			x: x,
			y: y,
			width: w,
			height: h,
			text: "New " + type,
			fontSize: 18,
			color: 0xFFFFFFFF,
			bgColor: 0xFF1A1A2E,
			borderColor: 0xFF00FFC8,
			alpha: 1.0,
			camera: "camHUD",
			scrollFactorX: 0,
			scrollFactorY: 0,
			imagePath: "",
			alignment: "left",
			visible: true,
			active: true,
			extra: {}
		};

		switch (type) {
			case PANEL:
				el.width = w > 0 ? w : 300;
				el.height = h > 0 ? h : 200;
				el.text = "Panel Title";
				el.bgColor = 0xFF12121E;
				el.borderColor = 0xFF00FFC8;
			case BUTTON:
				el.width = w > 0 ? w : 180;
				el.height = h > 0 ? h : 42;
				el.text = "Click Me";
				el.alignment = "center";
				el.bgColor = 0xFF1F1F35;
				el.borderColor = 0xFF00FFC8;
			case TEXT:
				el.width = w > 0 ? w : 250;
				el.height = h > 0 ? h : 32;
				el.text = "Sample Text";
				el.fontSize = 20;
				el.color = 0xFFFFFFFF;
			case PROGRESS_BAR:
				el.width = w > 0 ? w : 280;
				el.height = h > 0 ? h : 18;
				el.bgColor = 0xFF151520;
				el.color = 0xFF90FF90;
				el.borderColor = 0xFF00FFC8;
				el.text = "50%";
			case CHECKBOX:
				el.width = w > 0 ? w : 180;
				el.height = h > 0 ? h : 28;
				el.text = "Enable Feature";
				el.color = 0xFFFFFFFF;
			case IMAGE:
				el.width = w > 0 ? w : 128;
				el.height = h > 0 ? h : 128;
				el.imagePath = "icons/icon-bf";
				el.text = "";
			case CHARACTER:
				el.width = w > 0 ? w : 250;
				el.height = h > 0 ? h : 350;
				el.text = "bf"; // Nome do personagem
				el.extra = {anim: "idle", isPlayer: false, dance: true};
			case INPUT_BOX:
				el.width = w > 0 ? w : 220;
				el.height = h > 0 ? h : 36;
				el.text = "Enter text...";
				el.bgColor = 0xFF0A0A10;
				el.borderColor = 0xFF444466;
		}

		return el;
	}

	public static function serialize(project:UIProjectData):String {
		var schemaVersion:Dynamic = Reflect.field(project, "schemaVersion");
		if (schemaVersion != null && schemaVersion != CURRENT_SCHEMA_VERSION)
			throw new haxe.Exception('Cannot serialize unsupported UI project schema version: ${Std.string(schemaVersion)}');

		_validateCanvasDimensions(project);
		_ensureElementUids(project);
		_validateElementHierarchy(project);
		var serialized:Dynamic = Reflect.copy(project);
		Reflect.setField(serialized, "schemaVersion", CURRENT_SCHEMA_VERSION);
		return Json.stringify(serialized, "  ");
	}

	/**
	 * Returns visible components in their document order. The last component is drawn on top.
	 * Keep this ordering contract shared by the editor preview and generated runtime layouts.
	 */
	public static function visibleElementsInRenderOrder(project:UIProjectData):Array<UIElementData> {
		if (project == null || project.elements == null)
			return [];

		return [for (element in project.elements) if (element != null && element.visible) element];
	}

	public static function deserialize(jsonStr:String):UIProjectData {
		var parsed:UIProjectData;
		try {
			parsed = Json.parse(jsonStr);
		} catch (e:Dynamic) {
			throw new haxe.Exception('Failed to parse UI project JSON: ${Std.string(e)}', e);
		}

		if (!Reflect.isObject(parsed) || Std.isOfType(parsed, Array))
			throw new haxe.Exception("Invalid UI project JSON: the root value must be an object.");

		var sourceSchemaVersion:Dynamic = Reflect.field(parsed, "schemaVersion");
		if (sourceSchemaVersion != null && !Std.isOfType(sourceSchemaVersion, Int))
			throw new haxe.Exception("Invalid UI project JSON: schemaVersion must be an integer.");

		var schemaVersion:Int = sourceSchemaVersion == null ? 0 : cast sourceSchemaVersion;
		if (schemaVersion < 0 || schemaVersion > CURRENT_SCHEMA_VERSION)
			throw new haxe.Exception('Unsupported UI project schema version: ${schemaVersion}.');

		if (schemaVersion == 0 || schemaVersion == 1) {
			// Versions 0 and 1 used a flat element list. Existing UIDs are kept;
			// elements without a parentUid remain at the document root.
			parsed.schemaVersion = CURRENT_SCHEMA_VERSION;
		}

		_validateCanvasDimensions(parsed);
		if (parsed.elements == null) parsed.elements = [];
		for (el in parsed.elements) {
			if (el.extra == null) el.extra = {};
		}
		_ensureElementUids(parsed);
		_validateElementHierarchy(parsed);
		return parsed;
	}

	/** Returns the validated document elements in stable depth-first tree order. */
	public static function getHierarchyOrder(project:UIProjectData):Array<{element:UIElementData, depth:Int}> {
		if (project == null)
			throw new haxe.Exception("Invalid UI project: project data is required.");
		_ensureElementUids(project);
		_validateElementHierarchy(project);

		var roots:Array<UIElementData> = [];
		var childrenByParent = new Map<String, Array<UIElementData>>();
		for (element in project.elements) {
			var parentUid:Dynamic = Reflect.field(element, "parentUid");
			if (parentUid == null) {
				roots.push(element);
			} else {
				var children = childrenByParent.get(cast parentUid);
				if (children == null) {
					children = [];
					childrenByParent.set(cast parentUid, children);
				}
				children.push(element);
			}
		}

		var ordered:Array<{element:UIElementData, depth:Int}> = [];
		var visited = new Map<String, Bool>();
		var append:UIElementData->Int->Void;
		append = function(element:UIElementData, depth:Int):Void {
			if (visited.exists(element.uid))
				throw new haxe.Exception('Invalid UI project JSON: duplicate element UID "${element.uid}" in hierarchy traversal.');
			visited.set(element.uid, true);
			ordered.push({element: element, depth: depth});
			var children = childrenByParent.get(element.uid);
			if (children != null)
				for (child in children) append(child, depth + 1);
		};
		for (root in roots) append(root, 0);
		if (ordered.length != project.elements.length)
			throw new haxe.Exception("Invalid UI project JSON: hierarchy contains elements that cannot be reached from a root.");
		return ordered;
	}

	/** Returns parent choices that cannot make the selected element self-parented or cyclic. */
	public static function getValidParentCandidates(project:UIProjectData, elementUid:String):Array<UIElementData> {
		if (project == null)
			throw new haxe.Exception("Invalid UI project: project data is required.");
		_ensureElementUids(project);
		_validateElementHierarchy(project);

		var selected:UIElementData = null;
		var byUid = new Map<String, UIElementData>();
		for (element in project.elements) {
			byUid.set(element.uid, element);
			if (element.uid == elementUid) selected = element;
		}
		if (selected == null)
			throw new haxe.Exception('Invalid UI project: element UID "${elementUid}" does not exist.');

		var candidates:Array<UIElementData> = [];
		for (candidate in project.elements) {
			if (candidate.uid == elementUid)
				continue;

			var parentUid:Dynamic = Reflect.field(candidate, "parentUid");
			var visited = new Map<String, Bool>();
			var isDescendant = false;
			while (parentUid != null) {
				if (parentUid == elementUid) {
					isDescendant = true;
					break;
				}
				if (visited.exists(cast parentUid))
					break;
				visited.set(cast parentUid, true);
				var parent = byUid.get(cast parentUid);
				parentUid = parent == null ? null : Reflect.field(parent, "parentUid");
			}
			if (!isDescendant)
				candidates.push(candidate);
		}
		return candidates;
	}

	static function _validateElementHierarchy(project:UIProjectData):Void {
		var byUid = new Map<String, UIElementData>();
		for (element in project.elements) {
			var uid:Dynamic = Reflect.field(element, "uid");
			if (!Std.isOfType(uid, String) || cast(uid, String) == "")
				throw new haxe.Exception("Invalid UI project JSON: every element must have a UID before hierarchy validation.");
			byUid.set(cast uid, element);
		}

		for (element in project.elements) {
			var parentUid:Dynamic = Reflect.field(element, "parentUid");
			if (parentUid == null)
				continue;
			if (!Std.isOfType(parentUid, String) || StringTools.trim(cast parentUid) == "")
				throw new haxe.Exception("Invalid UI project JSON: parentUid must be a non-empty string or null.");
			if (!byUid.exists(cast parentUid))
				throw new haxe.Exception('Invalid UI project JSON: parent UID "${cast parentUid}" does not exist.');
		}

		for (element in project.elements) {
			var visited = new Map<String, Bool>();
			var current:UIElementData = element;
			while (current != null) {
				var uid:String = current.uid;
				if (visited.exists(uid))
					throw new haxe.Exception('Invalid UI project JSON: parent hierarchy contains a cycle at UID "${uid}".');
				visited.set(uid, true);
				var parentUid:Dynamic = Reflect.field(current, "parentUid");
				current = parentUid == null ? null : byUid.get(cast parentUid);
			}
		}
	}

	static function _validateCanvasDimensions(project:UIProjectData):Void {
		if (project == null)
			throw new haxe.Exception("Invalid UI project: project data is required.");

		var width:Dynamic = Reflect.field(project, "canvasWidth");
		var height:Dynamic = Reflect.field(project, "canvasHeight");
		if (!Std.isOfType(width, Int) || !Std.isOfType(height, Int) || (cast width:Int) <= 0 || (cast height:Int) <= 0)
			throw new haxe.Exception("Invalid UI project: canvasWidth and canvasHeight must be positive integers.");

		var canvasWidth:Int = cast width;
		var canvasHeight:Int = cast height;
		if (canvasWidth > MAX_CANVAS_DIMENSION || canvasHeight > MAX_CANVAS_DIMENSION || canvasWidth > Std.int(MAX_CANVAS_PIXELS / canvasHeight))
			throw new haxe.Exception('Invalid UI project: canvas dimensions cannot exceed ${MAX_CANVAS_DIMENSION} per side or ${MAX_CANVAS_PIXELS} pixels total.');
	}

	static function _ensureElementUids(project:UIProjectData):Void {
		if (project.elements == null) project.elements = [];
		var used = new Map<String, Bool>();
		for (element in project.elements) {
			if (element == null)
				throw new haxe.Exception("Invalid UI project JSON: elements cannot contain null entries.");

			var uid:Dynamic = Reflect.field(element, "uid");
			if (uid != null && !Std.isOfType(uid, String))
				throw new haxe.Exception("Invalid UI project JSON: element uid values must be strings.");

			if (uid == null || StringTools.trim(cast uid) == "" || used.exists(cast uid)) {
				element.uid = _generateElementUid(used);
			} else {
				used.set(cast uid, true);
			}
		}
	}

	static function _generateElementUid(used:Map<String, Bool>):String {
		var uid:String;
		do {
			uid = 'uce-${Std.string(Date.now().getTime())}-${_generatedElementUidCounter++}';
		} while (used.exists(uid));
		used.set(uid, true);
		return uid;
	}

	/**
	 * Gera script HScript pronto para execução no Codename Engine.
	 */
	public static function generateHScript(project:UIProjectData):String {
		_validateHScriptExport(project);
		var projectJson = serialize(project);
		var b = new StringBuf();
		b.add("// ============================================================\n");
		b.add('//  UI Layout: ${_singleLine(project.name)} (v${_singleLine(project.version)})\n');
		b.add("//  Gerado automaticamente pelo UI Builder Nativo DBE\n");
		b.add("// ============================================================\n\n");
		b.add("import flixel.FlxG;\n");
		b.add("import flixel.text.FlxText;\n");
		b.add("import funkin.editors.uibuilder.UIBuilderData;\n");
		b.add("import funkin.editors.uibuilder.UIBuilderRuntimeRenderer;\n\n");
		b.add('var uiProjectData = UIBuilderData.deserialize("${_escapeCodeString(projectJson)}");\n');
		b.add("var namedUIElements:Map<String, Dynamic> = new Map();\n");
		b.add("var uiElements:Array<Dynamic> = [];\n\n");
		b.add("var uiTargetState:Dynamic = null;\n\n");

		b.add("// ── Referências públicas aos componentes ──────────────────\n");
		for (el in project.elements) {
			b.add('var ${el.id}:Dynamic = null;\n');
			if (el.type == PANEL) {
				b.add('var ${el.id}_label:FlxText = null;\n');
			}
		}
		b.add("\n");

		b.add("// ── Inicialização ─────────────────────────────────────────\n");
		b.add("function createUI(targetState:Dynamic, ?defaultCam:Dynamic) {\n");
		b.add("    if (targetState == null) targetState = FlxG.state;\n");
		b.add("    UIBuilderRuntimeRenderer.destroyRuntimeElements(uiElements, uiTargetState);\n");
		b.add("    uiTargetState = targetState;\n");
		b.add("    namedUIElements = new Map();\n");
		b.add("    uiElements = UIBuilderRuntimeRenderer.createRuntimeElements(uiProjectData, targetState, defaultCam, namedUIElements);\n");
		for (el in project.elements) {
			b.add('    ${el.id} = namedUIElements.get("${_escapeCodeString(el.id)}");\n');
			if (el.type == PANEL && el.text != "")
				b.add('    ${el.id}_label = cast namedUIElements.get("${_escapeCodeString(el.id)}_label");\n');
		}

		b.add("}\n\n");
		b.add("// ── Destruição ────────────────────────────────────────────\n");
		b.add("function destroyUI(targetState:Dynamic) {\n");
		b.add("    UIBuilderRuntimeRenderer.destroyRuntimeElements(uiElements, uiTargetState != null ? uiTargetState : targetState);\n");
		b.add("    uiElements = [];\n");
		b.add("    uiTargetState = null;\n");
		b.add("}\n");

		return b.toString();
	}

	/**
	 * Gera script Lua pronto para Psych Engine.
	 */
	public static function generatePsychLua(project:UIProjectData):String {
		var b = new StringBuf();
		b.add('-- ============================================================\n');
		b.add('-- UI Layout: ' + _singleLine(project.name) + ' (Psych Engine Lua Export)\n');
		b.add('-- ============================================================\n\n');
		b.add('function onCreatePost()\n');
		for (el in project.elements) {
			var tag = _escapeCodeString(el.id);
			var img = (el.imagePath != null && el.imagePath != "") ? el.imagePath : "icons/icon-bf";
			b.add('\t-- [' + _singleLine(Std.string(el.type)) + '] ' + _singleLine(el.id) + '\n');
			if (el.type == TEXT) {
				b.add('\tmakeLuaText("' + tag + '", "' + _escapeCodeString(el.text) + '", ' + el.width + ', ' + el.x + ', ' + el.y + ')\n');
				b.add('\tsetTextSize("' + tag + '", ' + el.fontSize + ')\n');
				b.add('\tsetTextAlignment("' + tag + '", "' + _escapeCodeString(el.alignment) + '")\n');
				b.add('\tsetObjectCamera("' + tag + '", "' + _psychCamera(el.camera) + '")\n');
				b.add('\taddLuaText("' + tag + '")\n\n');
			} else {
				b.add('\tmakeLuaSprite("' + tag + '", "' + _escapeCodeString(img) + '", ' + el.x + ', ' + el.y + ')\n');
				b.add('\tsetGraphicSize("' + tag + '", ' + el.width + ', ' + el.height + ')\n');
				b.add('\tupdateHitbox("' + tag + '")\n');
				b.add('\tsetObjectCamera("' + tag + '", "' + _psychCamera(el.camera) + '")\n');
				b.add('\taddLuaSprite("' + tag + '", true)\n\n');
			}
		}
		b.add('end\n');
		return b.toString();
	}

	/**
	 * Gera definição XML compatível com a engine.
	 */
	public static function generateXML(project:UIProjectData):String {
		var b = new StringBuf();
		b.add('<?xml version="1.0" encoding="utf-8" ?>\n');
		b.add('<ui name="' + _escapeXmlAttribute(project.name) + '" width="' + project.canvasWidth + '" height="' + project.canvasHeight + '" defaultCamera="' + _escapeXmlAttribute(project.defaultCamera) + '">\n');
		for (el in project.elements) {
			b.add('\t<element id="' + _escapeXmlAttribute(el.id) + '" type="' + _escapeXmlAttribute(Std.string(el.type)) + '" x="' + el.x + '" y="' + el.y + '" width="' + el.width + '" height="' + el.height + '"');
			if (el.text != "") b.add(' text="' + _escapeXmlAttribute(el.text) + '"');
			if (el.imagePath != "") b.add(' image="' + _escapeXmlAttribute(el.imagePath) + '"');
			b.add(' camera="' + _escapeXmlAttribute(el.camera) + '" alpha="' + el.alpha + '" />\n');
		}
		b.add('</ui>\n');
		return b.toString();
	}

	static function escapeQuotes(s:String):String {
		return _escapeCodeString(s);
	}

	static function _validateHScriptExport(project:UIProjectData):Void {
		if (project == null || project.elements == null)
			throw new haxe.Exception("Cannot export an empty UI project to HScript.");

		var symbols = new Map<String, Bool>();
		symbols.set("uiElements", true);
		for (element in project.elements) {
			if (element == null || !_isHaxeIdentifier(element.id))
				throw new haxe.Exception('Cannot export UI element ID as a HScript variable: ${element == null ? "null" : Std.string(element.id)}');
			if (symbols.exists(element.id))
				throw new haxe.Exception('Cannot export duplicate HScript variable name: ${element.id}');
			symbols.set(element.id, true);

			if (element.camera != null && element.camera != "" && !_isHaxeIdentifier(element.camera))
				throw new haxe.Exception('Cannot export camera as a HScript property name: ${element.camera}');
			if (element.type == PANEL && element.text != null && element.text != "") {
				var labelId = element.id + "_label";
				if (symbols.exists(labelId))
					throw new haxe.Exception('Cannot export duplicate HScript variable name: ${labelId}');
				symbols.set(labelId, true);
			}
		}
	}

	static function _isHaxeIdentifier(value:String):Bool {
		if (value == null || value.length == 0)
			return false;
		var first = value.charCodeAt(0);
		if (!((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first == 95))
			return false;
		for (index in 1...value.length) {
			var code = value.charCodeAt(index);
			if (!((code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code == 95))
				return false;
		}
		return switch (value) {
			case "abstract" | "break" | "case" | "cast" | "catch" | "class" | "continue" | "default" | "do" | "dynamic" | "else" | "enum" | "extern" | "false" | "final" | "for" | "function" | "if" | "implements" | "import" | "in" | "inline" | "interface" | "macro" | "new" | "null" | "operator" | "override" | "package" | "private" | "public" | "return" | "static" | "super" | "switch" | "this" | "throw" | "true" | "try" | "typedef" | "untyped" | "using" | "var" | "while": false;
			default: true;
		}
	}

	static function _escapeCodeString(value:String):String {
		if (value == null)
			return "";
		var escaped = new StringBuf();
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			if (code == null)
				continue;
			switch (code) {
				case 0x5C: escaped.add("\\\\");
				case 0x22: escaped.add("\\\"");
				case 0x0A: escaped.add("\\n");
				case 0x0D: escaped.add("\\r");
				case 0x09: escaped.add("\\t");
				case control if (control < 0x20):
					escaped.add("\\x");
					escaped.add(StringTools.hex(control, 2));
				default: escaped.add(value.charAt(index));
			}
		}
		return escaped.toString();
	}

	static function _escapeXmlAttribute(value:String):String {
		if (value == null)
			return "";
		var escaped = new StringBuf();
		for (index in 0...value.length) {
			var code = value.charCodeAt(index);
			if (code == null)
				continue;
			if ((code < 0x20 && code != 0x09 && code != 0x0A && code != 0x0D) || code == 0xFFFE || code == 0xFFFF)
				throw new haxe.Exception('Cannot export invalid XML control character ${StringTools.hex(code, 4)}.');
			switch (code) {
				case 0x26: escaped.add("&amp;");
				case 0x3C: escaped.add("&lt;");
				case 0x3E: escaped.add("&gt;");
				case 0x22: escaped.add("&quot;");
				case 0x27: escaped.add("&apos;");
				case 0x0A: escaped.add("&#10;");
				case 0x0D: escaped.add("&#13;");
				case 0x09: escaped.add("&#9;");
				default: escaped.add(value.charAt(index));
			}
		}
		return escaped.toString();
	}

	static function _singleLine(value:String):String {
		if (value == null)
			return "";
		return StringTools.replace(StringTools.replace(value, "\r", " "), "\n", " ");
	}

	static function _psychCamera(value:String):String {
		return switch (value) {
			case "camGame": "game";
			case "camOther": "other";
			default: "hud";
		}
	}
}
