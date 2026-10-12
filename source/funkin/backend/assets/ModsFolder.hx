package funkin.backend.assets;

import flixel.util.FlxSignal.FlxTypedSignal;
import funkin.backend.system.MainState;
import funkin.backend.utils.CoolUtil;
import dbe.compatibility.mods.RuntimeModConverter;
import cne.compat.PsychLuaProfile;
import haxe.ds.StringMap;
import haxe.io.Path;
import lime.text.Font;
import openfl.text.Font as OpenFLFont;
import openfl.utils.AssetLibrary;
import openfl.utils.AssetManifest;

using StringTools;
#if MOD_SUPPORT
import sys.FileSystem;
import sys.io.File;
#end


class ModsFolder {
	/**
	 * INTERNAL - Only use when editing source mods!!
	 */
	@:dox(hide) public static var onModSwitch:FlxTypedSignal<String->Void> = new FlxTypedSignal<String->Void>();

	/**
	 * Current mod folder. Will affect `Paths`.
	 */
	public static var currentModFolder:String = null;
	/** Path to the converted runtime directory if the current mod required conversion. */
	public static var currentModLoadPath:String = null;
	/** Asset library identifier for the active mod, including ZIP and converted mods. */
	public static var currentModLibraryName:String = null;
	/** Conversion report produced for the active mod rather than an addon library. */
	public static var currentModConversionReport:Dynamic = null;
	/** Converted output associated with the active mod's report. */
	public static var currentModConversionLoadPath:String = null;
	/** Explicit Psych Lua profile scoped to the active mod. */
	public static var currentPsychLuaProfile(default, null):PsychLuaProfile = new PsychLuaProfile(null, PsychLuaProfile.UNSPECIFIED);
	/** Latest profile/config report for the active mod, including non-converted packages. */
	public static var lastPsychLuaCompatibilityReport:Dynamic = null;
	/** Last runtime conversion report; consumed by MainState to present blocked packages. */
	public static var lastRuntimeConversionReport:Dynamic = null;
	public static var lastRuntimeConversionBlocked:Bool = false;
	/**
	 * Path to the `mods` folder.
	 */
	public static var modsPath:String = "./mods/";
	/**
	 * Path to the `addons` folder.
	 */
	public static var addonsPath:String = "./addons/";

	/**
	 * If accessing a file as assets/data/global/LIB_mymod.hx should redirect to mymod:assets/data/global.hx
	 */
	public static var useLibFile:Bool = true;

	/**
	 * Whenever its the first time mods has been reloaded.
	 */
	private static var __firstTime:Bool = true;
	
	@:dox(hide) public static var modsListSortCache:StringMap<Array<String>> = new StringMap();

	/**
	 * Initializes `mods` folder.
	 */
	public static function init() {
		if(!getModsList().contains(Options.lastLoadedMod)) {
			if(Options.lastLoadedMod != null)
				Logs.warn("Mod \"" + Options.lastLoadedMod + "\" not found in mods list, switching to base game!");
			Options.lastLoadedMod = null;
		}
	}

	/**
	 * Switches mod - unloads all the other mods, then load this one.
	 * @param libName
	 */
	public static function switchMod(mod:String) {
		Options.lastLoadedMod = currentModFolder = mod;
		if (mod == null) currentModLoadPath = null;
		currentModLibraryName = null;
		currentModConversionReport = null;
		currentModConversionLoadPath = null;
		currentPsychLuaProfile = new PsychLuaProfile(mod, PsychLuaProfile.UNSPECIFIED, profileDiagnostic);
		lastPsychLuaCompatibilityReport = null;
		reloadMods();
		if(mod == null) {
			mod = "(default)";
		}
		Logs.traceColored([
			Logs.logText('Switched to mod: '),
			Logs.logText(mod, GREEN)
		], VERBOSE);
	}

	public static function reloadMods() {
		if (!__firstTime)
			FlxG.switchState(new MainState());
		__firstTime = false;
	}

