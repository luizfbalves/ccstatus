#!/usr/bin/env bash
# Claude Code statusLine: lê o payload JSON do stdin e imprime uma linha ANSI truecolor.

# ponto decimal e dia da semana em inglês, independente do locale do sistema
export LC_ALL=C

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
dir=$(basename "$cwd")

RESET='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'

rgb() { printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }

# tons médios/saturados (estilo tailwind-600) — contraste ok tanto em terminal
# claro quanto escuro; pastéis claros somem no claro, quase-pretos somem no escuro.
LIME=$(rgb 77 124 15)
CYAN=$(rgb 14 116 144)
PINK=$(rgb 190 24 93)
GREY=$(rgb 100 105 120)
DARK=$(rgb 128 128 128)
RED=$(rgb 185 28 28)
ORANGE=$(rgb 194 65 12)

fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n/1000000;
    else if (n >= 1000) printf "%.0fk", n/1000;
    else printf "%d", n;
  }'
}

# gradiente contínuo: 0% verde (21,128,61) → 50% âmbar (180,131,15) → 100% vermelho (185,28,28)
pct_rgb() {
  awk -v p="$1" 'BEGIN {
    if (p < 0) p = 0; if (p > 100) p = 100;
    if (p <= 50) {
      t = p / 50.0;
      r = 21  + t * (180 - 21);
      g = 128 + t * (131 - 128);
      b = 61  + t * (15  - 61);
    } else {
      t = (p - 50) / 50.0;
      r = 180 + t * (185 - 180);
      g = 131 + t * (28  - 131);
      b = 15  + t * (28  - 15);
    }
    printf "%d %d %d", r, g, b
  }'
}

pct_color() { rgb $(pct_rgb "$1"); }

# bar <pct> <largura>
bar() {
  local pct=$1 width=${2:-10}
  local filled
  filled=$(awk -v p="$pct" -v w="$width" 'BEGIN { f=int(p*w/100 + 0.5); if (f>w) f=w; if (f<0) f=0; print f }')
  local col; col=$(pct_color "$pct")
  printf '%b' "$col"
  for ((i=0; i<filled; i++)); do printf '▓'; done
  printf '%b' "$DARK"
  for ((i=filled; i<width; i++)); do printf '░'; done
  printf '%b' "$RESET"
}

dir_part="${BOLD}${CYAN}${dir}${RESET}"

model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // empty')
fast_mode=$(echo "$input" | jq -r '.fast_mode // empty')
effort=$(echo "$input" | jq -r '.effort | if type == "object" then .level else . end // empty')

effort_badge=""
if [ "$fast_mode" = "true" ]; then
  effort_badge=" ${DIM}${ORANGE}fast${RESET}"
elif [ -n "$effort" ]; then
  effort_badge=" ${DIM}${GREY}${effort}${RESET}"
fi

model_part=""
[ -n "$model_name" ] && model_part="${BOLD}${model_name}${RESET}${effort_badge}"

cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
lines_add=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_del=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')

cost_part=""
if [ -n "$cost_usd" ]; then
  # mesmo gradiente do contexto, com $30 como teto (100%)
  cost_col=$(pct_color "$(awk -v v="$cost_usd" 'BEGIN { print v * 100 / 30 }')")
  cost_fmt=$(awk -v v="$cost_usd" 'BEGIN { printf (v < 10 ? "$%.2f" : "$%.1f"), v }')
  cost_part="${BOLD}${cost_col}${cost_fmt}${RESET}"
  diff_part=""
  if [ -n "$lines_add" ] && [ -n "$lines_del" ] && [ $((lines_add + lines_del)) -gt 0 ] 2>/dev/null; then
    diff_part=" ${DIM}${LIME}+${lines_add}${RESET}${DIM}${RED}-${lines_del}${RESET}"
  fi
  cost_part="${cost_part}${diff_part}"
fi

git_part=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)

  status=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
  state=""
  [ -n "$status" ] && state=" ${BOLD}${RED}*$(printf '%s\n' "$status" | grep -c .)${RESET}"

  ahead_behind=$(git -C "$cwd" --no-optional-locks rev-list --left-right --count @{upstream}...HEAD 2>/dev/null)
  sync=""
  if [ -n "$ahead_behind" ]; then
    behind=$(echo "$ahead_behind" | awk '{print $1}')
    ahead=$(echo "$ahead_behind" | awk '{print $2}')
    [ "$ahead" -gt 0 ] 2>/dev/null && sync="${sync}${BOLD}${LIME}↑${RESET}${ahead}"
    [ "$behind" -gt 0 ] 2>/dev/null && sync="${sync}${BOLD}${ORANGE}↓${RESET}${behind}"
    [ -n "$sync" ] && sync=" $sync"
  fi

  git_part="${PINK}${branch}${RESET}${state}${sync}"
fi

used_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
limit_tokens=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

ctx_part=""
if [ -n "$used_tokens" ] && [ -n "$limit_tokens" ]; then
  [ -z "$used_pct" ] && used_pct=$(awk -v u="$used_tokens" -v l="$limit_tokens" 'BEGIN{ printf "%.1f", (l>0? u*100/l : 0) }')
  col=$(pct_color "$used_pct")
  ctx_part="${GREY}ctx ${RESET}$(bar "$used_pct" 10) ${col}$(printf '%.0f%%' "$used_pct")${RESET} ${DIM}${GREY}$(fmt_tokens "$used_tokens")/$(fmt_tokens "$limit_tokens")${RESET}"
fi

five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

five_reset_fmt=""
[ -n "$five_reset" ] && five_reset_fmt=$(date -r "$five_reset" "+%Hh%M" 2>/dev/null)
week_reset_fmt=""
[ -n "$week_reset" ] && week_reset_fmt=$(date -r "$week_reset" "+%a" 2>/dev/null)

rate_part=""
if [ -n "$five_pct" ]; then
  col=$(pct_color "$five_pct")
  suffix=""
  [ -n "$five_reset_fmt" ] && suffix=" ${DIM}${GREY}${five_reset_fmt}${RESET}"
  rate_part="${GREY}5h ${RESET}$(bar "$five_pct" 6) ${col}$(printf '%.0f%%' "$five_pct")${RESET}${suffix}"
fi
if [ -n "$week_pct" ]; then
  [ -n "$rate_part" ] && rate_part="${rate_part}  "
  col=$(pct_color "$week_pct")
  suffix=""
  [ -n "$week_reset_fmt" ] && suffix=" ${DIM}${GREY}${week_reset_fmt}${RESET}"
  rate_part="${rate_part}${GREY}7d ${RESET}$(bar "$week_pct" 6) ${col}$(printf '%.0f%%' "$week_pct")${RESET}${suffix}"
fi

SEP="${DARK} │ ${RESET}"

parts="$dir_part"
[ -n "$git_part" ]   && parts="${parts}${SEP}${git_part}"
[ -n "$model_part" ] && parts="${parts}${SEP}${model_part}"
[ -n "$ctx_part" ]   && parts="${parts}${SEP}${ctx_part}"
[ -n "$cost_part" ]  && parts="${parts}${SEP}${cost_part}"
[ -n "$rate_part" ]  && parts="${parts}${SEP}${rate_part}"

printf '%b' "$parts"
