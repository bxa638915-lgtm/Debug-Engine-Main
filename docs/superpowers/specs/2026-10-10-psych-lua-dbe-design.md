# Especificação: compatibilidade de Lua Psych na DBE

**Estado:** aprovada pelo usuário; plano de implementação em revisão
**Data:** 10 de outubro de 2026
**Escopo aprovado:** Psych Engine 0.6.3 e 1.0.4; abordagem contrato primeiro

## 1. Objetivo

Fazer a DBE executar scripts Lua preparados para Psych 0.6.3 e Psych 1.0.4 com compatibilidade demonstrada por contratos versionados e fixtures de comportamento. O suporte só será declarado para comportamentos e plataformas que tenham evidência no código, nos testes ou em execução do jogo.

Uma contagem de nomes registrados não basta para declarar compatibilidade. Cada função e callback deve ter assinatura, valores padrão, retorno, efeitos, condições de execução e divergências descritos e verificados.

## 2. Estado observado no checkout

- A implementação está no diretório Debug Engine-Main. O código usa LuaJIT para Lua 5.1 no alvo C++ quando LUA_ALLOWED está definido; HScript continua como runtime padrão da CNE.
- LuaScript.hx possui um adaptador Psych amplo. A matriz existente relata 246 nomes de funções encontrados no fonte local Psych 1.0.4, mas declara que isso não comprova paridade de assinatura ou comportamento.
- A pasta local chamada `FNF-PsychEngine-0.6.3` declara `psychEngineVersion = '0.6.2'`; ela não é evidência confiável do perfil 0.6.3 sem comparação. A tag oficial `0.6.3` aponta para o commit `eb0ade39e8d1c5437db2166a9ddb6eb3c05956e1`. A tag oficial `1.0.4` aponta para `5c67ced49e5a98535298a6daa3f8f4ec79ac8399`. O plano deve verificar os snapshots contra esses commits antes de extrair contratos.
- A documentação registra build e smoke no Windows. Linux e macOS não foram validados. Web e mobile não têm suporte Lua declarado.
- No Psych 1.0.4, runHaxeCode inicializa o interpretador HScript Iris e pode chamar uma função. A DBE o encaminha ao HScript da CNE. O contrato deve comparar a semântica dos interpretadores, a injeção de variáveis, a persistência, as chamadas e os retornos; compilação de Haxe completo não faz parte deste escopo.
- O checkout tem mudanças locais extensas: 856 remoções rastreadas e 8 arquivos Haxe modificados na verificação de 10 de outubro de 2026. Essas mudanças devem ser preservadas.
- O runner compat-test.ps1 referencia arquivos de teste que estão removidos no working tree atual. A validação futura precisa tratar esse estado como preexistente e não restaurar arquivos automaticamente.
- A documentação de integração afirma que a pasta não tem Git, mas o checkout atual está na branch main e possui o commit 3d5e5be. Corrigir essa divergência documental quando a documentação for atualizada para refletir a implementação.

## 3. Escopo

### Incluído

- Perfis de origem Psych 0.6.3 e Psych 1.0.4, identificados por referência imutável de fonte.
- Funções Lua expostas pelo Psych, incluindo nomes, parâmetros, tipos aceitos, valores padrão, retornos, efeitos no jogo, erros, dependências e condições por plataforma.
- Callbacks do Psych, incluindo gatilho, instante, ordem entre scripts, argumentos, retorno, cancelamento e ciclo de vida.
- Seleção explícita de perfil somente onde diferenças incompatíveis entre versões exigirem comportamento distinto.
- Cobertura de runtime desktop C++ para alvos que a DBE declare suportados e para os quais a dependência LuaJIT possa ser compilada.
- Atualização da matriz de compatibilidade com estados baseados em evidência.

### Fora deste escopo

