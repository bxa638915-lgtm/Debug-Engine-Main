package funkin.editors.uibuilder;

import flixel.FlxBasic;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.FlxSubState;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.editors.uibuilder.UIHXData;
import funkin.editors.uibuilder.LiveStateHost.LiveMemberInfo;
import sys.FileSystem;
import sys.io.File;

/**
 * Ponte bidirecional entre arquivos .uihx e instâncias nativas em execução de FlxState e FlxSubState.
 * Permite capturar objetos reais gerados pelo código da tela e reinjetar ajustes de layout
 * em tempo de execução sem alterar o código original.
 */
class UIHXStateBridge {
	/**
	 * Converte os membros reais extraídos do State em uma definição estruturada .uihx.
	 */
	public static function captureLiveStateToUIHX(
		members:Array<LiveMemberInfo>,
		screenName:String,
		screenType:UIHXScreenType = STATE,
		targetClass:String = ""
	):UIHXScreenDefinition {
		var def:UIHXScreenDefinition = {
			formatVersion: UIHXData.FORMAT_VERSION,
			screenName: screenName,
			screenType: screenType,
			targetStateClass: targetClass != "" ? targetClass : screenName,
			canvasWidth: 1280,
			canvasHeight: 720,
			defaultCamera: (screenType == SUBSTATE || screenType == MODAL) ? "camOther" : "camHUD",
			nodes: []
		};

		for (i in 0...members.length) {
			var m = members[i];
			var spr = m.sprite;
			if (spr == null) continue;

			var node:UIHXNode = {
				id: m.id,
				type: IMAGE,
				x: spr.x,
				y: spr.y,
				width: Std.int(Math.max(1, spr.width)),
				height: Std.int(Math.max(1, spr.height)),
				text: "",
				fontSize: 14,
				color: spr.color,
				bgColor: 0,
				borderColor: 0,
				alpha: spr.alpha,
				camera: def.defaultCamera,
				scrollFactorX: spr.scrollFactor.x,
				scrollFactorY: spr.scrollFactor.y,
				imagePath: "",
				alignment: "left",
				visible: spr.visible,
				active: true,
				anchor: TOP_LEFT,
				rotation: spr.angle,
				zIndex: i
			};

			def.nodes.push(node);
		}

		return def;
	}

	/**
	 * Aplica as alterações de um arquivo .uihx correspondente sobre a tela real em execução no jogo.
	 */
	public static function apply(stateInstance:FlxBasic, className:String):Void {
		if (stateInstance == null || className == null) return;

		var shortName = className.split(".").pop();
		var filePath = 'assets/data/ui/${shortName.toLowerCase()}.uihx';

		#if sys
		if (!FileSystem.exists(filePath)) {
			filePath = 'assets/data/ui/${shortName}.uihx';
		}

		if (!FileSystem.exists(filePath)) return;

		try {
			var raw = File.getContent(filePath);
			var def = UIHXData.parse(raw);
			applyDefinition(stateInstance, def);
		} catch (e:Dynamic) {
			trace('[UIHXStateBridge] Nao foi possivel aplicar .uihx a $shortName: ${Std.string(e)}');
		}
		#end
	}

	/**
	 * Aplica a definição .uihx diretamente sobre os membros de uma tela ativa.
	 */
	public static function applyDefinition(stateInstance:FlxBasic, def:UIHXScreenDefinition):Void {
		if (stateInstance == null || def == null || def.nodes == null) return;

		var sprites:Array<FlxSprite> = [];
		_gatherSprites(stateInstance, sprites);

		var nodeMap:Map<String, UIHXNode> = [];
		for (node in def.nodes) {
			if (node != null && node.id != null) nodeMap.set(node.id, node);
		}

		for (i in 0...sprites.length) {
			var spr = sprites[i];
			var clsName = Type.getClassName(Type.getClass(spr));
			var shortName = clsName != null ? clsName.split(".").pop() : "Sprite";
			var candidateId = '${shortName}_member_$i';

			var node:UIHXNode = null;
			if (nodeMap.exists(candidateId)) {
				node = nodeMap.get(candidateId);
			} else if (i < def.nodes.length && (def.nodes[i].id.indexOf(shortName) >= 0 || def.nodes.length == sprites.length)) {
				node = def.nodes[i];
			}

			if (node != null) {
				spr.x = node.x;
				spr.y = node.y;
				spr.alpha = node.alpha;
				if (node.rotation != null) spr.angle = node.rotation;
				spr.visible = node.visible;
			}
		}
	}

	private static function _gatherSprites(container:FlxBasic, out:Array<FlxSprite>):Void {
		if (container == null) return;

		if (Std.isOfType(container, FlxTypedGroup)) {
			var group:FlxTypedGroup<FlxBasic> = cast container;
			for (member in group.members) {
				if (member != null) _gatherSprites(member, out);
			}
		} else if (Std.isOfType(container, FlxSprite)) {
			out.push(cast container);
		}
	}
}
