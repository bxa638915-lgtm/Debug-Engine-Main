# DBE: culling e streaming espacial para cenários grandes

## Status

Proposta de design para revisão. Nenhuma mudança de engine, build ou arquivo do mod foi feita nesta etapa. O benchmark em gameplay ainda precisa ser executado com a build identificada abaixo antes de escolher uma implementação.

## Objetivo

Reduzir custo de desenho e, se os dados justificarem, memória e tráfego de textura para camadas grandes e estáticas de cenário. A solução deve manter scripts e mods existentes funcionando, sem editar seus arquivos, charts ou eventos.

## Estado confirmado no checkout

- A build Release presente é `export/release/windows/bin/CodenameEngine.exe`, versão de arquivo `1.1.0.0`, tamanho 73.387.008 bytes, SHA-256 `36F52D4198D63B2DE286F7DB454544493635D66FD2F38D25D01D69FA00587413`. O executável não informa o commit de origem.
- Não havia processo de gameplay ativo durante a inspeção; portanto não existe medição atual reproduzível de FPS/frame time. O checkout está em `3d5e5be` com muitas alterações locais, então não se deve presumir que a build corresponda exatamente ao código atual.
- O chart `genocide-D3R` seleciona o stage `Fire-Restaurant`. O script do stage instancia sprites Lua, inclusive elementos animados, com shader e uma camada de tela (`camOther`). As imagens maiores incluem `backmost flames.png` (8192×4356; estimativa RGBA8 de 136,1 MiB), `newfireglow.png` (3350×3262; 41,7 MiB), `youhavebeendestroyed.png` (3601×1694; 23,3 MiB) e as mesas (3379×1319; cerca de 17 MiB cada). Essas estimativas não são medições de RAM ou VRAM.
- A camada `backmostflames` é animada, usa shader, escala e rotação; não é candidata segura para a primeira versão. `newfireglow` também é animada. `vignette2` é uma sobreposição de tela e não deve ser submetida a culling de mundo.
- `WoWpart.lua` percorre e atualiza até 18 partículas em `onUpdate`, uma hipótese concorrente de custo de CPU. Um FPS baixo com scripts ativos não prova que o cenário seja o gargalo.

## Recursos existentes e limites

- `FlxSprite.draw()` já descarta o desenho de sprites fora da câmera. Isso economiza trabalho de renderização por sprite, mas não evita o carregamento e a decodificação do bitmap inteiro.
- `Paths.image()` resolve o caminho do asset; `FlxSprite.loadGraphic()` usa `FlxG.bitmap.add()` e carrega o gráfico inteiro no cache de bitmap.
- `GraphicCacheSprite` mantém referências e prepara gráficos para a GPU durante a vida do estado. `SongLoader`/`FunkinCache` têm escopos de pré-cache por estado; não foi encontrado um cache espacial LRU para partes de uma imagem.
- Os sprites grandes relevantes são criados por script Lua, não apenas pelos elementos declarados em `Stage.hx`. Uma solução restrita a sprites XML não cobriria esses casos. Qualquer integração deve manter a identidade e as propriedades que scripts já alteram.
- Não foi encontrado conversor de imagens em chunks nem carregador espacial de chunks no código inspecionado.

## Plano por etapas e gates

### 1. Baseline e diagnóstico

Antes de otimizar, registrar caminho, hash e versão do executável efetivamente iniciado, revisão/estado local do código, resolução, limite de FPS/VSync e trecho exato da música. Medir a mesma passagem com scripts ativos e, se houver um mecanismo de diagnóstico compatível já existente, com scripts desativados; não alterar scripts do mod para criar a comparação. Coletar série de frame time/FPS, memória do processo, tempo de entrada na música e inventário de gráficos/objetos. Usar profiler de CPU/GPU quando disponível para separar custo de script, desenho, decodificação e upload de textura.

Gate: só seguir com chunks se dados apontarem para desenho, memória ou upload de texturas do cenário. Se o custo estiver na execução Lua/partículas, esta proposta não resolverá a causa principal.

### 2. Candidato e compatibilidade

