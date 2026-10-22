package funkin.editors.uibuilder;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.FlxSubState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import funkin.backend.FunkinText;
import funkin.backend.chart.ChartData;
import funkin.backend.system.Flags;
import funkin.backend.utils.FunkinParentDisabler;
import funkin.game.PlayState;
import funkin.menus.MainMenuState;
import funkin.menus.ModSwitchMenu;
import funkin.menus.PauseSubState;
import funkin.menus.StoryMenuState;
import funkin.menus.ui.Alphabet;

/**
 * Informações de introspecção sobre um membro gráfico de um State real em execução.
 */
typedef LiveMemberInfo = {
	var id:String;
	var member:FlxBasic;
	var sprite:FlxSprite;
	var typeName:String;
	var originalX:Float;
	var originalY:Float;
	var width:Float;
	var height:Float;
}

/**
 * Hospedeiro para execução e inspeção de código real de FlxState e FlxSubState no UI Editor.
 * Executa o create() autêntico do State/SubState alvo dentro de um ambiente seguro,
 * redirecionando a renderização dos membros genuínos para a câmera do editor.
 */
class LiveStateHost {
	public static var currentActiveState:FlxBasic = null;
	public static var scrapedMembers:Array<LiveMemberInfo> = [];
	public static var isInteractive:Bool = false;
	public static var lastInterceptedStateChange:String = null;

	/**
	 * Instancia e executa o código nativo do State/SubState pelo nome da classe.
	 */
	public static function loadLiveState(className:String, targetCamera:FlxCamera):Array<LiveMemberInfo> {
		destroyCurrentState();

		_setupSafeEnvironment(className);

		var instance:Dynamic = null;
		var shortName = className.split(".").pop();
		try {
			switch (shortName) {
				case "PauseSubState":
					instance = new PauseSubState();
				case "MainMenuState":
					instance = new MainMenuState();
				case "StoryMenuState":
					instance = new StoryMenuState();
				case "ModSwitchMenu":
					instance = new ModSwitchMenu();
				default:
					var resolvedClass:Class<Dynamic> = Type.resolveClass(className);
					if (resolvedClass == null) {
						resolvedClass = Type.resolveClass("funkin.menus." + className);
					}
					if (resolvedClass == null)
						throw new haxe.Exception('Classe nao encontrada: $className');
					instance = Type.createInstance(resolvedClass, []);
			}
		} catch (e:Dynamic) {
			throw new haxe.Exception('Falha ao instanciar $className: ${Std.string(e)}');
		}

		currentActiveState = cast instance;

		// Executa o ciclo de vida real da classe diretamente de forma tipada
		if (Std.isOfType(instance, FlxState)) {
			var state:FlxState = cast instance;

			var existingCameras = FlxG.cameras.list.copy();
			var origCamTarget = FlxG.camera.target;
			var origCamScrollX = FlxG.camera.scroll.x;
			var origCamScrollY = FlxG.camera.scroll.y;

			try {
				state.create();
				state.createPost();
			} catch (e:Dynamic) {
				trace('[LiveStateHost] Aviso ao executar create() de $className: ${Std.string(e)}');
			}

			// Remove câmeras extras adicionadas pelo próprio state (ex: subCam em PauseSubState / ModSwitchMenu)
			for (cam in FlxG.cameras.list.copy()) {
				if (!existingCameras.contains(cam) && cam != targetCamera) {
					FlxG.cameras.remove(cam, true);
				}
			}

			// Restaura a câmera do editor
			FlxG.camera.target = origCamTarget;
			FlxG.camera.scroll.set(origCamScrollX, origCamScrollY);

			// Desativa FunkinParentDisabler para não congelar o editor
			var disablers:Array<FlxBasic> = [];
			for (m in state.members) {
				if (Std.isOfType(m, FunkinParentDisabler)) {
					disablers.push(m);
				}
			}
			for (m in disablers) {
				state.remove(m, true);
				m.destroy();
			}
			@:privateAccess {
				for (cam in FlxG.cameras.list) {
					cam.paused = false;
				}
			}

			// Silencia qualquer áudio disparado na criação do state
			if (FlxG.sound.music != null) {
				FlxG.sound.music.volume = 0;
				FlxG.sound.music.pause();
			}
			if (Reflect.hasField(instance, "pauseMusic")) {
				var pm:Dynamic = Reflect.field(instance, "pauseMusic");
				if (pm != null && Std.isOfType(pm, flixel.sound.FlxSound)) {
					cast(pm, flixel.sound.FlxSound).stop();
				}
			}
			for (snd in FlxG.sound.list) {
				if (snd != null && snd.playing && !snd.persist) {
					snd.stop();
				}
			}

			// Warmup: executa passos de simulação para estabilizar itens dinâmicos como Alphabet lerp e posições
			try {
				for (_ in 0...30) {
					state.update(1 / 60);
				}
			} catch (e:Dynamic) {
				trace('[LiveStateHost] Warmup notice: ${Std.string(e)}');
			}

			state.active = false;
			_scrapeGroupMembers(state, targetCamera, "");
		}

		return scrapedMembers;
	}

