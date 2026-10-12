# Baseline de `genocide-D3R` / `Fire-Restaurant`

Status: **Release instrumentada compilada e capturada em gameplay normal; médias de 21,7–24,8 updates/s e picos de até 602 ms apontam para custo de CPU/update; sem evidência de gargalo nas imagens estáticas; chunking não implementado nesta tentativa**.

## Inspeção inicial (2026-10-12 01:12:29 -03:00)

- Processo do jogo: nenhum processo `CodenameEngine`, `lime` ou `neko` ativo foi encontrado nesta inspeção inicial. A build ativa foi confirmada na seção seguinte.
- Executável encontrado no disco: `export/release/windows/bin/CodenameEngine.exe`.
- Metadados desse arquivo (não equivalem à identidade de um processo ativo): versão `1.1.0.0`; 73.387.008 bytes; modificado em `2026-10-12 00:36:22`; SHA-256 `36F52D4198D63B2DE286F7DB454544493635D66FD2F38D25D01D69FA00587413`.
- Fonte local: branch `main`, HEAD `3d5e5be2d17939ac63d8bff4525e8af86dabff72`; `git status --short` reportou 931 entradas. A árvore já contém alterações do usuário, inclusive uma modificação extensa em `source/funkin/backend/scripting/LuaScript.hx`; nenhuma dessas alterações foi descartada.
- Diagnóstico F8: recebido em `C:\Users\esque\AppData\Roaming\Yoshman29\CodenameEngine\dbe-playstate-diagnostic-20261012-011624.txt`.

## Processo ativo (2026-10-12 01:14:56 -03:00)

- PID `15596`; imagem `CodenameEngine.exe`.
- `ExecutablePath`: `C:\Users\esque\Downloads\A_1\A\Vs Impostor alternated Scripts Converts\DBE-Tests-Source\Debug Engine-Main\export\release\windows\bin\CodenameEngine.exe`.
- `CommandLine`: o executável acima, sem argumentos adicionais.
- Versão `1.1.0.0`; tamanho 73.387.008 bytes; `LastWriteTime` `2026-10-12 00:36:22`; SHA-256 `36F52D4198D63B2DE286F7DB454544493635D66FD2F38D25D01D69FA00587413`.
- Esta identidade coincide com o EXE já encontrado no disco. Durante a amostra, o título da janela indicava `Now playing: Genocide-d3r`; a execução ainda precisa ser confirmada como pós-countdown e representativa do modo normal.

## Amostra de memória durante `Genocide-d3r`

- Captura de 60 amostras, PID `15596`, entre `2026-10-12T01:15:52.4527001-03:00` e `2026-10-12T01:16:52.2386404-03:00` (~59,79 s). O título da janela mostrava `Now playing: Genocide-d3r`.
- Working Set: mínimo `1558,7 MiB`, média `1559,8 MiB`, máximo `1560,6 MiB`.
- Memória privada: mínimo `2334,1 MiB`, média `2335,0 MiB`, máximo `2336,7 MiB`.
- CPU acumulada do processo: de `68,796875 s` a `123,25 s`, delta `54,453125 s`, equivalente a ~`0,91` núcleo lógico ocupado em média durante a janela. Isso sugere atividade relevante de CPU, mas não atribui o custo a Lua, desenho ou upload.
- CSV bruto: `docs/superpowers/results/2026-10-12-genocide-d3r-memory.csv` (a coluna `CPUSeconds` usa vírgula decimal do locale pt-BR).
- FPS observado e configuração do jogo: aguardando confirmação do usuário. A amostra sozinha não identifica o gargalo.

## Diagnóstico F8 recebido (2026-10-12 01:16:24)