Começar avaliando elementos estáticos, sem shader, sem animação, sem rotação e sem atualização por script. A elegibilidade deve ser determinada pela engine em runtime, sem exigir alteração do mod. Sprites dinâmicos, animados, com shader, tela fixa ou modificados por script permanecem no caminho atual até que haja prova de compatibilidade.

Gate: demonstrar que posição, escala, hitbox, transparência, scroll factor, blend, câmera, ordem de desenho e referências Lua continuam equivalentes. Se a identidade/API de um `FlxSprite` não puder ser preservada, não converter esse sprite automaticamente.

### 3. Conversor offline e integração com cache

Se o gate anterior passar, criar ferramenta da engine que gere tiles com metadados de dimensão lógica e posição. Tiles devem preservar pixels e alpha; a borda precisa de padding/bleed apropriado ao filtro de textura para evitar emendas. Guardar resultados em cache derivado externo aos arquivos do mod, identificado por hash do asset de origem, parâmetros e versão do formato.

O carregador atual não lê esse formato. A implementação precisará de um caminho explícito para resolver metadados e carregar apenas os tiles requisitados, sem carregar primeiro o PNG original inteiro. Integrar referências e descarte com o ciclo de vida de `FlxGraphic`/GPU; não deixar `GraphicCacheSprite` fixar todos os tiles durante toda a música. O modo atual de carregamento deve continuar como fallback.

### 4. Seleção espacial e orçamento

Calcular a área visível por câmera com scroll, zoom, viewport e transformações relevantes. Expandir por uma margem configurável de antecipação. Preparar tiles próximos antes de desenhá-los; desenhar apenas os que intersectam a área visível. Descartar tiles distantes com LRU limitado e zona de histerese para evitar recarga ao redor da borda.

Se a câmera saltar além dos tiles preparados, usar fallback seguro e solicitar os tiles de destino. Uma margem finita não pode garantir que um teleporte arbitrário nunca mostre atraso; esse comportamento precisa ser validado e documentado.

### 5. Validação

Comparar a mesma build/cena antes e depois: frame time/FPS, memória de processo, tempo de carregamento, quantidade de tiles residentes e custo de upload. Exercitar pan rápido, zoom, salto de câmera, câmeras de mundo e de tela, transparência, escalas, filtros e ordem de desenho. Inspecionar emendas e áreas vazias. Confirmar que a engine não alterou arquivos do mod.

## Limitações e riscos

- Culling de um sprite inteiro já existe; o ganho de render só aparece quando uma imagem grande é dividida em partes menores e apenas as partes relevantes são desenhadas.
- Ocultar sprites ou não desenhar tiles não reduz por si só a memória do bitmap original. Para reduzir memória/decodificação, o PNG original não pode ser carregado no caminho de runtime depois que os tiles forem gerados.
- O cache e o ciclo de vida de texturas da DBE não são espaciais hoje. Um cache de tiles exige contagem correta de referências, descarte de recursos GPU e limite de memória; integração parcial pode aumentar memória ou causar stutter.
- Animação, shader, rotação, atlas/frames, offsets e mudanças de propriedades por scripts tornam a conversão mais difícil. Movimento rápido ou teleporte de câmera pode ultrapassar o pré-carregamento.
- Se CPU de scripts ou partículas for o gargalo, esta ferramenta pode não melhorar FPS. Os tamanhos RGBA8 citados são estimativas teóricas, não evidência do uso real de RAM/VRAM.

## Fora de escopo nesta fase

- Implementar o conversor, o renderer ou o cache espacial.
- Alterar qualquer script, imagem, evento, chart ou arquivo de mod.
- Converter sprites animados, com shader, tela fixa ou controlados por script sem uma prova de compatibilidade própria.
- Prometer um valor de FPS ou tratar a build existente como equivalente ao checkout atual.

## Próxima decisão

Revisar esta proposta. Após aprovação, preparar um plano técnico de implementação e executar primeiro o baseline com a build exata usada no teste. Se a medição não apontar para cenário/desenho/texturas, interromper a linha de chunks e redirecionar o diagnóstico ao gargalo observado.
