# Song Loader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. The user selected native execution. Track each step with checkbox syntax.

**Goal:** Preparar chart, áudio e assets estáticos de uma música numa tela com progresso antes de abrir o `PlayState`, reaproveitando os caches da DBE sem alterar o comportamento dos mods.

**Architecture:** Um pedido imutável identifica música, dificuldade, variação, modos de jogo e origem do asset. Um manifesto sem efeitos de gameplay lista recursos estáticos; um coordenador os aquece em pequenos passos na thread principal e entrega um contexto preparado ao `PlayState`. A API síncrona atual continua disponível para compatibilidade, e o relatório F8 recebe apenas um resumo da última preparação.

**Tech Stack:** Haxe, HaxeFlixel, OpenFL/Lime `Assets`, `FlxSoundData`, caches existentes da DBE e relatório `PlayStateDiagnostics`.

**Spec:** `docs/superpowers/specs/2026-10-11-song-loader-design.md`

## Global Constraints

- Não alterar Lua/HScript, charts, eventos, personagens, assets ou shaders dos mods.
- Não instanciar `Stage` nem `Character`, executar scripts ou emitir callbacks/eventos durante o pré-carregamento.
- Não modificar o comportamento de `makeGraphic`/`makeSolid` nem os sistemas globais de assets fora do caminho de carregamento de música.
- Usar `Paths`, `FunkinCache`, `FlxG.bitmap` e `FlxSoundData` existentes; respeitar `Options.lowMemoryMode`, `Options.streamedMusic` e `Options.streamedVocals`.
- Não manter `FlxFramesCollection` através da troca de estado: `Paths.tempFramesCache` é limpo nessa troca.
- Processar no máximo um recurso da fila por atualização; uma decodificação individual não pode ser interrompida.
- Preservar `PlayState.loadSong()` síncrono e manter fallback para chamadas externas que instanciam `PlayState` diretamente.
- Não executar scripts/eventos antecipadamente e não fazer logging por quadro.
- Não adicionar nem executar testes automatizados neste escopo; validar com build Release e roteiro manual abaixo.
- Não criar commits; as instruções locais da DBE proíbem commits sem pedido explícito.
- Não prometer aumento específico de FPS: o carregador trata entrada/engasgos, enquanto FPS durante a música exige perfil separado.

## File Structure

- Criar `source/funkin/backend/assets/SongLoadRequest.hx`: identidade e contexto de uma solicitação, incluindo origem do asset para invalidar contexto obsoleto.
- Criar `source/funkin/backend/assets/SongAssetManifest.hx`: descoberta sem efeitos de gameplay das imagens, folhas de sprites e sons estáticos da música.
- Criar `source/funkin/backend/assets/PreparedSong.hx`: chart e dados/cache preparados que serão consumidos uma única vez pelo `PlayState`.
- Criar `source/funkin/backend/assets/SongLoadReport.hx`: contagens, tempos por fase e erros da preparação concluída.
- Criar `source/funkin/backend/assets/SongLoader.hx`: fila, deduplicação, geração/cancelamento, aquecimento dos caches e entrega do contexto preparado.
- Criar `source/funkin/game/SongLoadingState.hx`: progresso, cancelamento, falha legível e transição ao gameplay.
- Modificar `source/funkin/game/Stage.hx` e `source/funkin/backend/utils/XMLUtil.hx`: compartilhar resolução/enumeração de XML sem construir objetos de gameplay ou duplicar as regras existentes.
- Modificar `source/funkin/game/PlayState.hx` e `source/funkin/game/StrumLine.hx`: consumir chart/dados preparados, preservar a criação normal do jogo e reaproveitar áudio carregado.
- Modificar pontos de entrada: `FreeplayState.hx`, `StoryMenuState.hx`, `LuaScript.hx`, `BuiltInCommands.hx`, `MainState.hx`, `GameOverSubstate.hx`, `PauseSubState.hx`, `GitarooPause.hx`, `Charter.hx` e a progressão de música em `PlayState.hx`.
- Modificar `source/funkin/backend/system/PlayStateDiagnostics.hx`: imprimir o último resumo do loader no relatório Ctrl+Shift+F8.

## Review Focus

