// ============================================================
//  PythonBridge.hx — Ponte HScript → Python via IPC subprocess
//  UCE — source/cne/compat/PythonBridge.hx
//
//  Protocolo de comunicação (stdin/stdout JSON, 1 linha cada):
//    → {"cmd":"call","fn":"functionName","args":[...]}
//    ← {"result": <valor>}   ou   {"error":"mensagem"}
//
//  Uso em HScript:
//    import cne.compat.PythonBridge;
//    var bridge = new PythonBridge("python3", "tools/python/chart_analyzer.py");
//    bridge.start();
//    bridge.call("analyze", ["mySong"], function(result) { trace(result); });
//    bridge.stop();
//
//  Segurança:
//    • Processo filho isolado — sem acesso ao processo do jogo
//    • Timeout de 5 s por comando (configurável)
//    • Máximo de 64 comandos pendentes na fila
// ============================================================

package cne.compat;

import sys.io.Process;
import haxe.Json;
import haxe.ds.StringMap;
import haxe.Timer;

class PythonBridge {
    // ── Configuração ─────────────────────────────────────────
    public var timeoutMs:Float  = 5000;   // ms por comando
    public var maxQueue:Int     = 64;     // comandos pendentes máximo

    var _executable:String;
    var _scriptPath:String;
    var _args:Array<String>;
    var _process:Process;
    var _running:Bool = false;
    var _cmdId:Int    = 0;

    // Pendentes: id → {callback, timestamp}
    var _pending:StringMap<Dynamic> = new StringMap();

    // ── Construtor ────────────────────────────────────────────
    public function new(executable:String, scriptPath:String, ?extraArgs:Array<String>) {
        _executable = executable != null ? executable : "python3";
        _scriptPath = scriptPath;
        _args       = extraArgs != null ? extraArgs : [];
    }

    // ── Iniciar processo filho ────────────────────────────────
    public function start():Bool {
        if (_running) return true;
        try {
            var allArgs:Array<String> = [_scriptPath].concat(_args);
            _process = new Process(_executable, allArgs);
            _running = true;
            trace("[PythonBridge] Processo iniciado: " + _executable + " " + _scriptPath);
            return true;
        } catch (e:Dynamic) {
            trace("[PythonBridge] Falha ao iniciar processo: " + e);
            _running = false;
            return false;
        }
    }

    // ── Encerrar processo filho ───────────────────────────────
    public function stop() {
        if (!_running || _process == null) return;
        try {
            // Envia sinal de encerramento gracioso
            _process.stdin.writeString("{\"cmd\":\"exit\"}\n");
            _process.stdin.flush();
        } catch (e:Dynamic) {}
        try { _process.close(); } catch (e:Dynamic) {}
        _running = false;
        _process = null;
        _pending = new StringMap();
        trace("[PythonBridge] Processo encerrado.");
    }

    // ── Chamar função Python ──────────────────────────────────
    /**
     * Envia um comando para o processo Python.
     * fn:       nome da função Python a chamar
     * args:     lista de argumentos (serializados como JSON)
     * callback: function(result:Dynamic) — chamado com o resultado
     *           Em caso de erro ou timeout, result é null e erroMsg é preenchido.
     */
    public function call(fn:String, args:Array<Dynamic>, callback:Dynamic, ?onError:Dynamic) {
        if (!_running) {
            trace("[PythonBridge] call() chamado mas processo não está rodando.");
            if (onError != null) onError("not_running");
            return;
        }
        if (_pendingCount() >= maxQueue) {
            trace("[PythonBridge] Fila cheia (" + maxQueue + "). Descartando chamada para: " + fn);
            if (onError != null) onError("queue_full");
            return;
        }

        var id:String = Std.string(++_cmdId);
        var payload:Dynamic = {cmd: "call", id: id, fn: fn, args: args != null ? args : []};
        var json:String = Json.stringify(payload);

        _pending.set(id, {
            callback:  callback,
            onError:   onError,
            timestamp: Timer.stamp() * 1000
        });

        try {
            _process.stdin.writeString(json + "\n");
            _process.stdin.flush();
        } catch (e:Dynamic) {
            trace("[PythonBridge] Falha ao escrever no stdin: " + e);
            _pending.remove(id);
            if (onError != null) onError(Std.string(e));
        }
    }

    // ── Processar respostas pendentes ─────────────────────────
    /**
     * Deve ser chamado a cada frame (em update(elapsed)) para
     * receber respostas e verificar timeouts.
     * Retorna o número de respostas processadas neste frame.
     */
    public function poll():Int {
        if (!_running || _process == null) return 0;

        var processed:Int = 0;

        // Lê linhas disponíveis sem bloquear
        var line:String = null;
        try {
            // tryReadLine retorna null se não há dados disponíveis
            line = _tryReadLine();
        } catch (e:Dynamic) {
            trace("[PythonBridge] Erro ao ler stdout: " + e);
            stop();
            return 0;
        }

        while (line != null) {
            line = StringTools.trim(line);
            if (line != "") {
                _handleResponse(line);
                processed++;
            }
            try { line = _tryReadLine(); } catch (e:Dynamic) { break; }
        }

        // Verificar timeouts
        var now:Float = Timer.stamp() * 1000;
        var timedOut:Array<String> = [];
        for (id in _pending.keys()) {
            var entry = _pending.get(id);
            if (now - entry.timestamp > timeoutMs) timedOut.push(id);
        }
        for (id in timedOut) {
            var entry = _pending.get(id);
            _pending.remove(id);
            trace("[PythonBridge] Timeout na chamada id=" + id);
            if (entry.onError != null) entry.onError("timeout");
        }

        return processed;
    }

    // ── Helpers internos ──────────────────────────────────────

    function _handleResponse(line:String) {
        var response:Dynamic;
        try { response = Json.parse(line); } catch (e:Dynamic) {
            trace("[PythonBridge] JSON inválido na resposta: " + line); return;
        }

        var id:String = response.id != null ? Std.string(response.id) : null;
        if (id == null || !_pending.exists(id)) {
            trace("[PythonBridge] Resposta sem id ou id desconhecido: " + line); return;
        }

        var entry = _pending.get(id);
        _pending.remove(id);

        if (response.error != null) {
            trace("[PythonBridge] Erro do Python (id=" + id + "): " + response.error);
            if (entry.onError != null) entry.onError(Std.string(response.error));
        } else {
            if (entry.callback != null) entry.callback(response.result);
        }
    }

    function _tryReadLine():String {
        if (_process == null) return null;
        // Process.stdout em Haxe sys é bloqueante por padrão.
        // Para não bloquear, usamos bytesAvailable se disponível.
        var stdout = _process.stdout;
        try {
            var avail = Reflect.field(stdout, "bytesAvailable");
            if (avail != null && avail <= 0) return null;
        } catch (e:Dynamic) {}
        // Lê até newline
        try { return stdout.readLine(); } catch (e:Dynamic) { return null; }
    }

    function _pendingCount():Int {
        var n:Int = 0;
        for (_ in _pending.keys()) n++;
        return n;
    }

    // ── Estado ───────────────────────────────────────────────
    public function isRunning():Bool     { return _running; }
    public function pendingCount():Int   { return _pendingCount(); }
}