- `song=genocide-d3r`, `difficulty=d3r`, `songPosition=55.572 s`, `generatedMusic=true`, `startingSong=false`; resolução do jogo `1280×720`. O F8 registra `chartingMode=true`; isso pode não representar uma execução normal pela Freeplay/story e precisa de confirmação antes de usar o baseline como go/no-go final.
- A câmera principal estava em zoom `0,751`. A engine tinha cinco câmeras registradas; os sprites do cenário usam camGame e também câmeras com viewports deslocados (`x=-740` e `x=1380`, zoom `0,8`). Um streaming futuro precisa selecionar a união de tiles visíveis por todas as câmeras do sprite, incluindo zoom/viewport, para preservar o layout mult câmera.
- O stage lista seis sprites. `youhavebeendestroyed.png`, `ltables.png` e `rtables.png` são estáticos e somam ~`57,3 MiB` teóricos RGBA8 por dimensões. `backmost flames.png` (~`136,1 MiB`) e `newfireglow.png` (~`41,7 MiB`, compartilhado por `Fire`/`Fire6`) são animados; o primeiro ainda usa shader. Eles permanecem fora do primeiro caminho de chunking.
- O snapshot lista `117` nós, `106` sprites, `50` candidatos heurísticos a fora da tela e `0` candidatos fullscreen. `FlxSprite.draw()` já faz culling de sprites fora da tela; esse número não prova custo de desenho recuperável pelo plano.
- Existem `32` scripts ativos (31 Lua e um HScript), inclusive `WoWpart.lua`; o cache `runHaxeCode` registra `2218` hits e `5` misses. O processo consumiu ~`0,91` núcleo durante a amostra, mas ainda sem perfil que atribua tempo a um script específico ou ao render.
- O maior backing teórico do snapshot é um `FlxSprite` 12000×12000, alpha `0,001`, estimado em `576.000.000` bytes (~`549,3 MiB`). A inspeção somente leitura do script ativo `EndingCinematics.lua` associa-o a `whiteOverlay`, criado com `makeGraphic(12000, 12000, 'FFFFFF')` e mantido carregado. É um candidato de memória muito maior do que os três bitmaps estáticos do stage; a estimativa não é medição real. Nenhum arquivo de mod foi alterado.
- O relatório mostra `SongLoader totalMs=1853,542` e `phaseMs[assets]=1034,888`, mas `dynamicScriptAndShaderAssets=not collected` e seis falhas de preloading para imagens dinâmicas que aparecem carregadas no PlayState. Isso confirma que o preloader atual não cobre todos os recursos criados por scripts; o fallback de streaming teria de continuar confiável.
- Caminho do relatório F8: `C:\Users\esque\AppData\Roaming\Yoshman29\CodenameEngine\dbe-playstate-diagnostic-20261012-011624.txt`.

## Valores estimados a partir dos arquivos

São estimativas de tamanho descomprimido RGBA8, não medições de memória residente nem atribuição do gargalo:

| Recurso | Dimensões | RGBA8 estimado | Observação |
|---|---:|---:|---|
| `backmost flames.png` | 8192 × 4356 | ~136,1 MiB | Animado e com shader; fora do primeiro recorte de streaming. |
| `newfireglow.png` | 3350 × 3262 | ~41,7 MiB | Animado; fora do primeiro recorte. |
| `youhavebeendestroyed.png` | 3601 × 1694 | ~23,3 MiB | Estático; candidato a medir. |
| `ltables.png` | 3379 × 1319 | ~17,0 MiB | Estático; candidato a medir. |
| `rtables.png` | 3379 × 1319 | ~17,0 MiB | Estático; candidato a medir. |
| `vignette2` | 1280 × 720 | ~3,5 MiB | Overlay de tela; não aplicar culling de mundo. |

`WoWpart.lua` também atualiza até 18 partículas por quadro e pode ser um gargalo concorrente de CPU. O custo acumulado confirma uso alto de CPU, mas sem perfil por script/render e sem as métricas restantes ainda não é possível atribuir a queda a desenho, script, decodificação ou upload de texturas. A busca no código também não encontrou um mecanismo de desativar scripts disponível para A/B sem mudar mods.

## Captura normal em Freeplay (2026-10-12 01:24-01:27)

