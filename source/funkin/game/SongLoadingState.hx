package funkin.game;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxColor;
import funkin.backend.FunkinText;
import funkin.backend.MusicBeatState;
import funkin.backend.assets.SongLoadRequest;
import funkin.backend.assets.SongLoader;
import funkin.menus.MainMenuState;

/** Small engine-owned loading screen for one SongLoader generation. */
class SongLoadingState extends MusicBeatState {
	final generation:Int;
	final request:SongLoadRequest;
	var firstUpdate:Bool = true;
	var transitioning:Bool = false;
	var failed:Bool = false;

	var progressFill:FlxSprite;
	var progressText:FunkinText;
	var phaseText:FunkinText;
	var errorText:FunkinText;
	var hintText:FunkinText;

	public function new(generation:Int, request:SongLoadRequest) {
		super(false);
		this.generation = generation;
		this.request = request;
	}

	public override function create():Void {
		super.create();
		FlxG.camera.bgColor = FlxColor.BLACK;

		var background = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		background.scrollFactor.set();
		add(background);

		var title = new FunkinText(40, FlxG.height * 0.30, FlxG.width - 80, "Carregando música", 34);
		title.alignment = CENTER;
		add(title);

		var songText = new FunkinText(40, title.y + title.height + 16, FlxG.width - 80,
			'${request.songName}  •  ${request.difficulty}', 22);
		songText.alignment = CENTER;
		add(songText);

		phaseText = new FunkinText(40, FlxG.height * 0.52, FlxG.width - 80, "Preparando...", 18);
		phaseText.alignment = CENTER;
		add(phaseText);

		var barWidth = Std.int(Math.min(620, FlxG.width - 100));
		var barX = Std.int((FlxG.width - barWidth) * 0.5);
		var barY = Std.int(FlxG.height * 0.61);
		var barBackground = new FlxSprite(barX, barY).makeGraphic(barWidth, 20, 0xFF302A38);
		barBackground.scrollFactor.set();
		add(barBackground);

		progressFill = new FlxSprite(barX, barY).makeGraphic(barWidth, 20, 0xFF45D9F2);
		progressFill.origin.set(0, 0);
		progressFill.scrollFactor.set();
		progressFill.scale.x = 0;
		add(progressFill);

		progressText = new FunkinText(barX, barY + 28, barWidth, "0%", 16);
		progressText.alignment = CENTER;
		add(progressText);

		errorText = new FunkinText(50, barY + 68, FlxG.width - 100, "", 16);
		errorText.alignment = CENTER;
		errorText.color = FlxColor.RED;
		errorText.visible = false;
		add(errorText);

		hintText = new FunkinText(30, FlxG.height - 44, FlxG.width - 60,
			"ESC: cancelar", 16);
		hintText.alignment = CENTER;
		add(hintText);
	}

	public override function createPost():Void {
		// The inherited transition fades the loading UI for 2/3s while loading continues.
		// Skip it so short loads are not hidden under a full-screen transition.
		MusicBeatState.skipTransIn = true;
		super.createPost();
	}

	public function cachePreloadedGraphic(graphic:FlxGraphic):Void {
		graphicCache.cacheGraphic(graphic);
	}

	public override function update(elapsed:Float):Void {
		super.update(elapsed);
		if (transitioning || !SongLoader.isActive(generation)) return;

		if (failed) {
			if (controls.ACCEPT || controls.BACK || FlxG.keys.justPressed.ESCAPE) returnToMenu();
			return;
		}

		if (controls.BACK || FlxG.keys.justPressed.ESCAPE) {
			SongLoader.cancel(generation);
			returnToMenu();
			return;
		}

		if (firstUpdate) {
			firstUpdate = false;
			return;
		}

		SongLoader.update(generation);
		var progress = SongLoader.progress(generation);
		progressFill.scale.x = progress;
		progressText.text = '${Std.int(progress * 100)}%';
		phaseText.text = phaseLabel(SongLoader.currentPhase(generation));

		var error = SongLoader.errorMessage(generation);
		if (error != null) {
			showFailure(error);
			return;
		}

		if (SongLoader.isComplete(generation)) {
			transitioning = true;
			FlxG.switchState(new PlayState());
		}
	}

	public function showFailure(message:String):Void {
		if (failed) return;
		failed = true;
		phaseText.text = 'Falha na etapa: ${SongLoader.currentPhase(generation)}';
		errorText.text = message == null ? "Falha desconhecida ao carregar a música." : message;
		errorText.visible = true;
		hintText.text = "ENTER ou ESC: voltar ao menu";
	}

	function returnToMenu():Void {
		if (transitioning) return;
		transitioning = true;
		FlxG.switchState(new MainMenuState());
	}

	static function phaseLabel(phase:String):String {
		return switch (phase) {
			case "chart": "Lendo chart...";
			case "manifest": "Listando recursos da música...";
			case "assets": "Carregando imagens e áudio...";
			case "completed": "Pronto";
			case "failed": "Falha no carregamento";
			case "cancelled": "Cancelado";
			default: "Preparando...";
		};
	}
}
