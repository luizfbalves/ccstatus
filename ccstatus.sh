#!/usr/bin/env bash
# Claude Code statusLine — tema "robbyrussell" + truecolor + ícones Nerd Font.

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
dir=$(basename "$cwd")

RESET='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'

# truecolor 24-bit (fg)
rgb() { printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }

# tons médios/saturados (estilo tailwind-600) — contraste ok tanto em terminal
# claro quanto escuro; pastéis claros somem no claro, quase-pretos somem no escuro.
GREEN=$(rgb 21 128 61)
LIME=$(rgb 77 124 15)
CYAN=$(rgb 14 116 144)
BLUE=$(rgb 29 78 216)
PURPLE=$(rgb 124 58 237)
PINK=$(rgb 190 24 93)
GREY=$(rgb 100 105 120)
DARK=$(rgb 128 128 128)
RED=$(rgb 185 28 28)
ORANGE=$(rgb 194 65 12)

# ícones Nerd Font
ICON_ARROW="➜"
ICON_BRANCH="⎇"
ICON_DIRTY="✗"
ICON_CLEAN="✔"
ICON_AHEAD="↑"
ICON_BEHIND="↓"
ICON_MODEL="◆"
ICON_CTX="▤"
ICON_COST="$"
ICON_ADD="+"
ICON_DEL="-"
ICON_CLOCK="→"

fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n/1000000;
    else if (n >= 1000) printf "%.0fk", n/1000;
    else printf "%d", n;
  }'
}

# gradiente contínuo truecolor: 0%=verde, 50%=amarelo, 100%=vermelho
pct_rgb() {
  awk -v p="$1" 'BEGIN {
    if (p < 0) p = 0; if (p > 100) p = 100;
    # verde(21,128,61) -> amber(180,131,15) -> vermelho(185,28,28)
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

# barra de progresso truecolor: bar <pct> <largura>
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

arrow="${BOLD}${GREEN}${ICON_ARROW}${RESET}"
dir_part="${BOLD}${CYAN}${dir}${RESET}"

# ── modelo ────────────────────────────────────────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // empty')
model_part=""
[ -n "$model_name" ] && model_part="${PURPLE}${ICON_MODEL} ${BOLD}${model_name}${RESET}"

# ── custo da sessão ───────────────────────────────────────────────────────────
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
lines_add=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_del=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')

cost_part=""
if [ -n "$cost_usd" ]; then
  cost_col=$(rgb $(awk -v v="$cost_usd" 'BEGIN {
    p = (v/30.0)*100; if (p > 100) p = 100;
    if (p <= 50) { t=p/50.0; r=21+t*(180-21); g=128+t*(131-128); b=61+t*(15-61); }
    else { t=(p-50)/50.0; r=180+t*(185-180); g=131+t*(28-131); b=15+t*(28-15); }
    printf "%d %d %d", r, g, b
  }'))
  cost_fmt=$(awk -v v="$cost_usd" 'BEGIN { printf (v < 10 ? "$%.2f" : "$%.1f"), v }')
  cost_part="${cost_col}${ICON_COST} ${cost_fmt}${RESET}"
  diff_part=""
  if [ -n "$lines_add" ] && [ -n "$lines_del" ] && [ $((lines_add + lines_del)) -gt 0 ] 2>/dev/null; then
    diff_part=" ${DIM}${LIME}${ICON_ADD}${lines_add}${RESET}${DIM}${RED}${ICON_DEL}${lines_del}${RESET}"
  fi
  cost_part="${cost_part}${diff_part}"
fi

# ── git ───────────────────────────────────────────────────────────────────────
git_part=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)

  status=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
  if [ -n "$status" ]; then
    n=$(printf '%s\n' "$status" | grep -c .)
    state="${RED}${ICON_DIRTY} ${n}${RESET}"
  else
    state="${GREEN}${ICON_CLEAN}${RESET}"
  fi

  ahead_behind=$(git -C "$cwd" --no-optional-locks rev-list --left-right --count @{upstream}...HEAD 2>/dev/null)
  sync=""
  if [ -n "$ahead_behind" ]; then
    behind=$(echo "$ahead_behind" | awk '{print $1}')
    ahead=$(echo "$ahead_behind" | awk '{print $2}')
    [ "$ahead" -gt 0 ] 2>/dev/null && sync="${sync}${LIME}${ICON_AHEAD}${ahead}${RESET}"
    [ "$behind" -gt 0 ] 2>/dev/null && sync="${sync}${ORANGE}${ICON_BEHIND}${behind}${RESET}"
    [ -n "$sync" ] && sync=" $sync"
  fi

  git_part="${BLUE}${ICON_BRANCH} ${PINK}${branch}${RESET} ${state}${sync}"
fi

# ── contexto ──────────────────────────────────────────────────────────────────
used_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
limit_tokens=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

ctx_part=""
if [ -n "$used_tokens" ] && [ -n "$limit_tokens" ]; then
  [ -z "$used_pct" ] && used_pct=$(awk -v u="$used_tokens" -v l="$limit_tokens" 'BEGIN{ printf "%.1f", (l>0? u*100/l : 0) }')
  col=$(pct_color "$used_pct")
  ctx_part="${GREY}${ICON_CTX} ${RESET}$(bar "$used_pct" 10) ${col}$(printf '%.0f%%' "$used_pct")${RESET} ${DIM}${GREY}$(fmt_tokens "$used_tokens")/$(fmt_tokens "$limit_tokens")${RESET}"
fi

# ── rate limits ───────────────────────────────────────────────────────────────
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
  [ -n "$five_reset_fmt" ] && suffix=" ${DIM}${GREY}${ICON_CLOCK}${five_reset_fmt}${RESET}"
  rate_part="${GREY}5h ${RESET}$(bar "$five_pct" 6) ${col}$(printf '%.0f%%' "$five_pct")${RESET}${suffix}"
fi
if [ -n "$week_pct" ]; then
  [ -n "$rate_part" ] && rate_part="${rate_part}  "
  col=$(pct_color "$week_pct")
  suffix=""
  [ -n "$week_reset_fmt" ] && suffix=" ${DIM}${GREY}${ICON_CLOCK}${week_reset_fmt}${RESET}"
  rate_part="${rate_part}${GREY}7d ${RESET}$(bar "$week_pct" 6) ${col}$(printf '%.0f%%' "$week_pct")${RESET}${suffix}"
fi

SEP="${DARK} │ ${RESET}"

parts="$arrow  $dir_part"
[ -n "$git_part" ]   && parts="${parts}${SEP}${git_part}"
[ -n "$model_part" ] && parts="${parts}${SEP}${model_part}"
[ -n "$ctx_part" ]   && parts="${parts}${SEP}${ctx_part}"
[ -n "$cost_part" ]  && parts="${parts}${SEP}${cost_part}"
[ -n "$rate_part" ]  && parts="${parts}${SEP}${rate_part}"

printf '%b' "$parts"