- O usuário confirmou repetir a música em gameplay normal. O processo continuou sendo o PID `15596`, com o mesmo executável Release e título `Now playing: Genocide-d3r`.
- F8 normal: `C:\Users\esque\AppData\Roaming\Yoshman29\CodenameEngine\dbe-playstate-diagnostic-20261012-012413.txt`; `chartingMode=false`, `origin=freeplay`, dificuldade `d3r`, resolução `1280×720`, `songPosition=8,180 s`, `startingSong=false`.
- O usuário relatou que a execução chegou a **1 FPS** e morreu durante a passagem. Esse é um valor observado pelo usuário, não uma série capturada pelo contador da engine; FPS mínimo/mediano e o trecho exato não foram registrados automaticamente.
- Amostra de processo (~59,79 s, 60 linhas; CSV em `docs/superpowers/results/2026-10-12-genocide-d3r-normal-memory.csv`): Working Set mínimo/média/máximo `1582,1/1582,5/1582,9 MiB`; memória privada `2379,5/2380,0/2380,8 MiB`; CPU delta `67,81 s` (~`1,13` núcleo lógico em média). Isso mede uso agregado do processo, sem atribuir tempo a cada callback.
- Captura adicional de contadores Windows por 15 s, com o processo ainda ativo e na música: engine GPU `3D` do PID ficou em `0%` nas 15 amostras. Memória GPU atribuída: `878.579.712 bytes` dedicados (~`837,6 MiB`) e `1.514.631.168 bytes` locais (~`1,41 GiB`); os valores ficaram constantes. Memória atribuída não demonstra pressão nem relaciona esses bytes a uma imagem específica.
- A tentativa de captura ETW com WPR não iniciou: Windows retornou `0xc5585011` (“Failed to enable the policy to profile system performance”). Portanto não há perfil de CPU, GPU ou upload de texturas que permita atribuir o tempo a um callback.
- O snapshot normal registrou `32` scripts ativos e `runHaxeCode cache hits=566/misses=5`. A leitura somente dos arquivos ativos do build encontrou em `data/genocide-d3r/somethincool.lua` duas chamadas `runHaxeCode` por iteração do `onUpdatePost`, para manter duas câmeras com `follow`; o cache do HScript reaproveita a expressão analisada, mas executa o interpretador em cada chamada. Isso é uma hipótese de custo de CPU, não uma medição por script.
- Outras rotinas ativas incluem shader de câmera (`wavy.lua`/`scaryohhh.lua`), update de partículas no trecho cinematográfico (`WoWpart.lua`) e atualizações de câmera. Ainda não há perfil para dizer qual delas domina.
- A câmera principal estava com `alpha=0`, zoom `0,6`, e `forcedPosition=true`. As câmeras adicionais 1 e 2 estavam visíveis e as imagens do cenário estavam atribuídas às câmeras 0, 1 e 2; uma implementação que avalie só `camGame` arriscaria apagar conteúdo ou causar quadros pretos.
- No snapshot, as três imagens estáticas candidatas continuam estimadas em `57,3 MiB` RGBA8 teóricos; isso equivale a ~`2,4%` da memória privada média do processo. O F8 também mostra atlases de personagem de `8192×8192` e `8192×4096`, o overlay gerado `12000×12000` (~`549,3 MiB` teóricos), além das chamas animadas. Tamanhos teóricos não são alocação residente medida.

## Gate e hipótese de diagnóstico

**Decisão: parar o chunking de cenário nesta tentativa.** O usuário observou 1 FPS, mas a evidência disponível não implica as três imagens estáticas: a GPU 3D reportou 0% durante a amostra, o processo usou ~1,13 núcleo, e as imagens estáticas são uma fração pequena da memória privada. O agregado de CPU não prova que scripts ou partículas sejam a causa, então também não se deve afirmar que `somethincool.lua` é o culpado. O código e os 566 hits de `runHaxeCode` tornam a manutenção de câmeras por HScript um candidato prioritário para um perfil por callback.

O plano de dividir texturas continua útil somente se um perfil posterior mostrar custo de render/residência em imagens estáticas. Para prosseguir com o diagnóstico de 1 FPS, a próxima medição adequada é um contador opt-in da engine que agregue tempo e quantidade de chamadas por script/callback (incluindo `update`/`postUpdate`, chamadas `runHaxeCode` e frame total) e reporte sob demanda no F8; isso não requer alterar mods. Esse instrumento ainda não foi implementado.

## Dados ainda necessários para atribuição fina

Ainda faltam escala do Windows, limite de FPS, VSync e low-memory, e esta captura curta não reproduziu o relato de 1 FPS sustentado. A build e o modo normal estão confirmados. A captura ETW foi bloqueada pela política do Windows, mas o perfil opt-in da engine agora separa custo de update, callbacks e draw CPU; apresentação/GPU continuam fora da medição.

