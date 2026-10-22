package dbe.modchart;

import flixel.math.FlxMath;

/**
 * Estrutura de dados contendo os coeficientes de intensidade dos modificadores de modchart.
 */
typedef ModchartConfig = {
	var name:String;
	var drunk:Float;
	var tipsy:Float;
	var bumpy:Float;
	var wave:Float;
	var speed:Float;
	var beatZoom:Float;
	var invert:Float;
	var flip:Float;
	var steer:Float;
	var tornado:Float;
	var spiral:Float;
	var pitch:Float;
	var roll:Float;
	var scaleX:Float;
	var scaleY:Float;
	var alpha:Float;
}

/**
 * Transformada espacial 2D/3D resultante aplicada a um receptor ou nota.
 */
typedef ModchartTransform = {
	var x:Float;
	var y:Float;
	var z:Float;
	var angle:Float;
	var scaleX:Float;
	var scaleY:Float;
	var alpha:Float;
}

/**
 * Simulador de alta precisão para modificadores de modchart e strumlines.
 * Utilizado pelo Charter para pré-visualização em tempo real e pelo motor de gameplay.
 */
class ModchartSimulator {
	public static function createDefaultConfig(name:String = "Default"):ModchartConfig {
		return {
			name: name,
			drunk: 0.0,
			tipsy: 0.0,
			bumpy: 0.0,
			wave: 0.0,
			speed: 1.0,
			beatZoom: 0.0,
			invert: 0.0,
			flip: 0.0,
			steer: 0.0,
			tornado: 0.0,
			spiral: 0.0,
			pitch: 0.0,
			roll: 0.0,
			scaleX: 1.0,
			scaleY: 1.0,
			alpha: 1.0
		};
	}

	/**
	 * Calcula a transformação de um receptor (strum) específico.
	 */
	public static function calculateReceptorTransform(
		index:Int,
		totalStrums:Int,
		isPlayer:Bool,
		baseX:Float,
		baseY:Float,
		songPos:Float,
		curBeat:Float,
		config:ModchartConfig
	):ModchartTransform {
		var time = (songPos * 0.001) * config.speed;
		var offsetX:Float = 0.0;
		var offsetY:Float = 0.0;
		var offsetAngle:Float = 0.0;
		var scaleMultiplier:Float = 1.0;

		// 1. Drunk (Ondulação no eixo X baseada no índice da seta)
		if (config.drunk != 0) {
			offsetX += Math.cos(time * 3.0 + index * 0.8) * (config.drunk * 40.0);
		}

		// 2. Tipsy (Ondulação vertical alternada)
		if (config.tipsy != 0) {
			offsetY += Math.sin(time * 4.0 + (index % 2 == 0 ? 0 : Math.PI)) * (config.tipsy * 35.0);
		}

		// 3. Wave (Onda contínua senoidal)
		if (config.wave != 0) {
			offsetY += Math.sin(time * 2.5 + index * 0.5) * (config.wave * 25.0);
		}

		// 4. Invert & Flip (Inversão e espelhamento de receptores)
		if (config.invert != 0) {
			var dist = (index == 0 || index == 3) ? 1.0 : -1.0;
			offsetX += dist * (config.invert * 50.0);
		}
		if (config.flip != 0) {
			var centerDist = (index - (totalStrums - 1) * 0.5);
			offsetX += (-centerDist * 2.0) * (config.flip * 45.0);
		}

		// 5. Tornado (Efeito redemoinho giratório)
		if (config.tornado != 0) {
			var rad = time * 3.5 + (index / totalStrums) * Math.PI * 2;
			offsetX += Math.sin(rad) * (config.tornado * 60.0);
			offsetAngle += Math.cos(rad) * (config.tornado * 35.0);
		}

		// 6. Spiral (Órbita espiral em torno do centro do strum)
		if (config.spiral != 0) {
			var angleRad = time * 2.0 + index * 0.7;
			var radius = config.spiral * 45.0;
			offsetX += Math.cos(angleRad) * radius;
			offsetY += Math.sin(angleRad) * radius;
		}

		// 7. Beat Zoom (Pulsar no ritmo da batida)
		if (config.beatZoom != 0) {
			var beatFract = curBeat - Math.floor(curBeat);
			var pulse = Math.max(0, 1.0 - beatFract * 2.5);
			scaleMultiplier += pulse * (config.beatZoom * 0.25);
		}

		// 8. Steer e Rotações 3D
		if (config.steer != 0) {
			offsetAngle += config.steer * 25.0;
		}
		if (config.roll != 0) {
			offsetAngle += config.roll;
		}

		// 9. Bumpy (Pulso de escala periódico)
		if (config.bumpy != 0) {
			var bump = Math.sin(time * 5.0 + index);
			scaleMultiplier += bump * (config.bumpy * 0.2);
		}

		return {
			x: baseX + offsetX,
			y: baseY + offsetY,
			z: 0.0,
			angle: offsetAngle,
			scaleX: config.scaleX * scaleMultiplier,
			scaleY: config.scaleY * scaleMultiplier,
			alpha: FlxMath.bound(config.alpha, 0.0, 1.0)
		};
	}

	/**
	 * Calcula a transformação de uma nota que desce/sobe até o receptor.
	 */
	public static function calculateNoteTransform(
		strumTime:Float,
		noteData:Int,
		totalStrums:Int,
		isPlayer:Bool,
		baseX:Float,
		baseY:Float,
		songPos:Float,
		curBeat:Float,
		scrollSpeed:Float,
		downscroll:Bool,
		config:ModchartConfig
	):ModchartTransform {
		var diff = (strumTime - songPos);
		var distance = diff * 0.45 * scrollSpeed;
		if (downscroll) distance = -distance;

		var receptor = calculateReceptorTransform(noteData, totalStrums, isPlayer, baseX, baseY, songPos, curBeat, config);

		// Aplica a trajetória de descida das notas respeitando as oscilações do modchart
		var noteX = receptor.x;
		var noteY = receptor.y + distance;

		// Deformação da trilha de notas quando o modchart está sob efeito de wave ou drunk
		if (config.drunk != 0) {
			noteX += Math.cos((songPos + diff) * 0.003 + noteData) * (config.drunk * 20.0);
		}
		if (config.wave != 0) {
			noteX += Math.sin(diff * 0.005) * (config.wave * 15.0);
		}

		return {
			x: noteX,
			y: noteY,
			z: 0.0,
			angle: receptor.angle,
			scaleX: receptor.scaleX,
			scaleY: receptor.scaleY,
			alpha: (Math.abs(diff) > 2500) ? 0.0 : receptor.alpha
		};
	}
}
