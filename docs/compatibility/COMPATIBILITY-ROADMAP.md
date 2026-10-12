# Roadmap de compatibilidade

O objetivo é maximizar compatibilidade comprovada sem afirmar suporte universal. Impacto, custo e risco são avaliações qualitativas.

## Concluído nesta etapa

| Trabalho | Resultado | Evidência |
|---|---|---|
| Registro modular de adaptadores | Criado para linguagem, runtime, extensões e fábricas de arquivo/fonte | `ScriptAdapterRegistryTest` passa; colisões são rejeitadas sem alterar o registro |
| Consulta de capacidades | `engine.compatibility` acompanha o suporte configurado e diferencia fontes de contêineres | Teste passa com Lua habilitado e desabilitado |
| Adaptador LuaJIT condicional | Lua 5.1 via dependência nativa C++ fixada em commit | Teste nativo Windows passa; engine Windows release compila |
| Adaptador de funções Psych Lua | Binds nativos mantidos e separados por perfil 0.6.3/1.0.4; sprites/textos, propriedades/grupos, timers, tweens, áudio, shaders, saves, substates e gameplay | Build Windows e 28 fixtures passaram antes dos últimos ajustes; fixtures direcionados de animação passaram depois deles; inventário não é prova de paridade de todas as APIs |
| Contratos Psych versionados | 201 funções + 39 callbacks em 0.6.3; 233 funções + 45 callbacks em 1.0.4 | Snapshot oficial fixado; 4 contratos estão `adapted` e 514 `not-verified`, então os perfis não estão certificados. Consulte `COMPATIBILITY-EVIDENCE.md` |
| Dispatch Psych entre Lua e HScript | Ordem Lua/HScript e `Function_StopLua`/`Function_StopHScript`/`Function_StopAll` | Teste de regras e build Windows; smoke dentro do jogo confirmou a ordem Lua→HScript e `Function_StopLua` |
| Hooks Psych/CNE | Lifecycle, countdown, chart event com `eventEarlyTrigger`, câmera, input com bloqueio por lane, spawn aproximado, hits/misses, pausa, game over e fim da música | Testes de hooks e smoke de gameplay no Windows |
| Barra de tempo e direção dos strums | `setTimeBarColors`, `timeBar`, `timeTxt`, `noteTweenDirection` e propriedade `direction` usam objetos CNE | Smoke em `bopeebo` confirmou cores e tween sem erro de runtime |
| Diálogo JSON Psych | JSON de `data/<música>` é convertido para cutscene CNE; idioma selecionado tem prioridade | Teste unitário da conversão e abertura de uma cutscene JSON no smoke |
| Normalizador inicial de mods | CLI aceita pasta/ZIP, identifica marcadores conhecidos, normaliza wrappers e `assets/`, preserva origem e grava relatório por arquivo | `python -m unittest discover -s tests -p 'test_mod_converter.py' -v`; conversão de scripts permanece fora do escopo |
| Exportadores do UI Builder mais seguros | HScript rejeita IDs/câmeras que não sejam identificadores seguros; HScript/Lua escapam strings; XML usa entidades e preserva quebras de linha | `UIBuilderDataTest` cobre strings com controles e entrada inválida |
| Checkpoints e backup | Backup integral validado e checkpoints incrementais fora do projeto | Manifestos SHA-256 e instruções de restauração |
| Validação automatizada Psych Lua | Testes de contrato, build release Windows e fixtures de gameplay para os dois perfis | `building/psych-lua-test.ps1`; logs e resultados persistidos em `export/compat-tests` |

## Próximas prioridades

| Prioridade | Trabalho | Impacto | Custo | Risco | Critério de saída |
|---|---|---:|---:|---:|---|
| A | Validar mods Psych representativos dentro de músicas CNE | Alto | Alto | Médio | Fixtures cobrindo grupos, sprites, tweens, eventos e múltiplas strumlines, com smoke no jogo |
| A | Fechar os 514 contratos Psych 0.6.3/1.0.4 ainda não verificados | Alto | Muito alto | Alto | Cada entrada tem assinatura/defaults/conversão/efeitos/erros ou timing reconciliados com a fonte fixada e fixture aprovado; o gate final passa sem `not-verified` |
| A | Expandir o conversor de hierarquia com fixtures reais por engine | Alto | Alto | Médio | Perfis Psych/CNE/V-Slice validam metadados, caminhos de assets, dependências e carga da cópia convertida; scripts não traduzidos sempre aparecem no relatório |
| A | Igualar o índice de `notes` do Psych em charts com várias strumlines | Alto | Médio | Médio | Reproduzir a ordem de spawn/removal Psych ou registrar divergência por callback |
| A | Fechar paridade do diálogo Psych, incluindo profiles JSON de retratos e comportamento de caixa | Médio | Alto | Médio | Retratos vanilla e customizados Psych mantêm posição, escala, animações e texto em fixtures |
| B | Igualar o instante de `onSpawnNote` e os índices de grupos ao scheduler Psych | Alto | Alto | Alto | Fixtures com várias strumlines confirmam o mesmo instante, ordem e ID de grupo |
| C | Auditar callbacks e modcharts Kade por versão | Médio | Médio | Médio | Fonte de uma versão identificada, API documentada e scripts representativos ou incompatibilidades claras |
| C | Validar parsers Psych/Kade com charts de fixture e conversão de ida/volta | Médio | Médio | Médio | Fixtures versionadas e diferenças observadas documentadas |
| D | Compilar Linux e macOS com o mesmo adaptador | Médio | Alto | Médio | Build e smoke test por alvo; atualizar matriz |
| D | Decidir se JavaScript/TypeScript justificam runtime adicional | Médio | Alto | Alto | Decisão baseada em licença, plataforma, manutenção, testes e custo de distribuição |
| E | Medir tempo de load, callbacks e memória com múltiplos scripts | Médio | Médio | Baixo | Benchmark repetível e comparação com uma linha de base equivalente |
| E | Avaliar limites reais de CPU/memória para Lua | Alto | Alto | Alto | Quotas testadas ou documentação explícita de confiança de mods |

## Decisões mantidas

- HScript permanece o runtime padrão e a referência de comportamento CNE.
- LuaJIT só entra nos alvos C++ onde a dependência está disponível. Web e outros alvos não anunciam Lua.
- O inventário completo de nomes é separado de compatibilidade de comportamento. Os dois perfis só serão declarados suportados quando os catálogos e os resultados por plataforma passarem pelo gate final.
- Diferenças de scheduler, UI, configurações persistentes e formatos de assets continuam explícitas no relatório de evidências e na matriz.
- JavaScript e TypeScript não são ativados até haver runtime portátil e custo de distribuição aceitável.
- Scripts continuam no processo do jogo; remover bibliotecas Lua reduz superfícies acessíveis, mas não torna o runtime isolado.