- Chart ou instrumental obrigatório ausente/inválido precisa informar música, caminho e fase e oferecer saída; verificar na tarefa 8 com um caminho inexistente enviado pelo comando interno, sem remover assets do mod.
- Stage Psych JSON/XML e grupos `low-memory`/`high-memory` precisam seguir as mesmas regras da criação normal; assets dinâmicos de scripts/shaders continuam lazy e são marcados `not collected` no F8 se não houver fronteira segura. Verificar a enumeração na tarefa 1 e a nota no relatório da tarefa 7.
- Chart com várias strumlines/personagens e prefixos diferentes de vozes deve carregar exatamente os recursos iniciais declarados; verificar na tarefa 1 com um chart que use múltiplas linhas e na tarefa 2 conferindo caminhos deduplicados.
- `needsVoices=false`, vozes opcionais ausentes e streaming ligado/desligado não podem bloquear nem dessincronizar a música; verificar na tarefa 2 pelas opções e na tarefa 8 durante gameplay.
- Cancelar ou iniciar outra faixa enquanto uma fila está ativa não pode abrir a faixa antiga; verificar na tarefa 8 cancelando e iniciando uma segunda música antes da conclusão.

---

### Task 1: Criar pedido e descoberta de assets sem efeitos de gameplay

**Arquivos:**
- Criar: `source/funkin/backend/assets/SongLoadRequest.hx`
- Criar: `source/funkin/backend/assets/SongAssetManifest.hx`
- Modificar: `source/funkin/game/Stage.hx:70-96` para compartilhar a leitura do XML/JSON
- Modificar: `source/funkin/backend/utils/XMLUtil.hx:122-147` para compartilhar a enumeração das folhas
- Ler: `source/funkin/game/Character.hx:714-789` para reaproveitar a resolução XML/JSON existente sem construir `Character`
- Ler: `source/funkin/backend/chart/ChartData.hx:1-58`, `source/funkin/game/PlayState.hx:1210-1257` e `source/funkin/game/StrumLine.hx:115-124`

**Interfaces:**
- Produz `SongLoadRequest(songName:String, difficulty:String, variation:String, opponentMode:Bool, coopMode:Bool, storyMode:Bool, chartingMode:Bool, origin:String, assetRoot:String)`, `SongLoadRequest.forSong(songName:String, difficulty:String, variation:String, opponentMode:Bool, coopMode:Bool, origin:String):SongLoadRequest`, `SongLoadRequest.fromPlayState(origin:String):SongLoadRequest` e `matchesCurrentPlayState():Bool`.
- Produz `enum abstract SongAssetKind(String) from String to String { var IMAGE = "image"; var AUDIO = "audio"; }`.
- Produz `typedef SongAssetEntry = { path:String, kind:SongAssetKind, required:Bool, stream:Null<Bool> }`, `SongAssetManifest.entries:Array<SongAssetEntry>`, `duplicateCount:Int` e `SongAssetManifest.build(request:SongLoadRequest, chart:ChartData):SongAssetManifest`.
- Produz `Stage.getStageXML(stageName:String):Access`, usado tanto pelo construtor de `Stage` quanto pelo manifesto, sem executar `loadXml()`.
- Produz `XMLUtil.getSpriteSheetPathsFromXML(node:Access, spriteName:String, parentFolder:String):Array<String>`, sem criar `FunkinSprite`.