	/**
	 * Configura ambiente mínimo para evitar Null Pointer ao instanciar substates dependentes de PlayState.
	 */
	private static function _setupSafeEnvironment(className:String):Void {
		if (PlayState.SONG == null) {
			PlayState.SONG = {
				strumLines: [],
				events: [],
				meta: {
					name: "Test Song",
					displayName: "Test Song",
					bpm: 100,
					icon: "face",
					instSuffix: "",
					color: flixel.util.FlxColor.WHITE
				},
				codenameChart: true,
				stage: "stage",
				scrollSpeed: 1.0,
				noteTypes: []
			};
		}

		if (PlayState.difficulty == null || PlayState.difficulty == "") {
			PlayState.difficulty = "normal";
		}

		if (FlxG.sound.music == null) {
			FlxG.sound.music = new flixel.sound.FlxSound();
			FlxG.sound.music.volume = 0;
		}
	}

	/**
	 * Varre recursivamente a lista de membros do State real e redireciona suas câmeras.
	 */
	private static function _scrapeGroupMembers(group:FlxTypedGroup<FlxBasic>, targetCamera:FlxCamera, prefix:String):Void {
		if (group == null || group.members == null) return;

		for (i in 0...group.members.length) {
			var basic = group.members[i];
			if (basic == null) continue;

			if (Std.isOfType(basic, FunkinParentDisabler)) continue;

			if (targetCamera != null) {
				basic.cameras = [targetCamera];
			}

			if (Std.isOfType(basic, FlxTypedGroup)) {
				var subGroup:FlxTypedGroup<FlxBasic> = cast basic;
				var groupName = (prefix == "") ? 'group_$i' : '${prefix}_group_$i';
				_scrapeGroupMembers(subGroup, targetCamera, groupName);
			} else if (Std.isOfType(basic, FlxSprite)) {
				var spr:FlxSprite = cast basic;
				spr.active = false; // Congela logica de animacao de menu/input
				spr.scrollFactor.set(0, 0); // Trava no viewport do canvas do editor
				if (spr.alpha <= 0.05) spr.alpha = 1.0;

				// Identificacao inteligente pelo tipo da classe
				var clsName = Type.getClassName(Type.getClass(spr));
				var shortName = clsName != null ? clsName.split(".").pop() : "Sprite";

				var contextLabel:String = "";
				if (Std.isOfType(spr, Alphabet)) {
					var alph:Alphabet = cast spr;
					if (alph.text != null && alph.text != "") {
						var clean = ~/[^a-zA-Z0-9_]/g.replace(alph.text, "_");
						if (clean.length > 24) clean = clean.substr(0, 24);
						contextLabel = clean;
					}
				} else if (Std.isOfType(spr, FunkinText) || Std.isOfType(spr, FlxText)) {
					var txt:FlxText = cast spr;
					if (txt.text != null && txt.text != "") {
						var clean = ~/[^a-zA-Z0-9_]/g.replace(txt.text, "_");
						if (clean.length > 24) clean = clean.substr(0, 24);
						contextLabel = clean;
					}
				} else if (spr.animation != null && spr.animation.curAnim != null && spr.animation.curAnim.name != null) {
					var animClean = ~/[^a-zA-Z0-9_]/g.replace(spr.animation.curAnim.name, "_");
					contextLabel = animClean;
				}

				var memberId = (prefix == "") ? '$i' : '${prefix}_$i';
				var finalId = contextLabel != "" ? '${shortName}_${contextLabel}' : '${shortName}_$memberId';

				var uniqueId = finalId;
				var counter = 1;
				while (_isIdUsed(uniqueId)) {
					uniqueId = '${finalId}_${counter++}';
				}

				scrapedMembers.push({
					id: uniqueId,
					member: basic,
					sprite: spr,
					typeName: shortName,
					originalX: spr.x,
					originalY: spr.y,
					width: spr.width,
					height: spr.height
				});
			}
		}
	}