	/**
	 * Loads a mod library from the specified path. Supports folders and zips.
	 * @param modName Name of the mod
	 * @param force Whenever the mod should be reloaded if it has already been loaded
	 */
	public static function loadModLib(path:String, force:Bool = false, ?modName:String) {
		#if MOD_SUPPORT
		lastRuntimeConversionReport = null;
		lastRuntimeConversionBlocked = false;
		var conversion = RuntimeModConverter.prepare(path, RuntimeModConverter.defaultManagedRoot());
		var isActiveMod = currentModFolder != null && modName == currentModFolder;
		lastRuntimeConversionReport = conversion.report;
		lastRuntimeConversionBlocked = conversion.blocked == true;
		if (isActiveMod)
		{
			currentModConversionReport = conversion.report;
			currentModConversionLoadPath = conversion.loadPath;
		}
		if (lastRuntimeConversionBlocked) {
			if (isActiveMod) currentModLibraryName = null;
			var details:Array<String> = cast Reflect.field(conversion.report, "incompatibilities");
			Logs.warn('Mod package was not loaded: ${details == null || details.length == 0 ? "conversion report required" : details.join("; ")}');
			return null;
		}
		if (isActiveMod) currentModLibraryName = path.toLowerCase();
		if (conversion.converted == true) {
			currentModLoadPath = conversion.loadPath;
			return loadLibraryFromFolder(path.toLowerCase(), conversion.loadPath, force, modName);
		}
		currentModLoadPath = null;

		for (ext in Flags.ALLOWED_ZIP_EXTENSIONS) {
			if (!FileSystem.exists('$path.$ext')) continue;
			return loadLibraryFromZip('$path'.toLowerCase(), '$path.$ext', force, modName);
		}
		return loadLibraryFromFolder('$path'.toLowerCase(), '$path', force, modName);

		#else
		return null;
		#end
	}

	/** Resolve the profile only after the active mod asset library has been registered. */
	public static function resolvePsychLuaProfile():PsychLuaProfileResolution
	{
		var configText:Null<String> = null;
		if (currentModLibraryName != null && Paths.assetsTree != null)
		{
			var configAsset = 'assets/${PsychLuaProfile.CONFIG_PATH}';
			for (registeredLibrary in Paths.assetsTree.libraries)
			{
				var library = AssetsLibraryList.getCleanLibrary(registeredLibrary);
				if (!Std.isOfType(library, IModsAssetLibrary)) continue;
				if (Reflect.field(library, "libName") != currentModLibraryName) continue;
				if (library.exists(configAsset, "TEXT")) configText = library.getText(configAsset);
				break;
			}
		}

		var resolution = PsychLuaProfile.resolveConfig(configText);
		var modName = currentModFolder == null ? "(default)" : currentModFolder;
		currentPsychLuaProfile = new PsychLuaProfile(modName, resolution.profile, profileDiagnostic);
		if (resolution.diagnostic != null) Logs.warn('Mod "$modName": ${resolution.diagnostic}');

		lastPsychLuaCompatibilityReport = {
			mod: modName,
			psychLuaProfile: resolution.profile,
			psychLuaProfileConfig: PsychLuaProfile.CONFIG_PATH,
			configStatus: resolution.configStatus,
			supportedProfiles: PsychLuaProfile.supportedProfiles()
		};
		writePsychProfileToConversionReport(resolution);
		return resolution;
	}

	private static function profileDiagnostic(message:String):Void
	{
		Logs.warn(message);
	}

	private static function writePsychProfileToConversionReport(resolution:PsychLuaProfileResolution):Void
	{
		var report = currentModConversionReport;
		if (report == null) return;
		Reflect.setField(report, "psychLuaProfile", resolution.profile);
		Reflect.setField(report, "psychLuaProfileConfig", PsychLuaProfile.CONFIG_PATH);
		Reflect.setField(report, "psychLuaProfileConfigStatus", resolution.configStatus);

		var outputPath:Dynamic = Reflect.field(report, "output");
		if (outputPath == null || currentModConversionLoadPath == null || Std.string(outputPath) != currentModConversionLoadPath) return;
		var reportPath = Path.join([Std.string(outputPath), RuntimeModConverter.REPORT_NAME]);
		#if MOD_SUPPORT
		if (!FileSystem.exists(reportPath)) return;
		try
		{
			File.saveContent(reportPath, haxe.Json.stringify(report, null, "\t") + "\n");
		}
		catch (error:Dynamic)
		{
			Logs.warn('Could not persist Psych Lua profile in the conversion report: ${Std.string(error)}');
		}
		#end
	}

	public static function getModConfig(mod:String):Map<String, Map<String, String>> {
		for (ext in Flags.ALLOWED_ZIP_EXTENSIONS) {
			var path = modsPath + mod + "." + ext;
			if (!FileSystem.exists(path))
				continue;

			var zip = new SysZip(path);
			for (entry in zip.entries) {
				if (entry.fileName.toLowerCase() == "data/config/modpack.ini") {
					var bytes = zip.unzipEntry(entry);
					return IniUtil.parseString(bytes.getString(0, bytes.length));
				}
			}
			break; // theoretically once it finds a zip mod, it'll stop even if there's no config
		}

		var filePath = modsPath + mod + "/data/config/modpack.ini";
		if (FileSystem.exists(filePath))
			return IniUtil.parseString(sys.io.File.getContent(filePath));

		return [];
	}