- [ ] Adicionar `SongLoadRequest` com campos finais para música, dificuldade, variação, modos, origem (`freeplay`, `story`, `retry`, `psychLua`, `console`, `autoStart` ou `charter`) e `Paths.getAssetsRoot()`. `forSong` representa uma música alvo ainda não carregada; `fromPlayState` captura a música/contexto atual para retry ou retorno, sem limpar nem alterar contexto de Story.
- [ ] Extrair de `Stage.new()` a leitura atual de XML e fallback Psych JSON para `Stage.getStageXML(stageName)`. Manter os mesmos caminhos, conversão por `RuntimeModConverter.convertPsychStageJson`, mensagens de erro e retorno `null`; o helper não pode chamar `loadXml`, criar scripts ou emitir eventos.
- [ ] Extrair de `XMLUtil.appendSpriteSheetsFromXML()` somente a enumeração do caminho padrão, aliases `<sheet>/<spritesheet>`, atributo `path`, conteúdo textual e deduplicação para `getSpriteSheetPathsFromXML`. Fazer `appendSpriteSheetsFromXML` consumir essa lista e manter validação, avisos, `Paths.getMultiFrames` e `spr.frames` atuais.
- [ ] Implementar `SongAssetManifest.build` lendo `ChartData` já parseado. Incluir `Inst` pelo `Paths.inst`, vozes globais quando `needsVoices` e `Assets.exists` indicarem que devem ser usadas, vozes por prefixo de strumline conforme `StrumLine`, Stage selecionado pelo chart e folhas das personagens iniciais de todas as strumlines. Definir `stream=null` para Inst e `stream=Options.streamedVocals` para cada arquivo de voz.
- [ ] Ao percorrer XML de Stage, respeitar `folder`, nós de sprite reconhecidos e a seleção atual entre grupos `low-memory`/`high-memory`; ignorar nós que só viram recursos por callbacks ou scripts. Ao percorrer personagens, usar `Character.getXMLFromCharName(String)` e a enumeração XML sem criar `Character` nem carregar o script da personagem.
- [ ] Resolver cada caminho final com `Paths`, marcar tipo/obrigatoriedade e deduplicar por caminho resolvido sem diferenciar maiúsculas/minúsculas além das regras de `Paths`. Falha em recurso opcional entra no manifesto como aviso; não alterar a ordem/timing de eventos.
- [ ] Fazer inspeção manual do diff de `Stage` e `XMLUtil`: gameplay/editor devem continuar usando os mesmos caminhos e chamadas de callback; confirmar no código que a construção do manifesto não chama `Stage.loadXml`, `Character.new`, `Script.create` ou `scripts.call`.

```haxe
var entryByResolvedPath:Map<String, SongAssetEntry> = [];
function addEntry(entry:SongAssetEntry):Void {
	if (entryByResolvedPath.exists(entry.path)) duplicateCount++;
	else {
		entryByResolvedPath.set(entry.path, entry);
		entries.push(entry);
	}
}
```

### Task 2: Implementar fila, cache preparado e relatório

**Arquivos:**
- Criar: `source/funkin/backend/assets/PreparedSong.hx`
- Criar: `source/funkin/backend/assets/SongLoadReport.hx`
- Criar: `source/funkin/backend/assets/SongLoader.hx`
- Ler: `.haxelib/flixel/git/flixel/sound/FlxSoundData.hx:42-110`, `.haxelib/flixel/git/flixel/system/frontEnds/SoundFrontEnd.hx:225-260`, `source/funkin/backend/system/modules/FunkinCache.hx:35-70` e `source/funkin/backend/assets/Paths.hx:24-35,266-347`

**Interfaces:**
- Consome: `SongLoadRequest`, `SongAssetManifest.build(request, chart)` e o `ChartData` retornado pelo callback de parse.
- Produz `SongLoader.start(request:SongLoadRequest, loadChart:Void->ChartData):Int`, `SongLoader.update(generation:Int):Void`, `SongLoader.progress(generation:Int):Float`, `SongLoader.isComplete(generation:Int):Bool`, `SongLoader.errorMessage(generation:Int):Null<String>`, `SongLoader.takePrepared():Null<PreparedSong>` e `SongLoader.cancel(generation:Int):Void`.
- `PreparedSong` contém `request`, `chart:ChartData` (a mesma instância retornada pelo callback), `audioDataByPath:Map<String, FlxSoundData>` e `report:SongLoadReport`. O relatório guarda tempo total/por fase, quantidade processada, duplicatas, cache hits/misses e falhas `{path, phase, message}`.
- `SongAssetKind` tem os valores `IMAGE` e `AUDIO`; o `SongLoader` usa uma estrutura privada `LoadJob` para estado da fila e gerações.
- `LoadJob(id:Int, request:SongLoadRequest, loadChart:Void->ChartData)` mantém `chart`, `manifest`, `assetIndex`, `phase`, `audioDataByPath:Map<String, FlxSoundData>` e o relatório ativo.
- `typedef SongLoadFailure = { path:String, phase:String, message:String }`.
- `SongLoadReport` expõe `totalMs:Float`, `phaseMs:Map<String, Float>`, contadores de recursos/duplicatas/hits/misses, `failures:Array<SongLoadFailure>`, `recordBitmap(path:String, cacheHit:Bool):Void` e `recordAudio(path:String, cacheHit:Bool, loaded:Bool):Void`.
- `SongLoader.lastReport(default,null):SongLoadReport` disponibiliza o snapshot final mais recente para o relatório F8.

