# Matriz de compatibilidade

Atualizada em 6 de outubro de 2026. Estados refletem evidências disponíveis neste workspace. Compilar um runtime não comprova que toda a API de outra engine funciona.

## Linguagens e formatos

| Origem / formato | Destino | Estado | Evidência e limite |
|---|---|---|---|
| HScript | HScript Improved da Codename Engine | Parcialmente compatível | Loader existente preservado; teste de capacidades e build Windows passaram. Scripts de mods não foram exercitados em uma música nesta rodada. |
| `.hx`, `.hscript`, `.hsc`, `.hxs` | HScript | Implementado e testado no build | O registro envia esses arquivos para `HScript`; `.hx` de mod é interpretado como HScript, não compilado como Haxe completo. |
| `.hxc` de V-Slice | HScript Improved da DBE | Extensão reconhecida; equivalência parcial e ainda sem fixture de jogo | O loader encaminha `.hxc` ao adaptador HScript. Isso não reproduz por si só os imports, classes-base ou APIs específicas do Polymod/V-Slice. |
| `.pack` | Contêiner com fonte HScript | Parcialmente compatível | Separador validado e conteúdo encaminhado ao adaptador correspondente. Não é uma linguagem. |
| Lua 5.1 via LuaJIT 2.0.4 | Codename Engine C++ | Implementado, parcialmente validado | Runtime nativo, build Windows e smoke em `bopeebo` passaram; o smoke cobre lifecycle, hit/miss, barra de tempo, direção do strum, diálogo JSON e dispatch Lua→HScript, inclusive a interrupção por `Function_StopLua`. |
| Psych Engine Lua | Codename Engine | API ampla, equivalência parcial | `LuaScript` liga os 246 nomes de callback explícitos encontrados nos fontes Psych presentes. O inventário confirma nomes, não paridade de assinatura, momento ou efeito. Diferenças documentadas abaixo. |
| JavaScript | Codename Engine | Planejado | Nenhum runtime está integrado. |
| TypeScript | Codename Engine | Planejado | Sem compilador ou runtime; requer também uma decisão sobre execução JavaScript. |
| Haxe completo de mods | Interpretador HScript | Parcialmente compatível | Só funciona a parte aceita pelo parser e pelas APIs do HScript Improved. |

O adaptador Lua é compilado somente quando `cpp` define `LUA_ALLOWED`. A consulta `engine.compatibility` e `Script.scriptExtensions` só anunciam `.lua` nessa configuração. Builds sem Lua continuam podendo compilar sem essa biblioteca.

### API Psych Lua

O fonte local do Psych foi usado para conferir os nomes das funções da API. A comparação estática encontrou 246 funções explícitas (`Lua_helper.add_callback` e `addLocalCallback`) e 247 nomes ligados no adaptador CNE, sem função Psych ausente. Isso não prova equivalência funcional; hooks ainda dependem de eventos que a CNE realmente emite e de objetos que existem nas duas engines.

| Evento CNE | Callback Psych encaminhado |
|---|---|
| `create` / `postCreate` | `onCreate` / `onCreatePost` |
| `update` / `postUpdate` | `onUpdate(elapsed)` / `onUpdatePost(elapsed)` |
| `stepHit` / `measureHit` / `beatHit` | `onStepHit` / `onSectionHit` / `onBeatHit` |
| `onPostStartCountdown` / `onStartCountdown` | `onCountdownStarted` / `onStartCountdown()` |
| `onCountdown` | `onCountdownTick(counter)` |
| `onSongStart` / `onSongEnd` | `onSongStart()` / `onEndSong()` |
| `onPlayerHit` / `onDadHit` | `goodNoteHit(id, direction, noteType, isSustainNote)` / `opponentNoteHit(...)` |
| `onPlayerMiss` | `noteMiss(...)` ou `noteMissPress(direction)` |
| `onEvent` | `onEvent(name, value1, value2, strumTime)` |
| `onCameraMove` | `onMoveCamera("dad" / "boyfriend" / "gf")` |
| `onGamePause` / `onGameOver` | `onPause()` / `onGameOver()` |
| `onInputUpdate` / `onPostInputUpdate` | Hooks `onKeyPressPre`/`onKeyReleasePre` e `onKeyPress`/`onKeyRelease` por lane; `Function_Stop` bloqueia somente aquela lane |
| Mudança de spawn de nota | `onSpawnNote(id, direction, noteType, isSustainNote, strumTime)` ao cruzar o limite de spawn CNE |

`Function_Stop` cancela eventos CNE canceláveis para countdown, fim da música, pausa, game over e hits/misses. Os outros valores de retorno não cancelam gameplay. `measureHit` não garante as mesmas fronteiras de seção para charts com durações variáveis.

`callOnScripts` chama primeiro os Lua e só chama HScript se o retorno Lua estiver em `excludeValues` ou não houver retorno. O smoke de gameplay confirmou a ordem Lua→HScript e que `Function_StopLua` impede o callback HScript seguinte. `Function_StopHScript` e `Function_StopAll` seguem as interrupções específicas do Psych, sujeitas a `ignoreStops` e `excludeValues`; estes dois caminhos permanecem cobertos pelos testes de regras, não pelo smoke de gameplay.

