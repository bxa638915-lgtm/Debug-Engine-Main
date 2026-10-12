# DBE: reduzir custo de interpretação dos scripts em genocide-D3R

## Status

Design revisado após inspeção de FlxSprite.makeSolid; aguardando aprovação desta especificação revisada. Nenhuma alteração de engine foi feita para este trabalho.

## Objetivo

Reduzir o trabalho repetido da ponte Lua→HScript na música genocide-D3R e ampliar o diagnóstico F8 para revelar scripts, câmeras, filtros e gráficos grandes. O usuário relata FPS baixo já no início em Release e FPS normal quando os scripts do mod estão desativados.

Esta fase preserva integralmente a semântica de makeGraphic. A imagem sólida de 12.000 × 12.000 pixels continua sendo uma alocação potencialmente muito cara; fica registrada para uma etapa própria, pois o atalho FlxSprite.makeSolid altera scale, frameWidth e frameHeight. Uma troca genérica poderia quebrar scripts e mods.

## Evidências no checkout

- mods/d 3 S 0 r mix/data/genocide-d3r/EndingCinematics.lua:6-15 cria em onCreate() um gráfico branco sólido de 12000 × 12000 pixels com alpha 0.001, usado depois. Em RGBA de 8 bits, o bitmap representa aproximadamente 576.000.000 bytes (549 MiB), sem contar outras alocações. A alocação está confirmada; sua contribuição exata aos 13–25 FPS ainda não foi medida.
- source/funkin/backend/scripting/LuaScript.hx:656-667 encaminha runHaxeCode a um interpretador HScript persistente. source/funkin/backend/scripting/HScript.hx:71-78,176-181 reparseia o texto em cada executeString.
- mods/d 3 S 0 r mix/data/genocide-d3r/somethincool.lua:175-192 monta trechos runHaxeCode dentro do update por personagem. O mesmo texto de cada personagem se repete; o custo por frame não foi medido.
- O hscript-improved local define Expr como estrutura de dados percorrida por Interp.execute; a segurança de executar a mesma expressão várias vezes deve ser confirmada antes do cache.
- Em .haxelib/flixel/git/flixel/FlxSprite.hx:743-749, makeSolid(Width, Height, Color) cria backing graphic de 1×1, aplica scale.set(Width, Height) e atualiza o hitbox. Portanto não é substituto semanticamente neutro para makeGraphic.
- PlayStateDiagnostics já captura relatório sob demanda via Ctrl+Shift+F8 em source/funkin/game/PlayState.hx:1540-1541; o relatório já enumera scripts, câmeras e objetos. O snapshot pode ser ampliado sem medição contínua por frame.
- PlayState ordena e consome os eventos do chart por fila; Paths.image usa cache de bitmap do Flixel. A inspeção estática não aponta para uma reescrita desses carregadores como primeira correção.

## Abordagens

1. Mudar makeGraphic para makeSolid em gráficos grandes: reduziria o bitmap, mas muda as dimensões internas do frame e os valores/efeitos de scale; risco amplo de compatibilidade.
2. Reutilizar o parse HScript e ampliar o snapshot F8 — recomendado: remove parse repetido confirmado e ajuda a identificar custos ainda não medidos, sem tocar em gráficos, eventos ou scripts do mod.
3. Criar um novo renderer de retângulos sólidos com semântica compatível: pode atacar a alocação de 549 MiB preservando o contrato, mas exige projeto e validação próprios; fica fora desta fase.

## Desenho recomendado

### 1. Cache limitado de expressões para runHaxeCode

No caminho de HScript.executeString(source), consultar um cache por instância e por texto-fonte exato antes de chamar loadFromString. Guardar apenas expressões parseadas com sucesso; executar a expressão no interpretador a cada chamada. O cache deve ser limitado a 64 fontes, ter eviction determinística, e ser limpo ao recarregar ou destruir o interpretador.