- [ ] Fazer `SongLoader.start` invalidar a geração anterior, guardar pedido e callback `loadChart`, registrar início e devolver o novo ID. Executar o callback uma única vez no primeiro `update`, dentro de captura de erro, para que falhas de `Chart.parse` sejam mostradas na tela de carregamento; usar exatamente o `ChartData` retornado sem parse adicional.
- [ ] Fazer `update(generation)` ignorar IDs cancelados/obsoletos; após o parse único, construir o manifesto e processar no máximo uma entrada de asset por chamada. Atualizar progresso, fase, tempos e resultado sem logging por frame.
- [ ] Para imagens, aquecer o cache Flixel pela mesma resolução `Paths` que os sprites normais usam; não guardar nem passar `FlxFramesCollection` após a troca, pois `Paths.tempFramesCache` é limpo. Medir hit antes da solicitação pelo cache `FlxG.bitmap` quando a chave existir.
- [ ] Para áudio, criar/reutilizar `FlxSoundData` pelo cache `FlxG.sound.getCache`/`FlxSoundData.fromAssetKey`; manter a política de streaming do instrumental (`Options.streamedMusic`/`FlxSoundData.allowStreaming`) e aplicar `Options.streamedVocals` às vozes. Não criar um `FlxSound` temporário, não iniciar reprodução e não inserir recurso duplicado no mixer.
- [ ] Contar `FlxG.sound.getCache(path) != null` como hit antes de `FlxSoundData.fromAssetKey`; se a chamada retornar `null` para Inst, registrar falha obrigatória; para voz opcional, registrar aviso e deixar `StrumLine` seguir o fallback atual.
- [ ] Armazenar no `PreparedSong` o `ChartData` devolvido pelo callback e os dados de áudio pelos caminhos resolvidos. Registrar `lastReport` só quando uma tentativa termina, falha ou é cancelada; `takePrepared()` consome o contexto da geração concluída uma única vez.
- [ ] Validar geração antes de completar: a geração ainda deve ser ativa e `request.assetRoot` deve coincidir com `Paths.getAssetsRoot()`. Se o mod/origem mudou, descartar o chart/contexto preparado e reportar invalidação.
- [ ] Diferenciar caminho obrigatório e opcional conforme o manifesto: chart ou instrumental ausente/inválido interrompe; Stage/personagem/voz opcionais ausentes geram avisos e preservam o fallback existente.

```haxe
if (entry.kind == SongAssetKind.IMAGE) {
	var wasCached = FlxG.bitmap.get(entry.path) != null;
	Paths.getFrames(entry.path, true);
	report.recordBitmap(entry.path, wasCached);
} else {
	var wasCached = FlxG.sound.getCache(entry.path) != null;
	var data = FlxSoundData.fromAssetKey(entry.path, entry.stream);
	if (data != null) job.audioDataByPath.set(entry.path, data);
	report.recordAudio(entry.path, wasCached, data != null);
}
```

> `stream` fica `null` para instrumental, preservando `FlxSoundData.allowStreaming`, e recebe `Options.streamedVocals` para cada voz. Não guardar as coleções de frames após a troca de estado.

```haxe
public static function start(request:SongLoadRequest, loadChart:Void->ChartData):Int {
	final id = nextGeneration++;
	active = new LoadJob(id, request, loadChart);
	return id;
}
```

### Task 3: Adicionar a tela de carregamento, progresso e cancelamento

**Arquivos:**
- Criar: `source/funkin/game/SongLoadingState.hx`
- Modificar: `source/funkin/backend/assets/SongLoader.hx` para abrir a tela com a geração retornada

**Interfaces:**
- Consome: `SongLoader.start/update/progress/isComplete/errorMessage/cancel`.
- Produz: `SongLoadingState(generation:Int, request:SongLoadRequest)` que exibe faixa/dificuldade, fase e progresso, e troca para `new PlayState()` somente quando a geração termina com sucesso. `showFailure(message:String):Void` apresenta falhas da fase/caminho.

