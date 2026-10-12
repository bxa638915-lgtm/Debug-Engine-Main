# Matriz de compatibilidade

Atualizada em 10 de outubro de 2026. Estados refletem evidências registradas neste workspace. Compilar um runtime não comprova que toda a API de outra engine funciona. O relatório detalhado está em [`COMPATIBILITY-EVIDENCE.md`](COMPATIBILITY-EVIDENCE.md).

## Linguagens e formatos

| Origem / formato | Destino | Estado | Evidência e limite |
|---|---|---|---|
| HScript | HScript Improved da Codename Engine | Parcialmente compatível | Loader existente preservado; teste de capacidades e build Windows passaram. Scripts de mods não foram exercitados em uma música nesta rodada. |
| `.hx`, `.hscript`, `.hsc`, `.hxs` | HScript | Implementado e testado no build | O registro envia esses arquivos para `HScript`; `.hx` de mod é interpretado como HScript, não compilado como Haxe completo. |
| `.hxc` de V-Slice | HScript Improved da DBE | Extensão reconhecida; equivalência parcial e ainda sem fixture de jogo | O loader encaminha `.hxc` ao adaptador HScript. Isso não reproduz por si só os imports, classes-base ou APIs específicas do Polymod/V-Slice. |
| `.pack` | Contêiner com fonte HScript | Parcialmente compatível | Separador validado e conteúdo encaminhado ao adaptador correspondente. Não é uma linguagem. |
| Lua 5.1 via LuaJIT 2.0.4 | Codename Engine C++ | Implementado, parcialmente validado | Runtime nativo, build Windows e smoke em `bopeebo` passaram; o smoke cobre lifecycle, hit/miss, barra de tempo, direção do strum, diálogo JSON e dispatch Lua→HScript, inclusive a interrupção por `Function_StopLua`. |
| Psych Engine Lua 0.6.3 | Codename Engine C++ | Não certificado; gate bloqueado | Fonte oficial fixada no commit `eb0ade39e8d1c5437db2166a9ddb6eb3c05956e1`. Build Windows x64 e 14 fixtures passaram; 2 funções estão `adapted` e 238 contratos seguem `not-verified`. |
| Psych Engine Lua 1.0.4 | Codename Engine C++ | Não certificado; gate bloqueado | Fonte oficial fixada no commit `5c67ced49e5a98535298a6daa3f8f4ec79ac8399`. Build Windows x64 e 14 fixtures passaram; 2 funções estão `adapted` e 276 contratos seguem `not-verified`. |
| JavaScript | Codename Engine | Planejado | Nenhum runtime está integrado. |
| TypeScript | Codename Engine | Planejado | Sem compilador ou runtime; requer também uma decisão sobre execução JavaScript. |
| Haxe completo de mods | Interpretador HScript | Parcialmente compatível | Só funciona a parte aceita pelo parser e pelas APIs do HScript Improved. |

O adaptador Lua é compilado somente quando `cpp` define `LUA_ALLOWED`. A consulta `engine.compatibility` e `Script.scriptExtensions` só anunciam `.lua` nessa configuração. Builds sem Lua continuam podendo compilar sem essa biblioteca.

### API Psych Lua

Os catálogos usam snapshots fixados das fontes oficiais 0.6.3 e 1.0.4 e listam funções e callbacks por perfil. A validação estrutural e a reconciliação de nomes passam. Isso ainda não certifica paridade: 4 de 518 contratos foram reconciliados e marcados `adapted` (dois por perfil); 514 continuam `not-verified` porque assinaturas, defaults, conversões e efeitos ainda não foram fechados por entrada. O build Windows e os 28 fixtures (14 por perfil) passaram antes dos últimos ajustes; fixtures direcionados de animação passaram depois deles. Veja o [relatório de evidências](COMPATIBILITY-EVIDENCE.md) e os arquivos de contrato em `contracts/`.

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

Limites observados nos fixtures incluem: diálogo JSON usa a apresentação CNE; retratos customizados do Psych precisam de definição e assets CNE; `onSpawnNote` segue o limite de spawn CNE; índices de grupos de notas podem divergir em charts multi-strumline; `runHaxeCode` executa HScript; `getModSetting` lê JSON sem a UI persistente Psych; desbloqueios de conquistas não exibem popup Psych. O smoke cobre 14 fixtures por perfil, mas isso não fecha os 514 contratos ainda `not-verified`.

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
| Windows x64 | Builds LuaJIT e HScript-only aprovados; perfil Psych não certificado | Release C++ com Lua compilado, build HScript-only sem `LUA_ALLOWED` e smoke com 14 fixtures em cada perfil passaram em 10 de outubro de 2026. O gate de paridade fica bloqueado pelos contratos `not-verified`. |
| Linux x64 | Não validada | Nenhum build ou smoke neste host Windows. |
| macOS universal | Não validada | Nenhum build ou smoke neste host Windows. |
| Web / HTML5 | Sem suporte declarado | Lua não é compilado para esse alvo; build não testado. |
| Mobile | Sem suporte declarado | Não testado; não presumir suporte a partir dos artefatos existentes no pacote LuaJIT. |

## Validação e desempenho

| Verificação | Resultado |
|---|---|
| Inventário dos contratos Psych | PASS estrutural e reconciliação de nomes; 4 `adapted`, 514 `not-verified` |
| Testes de contrato Python | PASS, 30/30; `building/psych-lua-test.ps1 -ValidateOnly` PASS |
| Build Windows release desta extensão | PASS: `building/psych-lua-test.ps1 -BuildEngine`, 10 de outubro de 2026; avisos de depreciação existentes |
| Fixtures Lua Psych executados no jogo | PASS: 14 fixtures para 0.6.3 e 14 para 1.0.4, em oito grupos de processo; resultado preservado no relatório de evidências |
| Gate final de paridade | BLOQUEADO: 238 contratos 0.6.3 e 276 contratos 1.0.4 permanecem `not-verified` |
| Build Windows sem LuaJIT / `LUA_ALLOWED` | PASS: `building/psych-lua-test.ps1 -BuildHScriptOnly`; a referência Lua descoberta foi protegida por `#if LUA_ALLOWED` |
| Linux/macOS, memória, tempo de callbacks e benchmark de gameplay | Não medidos |

Não foi feita comparação de desempenho antes/depois. O teste de runtime mede correção de uma amostra curta, não desempenho de jogo.
