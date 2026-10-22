package funkin.editors.uibuilder;

import haxe.Json;
import funkin.editors.uibuilder.UIBuilderData;

/**
 * Categorias de telas suportadas em formato .uihx.
 */
enum abstract UIHXScreenType(String) from String to String {
	var STATE = "state";
	var SUBSTATE = "substate";
	var OVERLAY = "overlay";
	var MODAL = "modal";
}

/**
 * Modos de ancoragem e alinhamento responsivo para elementos .uihx.
 */
enum abstract UIHXAnchor(String) from String to String {
	var TOP_LEFT = "top-left";
	var TOP_CENTER = "top-center";
	var TOP_RIGHT = "top-right";
	var CENTER_LEFT = "center-left";
	var CENTER = "center";
	var CENTER_RIGHT = "center-right";
	var BOTTOM_LEFT = "bottom-left";
	var BOTTOM_CENTER = "bottom-center";
	var BOTTOM_RIGHT = "bottom-right";
	var STRETCH = "stretch";
}

/**
 * Curvas de interpolação e aceleração suportadas para animações de UI.
 */
enum abstract UIHXEase(String) from String to String {
	var LINEAR = "linear";
	var QUAD_IN = "quadIn";
	var QUAD_OUT = "quadOut";
	var QUAD_IN_OUT = "quadInOut";
	var CUBE_OUT = "cubeOut";
	var EXPO_OUT = "expoOut";
	var BOUNCE_OUT = "bounceOut";
	var ELASTIC_OUT = "elasticOut";
	var SINE_IN_OUT = "sineInOut";
}

/**
 * Definição de evento / gatilho interativo acoplado a um nó .uihx.
 */
typedef UIHXEventBinding = {
	var trigger:String; // "onClick", "onHover", "onEnter", "onExit"
	var action:String;  // "changeState", "openSubState", "playSound", "tween", "custom"
	var ?target:String; // ID do elemento alvo ou nome da tela/som
	var ?param:Dynamic;
}

/**
 * Definição completa de um nó ou elemento de layout .uihx.
 */
typedef UIHXNode = {
	> UIElementData,
	var ?anchor:UIHXAnchor;
	var ?margin:Array<Float>; // [top, right, bottom, left]
	var ?rotation:Float;
	var ?skewX:Float;
	var ?skewY:Float;
	var ?zIndex:Int;
	var ?shader:String;
	var ?events:Array<UIHXEventBinding>;
}

/**
 * Estrutura do arquivo de tela .uihx (compatível com States e Substates).
 */
typedef UIHXScreenDefinition = {
	var formatVersion:String;
	var screenName:String;
	var screenType:UIHXScreenType;
	var targetStateClass:String;
	var canvasWidth:Int;
	var canvasHeight:Int;
	var defaultCamera:String;
	var ?globalTheme:{
		var primaryColor:Int;
		var secondaryColor:Int;
		var accentColor:Int;
		var backgroundColor:Int;
		var fontName:String;
	};
	var nodes:Array<UIHXNode>;
}

/**
 * Parser, serializador e gerador de templates para arquivos .uihx.
 */
class UIHXData {
	public static inline var FORMAT_VERSION:String = "1.0.0";

	/**
	 * Converte uma string JSON formatada em .uihx para UIHXScreenDefinition.
	 */
	public static function parse(content:String):UIHXScreenDefinition {
		if (content == null || content.length == 0)
			throw new haxe.Exception("Conteudo do arquivo .uihx vazio ou nulo.");

		var parsed:UIHXScreenDefinition;
		try {
			parsed = Json.parse(content);
		} catch (e:Dynamic) {
			throw new haxe.Exception('Falha de sintaxe ao processar arquivo .uihx: ${Std.string(e)}');
		}

		if (parsed == null || parsed.nodes == null)
			throw new haxe.Exception("Formato .uihx invalido: campo 'nodes' ausente ou nulo.");

		return parsed;
	}

	/**
	 * Serializa uma definicao de tela .uihx para string formatada e identada.
	 */
	public static function stringify(screen:UIHXScreenDefinition):String {
		if (screen == null)
			throw new haxe.Exception("Impossivel serializar tela .uihx nula.");

		screen.formatVersion = FORMAT_VERSION;
		return Json.stringify(screen, "  ");
	}

	/**
	 * Converte UIHXScreenDefinition em UIProjectData para edicao no UIBuilderEditor.
	 */
	public static function toProjectData(screen:UIHXScreenDefinition):UIProjectData {
		var proj:UIProjectData = {
			schemaVersion: UIBuilderData.CURRENT_SCHEMA_VERSION,
			name: screen.screenName,
			version: screen.formatVersion,
			canvasWidth: screen.canvasWidth > 0 ? screen.canvasWidth : 1280,
			canvasHeight: screen.canvasHeight > 0 ? screen.canvasHeight : 720,
			defaultCamera: screen.defaultCamera != null ? screen.defaultCamera : "camHUD",
			elements: []
		};

		for (node in screen.nodes) {
			if (node != null) {
				proj.elements.push(cast node);
			}
		}

		return proj;
	}