- [ ] Criar uma tela `MusicBeatState` com fundo opaco, nome da música, dificuldade, fase, barra/proporção numérica de progresso e indicação de cancelamento; manter a UI independente de assets do mod.
- [ ] Alterar `SongLoader.start` para abrir `SongLoadingState(id, request)` após guardar o job; não executar `loadChart` até uma atualização posterior. A primeira atualização da tela só arma a fila e permite um frame desenhado; começar o parse na atualização seguinte.
- [ ] Em `update`, chamar `SongLoader.update(generation)` uma vez por frame, desenhar progresso e ignorar resultado se a tela já não representa a geração ativa.
- [ ] Ao pressionar cancelar, chamar `SongLoader.cancel(generation)`, registrar cancelamento e voltar ao `MainMenuState`. Depois de cancelar, nenhum callback/timer desta tela pode trocar para `PlayState`.
- [ ] Em falha, mostrar fase, caminho e mensagem, manter o relatório disponível e aguardar `BACK` ou `ACCEPT` para voltar ao menu; não deixar tela preta nem tentar carregar repetidamente o mesmo recurso.
- [ ] Ao concluir, confirmar `isComplete(generation)` e chamar `FlxG.switchState(new PlayState())`; não consumir o contexto nesta tela, pois `PlayState.create` fará o consumo único. Se a geração não for mais ativa, não trocar o estado.

```haxe
override function update(elapsed:Float):Void {
	SongLoader.update(generation);
	progressBar.percent = SongLoader.progress(generation) * 100;
	var error = SongLoader.errorMessage(generation);
	if (error != null) showFailure(error);
	else if (SongLoader.isComplete(generation)) FlxG.switchState(new PlayState());
	super.update(elapsed);
}
```

### Task 4: Fazer o `PlayState` consumir a preparação sem duplicar chart ou áudio

**Arquivos:**
- Modificar: `source/funkin/game/PlayState.hx:718-870,1210-1257,2617-2645`
- Modificar: `source/funkin/game/StrumLine.hx:115-124`
- Ler: `source/funkin/backend/system/PlayStateDiagnostics.hx:1540-1541`, `source/funkin/backend/assets/Paths.hx:24-35` e `.haxelib/flixel/git/flixel/system/FlxAssets.hx` (`FlxSoundAsset`)

**Interfaces:**
- Consome: `PreparedSong` entregue uma vez por `SongLoader.takePrepared()`; quando não houver contexto correspondente, usa o caminho legado.
- Produz: criação normal de `Stage`, scripts, personagens, eventos, `Inst` e vozes em `PlayState`, usando `ChartData` já parseado e `FlxSoundData` preparado quando disponível.

- [ ] No começo de `PlayState.create`, consumir contexto se música/dificuldade/variação/mod e modos corresponderem aos campos atuais; substituir `SONG` pela referência já preparada apenas após essa validação. Se não corresponder ou não existir, limpar apenas contexto obsoleto e seguir o fluxo legado.
- [ ] Continuar criando `Stage`, personagens e ScriptPack no momento atual de `PlayState.create`; não deslocar callbacks, eventos, câmeras ou objetos do render tree para a tela de carregamento.
- [ ] Em `generateSong`, usar `PreparedSong` para criar Inst/Voices a partir dos `FlxSoundData` já aquecidos, preservando `needsVoices`, sufixos, `persist`, grupos e sincronismo. Para strumlines, usar os dados de voz indexados pelo caminho/prefixo e manter o `new FlxSound()` quando não houver voz.
- [ ] Não remover nem mudar a assinatura/comportamento síncrono de `PlayState.loadSong()` ou `__loadSong()`. Chamadas diretas a `new PlayState()` sem preparação continuam funcionais.
- [ ] Conferir por leitura de diff que `SONG` não passa por `Chart.parse()` uma segunda vez no caminho com loader e que nenhuma criação de `Stage`, `Character`, script, câmera ou evento foi antecipada.

```haxe
var preparedSong = SongLoader.takePrepared();
if (preparedSong != null && preparedSong.request.matchesCurrentPlayState())
	SONG = preparedSong.chart;
// null ou incompatível: continuar pelo fluxo legado e pelo SONG já configurado.
```

```haxe
var vocalData = preparedSong != null ? preparedSong.audioDataByPath.get(vocalsPath) : null;
var vocalSource:FlxSoundAsset = vocalData != null ? vocalData : (Options.streamedVocals ? Assets.getMusic(vocalsPath) : vocalsPath);
vocals = vocalPrefix != "" ? FlxG.sound.load(vocalSource) : new FlxSound();
```

### Task 5: Integrar entradas principais e progressão ao coordenador

**Arquivos:**
- Modificar: `source/funkin/menus/FreeplayState.hx:389-393`
- Modificar: `source/funkin/menus/StoryMenuState.hx:305-310`
- Modificar: `source/funkin/game/PlayState.hx:2080-2085,2600-2645`

