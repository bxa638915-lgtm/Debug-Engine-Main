# DBE: carregador de música próprio

## Estado

Especificação revisada e aprovada pelo usuário em 2026-10-11. Nenhum código foi alterado para este projeto.

## Objetivo

Criar um carregador por música para a DBE que prepare o chart e os recursos estáticos da faixa antes da criação normal do `PlayState`, mostre progresso e registre o que foi carregado. A primeira etapa deve reduzir engasgos e trabalho de carregamento ao entrar na música. Uma etapa posterior usará medições da própria execução para investigar o FPS contínuo; o carregador não será tratado como solução automática para custo de scripts por quadro.

O usuário relata que `genocide-D3R` começa com FPS baixo quando os scripts do mod estão ativos e que o FPS melhora ao desativá-los. O resultado mais recente após otimizações anteriores foi de aproximadamente 38–40 FPS. O comportamento dos arquivos do mod, charts e eventos deve permanecer intacto.

## Evidências do checkout DBE

- `source/funkin/menus/FreeplayState.hx:392-393` chama `PlayState.loadSong(...)` e depois troca para `new PlayState()`.
- `source/funkin/game/PlayState.hx:2637-2645` faz `Chart.parse()` em `__loadSong()` e define o chart estático `SONG` antes da troca de estado.
- `source/funkin/game/PlayState.hx:718-837` constrói o gameplay, cria `Stage`, carrega scripts e faz apenas um pré-cache limitado das imagens de pontuação e sons de miss. As linhas 867-870 criam os personagens iniciais.
- `source/funkin/game/PlayState.hx:1210-1257` ordena eventos e carrega `Inst` e `Voices`. `Options.streamedVocals` controla a obtenção das vozes, e `Options.streamedMusic` define `FlxSoundData.allowStreaming` em `source/funkin/options/Options.hx:286`.
- `source/funkin/game/Stage.hx:70-96` lê XML ou converte o JSON de Stage do Psych; `Stage.loadXml()` também executa scripts e callbacks ligados ao `PlayState`. Logo, construir um `Stage` durante o pré-carregamento poderia disparar efeitos antes da hora.
- `source/funkin/backend/utils/XMLUtil.hx:122-147` resolve folhas de sprites de XML; `source/funkin/game/Character.hx:77-100,417` carrega scripts e constrói o personagem. `CoolUtil.preloadCharacter()` em `source/funkin/backend/utils/CoolUtil.hx:456-462` já aquece XML e frames, mas as referências de frames são temporárias.
- `source/funkin/backend/assets/Paths.hx:24,29-35` mantém `tempFramesCache` e o limpa antes de cada troca de estado. O carregador não deve presumir que objetos `FlxFramesCollection` pré-carregados sobrevivem à troca.
- `source/funkin/backend/system/modules/FunkinCache.hx:35-70` divide o cache de assets do OpenFL entre estados e remove do segundo nível o que não for reutilizado no estado seguinte.
- `source/funkin/backend/system/GraphicCacheSprite.hx:5-59` mantém referências a `FlxGraphic` por estado e as desenha para upload à GPU; `MusicBeatState.destroy()` destrói esse cache. A primeira versão não prometerá manter upload de GPU através da troca de estado.
- `source/funkin/backend/system/PlayStateDiagnostics.hx` já grava um relatório sob demanda com câmeras, scripts, HScript cache e árvore de renderização. O carregador deve acrescentar métricas a esse relatório, sem criar coleta permanente por quadro.
- Foram encontrados caminhos para `PlayState` em Freeplay, Story, Lua compatível com Psych, console, MainState e retry. Devem ser tratados por uma API central do engine; uma chamada externa arbitrária que instancia `PlayState` diretamente pode manter o fluxo legado de fallback.
- O checkout contém a DBE, mas não contém a pasta `impostorLegacyPublic-main`; portanto, esta proposta é fundamentada no código DBE disponível e não afirma copiar ou reproduzir detalhes daquele source.

## Abordagens consideradas

1. **Trocar globalmente o sistema de assets:** alcançaria menus, jogo e editores, mas amplia bastante o risco de compatibilidade com mods e formatos variados.
2. **Criar `Stage` e `Character` completos antes do gameplay:** anteciparia mais trabalho, mas seus construtores carregam scripts e emitem callbacks vinculados ao estado ativo; isso pode duplicar ou adiantar efeitos.
3. **Coordenador de carregamento por música, reaproveitando caches DBE — recomendado:** cria um pedido por faixa, descobre recursos estáticos, carrega-os em uma tela própria e então entrega os dados ao `PlayState`. Mantém o comportamento dos scripts/eventos e limita a mudança ao caminho de entrada de gameplay.

## Desenho

### 1. Pedido e fila por música

Adicionar um coordenador e uma tela de carregamento de gameplay. O pedido contém música, dificuldade, variação e contexto de Story/opponent/co-op. A fila prepara:

1. O chart, parseado uma vez e entregue como o mesmo `ChartData` ao `PlayState`.
2. `Inst` e `Voices`, respeitando sufixos, `needsVoices` e as opções de streaming existentes.
3. XML/JSON do Stage e imagens referenciadas estaticamente por ele, respeitando as opções de low-memory.
4. XML e folhas declaradas para os personagens iniciais presentes nas strumlines do chart.

Recursos repetidos são deduplicados pelo caminho já resolvido por `Paths`. O carregador trabalha em etapas na thread principal, entre atualizações da tela de carregamento. Uma operação individual de decode ainda pode levar tempo; a fila não tentará interromper uma decodificação no meio.

