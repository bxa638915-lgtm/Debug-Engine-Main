# Auditoria da Universal Compatibility Engine

Atualizada em 10 de outubro de 2026. Projeto: DBE, fork Codename Engine 1.1.0. Este checkout é um repositório Git na branch `main`, baseline `3d5e5be2d179`; mudanças locais preexistentes foram preservadas.

## Execução Psych Lua 0.6.3 e 1.0.4 (10 de outubro de 2026)

- Fontes oficiais fixadas nos commits `eb0ade39e8d1c5437db2166a9ddb6eb3c05956e1` (0.6.3) e `5c67ced49e5a98535298a6daa3f8f4ec79ac8399` (1.0.4); SHA-256 por snapshot consta em `docs/compatibility/contracts/source-lock.json`.
- Catálogos reconciliam 201 funções + 39 callbacks para 0.6.3 e 233 funções + 45 callbacks para 1.0.4. Quatro contratos de função estão `adapted` (dois por perfil: `addAnimationByPrefix` e `addAnimationByIndices`); 514 continuam `not-verified` (238 em 0.6.3 e 276 em 1.0.4).
- `python -m unittest discover -s tests/psych_contracts -p "test_*.py"`: PASS 30/30. `building/psych-lua-test.ps1 -ValidateOnly`: PASS. Verificador estrutural e reconciliação dos nomes: PASS.
- `building/psych-lua-test.ps1 -BuildEngine`: PASS para Windows x64 com LuaJIT. `building/psych-lua-test.ps1 -GameplaySmoke -Profiles 0.6.3,1.0.4`: PASS para 14 fixtures por perfil, em oito grupos; logs e execução estão em `export/compat-tests/` e o [relatório de evidências](COMPATIBILITY-EVIDENCE.md).
- Gate final de paridade: BLOQUEADO intencionalmente, porque 514 contratos seguem `not-verified`. Portanto os dois perfis permanecem não certificados; chamadas presentes nos fixtures não são tratadas como equivalência de API.
- Build Windows HScript-only: PASS; o build sem `LUA_ALLOWED` encontrou uma referência Lua sem guarda em `LuaScript.hx`, corrigida envolvendo a classe com `#if LUA_ALLOWED`. O build Lua-enabled e o smoke completo foram repetidos depois da correção.
- Alvos Linux/macOS continuam sem validação: toolchains não estão disponíveis neste host Windows.

## Tecnologias e dependências confirmadas

| Área | Evidência | Estado usado |
|---|---|---|
| Linguagem e compilador | Haxe | 4.3.7 |
| Render/gameplay | HaxeFlixel, OpenFL e Lime | Forks CNE instalados no `.haxelib` local do projeto |
| Scripting padrão | HScript Improved | Declarado em `project.xml`; HScript permanece inalterado como runtime padrão |
| Lua adicional | `linc_luajit` commit `46425aeccdd1d76e65782613a0710f96786c8b4c` | LuaJIT 2.0.4 / API Lua 5.1; só alvo C++ |
| JavaScript / TypeScript | Sem runtime no projeto | Não executa essas linguagens |

`building/libs.xml` agora fixa o binding LuaJIT no commit acima. O binding é MIT; o pacote também contém avisos de licença do LuaJIT e Lua 5.1 em `lib/lua/COPYRIGHT`. As bibliotecas estáticas listadas pelo pacote incluem Windows x64, Linux x64 e macOS, mas esta etapa compilou apenas Windows x64.

O `project.xml` ativa `LUA_ALLOWED` e `linc_luajit` no alvo C++. Outras plataformas não anunciam Lua. Para instalar dependências em um clone novo, o procedimento da engine é `building/setup-windows.bat`; depois rode `haxelib run lime build windows -release`.

## Arquitetura implementada

- `ScriptAdapterRegistry<T>` registra linguagens, runtimes, extensões e fábricas para arquivos ou fonte em memória. Colisões de extensão são rejeitadas sem alteração parcial.
- `ScriptAdapterManager` conecta o registro genérico aos scripts concretos. `Script.create` e `Script.fromString` usam esse caminho para criar HScript ou Lua.
- `ScriptCapabilities` expõe `engine.compatibility`, com linguagem, runtime, extensões executáveis, contêineres, plataforma e defines do build. O conjunto de capacidades é informado pelo build e pelas extensões registradas.
- `LuaCallbackScope` dá nomes nativos exclusivos a cada estado Lua, remove callbacks ao encerrar o script, retorna `nil` para resultados Haxe não conversíveis e captura exceções antes que atravessem a fronteira C++.
- `PsychHookMap` liga lifecycle CNE a hooks Psych; `LuaScript` converte eventos canceláveis e eventos de chart em argumentos escalares onde há correspondência.