**Interfaces:**
- Consome um `SongLoadRequest` explícito e `SongLoader.start(request, loadChart)`; o callback usa as APIs síncronas atuais para preparar o contexto e devolver `PlayState.SONG`.
- Produz o início centralizado de Freeplay, Story e progressão, mantendo a playlist/contexto entre músicas.

- [ ] Em Freeplay, chamar `SongLoader.start` com `SongLoadRequest.forSong(...)` usando os parâmetros do evento; o callback chama `PlayState.loadSong(...)` e retorna `PlayState.SONG`, preservando dificuldade, variação, opponent e co-op.
- [ ] Em início de Story, iniciar o loader dentro do timer atual de confirmação; o request identifica a primeira música da semana e o callback chama `PlayState.loadWeek(week, difficulty)` e retorna `PlayState.SONG`, preservando playlist, dificuldade, variação e contadores de campanha.
- [ ] No avanço de Story em `PlayState`, iniciar o loader para `storyPlaylist[0]`; o request marca `storyMode=true` e o callback chama `__loadSong(...)` e retorna `SONG`, sem zerar o contexto de campanha.
- [ ] Confirmar manualmente Freeplay, primeira faixa e avanço de Story; verificar que cada callback ocorre uma vez e usa o chart/dificuldade/variação esperados.

```haxe
SongLoader.start(request, () -> {
	PlayState.loadSong(event.song, event.difficulty, event.variant, event.opponentMode, event.coopMode);
	return PlayState.SONG;
});
```

### Task 6: Integrar rotas alternativas e compatibilidade

**Arquivos:**
- Modificar: `source/funkin/backend/scripting/LuaScript.hx:1209-1222`
- Modificar: `source/funkin/backend/system/console/BuiltInCommands.hx:73-106`
- Modificar: `source/funkin/backend/system/MainState.hx:178-184`
- Modificar: `source/funkin/game/GameOverSubstate.hx:166-172`
- Modificar: `source/funkin/menus/PauseSubState.hx:176`
- Modificar: `source/funkin/menus/GitarooPause.hx:61-65`
- Modificar: `source/funkin/editors/charter/Charter.hx:2784-2786`

**Interfaces:**
- Consome `SongLoadRequest.fromPlayState(origin)` e `SongLoader.start(request, loadChart)`.
- Produz integração uniforme sem remover `PlayState.loadSong()` nem alterar retorno, pausa/volume ou estado do charting.

- [ ] Integrar `loadPsychSong`: manter retorno `Bool`, pausa/volume da música anterior e argumentos atuais; construir `forSong` com o alvo e mover a chamada existente `PlayState.loadSong(...)` para o callback, substituindo somente a troca de estado pela entrada no loader.
- [ ] Atualizar comando `playSong` para sempre iniciar o loader mesmo quando o chart não existe, deixando a tela mostrar o erro de caminho/fase; `playWeek` mantém a validação de semana e chama `loadWeek` no callback; `goToPlayState` usa `fromPlayState` e o chart carregado sem parse novo.
- [ ] Atualizar `MainState` auto-start com `forSong` e callback que chama `PlayState.loadSong` uma vez e retorna `SONG`.
- [ ] Integrar retry em `GameOverSubstate`, replay em `GitarooPause` e retorno de Options em `PauseSubState` com `fromPlayState`; os callbacks devolvem a música atual, sem manter `PreparedSong` já consumido.
- [ ] Integrar playtest do Charter com `fromPlayState` após definir `chartingMode`, usando o chart que o editor já preparou e preservando personagem/opponent selecionados e demais flags.
- [ ] Fazer busca final por `switchState(new PlayState())` em `source/funkin` e classificar cada ocorrência restante: rota de música deve usar o coordenador; chamada externa/de fallback deve continuar intencionalmente direta.
- [ ] Verificar manualmente `loadPsychSong`, comandos, auto-start, retry, retorno de Options, replay e Charter; confirmar que contexto/música estão corretos e que cada `loadChart` roda no máximo uma vez.

### Task 7: Acrescentar o resumo do loader ao relatório F8

**Arquivos:**
- Modificar: `source/funkin/backend/system/PlayStateDiagnostics.hx: buildReport`
- Ler: `source/funkin/backend/assets/SongLoadReport.hx` e `source/funkin/backend/assets/SongLoader.hx`

