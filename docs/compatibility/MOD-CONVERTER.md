# Conversor inicial de mods para DBE

`tools/dbe_mod_converter.py` prepara uma cópia de um mod em pasta ou ZIP para a hierarquia de pasta aceita pelo carregador da DBE. O conversor normaliza um diretório externo que envolve o mod e remove o prefixo `assets/` quando ele precede uma pasta de assets conhecida (`data`, `images`, `songs`, entre outras).

## Uso

```powershell
python tools/dbe_mod_converter.py "C:\mods\MeuMod.zip" "mods\MeuMod-DBE" --source-format psych
```

Formatos aceitos: `psych`, `cne` e `vslice`. `--source-format auto` é o padrão e reconhece marcadores conhecidos como `pack.json`, `_polymod_meta.json`, `data/config/modpack.ini` e caminhos de scripts. Quando as evidências forem insuficientes, informe `--source-format` explicitamente.

O destino precisa ser novo e ficar fora da pasta de origem. O comando não altera a origem nem substitui um destino existente. O resultado inclui `_dbe_conversion_report.json`, com a origem identificada, dependências encontradas, caminhos movidos, arquivos preservados, conteúdo ignorado e avisos.

## Conversão e limites

- O conversor ajusta caminhos e remove wrappers conhecidos. Ele não reescreve a lógica de gameplay ou metadados desconhecidos.
- Scripts são copiados. O relatório avisa que código Lua/HScript não foi traduzido; extensões de runtime sem suporte reconhecido aparecem em `unsupported` e continuam preservadas para revisão manual.
- Arquivos fora da raiz detectada ficam em `_dbe_preserved/`, com um aviso no relatório.
- Metadados comuns de sistema operacional (`__MACOSX`, `.DS_Store`, `Thumbs.db` e `desktop.ini`) são listados em `ignored`.
- O leitor de ZIP recusa caminhos absolutos, `..`, links simbólicos, entradas criptografadas, colisões que diferem apenas por caixa, arquivos corrompidos e pacotes acima dos limites de tamanho.
- O relatório não certifica que o mod vai carregar ou que suas APIs são compatíveis. Faça smoke test na DBE e revise cada item em `unsupported` e cada aviso antes de distribuir a cópia.