	/**
	 * Converte dados do projeto do UIBuilderEditor em uma especificacao formal .uihx.
	 */
	public static function fromProjectData(proj:UIProjectData, screenType:UIHXScreenType = STATE, targetState:String = "MainMenuState"):UIHXScreenDefinition {
		var screen:UIHXScreenDefinition = {
			formatVersion: FORMAT_VERSION,
			screenName: proj.name,
			screenType: screenType,
			targetStateClass: targetState,
			canvasWidth: proj.canvasWidth,
			canvasHeight: proj.canvasHeight,
			defaultCamera: proj.defaultCamera,
			globalTheme: {
				primaryColor: 0xFF00FFC8,
				secondaryColor: 0xFF1A1A2E,
				accentColor: 0xFFFF3366,
				backgroundColor: 0xFF0B0B16,
				fontName: "vcr.ttf"
			},
			nodes: []
		};

		for (el in proj.elements) {
			if (el != null) {
				var node:UIHXNode = cast Reflect.copy(el);
				if (node.anchor == null) node.anchor = TOP_LEFT;
				if (node.rotation == null) node.rotation = 0;
				if (node.zIndex == null) node.zIndex = screen.nodes.length;
				screen.nodes.push(node);
			}
		}

		return screen;
	}

	/**
	 * Cria um template oficial .uihx pronto para telas conhecidas do jogo.
	 */
	public static function createScreenTemplate(screenName:String, screenType:UIHXScreenType):UIHXScreenDefinition {
		var targetClass = screenName;
		var isSubstate = (screenType == SUBSTATE || screenType == MODAL);

		var def:UIHXScreenDefinition = {
			formatVersion: FORMAT_VERSION,
			screenName: screenName,
			screenType: screenType,
			targetStateClass: targetClass,
			canvasWidth: 1280,
			canvasHeight: 720,
			defaultCamera: isSubstate ? "camOther" : "camHUD",
			globalTheme: {
				primaryColor: 0xFF00FFC8,
				secondaryColor: 0xFF12121E,
				accentColor: 0xFFFF0055,
				backgroundColor: isSubstate ? 0x99000000 : 0xFF0A0A12,
				fontName: "vcr.ttf"
			},
			nodes: []
		};

		switch (screenName.toLowerCase()) {
			case "mainmenustate" | "mainmenu":
				def.screenType = STATE;
				def.targetStateClass = "MainMenuState";
				def.nodes = [
					{
						id: "bgWallpaper",
						type: IMAGE,
						x: 0,
						y: 0,
						width: 1280,
						height: 720,
						text: "",
						fontSize: 14,
						color: 0xFFFFFFFF,
						bgColor: 0xFF000000,
						borderColor: 0,
						alpha: 1.0,
						camera: "camHUD",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "menus/menuBG",
						alignment: "left",
						visible: true,
						active: true,
						anchor: TOP_LEFT,
						zIndex: 0
					},
					{
						id: "btnStoryMode",
						type: BUTTON,
						x: 80,
						y: 180,
						width: 320,
						height: 54,
						text: "MODO HISTORIA",
						fontSize: 22,
						color: 0xFFFFFFFF,
						bgColor: 0xFF1C1C30,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: "camHUD",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: TOP_LEFT,
						zIndex: 1,
						events: [{trigger: "onClick", action: "changeState", target: "StoryMenuState"}]
					},
					{
						id: "btnFreeplay",
						type: BUTTON,
						x: 80,
						y: 250,
						width: 320,
						height: 54,
						text: "JOGO LIVRE",
						fontSize: 22,
						color: 0xFFFFFFFF,
						bgColor: 0xFF1C1C30,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: "camHUD",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: TOP_LEFT,
						zIndex: 2,
						events: [{trigger: "onClick", action: "changeState", target: "FreeplayState"}]
					},
					{
						id: "btnOptions",
						type: BUTTON,
						x: 80,
						y: 320,
						width: 320,
						height: 54,
						text: "OPCOES",
						fontSize: 22,
						color: 0xFFFFFFFF,
						bgColor: 0xFF1C1C30,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: "camHUD",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: TOP_LEFT,
						zIndex: 3,
						events: [{trigger: "onClick", action: "changeState", target: "OptionsMenu"}]
					},
					{
						id: "lblVersion",
						type: TEXT,
						x: 20,
						y: 685,
						width: 300,
						height: 25,
						text: "DBE ENGINE v1.0.0",
						fontSize: 16,
						color: 0x88FFFFFF,
						bgColor: 0,
						borderColor: 0,
						alpha: 0.8,
						camera: "camHUD",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "left",
						visible: true,
						active: true,
						anchor: BOTTOM_LEFT,
						zIndex: 4
					}
				];

			case "pausesubstate" | "pause":
				def.screenType = SUBSTATE;
				def.targetStateClass = "PauseSubState";
				def.nodes = [
					{
						id: "dimBackground",
						type: PANEL,
						x: 0,
						y: 0,
						width: 1280,
						height: 720,
						text: "",
						fontSize: 14,
						color: 0xFFFFFFFF,
						bgColor: 0xAA000000,
						borderColor: 0,
						alpha: 0.7,
						camera: "camOther",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "left",
						visible: true,
						active: true,
						anchor: TOP_LEFT,
						zIndex: 0
					},
					{
						id: "pauseWindow",
						type: PANEL,
						x: 440,
						y: 160,
						width: 400,
						height: 400,
						text: "JOGO PAUSADO",
						fontSize: 20,
						color: 0xFF00FFC8,
						bgColor: 0xEE121220,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: "camOther",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: CENTER,
						zIndex: 1
					},
					{
						id: "btnResume",
						type: BUTTON,
						x: 480,
						y: 240,
						width: 320,
						height: 48,
						text: "CONTINUAR",
						fontSize: 18,
						color: 0xFFFFFFFF,
						bgColor: 0xFF202035,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: "camOther",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: CENTER,
						zIndex: 2,
						events: [{trigger: "onClick", action: "closeSubState"}]
					},
					{
						id: "btnRestart",
						type: BUTTON,
						x: 480,
						y: 310,
						width: 320,
						height: 48,
						text: "REINICIAR CANCAO",
						fontSize: 18,
						color: 0xFFFFFFFF,
						bgColor: 0xFF202035,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: "camOther",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: CENTER,
						zIndex: 3,
						events: [{trigger: "onClick", action: "custom", param: "restartSong"}]
					},
					{
						id: "btnQuit",
						type: BUTTON,
						x: 480,
						y: 380,
						width: 320,
						height: 48,
						text: "SAIR PARA O MENU",
						fontSize: 18,
						color: 0xFFFFFFFF,
						bgColor: 0xFF202035,
						borderColor: 0xFFFF3366,
						alpha: 1.0,
						camera: "camOther",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: CENTER,
						zIndex: 4,
						events: [{trigger: "onClick", action: "changeState", target: "MainMenuState"}]
					}
				];

			case "storymenustate" | "storymenu":
				def.screenType = STATE;
				def.targetStateClass = "StoryMenuState";
				def.nodes = [
					{
						id: "storyHeaderPanel",
						type: PANEL,
						x: 0,
						y: 0,
						width: 1280,
						height: 80,
						text: "SELECIONE A SEMANA",
						fontSize: 24,
						color: 0xFF00FFC8,
						bgColor: 0xEE0B0B14,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: "camHUD",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: TOP_CENTER,
						zIndex: 0
					},
					{
						id: "bannerWeek",
						type: IMAGE,
						x: 240,
						y: 120,
						width: 800,
						height: 380,
						text: "",
						fontSize: 14,
						color: 0xFFFFFFFF,
						bgColor: 0xFF000000,
						borderColor: 0xFF333355,
						alpha: 1.0,
						camera: "camHUD",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "menus/storymenu/week1",
						alignment: "center",
						visible: true,
						active: true,
						anchor: CENTER,
						zIndex: 1
					},
					{
						id: "difficultySelector",
						type: BUTTON,
						x: 490,
						y: 530,
						width: 300,
						height: 50,
						text: "< NORMAL >",
						fontSize: 20,
						color: 0xFFFFFFFF,
						bgColor: 0xFF1C1C30,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: "camHUD",
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "center",
						visible: true,
						active: true,
						anchor: CENTER,
						zIndex: 2
					}
				];

			default:
				def.nodes = [
					{
						id: "rootPanel",
						type: PANEL,
						x: 40,
						y: 40,
						width: 1200,
						height: 640,
						text: screenName,
						fontSize: 22,
						color: 0xFF00FFC8,
						bgColor: 0xEE10101C,
						borderColor: 0xFF00FFC8,
						alpha: 1.0,
						camera: def.defaultCamera,
						scrollFactorX: 0,
						scrollFactorY: 0,
						imagePath: "",
						alignment: "left",
						visible: true,
						active: true,
						anchor: TOP_LEFT,
						zIndex: 0
					}
				];
		}

		return def;
	}
}
