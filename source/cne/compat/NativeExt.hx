// ============================================================
//  NativeExt.hx — Wrapper HScript para extensões C++ básicas
//  UCE — source/cne/compat/NativeExt.hx
//
//  Uso em HScript:
//    import cne.compat.NativeExt;
//    var mem  = NativeExt.getMemoryUsageMB();
//    var data = NativeExt.readFileFast("assets/data/test.json");
//    var sq   = NativeExt.fastSqrt(16.0);   // → 4.0
//
//  Notas:
//    • As funções C++ pesadas são acessadas via Sys/cpp.vm.Gc e stdlib.
//    • fastSqrt/Sin/Cos usam LUT de 4096 entradas pré-computadas.
//    • AudioAnalyzer.getBPM usa análise de energia por janela.
//    • Todas as funções têm fallback seguro se o recurso não estiver disponível.
// ============================================================

package cne.compat;

import sys.io.File;
import haxe.io.Bytes;

// ── LUT estática compartilhada ────────────────────────────────
private class MathLUT {
    static var _sinTable:Array<Float> = null;
    static var _sqrtTable:Array<Float> = null;
    static inline var SIZE:Int   = 4096;
    static inline var MASK:Int   = SIZE - 1;
    static inline var INV:Float  = SIZE / (2 * Math.PI);

    public static function init() {
        if (_sinTable != null) return;
        _sinTable  = [];
        _sqrtTable = [];
        for (i in 0...SIZE) {
            _sinTable.push(Math.sin(i * 2 * Math.PI / SIZE));
            _sqrtTable.push(Math.sqrt(i / SIZE)); // normalizado 0–1
        }
    }

    public static inline function sin(x:Float):Float {
        var idx:Int = Std.int(x * INV) & MASK;
        return _sinTable[idx];
    }

    public static inline function cos(x:Float):Float {
        var idx:Int = Std.int((x + Math.PI * 0.5) * INV) & MASK;
        return _sinTable[idx];
    }

    // Sqrt via LUT só para 0–16 (rápido pra cálculos de gameplay)
    // Fora desse range, delega para Math.sqrt
    public static inline function sqrt(x:Float):Float {
        if (x < 0) return 0;
        if (x <= 16) {
            var norm:Float = x / 16.0;
            var idx:Int = Std.int(norm * SIZE);
            if (idx >= SIZE) return 4.0; // sqrt(16)
            return _sqrtTable[idx] * 4.0;
        }
        return Math.sqrt(x);
    }
}

// ── AudioAnalyzer ─────────────────────────────────────────────
private class AudioAnalyzer {
    /**
     * Estima BPM de bytes PCM 16-bit mono via análise de energia por janela.
     * bytes:      Haxe Bytes de áudio PCM 16-bit little-endian
     * sampleRate: taxa de amostragem (ex: 44100)
     * Retorna BPM estimado (60–300) ou -1 em caso de erro.
     */
    public static function getBPM(bytes:Bytes, sampleRate:Int):Float {
        if (bytes == null || bytes.length < 4 || sampleRate <= 0) return -1;

        // Janela de ~23ms (512 samples a 44100 Hz)
        var windowSize:Int = 512;
        var hopSize:Int    = 256;
        var numSamples:Int = bytes.length >> 1; // 2 bytes por sample PCM16

        if (numSamples < windowSize * 2) return -1;

        // Calcula energia RMS por janela
        var energies:Array<Float> = [];
        var pos:Int = 0;
        while (pos + windowSize <= numSamples) {
            var energy:Float = 0;
            for (i in 0...windowSize) {
                var idx:Int   = (pos + i) * 2;
                var lo:Int    = bytes.get(idx);
                var hi:Int    = bytes.get(idx + 1);
                var sample:Int = lo | (hi << 8);
                if (sample > 32767) sample -= 65536; // signed
                energy += sample * sample;
            }
            energies.push(energy / windowSize);
            pos += hopSize;
        }

        if (energies.length < 8) return -1;

        // Detecta picos de energia (onset detection simplificada)
        var mean:Float = 0;
        for (e in energies) mean += e;
        mean /= energies.length;

        var peaks:Array<Int> = [];
        var threshold:Float  = mean * 1.5;
        var minDist:Int      = Std.int(sampleRate * 0.25 / hopSize); // 250ms mínimo

        for (i in 1...energies.length - 1) {
            if (energies[i] > threshold && energies[i] > energies[i-1]
                && energies[i] >= energies[i+1]) {
                if (peaks.length == 0 || i - peaks[peaks.length - 1] >= minDist)
                    peaks.push(i);
            }
        }

        if (peaks.length < 2) return -1;

        // Calcula intervalo médio entre picos
        var totalInterval:Float = 0;
        for (i in 1...peaks.length)
            totalInterval += peaks[i] - peaks[i - 1];
        var avgInterval:Float = (totalInterval / (peaks.length - 1)) * hopSize;
        var bpm:Float = (sampleRate / avgInterval) * 60;

        // Ajusta para faixa razoável (60–300 BPM)
        while (bpm < 60)  bpm *= 2;
        while (bpm > 300) bpm /= 2;

        return Math.round(bpm * 10) / 10;
    }
}

// ============================================================
//  NativeExt — API pública
// ============================================================

class NativeExt {
    static var _lutReady:Bool = false;

    static function _ensureLUT() {
        if (!_lutReady) { MathLUT.init(); _lutReady = true; }
    }

    // ── Sistema / Diagnóstico ─────────────────────────────────