Callbacks de conquistas persistem desbloqueio/progresso por save, sem o popup visual Psych. Frases `.lang` do mod ativo são lidas pelo adaptador; quando não existem, o CNE consulta seu sistema XML de traduções.

O adaptador oferece sprites/textos Lua, animações, grupos, propriedades, timers, tweens, áudio, shaders, save data, substates e funções de utilidade. As coleções Psych `notes`, `unspawnNotes`, `strumLineNotes`, `playerStrums` e `opponentStrums` são vistas construídas a partir das strumlines CNE. `notes`/`unspawnNotes` usam o limite de spawn da CNE; índices podem divergir em charts com várias strumlines ou scripts que dependam do ciclo exato de spawn/removal do Psych.

Limites conhecidos: diálogo JSON usa a apresentação CNE; retratos customizados do Psych só aparecem se também tiverem definição de personagem e assets CNE. `onSpawnNote` segue o limite de spawn da CNE, e índices de grupos de notas podem divergir do Psych em charts com várias strumlines. `runHaxeCode` executa HScript, não Haxe completo; `getModSetting` lê valores JSON, mas não reproduz a UI persistente do Psych. Desbloqueios de conquistas não exibem popup Psych. A integração foi exercitada em um smoke curto, sem validar todos os 246 contratos de API nem todas as plataformas.

## Engines e dados FNF

| Engine / formato | Área | Estado | Evidência e limite |
|---|---|---|---|
| Psych Engine | Scripts Lua | API ampla, equivalência parcial | Nomes da API e limitações acima foram comparados com o fonte Psych local. Build não substitui gameplay com mods representativos. [API Lua oficial](https://github.com/ShadowMario/FNF-PsychEngine/wiki/Lua-Script-API/4674011f51aa6de9405dc161b2c667d4b22dca9d). |
| Psych Engine | Charts | Implementado no código, ainda sem fixture validada nesta rodada | Há `PsychParser` e exportação Psych no projeto; esta alteração não mudou esses caminhos. |
| Kade Engine | Charts legados | Parcialmente compatível, sem fixture nesta rodada | O parser local reconhece formato legado; isso não valida scripts Kade. |
| Kade Engine | Scripts / modcharts | Não investigado a fundo | O upstream contém recurso opcional `FEATURE_LUAMODCHART` para C++, que não demonstra equivalência com Psych Lua. [Fonte oficial Kade](https://github.com/KadeDevelop/Kade-Engine/blob/stable/source/PlayState.hx). |
| V-Slice 0.8.7 | Chart/editor CNE | Parcial; importação e exportação da dificuldade ativa | `VSliceParser` importa para o Charter CNE; File oferece exportação separada do chart e metadata da dificuldade ativa em schema de chart 2.0. O codec cobre lanes padrão, holds, note kinds e parâmetros preservados também ao copiar/colar/duplicar, eventos conhecidos e payloads desconhecidos. Parâmetros customizados ainda não têm inspetor próprio. Export aborta se encontrar linhas/lane extras, BPM contínuo ou eventos sem equivalente. Não é um porte do `ChartEditorState` HaxeUI da V-Slice; round-trip com fixtures oficiais reais ainda pendente. |

Psych Engine foi arquivado em 31 de março de 2025. [Repositório oficial](https://github.com/ShadowMario/FNF-PsychEngine).

## Plataformas

| Plataforma | Estado da engine | Verificação desta etapa |
|---|---|---|
| Windows x64 | Suportada | Build `haxelib run lime build windows -release` passou com LuaJIT habilitado em 6 de outubro de 2026. |
| Linux x64 | Declarada pela engine | Não compilada nem executada nesta etapa. |
| macOS universal | Declarada pela engine | Não compilada nem executada nesta etapa. |
| Web / HTML5 | Sem suporte declarado | Lua não é compilado para esse alvo; build não testado. |
| Mobile | Sem suporte declarado | Não testado; não presumir suporte a partir dos artefatos existentes no pacote LuaJIT. |

## Validação e desempenho

| Verificação | Resultado |
|---|---|
| Comparação de funções API do Psych local com binds CNE | 246 encontradas no Psych; binds e efeitos ainda não equivalem automaticamente |
| Registro, capacidades, property paths, hooks, diálogo JSON e runtime LuaJIT | PASS em `building/compat-test.ps1` |
| Build Windows release desta extensão | PASS: `haxelib run lime build windows -release`, 6 de outubro de 2026; avisos de depreciação existentes |
| Mod Lua real em música CNE | Smoke PASS em `bopeebo`: callbacks lifecycle, beat, miss, cores da barra, tween de direção e abertura de diálogo JSON |
| Linux/macOS, memória, tempo de callbacks e benchmark de gameplay | Não medidos |

Não foi feita comparação de desempenho antes/depois. O teste de runtime mede correção de uma amostra curta, não desempenho de jogo.
