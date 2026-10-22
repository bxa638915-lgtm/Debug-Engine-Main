package;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
#end

@:dox(hide)
@:access(lime.app.Application)
@:access(lime.system.System)
@:access(openfl.display.Stage)
@:access(openfl.events.UncaughtErrorEvents)
#if (static_link || ios)
@:cppFileCode("\nextern \"C\" int lime_register_prims ();\nextern \"C\" int lime_register_prims ();extern \"C\" int lime_register_prims ();")
#end
class ApplicationMain
{
	#if !macro
	public static function main()
	{
		#if (static_link || ios)
		untyped __cpp__("lime_register_prims ()");
		untyped __cpp__("lime_register_prims ()");untyped __cpp__("lime_register_prims ()");
		#end

		lime.system.System.__registerEntryPoint("DBE-Launcher", create);

		#if !html5
		create(null);
		#end
	}

	public static function create(config):Void
	{
		
		lime.system.System.setHint("ORIENTATIONS", "LandscapeLeft LandscapeRight");
		

		final appMeta:Map<String, String> = [];

		appMeta.set("build", "5");
		appMeta.set("company", "DBE Team");
		appMeta.set("file", "DBE-Launcher");
		appMeta.set("name", "DBE Launcher");
		appMeta.set("packageName", "com.dbe.launcher");
		appMeta.set("version", "1.0.0");

		var app = new openfl.display.Application(appMeta);

		
		var attributes:lime.ui.WindowAttributes = {
			allowHighDPI: false,
			alwaysOnTop: false,
			transparent: false,
			borderless: false,
			element: null,
			frameRate: 60,
			#if !web
			fullscreen: false,
			#end
			height: 540,
			hidden: false,
			maximized: false,
			minimized: false,
			parameters: {},
			resizable: false,
			title: "DBE Launcher",
			width: 960,
			x: null,
			y: null,
		};

		attributes.context = {
			antialiasing: 0,
			background: 16777215,
			colorDepth: 32,
			depth: true,
			hardware: true,
			stencil: true,
			type: null,
			vsync: true
		};

		if (app.window == null)
		{
			if (config != null)
			{
				for (field in Reflect.fields(config))
				{
					if (Reflect.hasField(attributes, field))
					{
						Reflect.setField(attributes, field, Reflect.field(config, field));
					}
					else if (Reflect.hasField(attributes.context, field))
					{
						Reflect.setField(attributes.context, field, Reflect.field(config, field));
					}
				}
			}
		}

		app.createWindow(attributes);
		

		var preloader = getPreloader();
		app.preloader.onProgress.add (function(loaded, total)
		{
			@:privateAccess preloader.update(loaded, total);
		});
		app.preloader.onComplete.add(function()
		{
			@:privateAccess preloader.start();
		});

		preloader.onComplete.add(start.bind((cast app.window:openfl.display.Window).stage));

		#if !disable_preloader_assets
		ManifestResources.init(config);

		for (library in ManifestResources.preloadLibraries)
		{
			app.preloader.addLibrary(library);
		}

		for (name in ManifestResources.preloadLibraryNames)
		{
			app.preloader.addLibraryName(name);
		}
		#end

		app.preloader.load();

		var result = app.exec();

		#if (sys && !ios && !nodejs)
		lime.system.System.exit(result);
		#end
	}

	public static function start(stage:openfl.display.Stage):Void
	{
		if (stage.__uncaughtErrorEvents.__enabled)
		{
			try
			{
				ApplicationMain.getEntryPoint();

				stage.loaderInfo.dispatchEvent(new openfl.events.Event(openfl.events.Event.INIT));
				stage.loaderInfo.dispatchEvent(new openfl.events.Event(openfl.events.Event.COMPLETE));

				stage.dispatchEvent(new openfl.events.Event(openfl.events.Event.RESIZE, false, false));

				if (stage.window.fullscreen)
				{
					stage.dispatchEvent(new openfl.events.FullScreenEvent(openfl.events.FullScreenEvent.FULL_SCREEN, false, false, true, true));
				}
			}
			catch (e:Dynamic)
			{
				#if !display
				stage.__handleError(e);
				#end
			}
		}
		else
		{
			ApplicationMain.getEntryPoint();

			stage.loaderInfo.dispatchEvent(new openfl.events.Event(openfl.events.Event.INIT));
			stage.loaderInfo.dispatchEvent(new openfl.events.Event(openfl.events.Event.COMPLETE));

			stage.dispatchEvent(new openfl.events.Event(openfl.events.Event.RESIZE, false, false));

			if (stage.window.fullscreen)
			{
				stage.dispatchEvent(new openfl.events.FullScreenEvent(openfl.events.FullScreenEvent.FULL_SCREEN, false, false, true, true));
			}
		}
	}
	#end

	macro public static function getEntryPoint()
	{
		var hasMain = false;

		switch (Context.follow(Context.getType("dbe.launcher.ui.Main")))
		{
			case TInst(t, params):

				var type = t.get();
				for (method in type.statics.get())
				{
					if (method.name == "main")
					{
						hasMain = true;
						break;
					}
				}

				if (hasMain)
				{
					return Context.parse("@:privateAccess dbe.launcher.ui.Main.main()", Context.currentPos());
				}
				else if (type.constructor != null)
				{
					return macro
					{
						var current = stage.getChildAt (0);

						if (current == null || !(current is openfl.display.DisplayObjectContainer))
						{
							current = new openfl.display.MovieClip();
							stage.addChild(current);
						}

						//this define is for internal use only
						//note: it may be removed abruptly in the future
						#if !no_openfl_entry_point
						new DocumentClass(cast current);
						#end
					};
				}
				else
				{
					Context.fatalError("Main class \"dbe.launcher.ui.Main\" has neither a static main nor a constructor.", Context.currentPos());
				}

			default:

				Context.fatalError("Main class \"dbe.launcher.ui.Main\" isn't a class.", Context.currentPos());
		}

		return null;
	}

	macro public static function getPreloader()
	{
		
		return macro
		{
			new openfl.display.Preloader(new openfl.display.Preloader.DefaultPreloader());
		};
		
	}

	#if !macro
	@:noCompletion @:dox(hide) public static function __init__()
	{
		var init = lime.app.Application;
	}
	#end
}