HScript continua executando no processo do jogo e preserva as APIs Haxe/CNE já expostas. `.hx` de mod é fonte HScript; isso não compila Haxe completo do mod. `.hxc` agora é encaminhado ao mesmo runtime, sem equivalência comprovada para classes-base ou APIs Polymod/V-Slice. `.pack` permanece contêiner.

### Lua disponível

O adaptador liga os 246 nomes explícitos (`Lua_helper.add_callback`/`addLocalCallback`) encontrados nos fontes do Psych, incluindo módulos de conquistas, Discord e idioma; cobre sprites/textos, propriedades, grupos, timers, tweens, áudio, shaders, save data, substates e várias funções de gameplay. O inventário valida presença de nomes, não compatibilidade integral de parâmetros ou efeitos. Conquistas persistem sem o popup Psych, RPC usa os recursos CNE e traduções `.lang` são lidas do mod ativo com fallback XML CNE.

Hooks disponíveis incluem lifecycle, hits/misses, countdown, eventos de chart com `eventEarlyTrigger`, movimento de câmera, input com bloqueio por lane, spawn aproximado, pausa, game over e fim da música. `Function_Stop` cancela eventos CNE compatíveis e pode bloquear uma lane de input sem interromper as demais. `callOnScripts` despacha Lua antes de HScript e entende `Function_StopLua`, `Function_StopHScript` e `Function_StopAll`. As coleções Psych de notas e strums são vistas temporárias calculadas sobre as strumlines CNE; seus índices refletem o limite de spawn CNE e podem divergir do Psych em charts multi-strumline ou scripts que alterem notas pelo índice.

Diferenças restantes: `setTimeBarColors` cria uma barra de tempo CNE sob demanda; `noteTweenDirection` converte direção Psych em ângulo de movimento CNE; `startDialogue` converte o JSON Psych e usa a apresentação de diálogo CNE. Retratos customizados precisam de definições de personagem e assets CNE. `onSpawnNote` segue o scheduler CNE, e `runHaxeCode` aceita HScript, não Haxe completo. `getModSetting` lê JSON sem reproduzir as configurações persistentes do Psych.

## Engines e dados FNF