**Interfaces:**
- Consome: `SongLoader.lastReport`.
- Produz: uma seção `SONG LOADER` no arquivo da captura Ctrl+Shift+F8, com pedido, estado, tempo total/por fase, recursos, duplicatas, hits/misses e falhas limitadas por caminho/fase.

- [ ] Acrescentar a seção ao relatório existente, sem nova tecla, timer ou consulta por frame. Se nunca houve tentativa, imprimir `No song load report available`.
- [ ] Limitar a lista de falhas a 64 entradas e imprimir total omitido; sanitizar quebras de linha em caminhos/mensagens para o relatório permanecer legível.
- [ ] Reportar assets dinâmicos de scripts/shaders como `not collected` nesta etapa, a menos que exista uma fronteira de carga já segura e fora de caminhos chamados por frame; não instrumentar getters globais de assets nem callbacks de gameplay para fabricar esses contadores.
- [ ] Confirmar por inspeção que a captura só lê o snapshot concluído/cancelado e não chama loaders nem retém `PreparedSong`/objetos Flixel.

```text
SONG LOADER: completed
song=genocide-D3R difficulty=hard variation=<none> generation=4
totalMs=812 chartMs=21 manifestMs=37 assetsLoaded=28 duplicates=6
bitmapCacheHits=9 bitmapCacheMisses=14 audioCacheHits=1 audioCacheMisses=2
dynamicScriptAndShaderAssets=not collected
failures=0
```

### Task 8: Compilar e validar o fluxo aprovado

**Arquivos:**
- Build: projeto Windows Release em `Debug Engine-Main`
- Runtime: `genocide-D3R` com arquivos do mod intactos

**Interfaces:**
- Consome: as rotas e métricas das tarefas 1–6.
- Produz: build Release bem-sucedida e resultados observados para os critérios de aceitação; limitações de runtime ficam registradas.

- [ ] Executar `haxelib run lime build windows -release` na pasta `Debug Engine-Main` e registrar código de saída e erros/avisos relevantes.
- [ ] Abrir uma música por Freeplay e confirmar progresso, entrada no gameplay, chart correto, Stage/personagens visíveis, Inst/Voices sincronizados e ausência de execução antecipada de callbacks.
- [ ] Executar começo e avanço de Story, retry, `loadPsychSong` e playtest do Charter; conferir que cada fluxo mantém contexto e não abre uma faixa antiga.
- [ ] Repetir a preparação com low-memory ligado/desligado e `streamedMusic`/`streamedVocals` ligados/desligados; verificar voz opcional ausente sem modificar o mod.
- [ ] Cancelar uma preparação e iniciar outra; confirmar que somente a segunda pode entrar no gameplay. Consultar F8 durante a música e conferir tempos/contagens/falhas do último pedido.
- [ ] No console interno, executar `playSong __dbe_missing_chart__` e confirmar que o erro é mostrado com caminho/fase e que `BACK` retorna ao menu; não criar arquivo de teste nem editar mod.
- [ ] Comparar no mesmo computador, mesma build Release, mesma seção de `genocide-D3R` e scripts ativos com a observação atual de 38–40 FPS: tempo de entrada, FPS e memória antes/depois. Reportar números observados e separar engasgo de entrada de FPS contínuo.
- [ ] Encerrar sem commit e reportar arquivos alterados, resultado do build, rotas exercitadas e qualquer falha restante.

---

## Auto-revisão do plano

- Cobertura: pedido, manifesto, stage XML/Psych JSON, personagens/folhas, low-memory, áudio/streaming, fila, progresso, cancelamento, falhas, consumo no `PlayState`, rotas DBE, F8 e validação Release estão ligados a tarefas explícitas.
- Consistência de tipos: request/manifesto são produzidos na tarefa 1; loader/report/contexto na tarefa 2; tela usa as funções da tarefa 2; `PlayState` consome `PreparedSong`; rotas fornecem `Void->ChartData`; diagnóstico lê `lastReport` da tarefa 2.
- Placeholders: não há marcadores de conteúdo pendente nem etapas genéricas sem critério. A implementação de áudio usa APIs presentes no checkout listadas na tarefa 2.
- Testes: não serão criados arquivos nem executados testes automatizados; os gates são build Release e validação manual consentida na especificação.
- Revisão: o ponto mais sensível é compatibilidade do `FlxSoundData` preparado com carregamento de vozes por strumline; manter a API existente como fallback e comparar sincronismo na tarefa 8 antes de considerar a etapa concluída.