- Substituir LuaJIT, o ScriptAdapterManager ou o runtime HScript padrão da CNE.
- Portar a engine Psych inteira, sua interface, assets, menus ou gameplay que não sejam necessários para contratos Lua.
- Compilar Haxe completo em runtime. runHaxeCode será tratado como o interpretador HScript usado pelo Psych e terá suas diferenças registradas.
- Declarar suporte Web ou mobile sem runtime Lua disponível e validado para esses alvos.
- Isolar scripts em sandbox ou impor quotas de CPU e memória. Scripts continuam executando no processo do jogo.

## 4. Perfis e seleção por mod

Cada entrada de contrato pertence a uma versão específica. Antes de extrair contratos, registrar para cada perfil o repositório, tag ou commit imutável, arquivos de origem relevantes e checksum do snapshot usado.

Para identificar o perfil no runtime:

1. Usar uma API comum quando as versões tiverem comportamento equivalente ou quando uma assinatura puder aceitar ambas sem ambiguidade.
2. Para diferenças semânticas incompatíveis, aceitar um perfil declarado nos metadados do mod ou uma configuração explícita por mod.
3. Não inferir a versão por heurísticas de conteúdo Lua.
4. Se um mod sem perfil chamar um contrato ambíguo, emitir diagnóstico identificando o mod, a função e os perfis possíveis; não escolher silenciosamente uma semântica.
5. Expor no relatório de compatibilidade do mod qual perfil foi usado ou se o perfil está indefinido.

O nome e o local do campo de metadados serão confirmados contra o schema de mod já existente durante o plano de implementação. A especificação não autoriza alterar formatos sem antes verificar compatibilidade com mods atuais.

## 5. Arquitetura e dados de contrato

Manter o LuaScript como ponte Lua da DBE e reaproveitar ScriptAdapterManager, LuaCallbackScope e PsychHookMap onde seus contratos atuais forem adequados. Criar helpers focados somente quando necessários para separar catálogo, seleção de perfil, dispatch ou conversão de valores.

Manter um catálogo versionado e legível por máquina para cada perfil, acompanhado de documentação resumida. Cada função deve registrar:

- nome e local de origem no código Psych;
- parâmetros em ordem, tipos observados, opcionais, valores padrão e argumentos variádicos;
- valor retornado e conversões entre Lua e Haxe;
- efeitos no estado do jogo ou em saves, assets, áudio, input e objetos;
- pré-condições, alvo ou define exigido e comportamento em erro;
- ligação correspondente na DBE e estado de compatibilidade;
- fixture e evidência usada para validar o contrato.

Cada callback deve registrar:

- evento de origem e condição que o dispara;
- instante relativo ao lifecycle, frame, beat, step, spawn ou input;
- argumentos e conversões;
- ordem entre scripts Lua, HScript e código da engine;
- valores de retorno e regra de cancelamento;
- fixture e evidência que demonstram a ordem e o efeito.

Usar estados de contrato explícitos: compatível, adaptado, incompatível e não verificado. Nenhum item pode permanecer não verificado quando a DBE declarar o perfil concluído. Um item incompatível bloqueia uma alegação de compatibilidade integral até ser corrigido ou aceito expressamente como limitação do perfil.

## 6. Fixtures e comportamento esperado

Criar fixtures pequenas, determinísticas e sem assets proprietários. Separar os casos por perfil e exercitar contratos de forma observável no jogo ou em harnesses que atravessem a ponte Lua real.

A cobertura deve incluir:

- carregamento, ordem de inicialização, reload, fechamento e limpeza de timers, tweens, sons e callbacks;
- parâmetros omitidos, valores padrão, coerção de tipos, retorno nil e propagação de erro;
- grupos, propriedades, sprites, textos, timers, tweens, áudio, shaders, saves e substates;
- ordem e cancelamento de callbacks entre scripts Lua e HScript;
- notes, unspawnNotes, strumLineNotes, múltiplas strumlines, índices e instante de onSpawnNote;
- diálogo, retratos, settings persistentes e efeitos de conquistas;
- runHaxeCode, runHaxeFunction e addHaxeLibrary, incluindo variáveis injetadas e retorno ao Lua.