## Perfil de callbacks na Release instrumentada (2026-10-12 01:43:29)

- A Release foi recompilada com sucesso (`lime build windows -release`, exit code 0). O novo `CodenameEngine.exe` tem 73.423.360 bytes, LastWriteTime `01:42:02 -03:00`, SHA-256 `0E5D1CE74EB9BCAB5616E4A84FFBF2D7267076843C509E5999D669C8D12C6B0B`; a build anterior tinha hash `36F52D...` e timestamp `00:36:22`. A captura seguinte veio do processo iniciado às 01:42:27 no caminho Release. A árvore já tinha 931 entradas modificadas antes desta instrumentação; a Release contém o estado completo atual do checkout, não apenas o profiler. Portanto, não é um A/B controlado contra o executável anterior.
- F8 `dbe-playstate-diagnostic-20261012-014329.txt`: Freeplay, `chartingMode=false`, `genocide-d3r` / `d3r`, `songPosition=20.306 s`, resolução `1280×720`.
- 562 amostras: intervalo entre updates médio `40,38 ms` (~`24,8 FPS` equivalente), máximo `601,65 ms`; `PlayState.update` médio `36,20 ms`, máximo `193,76 ms`; `PlayState.draw` CPU médio `0,63 ms`, máximo `43,21 ms`. Portanto, esta captura não demonstra 1 FPS sustentado, mas registra travamentos isolados muito grandes.
- Maior callback: `assets/data/stages/Fire-Restaurant.lua::update`, média `2,23 ms`, máximo `13,91 ms`; próximo foi `scripts/HealthBarTabiRemade.lua::update`, média `1,00 ms`. A maioria dos outros callbacks no top 24 ficou entre `0,81–0,96 ms` por chamada. `runHaxeCode` não aparece entre os 24 maiores por tempo acumulado nesta amostra, embora seu cache tenha 1.124 hits e 5 misses.
- Interpretação: o custo contínuo observado está no caminho de atualização CPU/script, não no tempo CPU de desenho. `PlayState.draw` não mede espera/apresentação da GPU, então isso não exclui todo custo de GPU; ainda assim, chunking das três imagens estáticas não é uma resposta sustentada por estes dados. Não implementar chunking nesta tentativa. As três imagens somam ~57,3 MiB teóricos e o perfil não mostra culling/render como custo dominante.
- Nenhum arquivo de mod foi alterado. O nome do callback líder é registrado apenas para atribuição; esta tarefa não altera o script do estágio. O instrumento usa timers por callback e adiciona uma sobrecarga pequena de medição.


## Captura estendida do perfil (2026-10-12 01:44:23)

O usuário forneceu uma segunda captura da mesma Release em Freeplay normal: `dbe-playstate-diagnostic-20261012-014423.txt`, `genocide-d3r` / `d3r`, `chartingMode=false`, posição `73.676 s`, 1280×720. É um agregado desde o início da música, agora com 1.647 amostras: intervalo médio `46,18 ms` (~`21,7 updates/s` equivalente), máximo `601,65 ms`; `PlayState.update` média `43,03 ms`, máximo `207,25 ms`; `PlayState.draw` CPU média `0,65 ms`, máximo `43,21 ms`. A amostra continua sem mostrar 1 FPS sustentado; o pior intervalo isolado mede ~0,60 s. O crescimento da média entre as capturas de 20,3 s e 73,7 s indica que a cadência média ficou pior durante esse trecho, não melhor.

A ordem se manteve: `assets/data/stages/Fire-Restaurant.lua::update` avg `2,21 ms`; `scripts/storyintro.lua::update` `1,08 ms`; `songs/genocide-d3r/scripts/black.lua::update` `1,07 ms`; `scripts/smoothcam.lua::update` `1,04 ms`; `scripts/HealthBarTabiRemade.lua::update` `1,02 ms`. O cache HScript marcou 3.294 hits e 5 misses, mas `runHaxeCode` não aparece no top 24. Isso reforça o caminho de CPU/update com callbacks distribuídos como a área a investigar; ainda não autoriza pular nem reduzir a frequência de callbacks, pois isso pode mudar comportamento dos mods.


