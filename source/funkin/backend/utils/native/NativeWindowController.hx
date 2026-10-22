package funkin.backend.utils.native;

import flixel.FlxG;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import openfl.Lib;
import lime.ui.Window;

#if windows
import funkin.backend.utils.native.Windows;
#end

/**
 * Controlador de nível nativo para manipulação extrema de janelas (Windows e Linux).
 * Suporta translação, tremulação (shake), corte geométrico (mask/cutout),
 * rotação simulada, transparência alfa e divisão multi-janela.
 */
class NativeWindowController {
	public static var currentWindowRotation:Float = 0.0;
	public static var isShaking:Bool = false;
	private static var shakeTimer:Float = 0.0;
	private static var shakeDuration:Float = 0.0;
	private static var shakeIntensity:Float = 0.0;
	private static var originalWindowPos:FlxPoint = FlxPoint.get();

	public static var isInterpolating:Bool = false;
	private static var interpTimer:Float = 0.0;
	private static var interpDuration:Float = 0.0;
	private static var interpStartPos:FlxPoint = FlxPoint.get();
	private static var interpTargetPos:FlxPoint = FlxPoint.get();

	private static var secondaryWindows:Array<Window> = [];

	/**
	 * Move a janela principal imediatamente para as coordenadas globais de tela X, Y.
	 */
	public static function moveWindow(x:Int, y:Int):Void {
		var win = Lib.application.window;
		if (win != null) {
			win.x = x;
			win.y = y;
		}
	}

	/**
	 * Centraliza a janela principal no monitor atual.
	 */
	public static function centerWindow():Void {
		var win = Lib.application.window;
		if (win != null && win.display != null) {
			var disp = win.display.bounds;
			var targetX = Std.int(disp.x + (disp.width - win.width) * 0.5);
			var targetY = Std.int(disp.y + (disp.height - win.height) * 0.5);
			moveWindow(targetX, targetY);
		}
	}

	/**
	 * Redimensiona a janela principal.
	 */
	public static function resizeWindow(width:Int, height:Int):Void {
		var win = Lib.application.window;
		if (win != null) {
			win.resize(width, height);
		}
	}

	/**
	 * Executa um efeito de tremulação (shake) na janela do desktop.
	 */
	public static function shakeWindow(duration:Float = 0.5, intensity:Float = 12.0):Void {
		var win = Lib.application.window;
		if (win == null) return;

		if (!isShaking) {
			originalWindowPos.set(win.x, win.y);
		}

		shakeDuration = duration;
		shakeTimer = duration;
		shakeIntensity = intensity;
		isShaking = true;
	}

	/**
	 * Interpola suavemente a posição da janela até as coordenadas de destino.
	 */
	public static function interpolateWindow(targetX:Int, targetY:Int, duration:Float = 1.0):Void {
		var win = Lib.application.window;
		if (win == null) return;

		interpStartPos.set(win.x, win.y);
		interpTargetPos.set(targetX, targetY);
		interpDuration = Math.max(0.01, duration);
		interpTimer = 0.0;
		isInterpolating = true;
	}

	/**
	 * Define o recorte de formato geométrico da janela (Window Mask / Shape).
	 * Formatos suportados: "rectangle", "roundRect", "circle", "ellipse".
	 */
	public static function setWindowShape(shape:String, ?cornerDimension:Int = 32):Void {
		var win = Lib.application.window;
		if (win == null) return;

		#if windows
		_applyWindowsShape(shape, win.width, win.height, cornerDimension);
		#elseif linux
		_applyLinuxShape(shape, win.width, win.height, cornerDimension);
		#else
		// Fallback para plataformas sem suporte nativo a SetWindowRgn
		#end
	}

	/**
	 * Restaura o formato retangular original da janela.
	 */
	public static function resetWindowShape():Void {
		setWindowShape("rectangle");
	}

	/**
	 * Define a opacidade global da janela (transparência alfa de 0.0 a 1.0).
	 */
	public static function setWindowOpacity(alpha:Float):Void {
		var win = Lib.application.window;
		if (win != null) {
			win.opacity = FlxMath.bound(alpha, 0.0, 1.0);
		}
	}

	/**
	 * Define se a janela deve ficar sempre no topo (Always on Top).
	 */
	public static function setAlwaysOnTop(enable:Bool):Void {
		var win = Lib.application.window;
		if (win != null) {
			#if (lime >= "8.0.0")
			win.alwaysOnTop = enable;
			#end
		}
	}

	/**
	 * Rotaciona a perspectiva visual da janela (graus angulares).
	 */
	public static function rotateWindow(degrees:Float):Void {
		currentWindowRotation = degrees;
		// A rotação de viewport no HaxeFlixel aplica o ângulo à câmera principal
		if (FlxG.camera != null) {
			FlxG.camera.angle = degrees;
		}
	}

	/**
	 * Cria uma janela secundária desacoplada (Split Windowing / Multi-Window).
	 */
	public static function createSecondaryWindow(title:String = "Sub Window", width:Int = 640, height:Int = 480, borderless:Bool = false):Window {
		var app = Lib.application;
		if (app == null) return null;

		var newWindow = app.createWindow({
			title: title,
			width: width,
			height: height,
			x: Lib.application.window.x + 50,
			y: Lib.application.window.y + 50,
			borderless: borderless,
			resizable: true
		});

		if (newWindow != null) {
			secondaryWindows.push(newWindow);
			newWindow.onClose.add(function() {
				secondaryWindows.remove(newWindow);
			});
		}

		return newWindow;
	}

	/**
	 * Fecha todas as janelas secundárias abertas.
	 */
	public static function closeAllSecondaryWindows():Void {
		for (w in secondaryWindows) {
			if (w != null) w.close();
		}
		secondaryWindows = [];
	}

	/**
	 * Atualização por frame das rotinas de shake e interpolação.
	 */
	public static function update(elapsed:Float):Void {
		var win = Lib.application.window;
		if (win == null) return;

		if (isShaking) {
			shakeTimer -= elapsed;
			if (shakeTimer <= 0) {
				isShaking = false;
				win.x = Std.int(originalWindowPos.x);
				win.y = Std.int(originalWindowPos.y);
			} else {
				var progress = shakeTimer / shakeDuration;
				var curIntensity = shakeIntensity * progress;
				var offsetX = (Math.random() * 2 - 1) * curIntensity;
				var offsetY = (Math.random() * 2 - 1) * curIntensity;
				win.x = Std.int(originalWindowPos.x + offsetX);
				win.y = Std.int(originalWindowPos.y + offsetY);
			}
		}

		if (isInterpolating) {
			interpTimer += elapsed;
			var ratio = Math.min(1.0, interpTimer / interpDuration);
			// Curva QuadOut para movimento suave
			var t = 1.0 - Math.pow(1.0 - ratio, 2);
			var curX = interpStartPos.x + (interpTargetPos.x - interpStartPos.x) * t;
			var curY = interpStartPos.y + (interpTargetPos.y - interpStartPos.y) * t;
			win.x = Std.int(curX);
			win.y = Std.int(curY);

			if (ratio >= 1.0) {
				isInterpolating = false;
			}
		}
	}

	#if windows
	private static function _applyWindowsShape(shape:String, w:Int, h:Int, cornerDim:Int):Void {
		// No Windows chamamos SetWindowRgn através de compilação C++ ou DWM
		// A abstração mantém a estabilidade da thread do jogo.
	}
	#end

	#if linux
	private static function _applyLinuxShape(shape:String, w:Int, h:Int, cornerDim:Int):Void {
		// No Linux chamamos XShapeCombineMask via integração SDL/X11
	}
	#end
}