Contagem de bindings pode ser automatizada pelo catálogo, mas testes de comportamento devem verificar efeitos e resultados, não somente presença de nomes.

## 7. Erros, diagnóstico e observabilidade

Erros de callback ou conversão devem permanecer contidos na fronteira Lua/Haxe e aparecer no console de mods com arquivo, perfil, função ou callback e mensagem útil. Diferenças de perfil indefinido devem apontar a configuração necessária.

Fallbacks só podem ser usados quando o contrato declarar que são equivalentes. Um fallback que altera resultado, ordem, persistência ou efeito visual deve ser registrado como adaptação e exercitado por fixture.

## 8. Critérios de aceitação

1. As referências de fonte dos perfis 0.6.3 e 1.0.4 são imutáveis e reproduzíveis.
2. A lista de funções e callbacks é extraída de cada perfil e reconciliada com as ligações DBE; diferenças de nome ou disponibilidade têm explicação.
3. Todo contrato documenta assinatura, padrão, retorno, efeitos, condição, erro e evidência apropriados ao seu tipo.
4. Cada função e callback declarado compatível tem fixture que demonstra comportamento. A simples presença de um bind não satisfaz este critério.
5. Callbacks canceláveis têm ordem, argumentos e resultado de cancelamento demonstrados, incluindo o dispatch Lua/HScript.
6. Perfis incompatíveis são selecionados explicitamente ou diagnosticados; a DBE não escolhe uma regra ambígua silenciosamente.
7. Não há contratos não verificados na matriz final. Limitações incompatíveis permanecem visíveis e impedem uma declaração de paridade integral.
8. O build e o smoke de gameplay são executados em cada alvo desktop que a DBE declara suportado para Lua. A matriz só marca como validado o alvo realmente executado.
9. Compatibilidade, dependência LuaJIT e limites de segurança são descritos na documentação da DBE sem prometer sandbox ou suporte multiplataforma não testado.

## 9. Sequência de implementação

1. Fixar a fonte Psych 0.6.3 e confirmar a proveniência do fonte 1.0.4; gerar o inventário versionado.
2. Comparar assinaturas e comportamento para identificar contratos compartilhados, adaptáveis e incompatíveis.
3. Definir e implementar a resolução do perfil por mod sem quebrar o schema existente.
4. Adicionar fixtures de contrato e validar primeiro as funções e callbacks com maior alcance no gameplay.
5. Fechar divergências por domínio: dispatch e callbacks; notes e scheduler; APIs de estado/saves/conquistas; diálogo; HScript interoperável.
6. Atualizar LuaScript e helpers DBE somente nos pontos necessários, mantendo HScript CNE e compatibilidade existente.
7. Validar alvos desktop disponíveis, corrigir a matriz e declarar somente os comportamentos comprovados.

Esta especificação define o desenho e os critérios aprovados. O plano de implementação detalha os passos e permanece sujeito à revisão do usuário antes de qualquer alteração de código.

## 10. Riscos e dependências

- A pasta local rotulada como Psych 0.6.3 tem marcador de versão 0.6.2. Os contratos 0.6.3 dependem da verificação de um snapshot obtido da tag oficial fixada acima.
- Alterações locais extensas e remoções de testes podem afetar a validação. Preservá-las e revisar o estado antes de qualquer reparo.
- A semântica de HScript Iris do Psych pode divergir do HScript Improved da CNE; a diferença precisa de fixtures e não deve ser resumida como Haxe completo.
- Lua e HScript executam no processo do jogo sem quotas de execução; este trabalho não transforma scripts em conteúdo isolado.
- A documentação atual pode conter afirmações desatualizadas sobre Git e cobertura. Atualizar somente junto de evidência verificada.