    /**
     * Retorna uso de memória do processo em MB.
     * Usa cpp.vm.Gc.memInfo64 em C++, fallback via Sys em outros targets.
     */
    public static function getMemoryUsageMB():Float {
        try {
            var gcInfo = Reflect.field(Type.resolveClass("cpp.vm.Gc"), "memInfo64");
            if (gcInfo != null && Reflect.isFunction(gcInfo)) {
                var bytes:Float = Reflect.callMethod(null, gcInfo, [3]); // MEM_INFO_USAGE
                return bytes / (1024 * 1024);
            }
        } catch (e:Dynamic) {}
        // Fallback: haxe.System (disponível em sys targets)
        try {
            var mem = Reflect.field(Type.resolveClass("haxe.System"), "memoryUsage");
            if (mem != null) return mem / (1024 * 1024);
        } catch (e:Dynamic) {}
        return -1;
    }

    /**
     * Retorna tempo de CPU do processo em segundos.
     * Usa Sys.cpuTime() em targets sys.
     */
    public static function getCPUTime():Float {
        try { return Sys.cpuTime(); } catch (e:Dynamic) { return -1; }
    }

    /**
     * Retorna número de núcleos lógicos disponíveis.
     */
    public static function getCoreCount():Int {
        try {
            var n = Reflect.field(Type.resolveClass("sys.thread.Thread"), "cpuCount");
            if (n != null) return n;
        } catch (e:Dynamic) {}
        // Fallback via variável de ambiente no Windows
        try {
            var env = Sys.environment();
            if (env.exists("NUMBER_OF_PROCESSORS"))
                return Std.parseInt(env.get("NUMBER_OF_PROCESSORS"));
        } catch (e:Dynamic) {}
        return 1;
    }

    // ── FileIO rápido ─────────────────────────────────────────

    /**
     * Lê um arquivo como String sem passar pelo pipeline OpenFL/Assets.
     * Mais rápido para arquivos grandes ou acesso direto ao disco.
     * Retorna null em caso de falha.
     */
    public static function readFileFast(path:String):String {
        if (path == null || path == "") return null;
        try { return File.getContent(path); } catch (e:Dynamic) {
            trace("[NativeExt] readFileFast falhou para '" + path + "': " + e);
            return null;
        }
    }

    /**
     * Lê um arquivo como Bytes.
     */
    public static function readFileBytes(path:String):Bytes {
        if (path == null || path == "") return null;
        try { return File.getBytes(path); } catch (e:Dynamic) {
            trace("[NativeExt] readFileBytes falhou para '" + path + "': " + e);
            return null;
        }
    }

    /**
     * Escreve String em arquivo.
     * Retorna true se bem-sucedido.
     */
    public static function writeFileFast(path:String, content:String):Bool {
        if (path == null || path == "") return false;
        try { File.saveContent(path, content); return true; } catch (e:Dynamic) {
            trace("[NativeExt] writeFileFast falhou para '" + path + "': " + e);
            return false;
        }
    }

    // ── Math LUT ──────────────────────────────────────────────

    /**
     * Raiz quadrada via LUT (exata para x > 16, LUT para 0–16).
     */
    public static function fastSqrt(x:Float):Float {
        _ensureLUT();
        return MathLUT.sqrt(x);
    }

    /**
     * Seno via LUT de 4096 entradas. Erro máximo ~0.0008 rad.
     */
    public static function fastSin(x:Float):Float {
        _ensureLUT();
        return MathLUT.sin(x);
    }

    /**
     * Cosseno via LUT de 4096 entradas.
     */
    public static function fastCos(x:Float):Float {
        _ensureLUT();
        return MathLUT.cos(x);
    }

    /**
     * Lerp linear simples (sem LUT, já é O(1)).
     */
    public static inline function lerp(a:Float, b:Float, t:Float):Float {
        return a + (b - a) * t;
    }

    /**
     * Clamp de float.
     */
    public static inline function clamp(v:Float, min:Float, max:Float):Float {
        return v < min ? min : (v > max ? max : v);
    }

    // ── AudioAnalyzer ─────────────────────────────────────────

    /**
     * Estima BPM a partir de bytes PCM 16-bit mono.
     * Útil para pré-análise de áudio antes do gameplay.
     * Retorna BPM (60–300) ou -1 se não for possível estimar.
     */
    public static function getBPM(bytes:Bytes, sampleRate:Int):Float {
        return AudioAnalyzer.getBPM(bytes, sampleRate);
    }

    /**
     * Converte Bytes de um arquivo de áudio (OGG/WAV) em BPM.
     * Tenta extrair PCM; para OGG precisa de decoder disponível.
     * Para WAV PCM 16-bit padrão, funciona diretamente.
     */
    public static function getBPMFromFile(path:String, sampleRate:Int = 44100):Float {
        var bytes:Bytes = readFileBytes(path);
        if (bytes == null) return -1;
        // Detecta WAV e pula header (44 bytes padrão)
        if (bytes.length > 44 && bytes.getString(0, 4) == "RIFF") {
            var sampleRateFromHeader:Int =
                bytes.get(24) | (bytes.get(25) << 8) |
                (bytes.get(26) << 16) | (bytes.get(27) << 24);
            if (sampleRateFromHeader > 0) sampleRate = sampleRateFromHeader;
            var stripped:Bytes = bytes.sub(44, bytes.length - 44);
            return AudioAnalyzer.getBPM(stripped, sampleRate);
        }
        return AudioAnalyzer.getBPM(bytes, sampleRate);
    }
}