	private static function _isIdUsed(id:String):Bool {
		for (m in scrapedMembers) {
			if (m.id == id) return true;
		}
		return false;
	}

	/**
	 * Habilita a interatividade real do State/SubState (Modo Teste do Editor).
	 */
	public static function enableInteractiveMode():Void {
		if (currentActiveState == null) return;
		isInteractive = true;
		lastInterceptedStateChange = null;

		currentActiveState.active = true;
		for (m in scrapedMembers) {
			if (m.sprite != null) m.sprite.active = true;
		}

		// Desmuta ou inicia áudio do menu para teste
		if (FlxG.sound.music != null) {
			FlxG.sound.music.volume = 1;
			if (!FlxG.sound.music.playing) FlxG.sound.music.play();
		} else {
			CoolUtil.playMenuSong();
		}

		if (Reflect.hasField(currentActiveState, "pauseMusic")) {
			var pm:Dynamic = Reflect.field(currentActiveState, "pauseMusic");
			if (pm != null && Std.isOfType(pm, flixel.sound.FlxSound)) {
				cast(pm, flixel.sound.FlxSound).volume = 1;
				cast(pm, flixel.sound.FlxSound).play();
			}
		}
	}

	/**
	 * Desabilita a interatividade, retornando ao modo de edição estático.
	 */
	public static function disableInteractiveMode():Void {
		isInteractive = false;
		lastInterceptedStateChange = null;

		if (currentActiveState != null) {
			currentActiveState.active = false;
		}
		for (m in scrapedMembers) {
			if (m.sprite != null) m.sprite.active = false;
		}

		if (FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			FlxG.sound.music.volume = 0;
		}
		if (Reflect.hasField(currentActiveState, "pauseMusic")) {
			var pm:Dynamic = Reflect.field(currentActiveState, "pauseMusic");
			if (pm != null && Std.isOfType(pm, flixel.sound.FlxSound)) {
				cast(pm, flixel.sound.FlxSound).pause();
			}
		}
		for (snd in FlxG.sound.list) {
			if (snd != null && snd.playing && !snd.persist) {
				snd.stop();
			}
		}
	}

	/**
	 * Executa um frame do ciclo de atualização do State com salvaguarda de transição.
	 */
	public static function updateInteractive(elapsed:Float):Void {
		if (!isInteractive || currentActiveState == null) return;

		if (Std.isOfType(currentActiveState, FlxState)) {
			var state:FlxState = cast currentActiveState;
			try {
				state.update(elapsed);
			} catch (e:Dynamic) {
				trace('[LiveStateHost] Erro no update interativo: ${Std.string(e)}');
			}
		}

		// Intercepta qualquer transição de tela acionada durante o teste
		@:privateAccess {
			if (FlxG.game._nextState != null && FlxG.game._nextState != FlxG.state) {
				var targetClass = Type.getClassName(Type.getClass(FlxG.game._nextState));
				lastInterceptedStateChange = targetClass;
				FlxG.game._nextState = null;

				if (Reflect.hasField(currentActiveState, "selectedSomethin")) {
					Reflect.setField(currentActiveState, "selectedSomethin", false);
				}
			}
		}
	}

	/**
	 * Libera o estado inspecionado com seguranca.
	 */
	public static function destroyCurrentState():Void {
		isInteractive = false;
		lastInterceptedStateChange = null;
		if (currentActiveState != null) {
			if (Reflect.hasField(currentActiveState, "destroy")) {
				try {
					Reflect.callMethod(currentActiveState, Reflect.field(currentActiveState, "destroy"), []);
				} catch (e:Dynamic) {}
			}
			currentActiveState = null;
		}
		scrapedMembers = [];
	}
}
