# API de compatibilidade

## Descobrir capacidades em HScript

Scripts HScript recebem `engine.compatibility` e `engine.modApiVersion`:

```haxe
var compatibility = engine.compatibility;
if (compatibility.supportsLanguage("hscript")) {
    trace("HScript está disponível");
}

if (compatibility.supportsScriptFile("mods/example.lua")) {
    trace("Este build anuncia um adaptador Lua");
}
```

`compatibility.apiVersion` identifica o formato deste objeto. `languages`, `runtimes`, `scriptExtensions` e `containerExtensions` são cópias dos dados do build. `.pack` é um contêiner e não aparece como linguagem.

O build também reconhece `.hxc` e encaminha esses arquivos ao interpretador HScript Improved, para permitir exercitar a extensão de scripted classes do V-Slice. Isso não implica paridade com o loader Polymod, classes-base ou APIs do FNF 0.8.7; scripts `.hxc` precisam ser validados no jogo e podem exigir adaptação.

## Adicionar um adaptador

`cne.compat.ScriptAdapterRegistry<T>` guarda o despacho sem depender de um runtime concreto. `funkin.backend.scripting.ScriptAdapterManager` registra as implementações do jogo. Um adaptador informa linguagem, runtime, extensões, uma fábrica para caminho de asset e outra para fonte em memória. A extensão é normalizada, e registro inválido ou colisão é rejeitado sem alterar o registro.

```haxe
ScriptAdapterManager.register(
    "example",
    "example-runtime",
    ["example"],
    (path:String) -> new ExampleScript(path),
    (code:String, path:String) -> new ExampleScript(path, code)
);
```

Registre a implementação antes de carregar arquivos com essas extensões. O registro atual é inicializado de forma preguiçosa pelo loader; HScript é sempre incluído. LuaJIT é adicionado apenas em builds C++ com `LUA_ALLOWED`.

## Exemplo Psych Lua

No build C++ com LuaJIT, arquivos `.lua` são criados pelo loader da engine. O adaptador liga as funções explícitas encontradas no fonte Psych presente e oferece helpers para sprites/textos, propriedades/grupos, timers, tweens, áudio, shaders, saves, substates e gameplay:

```lua
function onCreate()
    debugPrint("Adaptador Lua carregado")
end

function onBeatHit(beat)
    local zoom = getProperty("camGame.zoom")
    if zoom ~= nil then
        setProperty("camGame.zoom", zoom + 0.01)
    end
end
```

Arquivo equivalente versionado: [`examples/psych-basic.lua`](examples/psych-basic.lua).

O adaptador chama lifecycle, batidas/passos, countdown, evento de chart, movimento de câmera, input por lane, hits/misses, pausa, game over e fim da música. `Function_Stop` cancela os eventos CNE correspondentes. Consulte a [matriz](COMPATIBILITY-MATRIX.md) para o mapeamento e os limites específicos.

Callbacks de hit/miss e `getPropertyFromGroup` usam uma vista agregada das notas atualmente spawnadas pelas strumlines CNE. A vista ordena por tempo, mas os índices ainda podem divergir do Psych em charts com várias strumlines ou quando scripts dependem da ordem exata em que notas entram e saem do grupo.

`startDialogue` aceita JSON Psych e XML CNE. O JSON é convertido para a cutscene e as caixas CNE; o retrato `bf` usa o personagem `boyfriend` CNE. Retratos customizados do Psych precisam também ter uma definição de personagem em `data/dialogue/characters/<id>.xml` e assets no formato CNE. `setTimeBarColors` cria sob demanda uma barra de tempo no HUD, acessível como `timeBar` e `timeTxt`. `noteTweenDirection` e a propriedade de strum `direction` convertem os graus Psych para o ângulo de movimento das notas do CNE, sem girar visualmente o receptor.

`eventEarlyTrigger` agenda eventos usando o offset retornado pelo Lua; `onSpawnNote` dispara quando a nota cruza o limite de spawn do CNE, que não é necessariamente o instante exato do scheduler Psych. `Function_Stop` em hooks de teclado bloqueia apenas a lane pressionada ou solta. `runHaxeCode` continua interpretando HScript, e `getModSetting` lê valores JSON sem reproduzir a tela persistente de configurações do Psych.

`callOnLuas`, `callOnHScript` e `callOnScripts` mantêm a ordem e os retornos da Psych: `callOnScripts` chama Lua antes de HScript; `Function_StopLua` e `Function_StopHScript` interrompem os callbacks restantes da linguagem correspondente; `Function_StopAll` interrompe essa etapa e impede a etapa seguinte. `ignoreStops` desativa essas interrupções, e `excludeValues` afeta tanto a propagação do retorno quanto as interrupções.

Os callbacks `getAchievementScore`, `setAchievementScore`, `addAchievementScore`, `unlockAchievement`, `isAchievementUnlocked` e `achievementExists` leem definições Psych em `data/achievements.json` e persistem progresso no save da compatibilidade. Desbloqueios não exibem a janela de popup Psych. `changeDiscordPresence` e `changeDiscordClientID` usam a integração RPC CNE. `getTranslationPhrase` e `getFileTranslation` leem `.lang` Psych do mod ativo e usam as traduções XML CNE como fallback.

## Instalação e compilação

`building/libs.xml` fixa o binding LuaJIT no commit `46425aeccdd1d76e65782613a0710f96786c8b4c`; o projeto habilita a dependência e o define `LUA_ALLOWED` para o alvo C++. Em uma cópia nova, execute `building/setup-windows.bat` e depois:

```powershell
haxelib run lime build windows -release
```

Haxe 4.3.7 é a versão usada neste build. O pacote inclui bibliotecas estáticas por plataforma; só Windows x64 foi compilado nesta etapa. A dependência `linc_luajit` é MIT; as notificações de LuaJIT e Lua 5.1 também estão no pacote (`lib/lua/COPYRIGHT`). Preserve esses avisos ao distribuir builds.

## Testes e checkpoint

No Windows, execute todos os testes compatíveis com a máquina e, opcionalmente, compile a engine:

```powershell
.\building\compat-test.ps1 -BuildEngine -GameplaySmoke
```

O runner executa os testes Haxe em `--interp`, compila e executa `LuaRuntimeTest` com LuaJIT nativo e guarda logs em `export/compat-tests`. `-BuildEngine` compila o release Windows; `-GameplaySmoke` carrega um mod temporário em `bopeebo`, confere callbacks no log e remove somente a pasta temporária criada para esse teste.

Para executar somente os testes interpretados sem recompilar os artefatos LuaJIT existentes, use:

```powershell
.\building\compat-test.ps1 -SkipNativeLua
```

Depois da validação, crie um checkpoint seletivo com hashes e instruções de recuperação:

```powershell
.\building\compat-checkpoint.ps1 -Suffix completed -Validation "Testes, build Windows e gameplay smoke passaram"
```

Para conferir/restaurar os arquivos do checkpoint em uma pasta vazia separada:

```powershell
.\building\compat-restore.ps1 -CheckpointPath "..\backups\<checkpoint>" -Destination "C:\temp\cne-restore-review"
```

O utilitário verifica o manifesto SHA-256 e se recusa a gravar dentro da pasta da engine ou sobre uma pasta de destino que já tenha arquivos.

## Limites de segurança

O adaptador esconde `io`, `os`, `package`, `debug`, `require` e funções de arquivo/GC dos scripts Lua. Isso reduz acesso direto a esses módulos, mas não implementa sandbox, limite de memória ou limite de instruções. Um loop infinito ainda pode travar o jogo. HScript também executa no processo e deve ser tratado como código confiável.