- Psych Engine: API Lua examinada na documentação e no template oficial; o repositório foi arquivado em 31 de março de 2025. [API Lua oficial](https://github.com/ShadowMario/FNF-PsychEngine/wiki/Lua-Script-API/4674011f51aa6de9405dc161b2c667d4b22dca9d).
- Kade Engine: o parser local identifica charts legados, mas não valida scripts. O upstream inclui modchart Lua opcional para C++; isso não equivale a Psych Lua. [Fonte oficial Kade](https://github.com/KadeDevelop/Kade-Engine/blob/stable/source/PlayState.hx).
- O Charter CNE agora exporta a dificuldade ativa em V-Slice 2.0 (chart JSON e metadata JSON separados), mantendo a UI/skin e as traduções da CNE. O codec cobre lanes de oponente/jogador com 4 teclas, holds, note kinds/params e eventos mapeados; parâmetros customizados são mantidos ao carregar, duplicar, copiar/colar e exportar, mas ainda não têm inspetor próprio. Eventos V-Slice desconhecidos passam como payload opaco. Linhas adicionais, lanes fora de 0–3, BPM contínuo, eventos CNE sem equivalente e zoom fora de `camGame` são recusados para evitar perda silenciosa. A suíte do codec valida esses contratos e o build Windows passou; a interface/editor completo da V-Slice e round-trip de fixtures reais ainda não foram portados/validados.

## Backup, checkpoints e restauração

Backup integral verificado antes das alterações: `backups/CNE-compat-master-20261003-213953`, fora da árvore da engine. Ele contém o snapshot do código e da instalação identificados no início: 2.977 arquivos, 1.053.663.535 bytes, caminhos/tamanhos/hashes SHA-256 verificados. O checkout permanece dentro do repositório Git; os backups e checkpoints antigos são arquivos históricos externos a esta árvore.

Checkpoints incrementais, todos fora do projeto:

| Checkpoint | Conteúdo |
|---|---|
| `CNE-compat-master-checkpoint-03-20261003-235611` | Fontes, testes e docs antes do registro modular |
| `CNE-compat-master-checkpoint-04-20261004-000904` | Registro modular após testes e build Windows |
| `CNE-compat-master-checkpoint-05-completed` | Implementação, scripts, testes, logs e docs desta rodada; manifesto SHA-256 verificado |
| `CNE-compat-master-checkpoint-06-20261004-final` | Smoke de gameplay com dispatch Lua/HScript, documentação atualizada e manifesto SHA-256 verificado |

Cada checkpoint tem `checkpoint-manifest.json` com SHA-256 e instruções `RESTORE.txt`. Para recuperar, restaure arquivos selecionados para uma pasta separada, confira o manifesto e revise as diferenças antes de substituir arquivos de trabalho. O backup integral preserva o estado original.

## Validação histórica (6 de outubro de 2026)

| Verificação | Resultado |
|---|---|
| Inventário de funções Lua do Psych local | 246 nomes explícitos comparados; todos têm bind CNE. É validação estática de nomes |
| Testes Haxe: registro, capacidades, hooks, dispatch de retornos, property paths e diálogo JSON | PASS em `building/compat-test.ps1` |
| Runtime LuaJIT nativo Windows | PASS em `building/compat-test.ps1` |
| Build release Windows desta extensão | PASS: `haxelib run lime build windows -release`, 6 de outubro de 2026; avisos de depreciação do projeto/dependências continuam |
| Smoke de gameplay Lua em `bopeebo` | PASS: lifecycle, beat/hit/miss, barra de tempo, direção de nota, diálogo JSON Psych, definição de conquista, fallback de tradução e dispatch Lua→HScript; ordem e interrupção `Function_StopLua` verificadas dentro do jogo |
| Grupos globais Psych de notas e strums | Vistas CNE agregadas implementadas; limite/ordem de spawn não reproduz exatamente os índices Psych em todos os charts |
| Linux/macOS, memória, tempo de callbacks e benchmark | Não executados |

O smoke usa um mod temporário e o remove ao final. Ele confirma os caminhos cobertos, mas não valida cada uma das 246 funções nem todos os formatos de assets de mods.

## Desempenho, plataforma e segurança

Não há comparação de desempenho antes/depois. O build e o smoke test medem correção de compilação e marshalling simples, não latência de gameplay, memória ou carga com muitos scripts.

Windows x64 é o único alvo compilado nesta rodada. A documentação da engine também declara Linux x64 e macOS universal, mas ambos permanecem sem verificação. Web e mobile não são tratados como suportados.

O Lua adapter esconde `io`, `os`, `package`, `debug`, `require` e funções de arquivo/GC dos scripts. Não há quota de memória ou instruções, portanto o runtime não é um sandbox; um script pode travar o jogo com trabalho excessivo. HScript permanece sem isolamento. Trate mods como código confiável.

## Arquivos principais

- Runtime/loader: `source/cne/compat/ScriptAdapterRegistry.hx`, `LuaCallbackScope.hx`, `PsychHookMap.hx`, `ScriptCapabilities.hx`, `source/funkin/backend/scripting/ScriptAdapterManager.hx`, `LuaScript.hx` e `Script.hx`.
- Dependência/configuração: `project.xml`, `building/libs.xml`.
- Testes: `tests/ScriptAdapterRegistryTest.hx`, `ScriptCapabilitiesTest.hx`, `PsychHookMapTest.hx`, `PsychCallbackResultTest.hx`, `PsychLuaPropertyPathTest.hx`, `PsychDialogueConverterTest.hx`, `LuaRuntimeTest.hx`.
- Documentação e exemplo: `docs/compatibility/COMPATIBILITY-API.md`, `COMPATIBILITY-MATRIX.md`, `COMPATIBILITY-ROADMAP.md` e `examples/psych-basic.lua`.
- Automação: `building/compat-test.ps1`, `compat-checkpoint.ps1` e `compat-restore.ps1`.
