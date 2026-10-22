package dbe.launcher.ui;

import flixel.util.FlxColor;

class UITheme {
	public static inline var FONT:String = "fonts/vcr.ttf";

	// Palette
	public static inline var BG_DARK:FlxColor = 0xFF101216;
	public static inline var BG_PANEL:FlxColor = 0xFF181C24;
	public static inline var BG_CARD:FlxColor = 0xFF202632;
	public static inline var BG_HOVER:FlxColor = 0xFF2A3242;
	public static inline var BORDER:FlxColor = 0xFF2E3848;
	public static inline var BORDER_LIGHT:FlxColor = 0xFF425066;

	public static inline var TEXT:FlxColor = 0xFFF0F4F8;
	public static inline var TEXT_MUTED:FlxColor = 0xFF8E9BAE;
	public static inline var TEXT_DARK:FlxColor = 0xFF586578;

	public static inline var PRIMARY:FlxColor = 0xFF00B4D8;
	public static inline var PRIMARY_HOVER:FlxColor = 0xFF48CAE4;
	public static inline var PRIMARY_DARK:FlxColor = 0xFF0077B6;

	public static inline var SUCCESS:FlxColor = 0xFF06D6A0;
	public static inline var SUCCESS_HOVER:FlxColor = 0xFF2EC4B6;

	public static inline var WARNING:FlxColor = 0xFFFFB703;
	public static inline var WARNING_BG:FlxColor = 0xFF3D2C00;

	public static inline var DANGER:FlxColor = 0xFFEF476F;
	public static inline var DANGER_HOVER:FlxColor = 0xFFFF5D8F;

	public static inline var PURPLE:FlxColor = 0xFF8338EC;

	public static function formatBytes(bytes:Float):String {
		if (bytes < 1024) return Math.round(bytes) + " B";
		if (bytes < 1024 * 1024) return (Math.round(bytes / 102.4) / 10) + " KB";
		if (bytes < 1024 * 1024 * 1024) return (Math.round(bytes / (1024 * 102.4)) / 10) + " MB";
		return (Math.round(bytes / (1024 * 1024 * 102.4)) / 10) + " GB";
	}

	public static function formatSpeed(bytesPerSec:Float):String {
		return formatBytes(bytesPerSec) + "/s";
	}
}
