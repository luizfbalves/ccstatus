# ccstatus

Status line para o Claude Code CLI. Um script bash que lê JSON do stdin (payload passado pelo Claude Code a cada render) e imprime uma linha ANSI colorida com diretório, git, modelo, uso de contexto, custo da sessão e rate limits.

Este README é escrito para um agente (Claude Code ou outro) instalar e configurar isso sozinho, sem intervenção humana além de aprovar os comandos.

## Instalação (para o agente executar)

```bash
curl -fsSL -o ~/.claude/ccstatus.sh https://raw.githubusercontent.com/luizfbalves/ccstatus/main/ccstatus.sh
chmod +x ~/.claude/ccstatus.sh
```

Depois, editar `~/.claude/settings.json` (criar se não existir) e garantir a chave `statusLine`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"~/.claude/ccstatus.sh\""
  }
}
```

Se o arquivo já tiver outras chaves, fazer merge — não sobrescrever o settings.json inteiro. Não é necessário reiniciar o Claude Code; a statusline é reavaliada a cada render.

### Dependências

`bash`, `jq`, `git`, `awk`, `date` — todas usualmente já presentes em macOS/Linux. Sem dependências de rede, sem pacotes npm/pip. O script não escreve em disco nem faz chamadas externas; é puramente stdin → stdout.

### Verificar que funcionou

```bash
echo '{"workspace":{"current_dir":"'"$HOME"'"},"model":{"display_name":"Test Model"},"context_window":{"total_input_tokens":50000,"context_window_size":200000,"used_percentage":25},"cost":{"total_cost_usd":1.23,"total_lines_added":10,"total_lines_removed":2}}' | bash ~/.claude/ccstatus.sh
```

Deve imprimir uma linha colorida sem erros no stderr.

## Contrato de entrada (o que o Claude Code envia)

O script lê um único JSON via stdin. Campos usados (todos opcionais — a seção correspondente da linha é omitida se ausente):

| Campo | Tipo | Uso |
|---|---|---|
| `workspace.current_dir` / `cwd` | string | diretório exibido (basename) |
| `model.display_name` / `model.id` | string | nome do modelo |
| `cost.total_cost_usd` | number | custo USD acumulado da sessão |
| `cost.total_lines_added` / `total_lines_removed` | number | diff de linhas na sessão |
| `context_window.total_input_tokens` | number | tokens usados |
| `context_window.context_window_size` | number | limite de tokens da janela |
| `context_window.used_percentage` | number | % pronto (senão é calculado) |
| `rate_limits.five_hour.used_percentage` / `.resets_at` | number / epoch | barra da janela de 5h |
| `rate_limits.seven_day.used_percentage` / `.resets_at` | number / epoch | barra da janela de 7d |

Git não vem no payload — o script roda `git -C "$cwd"` diretamente no diretório recebido.

## Estrutura interna (para quem for editar)

- `c()` — helper que gera escape ANSI 256-cor a partir de um código
- `pct_color <pct>` — mapeia percentual → código de cor (76 verde / 154 lima / 220 amarelo / 208 laranja / 203 vermelho), limiares em 40/60/75/90
- `bar <pct> <largura>` — desenha barra `█`/`░` de `largura` colunas (default 10), colorida via `pct_color`
- `fmt_tokens <n>` — formata `50000` → `50k`, `1500000` → `1.5M`
- Cada seção da linha (`git_part`, `model_part`, `cost_part`, `ctx_part`, `rate_part`) é montada isoladamente e só concatenada ao final se não-vazia, separada por `SEP` (` │ ` em cinza escuro)

Para mudar limiares de cor: editar os números em `pct_color`. Para mudar largura das barras: editar os literais `10`/`6` nas chamadas a `bar`. Para adicionar uma seção nova: seguir o padrão — montar `<nome>_part=""`, preencher condicionalmente, e adicionar `[ -n "$<nome>_part" ] && parts="${parts}${SEP}${<nome>_part}"` perto do final do arquivo, antes do `printf '%b' "$parts"`.

## Preview

```
➜  orulpro │ git:(main) ✗3 ↑2 │ ◆ Opus 5 │ ctx ██████░░░░ 55% 110k/200k │ $3.47 +156-23 │ 5h ███░░░ 55% →12h33  7d ██░░░░ 33% →Sun
```

## Atualizar depois de instalado

Re-executar o comando de instalação sobrescreve `~/.claude/ccstatus.sh` com a versão mais recente do `main`. Não há versionamento/pin — se for preciso reprodutibilidade, fixar um commit SHA na URL do `curl` em vez de `main`.