### 2. Limites de execução e cache

- O carregador não instancia `Stage` nem `Character`, não roda Lua/HScript e não dispara callbacks/eventos do mod. Esses objetos continuam sendo criados uma vez no `PlayState`.
- Assets declarados no chart/XML podem ser aquecidos antes. Assets dinâmicos pedidos por scripts e shaders continuam sob demanda na primeira versão; o relatório registra requests/misses quando for tecnicamente seguro fazê-lo.
- Reutilizar os caches existentes do OpenFL/Flixel. A troca de estado limpa `Paths.tempFramesCache`, então coleções de frames podem ser reconstruídas no `PlayState` a partir dos bitmaps mantidos no cache de assets. Não manter referências antigas de frames nem alegar que texturas já estão na GPU após a troca.
- Não criar cache permanente de músicas/mods. Um novo pedido substitui o contexto anterior; retry da mesma faixa pode reutilizar assets que ainda estejam nos caches DBE. Mudança de mod ou de origem invalida o chart preparado.
- A música segue as opções atuais de streaming; a primeira versão não decodifica todas as faixas inteiras só para mantê-las na memória.

### 3. Entrada, cancelamento e falhas

Os pontos de entrada do engine devem chamar o mesmo coordenador: Freeplay, início/avanço de Story, comandos internos, início automático, `loadPsychSong()` da ponte Lua e retry de gameplay. A API síncrona existente `PlayState.loadSong()` não deve perder o comportamento que scripts podem esperar; os pontos de entrada assíncronos do engine passam a usar a nova API. Instâncias externas que troquem diretamente para `new PlayState()` podem usar o fluxo legado sem pré-carregamento.

Cada pedido recebe um identificador crescente. Cancelar ou iniciar outra faixa invalida passos restantes do pedido anterior e impede que sua conclusão abra uma música antiga. Depois de concluir, o contexto preparado é consumido pelo `PlayState` uma vez e solto; os caches seguem o ciclo de vida atual de `FunkinCache`/Flixel.

Erros de chart devem interromper a entrada e mostrar o caminho e a fase com opção de voltar. Vozes opcionais ausentes continuam permitidas conforme `needsVoices`; erros de assets não essenciais devem ser listados sem impedir o fallback atual. Falhas de áudio instrumental devem ser visíveis no relatório e não parecer uma tela preta sem explicação.

### 4. Diagnóstico e segunda etapa

Adicionar ao relatório já existente de `PlayStateDiagnostics` um resumo do último carregamento: duração total e por fase, quantidade de recursos, duplicatas removidas, cache hits/misses e falhas com caminho/fase. Não fazer logging por frame.

Após o carregador, comparar `genocide-D3R` no mesmo computador e em Release, com os mesmos scripts ligados, registrando tempo de entrada, FPS e memória. A segunda etapa de FPS contínuo deve identificar primeiro o trabalho por quadro (scripts, eventos, renderização ou shaders) e só então propor uma otimização focada. Nenhuma taxa de FPS é prometida nesta especificação.

## Fora de escopo

- Editar arquivos Lua/HScript, charts, eventos, personagens, assets ou shaders dos mods.
- Alterar ordem/timing/semântica de eventos ou executar scripts antes da entrada normal em `PlayState`.
- Reescrever toda a API de assets do engine ou carregar todos os mods/músicas no boot.
- Compilar shaders ou criar objetos Flixel de gameplay fora do estado ativo nesta primeira versão.
- Corrigir o custo de callbacks por quadro apenas adicionando pré-carregamento.

## Critérios de aceitação

- As rotas de jogo cobertas usam o mesmo carregador e recebem a faixa/contexto corretos; a API síncrona existente continua disponível.
- O chart não é parseado novamente ao passar do carregador para o `PlayState`.
- `Inst`, vozes, Stage e personagens iniciais declarados são pedidos conforme os dados selecionados, com deduplicação e progresso compreensível.
- O carregador não executa scripts/eventos; durante o jogo, ordem e timing dos callbacks/eventos permanecem iguais ao fluxo atual, assim como o sincronismo de música/vozes, câmera e conteúdo visual.
- Cancelar e escolher outra música não deixa uma conclusão antiga trocar para a faixa anterior.
- Assets opcionais ausentes não bloqueiam a faixa; falhas essenciais informam recurso e fase.
- O relatório F8 contém métricas do carregador sem custo contínuo em Release.
- Build Windows Release e comparação manual de uma rota Freeplay, uma rota Story/retry e `genocide-D3R` com scripts ativos são feitos no ciclo de implementação; limitações de runtime são reportadas, sem alegar teste não executado.

## Riscos e limites

- Assets dinâmicos de scripts não podem ser listados completamente sem executar os scripts; eles continuam em carregamento sob demanda.
- `Paths.tempFramesCache` é limpo entre estados, e `GraphicCacheSprite` é destruído junto do estado. A primeira versão conserva bitmaps/áudio nos caches usuais, mas não garante evitar todo custo de criação de frames ou upload à GPU.
- Uma tarefa grande ainda pode ocupar um frame da tela de carregamento; o orçamento por etapa não pode interromper a rotina interna de decode.
- A conclusão de uma preparação não implica melhora de FPS durante toda a música; a medição de custo de execução será uma etapa separada.
- O código Legacy solicitado como referência não está disponível neste checkout e deve ser comparado depois, caso o source seja colocado no workspace.

## Próxima etapa

O próximo passo é revisar o plano de implementação em `docs/superpowers/plans/2026-10-11-song-loader.md`. Nenhum código de carregador começa antes da aprovação desse plano.
