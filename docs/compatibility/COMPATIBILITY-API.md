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

No build C++ com LuaJIT, arquivos `.lua` são criados pelo loader da engine. Os perfis catalogados são Psych 0.6.3 e 1.0.4; a lista de binds não equivale a paridade de comportamento. Quatro contratos estão `adapted` e 514 seguem `not-verified`; builds e fixtures aprovados estão listados em [`COMPATIBILITY-EVIDENCE.md`](COMPATIBILITY-EVIDENCE.md). O exemplo usa helpers comuns:

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

### Selecionar o perfil Psych de um mod

Crie `data/config/dbe-compat.json` dentro do mod e selecione o perfil que o mod espera:

```json
{
  "psychLuaProfile": "1.0.4"
}
```

Os valores aceitos são `0.6.3` e `1.0.4`. Sem configuração, com JSON malformado ou com valor não suportado, a DBE usa `unspecified`; APIs cuja semântica depende do perfil falham fechadas e registram o mod e o nome da API no diagnóstico. Scripts HScript/Lua podem consultar `engine.compatibility.psychLuaProfile`, `psychLuaProfiles`, `psychLuaProfileConfig` e `psychLuaProfileConfigStatus`.

O adaptador contém dispatch para lifecycle, batidas/passos, countdown, evento de chart, movimento de câmera, input por lane, hits/misses, pausa, game over e fim da música. Alguns caminhos possuem fixtures de runtime; a lista total de callbacks ainda não foi reconciliada por assinatura e timing. `Function_Stop` cancela eventos CNE correspondentes nos caminhos implementados. Consulte a [matriz](COMPATIBILITY-MATRIX.md) e o [relatório de evidências](COMPATIBILITY-EVIDENCE.md) para estados e limites.

Callbacks de hit/miss e `getPropertyFromGroup` usam uma vista agregada das notas atualmente spawnadas pelas strumlines CNE. A vista ordena por tempo, mas os índices ainda podem divergir do Psych em charts com várias strumlines ou quando scripts dependem da ordem exata em que notas entram e saem do grupo. `eventNotes` expõe os eventos completos do chart com os campos Psych `strumTime`, `event`, `value1` e `value2`.

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

No Windows, valide os catálogos, compile a engine e execute os fixtures Lua para os dois perfis:

```powershell
.\building\psych-lua-test.ps1 -ValidateOnly
.\building\psych-lua-test.ps1 -BuildEngine
.\building\psych-lua-test.ps1 -GameplaySmoke -Profiles 0.6.3,1.0.4
```

`-ValidateOnly` executa a suíte Python de contratos e valida catálogos/manifests. `-BuildEngine` compila o release Windows com LuaJIT e grava o resultado; `-GameplaySmoke` carrega os fixtures em um mod temporário, confere marcadores e ordem de callbacks, registra logs/resultados em `export/compat-tests` e remove somente a pasta temporária daquela execução. O gate final permanece bloqueado até cada contrato ser completado e comprovado.

Para executar os testes Python diretamente e gerar/validar o relatório de evidências:

```powershell
python -m unittest discover -s tests/psych_contracts -p "test_*.py"
python tools/psych-compat/verify_contracts.py --write-evidence-report docs/compatibility/COMPATIBILITY-EVIDENCE.md
python tools/psych-compat/verify_contracts.py --final-gate
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

O adaptador esconde `io`, `package`, `debug`, `require` e funções de arquivo/GC dos scripts Lua. Ele oferece somente `os.clock` por uma tabela limitada, sem reabrir o módulo `os` do sistema. Isso reduz acesso direto a esses módulos, mas não implementa sandbox, limite de memória ou limite de instruções. Um loop infinito ainda pode travar o jogo. HScript também executa no processo e deve ser tratado como código confiável.