	public static function getModsList(?sortingOptions:ModSortingOptions):Array<String> {
		var mods:Array<String> = [];
		#if MOD_SUPPORT
		// Mods directory does not exist yet, create it
		if (!FileSystem.exists(modsPath)) FileSystem.createDirectory(modsPath);
		
		final modsList:Array<String> = FileSystem.readDirectory(modsPath);

		if (modsList == null || modsList.length <= 0) return mods;

		for (modFolder in modsList) {
			if (FileSystem.isDirectory(modsPath + modFolder)) mods.push(modFolder);
			else if (Flags.ALLOWED_ZIP_EXTENSIONS.contains(Path.extension(modFolder))) mods.push(Path.withoutExtension(modFolder));
		}
		
		if (sortingOptions != null) {
		    var sortForge:StringBuf = new StringBuf();
			for (i in mods) {
			    sortForge.add(i);
				sortForge.add("::");
			}

			sortForge.add(Std.string(sortingOptions.descending ? 1 : 0));

			sortForge.add(sortingOptions.mode);
			
			final sortForgePure:String = sortForge.toString();

			if (modsListSortCache.exists(sortForgePure))
			    mods = modsListSortCache.get(sortForgePure);
				if (mods.length > 0 && mods[mods.length - 1] == null) mods.pop();
			else {
			    ModSortingController.sort(sortingOptions, mods);
				modsListSortCache.set(sortForgePure, mods);
			}
		}
		#end
		return mods;
	}
	public static function getLoadedModsLibs(skipTranslated:Bool = false):Array<IModsAssetLibrary> {
		var libs = [];
		for (i in Paths.assetsTree.libraries) {
			var l = AssetsLibraryList.getCleanLibrary(i);
			#if TRANSLATIONS_SUPPORT
			if(skipTranslated && (l is TranslatedAssetLibrary)) continue;
			#end
			// No need to check for it being a `ScriptedAssetLibrary`, if `ScriptedAssetLibrary` extends ModsFolderLibrary, which implements `IModsAssetLibrary`
			// If you have to revert this change then uhhhhh wasn't me, trust 🙏
			if (/*l is ScriptedAssetLibrary ||*/ l is IModsAssetLibrary) libs.push(cast(l, IModsAssetLibrary));
		}
		return libs;
	}
	public static function getLoadedMods(skipTranslated:Bool = false):Array<String>
		return [for (modLib in getLoadedModsLibs(skipTranslated)) modLib.modName];

	public static function prepareLibrary(libName:String, force:Bool = false) {
		var assets:AssetManifest = new AssetManifest();
		assets.name = libName;
		assets.version = 2;
		assets.libraryArgs = [];
		assets.assets = [];

		return AssetLibrary.fromManifest(assets);
	}

	public static function registerFont(font:Font) {
		var openflFont = new OpenFLFont();
		@:privateAccess
		openflFont.__fromLimeFont(font);
		OpenFLFont.registerFont(openflFont);
		return font;
	}

	public static function prepareModLibrary(libName:String, lib:IModsAssetLibrary, force:Bool = false, ?tag:AssetSource) {
		var openLib = prepareLibrary(libName, force);
		lib.prefix = 'assets/';
		@:privateAccess
		openLib.__proxy = cast(lib, lime.utils.AssetLibrary);
		if (tag != null) {
			openLib.tag = tag;
			cast(lib, lime.utils.AssetLibrary).tag = tag;
		}
		return openLib;
	}

	#if MOD_SUPPORT
	public static function loadLibraryFromFolder(libName:String, folder:String, force:Bool = false, ?modName:String, ?tag:AssetSource = MODS) {
		return prepareModLibrary(libName, new ModsFolderLibrary(folder, libName, modName), force, tag);
	}

	public static function loadLibraryFromZip(libName:String, zipPath:String, force:Bool = false, ?modName:String, ?tag:AssetSource = MODS) {
		return prepareModLibrary(libName, new ZipFolderLibrary(zipPath, libName, modName), force, tag);
	}
	#end
}

/**
 * Describes how mods should be sorted when getting the mods list.
 */
typedef ModSortingOptions = {
    /**
     * Whether or not the list should go in descending order (e.g. `[2, 1, 0]`).
     */
    var descending:Bool;
    /**
     * The sorting mode to use.
     */
    var mode:ModSortingMode;
}

/**
 * This class performs the actual sorting for the mods list.
 */
class ModSortingController {
    /**
     * Sort the mods list, according to the provided sorting options.
     */
    public static function sort(sortingOptions:ModSortingOptions, list:Array<String>):Void {
        switch (sortingOptions.mode) {
            case ModSortingMode.CLEAN: {}
            case ModSortingMode.ALPHABETICAL: CoolUtil.sortAlphabetically(list);
        }
        if (sortingOptions.descending) list.reverse();
    }
}

/**
 * The mods list can be sorted in all of the ways provided by this enum.
 */
enum abstract ModSortingMode(String) {
    /**
     * Use the original list received from reading the directory. This may depend
     * on the current platform, but remains for legacy purposes.
     */
    var CLEAN;
    /**
     * The list should be in alphabetical order.
     */
    var ALPHABETICAL;
}