Contabilizar hits/misses do cache para o relatório F8. Snippets vazios, entradas que não podem ser cacheadas e erros de sintaxe conservam o caminho atual e o contexto de arquivo/linha. Antes de ativar a reutilização, confirmar no hscript-improved local que Interp.execute não modifica a AST de forma que a próxima execução mude o resultado.

### 2. Snapshot F8 para scripts, câmeras e gráficos

Estender PlayStateDiagnostics sem mudar a tecla existente nem coletar métricas continuamente:

- resumir quantidade de scripts ativos por tipo e hits/misses do cache HScript;
- resumir câmeras registradas e listar quantidade/tipo dos filtros em cada uma, tratando listas nulas;
- para os sprites já percorridos, informar dimensões do backing graphic e estimativa CPU RGBA8 (width × height × 4), identificando isso como estimativa e sem alegar que representa memória real de GPU;
- manter o texto limitado e sem spam por frame; dados indisponíveis aparecem como desconhecidos em vez de abortar a captura.

### 3. Imagem sólida gigante permanece sem alteração nesta fase

Não interceptar makeGraphic, não trocar para makeSolid e não editar EndingCinematics.lua. O relatório F8 ajudará a localizar e quantificar graficamente o overlay durante o jogo. Um caminho de renderização compatível para gráficos planos será um projeto separado, com contrato de escala e dimensões especificado antes de implementação.

## Fluxo

1. runHaxeCode recebe o texto como hoje.
2. O interpretador procura a string exata no cache; em miss faz o parse atual e armazena AST válida se houver espaço.
3. Cada chamada executa a AST no mesmo interpretador; reload/destroy limpa cache e contadores da instância.
4. Ctrl+Shift+F8 captura os contadores e um snapshot de scripts/câmeras/filtros/gráficos sem alterar o gameplay.

## Fora de escopo

- Alterar makeGraphic, a representação de gráficos sólidos ou a alocação de whiteOverlay.
- Editar genocide-D3R, scripts Lua, charts, eventos, personagens ou shaders do mod.
- Alterar ordem, cancelamento ou timing dos eventos do chart.
- Refatorar ou pre-carregar carregadores de eventos, assets ou personagens.
- Substituir/converter câmeras ou aplicar filtros automaticamente.
- Medir tempo de GPU ou prometer uma taxa fixa de FPS.

## Compatibilidade e riscos

- Reutilizar AST pode manter estado interno inválido se o interpretador mutar nós. Conferir implementação e, se houver mutação incompatível, não ativar cache nessa forma.
- Cache por fonte exata pode crescer; limite 64 por interpretador e limpeza no ciclo de vida são obrigatórios.
- Erros não podem desaparecer por cache: falhas de parse não entram no cache e continuam mostrando caminho/linha.
- A estimativa de memória usa RGBA8 como aproximação; reportá-la como orçamento teórico da imagem, não como medição de memória de processo/GPU.
- A imagem 12.000 × 12.000 continua alocada e pode continuar afetando memória/render. Esta fase não garante resolver toda a queda de FPS.
- O F8 deve permanecer sob demanda, para não introduzir custo permanente na build Release.

## Critérios de aceitação

- Nenhum arquivo do mod, chart ou evento muda.
- Chamadas repetidas de texto Haxe idêntico atingem o cache depois do primeiro parse e executam efeitos em todas as chamadas.
- Cache tem limite de 64 entradas por HScript e é esvaziado em reload/destroy; parsing inválido continua apresentando contexto.
- Ctrl+Shift+F8 gera relatório com dados disponíveis de scripts, câmeras, filtros, hits/misses e dimensões/estimativas de gráficos, sem travar quando dados são nulos.
- A build Windows Release compila. A mesma música e máquina são comparadas com os scripts ativos antes/depois, registrando FPS e memória observados, sem garantia de um número específico.
- Se o FPS continuar baixo, a etapa seguinte usa esses dados para priorizar; o renderer compatível de gráficos sólidos exige especificação própria.

## Próxima etapa

Após a aprovação desta especificação revisada, preparar planos separados para o cache HScript e para o snapshot F8. Nenhuma implementação começa antes da aprovação dos planos e da escolha do método de execução.