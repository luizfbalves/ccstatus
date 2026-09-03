# ccstatus

Status line customizada para o Claude Code — tema inspirado no "robbyrussell" do Oh My Zsh, com barras de progresso coloridas e informações de custo/uso.

## Preview

```
➜  orulpro │ git:(main) ✗3 ↑2 │ ◆ Opus 5 │ ctx ██████░░░░ 55% 110k/200k │ $3.47 +156-23 │ 5h ███░░░ 55% →12h33  7d ██░░░░ 33% →Sun
```

## O que mostra

- **Diretório** e **branch git** (com contador de arquivos sujos `✗N` / limpo `✔`, e `↑ahead ↓behind` do upstream)
- **Modelo** ativo na sessão (`◆ Opus 5`)
- **Contexto**: barra de progresso + tokens usados/limite
- **Custo da sessão** em USD + linhas adicionadas/removidas
- **Rate limits** de 5h e 7d, cada um com barra e horário de reset

Cada barra e percentual muda de cor conforme o uso avança: verde (<40%) → lima (<60%) → amarelo (<75%) → laranja (<90%) → vermelho (≥90%). O custo em dólar segue faixas próprias.

## Instalação

```bash
curl -o ~/.claude/ccstatus.sh https://raw.githubusercontent.com/luizfbalves/ccstatus/main/ccstatus.sh
chmod +x ~/.claude/ccstatus.sh
```

No `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"~/.claude/ccstatus.sh\""
  }
}
```

Requer `bash`, `jq` e `git` no PATH. Testado no Claude Code CLI.
