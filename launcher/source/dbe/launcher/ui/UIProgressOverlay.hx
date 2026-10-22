package dbe.launcher.ui;

import dbe.launcher.App;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;

class UIProgressOverlay extends FlxSpriteGroup {
	var backdrop:FlxSprite;
	var panel:FlxSprite;
	var panelBorder:FlxSprite;

	var titleText:FlxText;
	var statusText:FlxText;
	var detailText:FlxText;
	var percentText:FlxText;

	var barBg:FlxSprite;
	var barFill:FlxSprite;

	var cancelBtn:UIButton;
	var closeBtn:UIButton;

	var lastBytes:Float = 0;
	var lastTime:Float = 0;
	var speed:Float = 0;

	public function new() {
		super(0, 0);

		backdrop = new FlxSprite(0, 0);
		backdrop.makeGraphic(960, 540, 0xCC000000);
		add(backdrop);

		var pw = 580;
		var ph = 240;
		var px = (960 - pw) / 2;
		var py = (540 - ph) / 2;

		panelBorder = new FlxSprite(px, py);
		panelBorder.makeGraphic(pw, ph, UITheme.BORDER_LIGHT);
		add(panelBorder);

		panel = new FlxSprite(px + 2, py + 2);
		panel.makeGraphic(pw - 4, ph - 4, UITheme.BG_PANEL);
		add(panel);

		titleText = new FlxText(px + 20, py + 20, pw - 40, "OPERACAO EM ANDAMENTO", 18);
		titleText.font = UITheme.FONT;
		titleText.color = UITheme.PRIMARY;
		add(titleText);

		statusText = new FlxText(px + 20, py + 55, pw - 40, "Iniciando...", 14);
		statusText.font = UITheme.FONT;
		statusText.color = UITheme.TEXT;
		add(statusText);

		// Progress Bar
		var barW = pw - 40;
		var barH = 18;
		var barX = px + 20;
		var barY = py + 95;

		barBg = new FlxSprite(barX, barY);
		barBg.makeGraphic(barW, barH, UITheme.BG_CARD);
		add(barBg);

		barFill = new FlxSprite(barX, barY);
		barFill.makeGraphic(1, barH, UITheme.PRIMARY);
		add(barFill);

		percentText = new FlxText(px + 20, barY + 24, pw - 40, "0%", 13);
		percentText.font = UITheme.FONT;
		percentText.alignment = RIGHT;
		percentText.color = UITheme.TEXT_MUTED;
		add(percentText);

		detailText = new FlxText(px + 20, barY + 24, pw - 120, "", 12);
		detailText.font = UITheme.FONT;
		detailText.color = UITheme.TEXT_MUTED;
		add(detailText);

		cancelBtn = new UIButton(Math.floor(px + (pw - 140) / 2), Math.floor(py + ph - 55), 140, 36, "Cancelar", () -> {
			App.cancel();
			cancelBtn.enabled = false;
			cancelBtn.setText("Cancelando...");
		}, UITheme.DANGER, 14);
		add(cancelBtn);

		closeBtn = new UIButton(Math.floor(px + (pw - 140) / 2), Math.floor(py + ph - 55), 140, 36, "Fechar", () -> {
			hide();
		}, UITheme.BG_CARD, 14);
		closeBtn.visible = false;
		add(closeBtn);

		visible = false;
	}

	public function show(title:String) {
		titleText.text = title.toUpperCase();
		statusText.text = "Aguarde...";
		detailText.text = "";
		percentText.text = "0%";
		barFill.scale.x = 0;
		barFill.visible = false;
		cancelBtn.visible = true;
		cancelBtn.enabled = true;
		cancelBtn.setText("Cancelar");
		closeBtn.visible = false;
		lastBytes = 0;
		lastTime = Sys.time();
		speed = 0;
		visible = true;
	}

	public function hide() {
		visible = false;
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		if (!visible) return;

		var p = App.getProgress();
		var isBusy = Worker.busy;

		if (!isBusy) {
			cancelBtn.visible = false;
			closeBtn.visible = true;
			if (App.lastError != "") {
				titleText.text = "FALHA NA OPERACAO";
				titleText.color = UITheme.DANGER;
				statusText.text = App.lastError;
				statusText.color = UITheme.DANGER_HOVER;
				detailText.text = "Consulte launcher.log para mais detalhes.";
			} else {
				titleText.text = "CONCLUIDO COM SUCESSO!";
				titleText.color = UITheme.SUCCESS;
				statusText.text = "Operacao finalizada com exito.";
				statusText.color = UITheme.SUCCESS;
				detailText.text = "";
				barFill.scale.x = barBg.width;
				barFill.visible = true;
				percentText.text = "100%";
			}
			return;
		}

		var now = Sys.time();
		var dt = now - lastTime;
		if (dt >= 0.5) {
			if (p.done > lastBytes && dt > 0) {
				speed = (p.done - lastBytes) / dt;
			}
			lastBytes = p.done;
			lastTime = now;
		}

		var barW = barBg.width;
		var pct = p.total > 0 ? Math.min(1.0, Math.max(0.0, p.done / p.total)) : 0;
		barFill.scale.x = barW * pct;
		barFill.x = barBg.x + (barFill.scale.x / 2);
		barFill.visible = pct > 0;

		percentText.text = Math.floor(pct * 100) + "%";

		switch (p.phase) {
			case FetchingReleases:
				statusText.text = "Consultando releases no GitHub...";
				detailText.text = "";
			case FetchingManifest:
				statusText.text = "Baixando manifesto da versao " + p.detail + "...";
				detailText.text = "";
			case Verifying:
				statusText.text = "Verificando arquivos locais (" + Math.floor(p.done) + "/" + Math.floor(p.total) + ")...";
				detailText.text = p.detail;
			case Downloading:
				statusText.text = "Baixando: " + UITheme.formatBytes(p.done) + " / " + UITheme.formatBytes(p.total);
				var spdStr = speed > 0 ? " • " + UITheme.formatSpeed(speed) : "";
				detailText.text = p.detail + spdStr;
			case Applying:
				statusText.text = "Aplicando atualizacao (" + Math.floor(p.done) + "/" + Math.floor(p.total) + ")...";
				detailText.text = p.detail;
			case RollingBack:
				statusText.text = "Revertendo alteracoes (" + Math.floor(p.done) + "/" + Math.floor(p.total) + ")...";
				detailText.text = p.detail;
			case Done:
				statusText.text = "Finalizado!";
				detailText.text = "";
			case Idle:
		}
	}
}
