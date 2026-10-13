package kade.hex.chart;

/**
 * Base Scene class compatible with Kade's Modchart Engine (Hex).
 * Original concept by KadeDev (Apache-2.0 License).
 */
class Scene {
    public var id:String;
    public var priority:Int;

    var channels:Map<String, Float> = new Map();
    var channelIds:Array<String> = [];
    var watchedIds:Array<Int> = [];

    var activeShaders:Map<String, Dynamic> = new Map();

    public function new(id:String, priority:Int = 0) {
        this.id = id;
        this.priority = priority;
    }

    public function declare():Void {}
    public function open():Void {}
    public function frame(beat:Float):Void {}
    public function close():Void {}

    public function channel(name:String, defaultValue:Float = 0):Int {
        channels.set(name, defaultValue);
        var idx = channelIds.indexOf(name);
        if (idx == -1) {
            channelIds.push(name);
            return channelIds.length - 1;
        }
        return idx;
    }

    public function idOf(name:String):Int {
        return channelIds.indexOf(name);
    }

    public function watch(ids:Array<Int>):Void {
        this.watchedIds = ids.copy();
    }

    public function readWatched():Array<Float> {
        var values:Array<Float> = [];
        for (idx in watchedIds) {
            if (idx >= 0 && idx < channelIds.length) {
                var name = channelIds[idx];
                values.push(channels.exists(name) ? channels.get(name) : 0);
            } else {
                values.push(0);
            }
        }
        return values;
    }

    public function setChannel(name:String, value:Float):Void {
        channels.set(name, value);
    }

    public function shader(tag:String, path:String):Void {
        #if !macro
        try {
            var cls:Dynamic = Type.resolveClass("funkin.backend.shaders.FunkinShader");
            if (cls != null) {
                var s = Reflect.callMethod(cls, Reflect.field(cls, "fromFile"), [path]);
                if (s != null) activeShaders.set(tag, s);
            }
        } catch (_:Dynamic) {}
        #end
    }

    public function filter(shaderTag:String, target:String = "final"):Void {
        #if !macro
        var s = activeShaders.get(shaderTag);
        if (s == null) return;

        try {
            var flxG:Dynamic = Type.resolveClass("flixel.FlxG");
            var playStateCls:Dynamic = Type.resolveClass("funkin.game.PlayState");
            var playInstance:Dynamic = playStateCls != null ? Reflect.field(playStateCls, "instance") : null;
            var cam:Dynamic = flxG != null ? Reflect.field(flxG, "camera") : null;

            if (target == "camHUD" && playInstance != null) cam = Reflect.field(playInstance, "camHUD");
            else if (target == "camGame" && playInstance != null) cam = Reflect.field(playInstance, "camGame");

            if (cam != null) {
                var filterCls:Dynamic = Type.resolveClass("openfl.filters.ShaderFilter");
                if (filterCls != null) {
                    var filterInst = Type.createInstance(filterCls, [s]);
                    var current:Array<Dynamic> = Reflect.field(cam, "filters");
                    if (current == null) current = [];
                    current.push(filterInst);
                    Reflect.setProperty(cam, "filters", current);
                }
            }
        } catch (_:Dynamic) {}
        #end
    }

    public function live(field:String, value:Dynamic):Void {
        var parts = field.split(".");
        if (parts.length < 2) return;
        var tag = parts[0];
        var prop = parts[1];
        var s = activeShaders.get(tag);
        if (s != null) {
            try {
                var data = Reflect.field(s, "data");
                if (data != null) Reflect.setProperty(data, prop, value);
            } catch (_:Dynamic) {}
        }
    }

    public function stage3d():Void {}
    public function material(tag:String, prop:String):Void {}
    public function ball(name:String, path:String, radius:Float):Void {}
    public function follow(name:String, active:Bool):Void {}
    public function place(name:String, x:Float, y:Float, z:Float):Void {}
    public function size(name:String, scale:Float):Void {}
    public function roundAt(name:String, x:Float, y:Float):Void {}
    public function stageDrawn(active:Bool):Void {}
    public function stagePath():String return "stage";
}
