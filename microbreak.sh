#!/usr/bin/env zsh

# ==============================================================================
# MICROBREAK T2D - TERMINAL AUTOMATION (macOS + Zsh)
# Objetivo:
# - 60 min trabajo + 5 min pausa activa
# - Mejor alineado con salud metabólica, ergonomía y rotación inteligente
# - Totalmente usable desde Terminal
# ==============================================================================

emulate -L zsh

# ------------------------------------------------------------------------------
# 1) CONFIGURACIÓN DEL USUARIO
# ------------------------------------------------------------------------------
WORK_MINUTES=60
BREAK_MINUTES=5

USE_VOICE=1
USE_NOTIFICATIONS=1
VOICE_NAME="Mónica"          # Usa una voz real de macOS. Cambia si quieres.
SHOW_MISTAKES=1             # 1 = mostrar error común a evitar
ANNOUNCE_NEXT_WORK=1        # 1 = avisar al terminar la pausa
MODE="normal"               # normal | minimal | intense
TEST_MODE=0

# Si sueles almorzar o comer fuerte durante la jornada, puedes sesgar ciertos ciclos
# hacia bloques metabólicos/cardio. Esto ayuda a DT2.
POST_MEAL_BIAS_CYCLES=(2 4 6)

# ------------------------------------------------------------------------------
# 2) VARIABLES INTERNAS
# ------------------------------------------------------------------------------
WORK_SECONDS=$((WORK_MINUTES * 60))
BREAK_SECONDS=$((BREAK_MINUTES * 60))
CYCLES_COMPLETED=0
LAST_CATEGORY=""
LAST_ROUTINE_ID=""
INTERRUPTED=0

# Contadores por categoría para repartir carga
typeset -A CATEGORY_COUNTS
CATEGORY_COUNTS=(
  movilidad 0
  metabolico 0
  superior 0
  cardio 0
  core 0
  full_body 0
)

# Fases sugeridas para una jornada real:
# 1 = movilidad / arranque
# 2 = metabólico piernas
# 3 = tren superior o core
# 4 = cardio ligero / postprandial
# 5 = full body o metabólico
# luego se recicla
PHASE_SEQUENCE=(
  movilidad
  metabolico
  superior
  cardio
  core
  full_body
  metabolico
  movilidad
)

# Rutinas disponibles
ROUTINES=(
  movilidad_1
  metabolico_1
  metabolico_2
  superior_1
  cardio_1
  core_1
  full_body_1
  movilidad_2
  minimal_reset
  intense_1
)

# ------------------------------------------------------------------------------
# 3) UTILIDADES
# ------------------------------------------------------------------------------
color_reset=$'\033[0m'
color_blue=$'\033[1;34m'
color_green=$'\033[1;32m'
color_yellow=$'\033[1;33m'
color_red=$'\033[1;31m'
color_cyan=$'\033[1;36m'
color_magenta=$'\033[1;35m'
color_white=$'\033[1;37m'

hide_cursor() { tput civis 2>/dev/null; }
show_cursor() { tput cnorm 2>/dev/null; }

cleanup() {
  INTERRUPTED=1
  show_cursor
  printf "\n\n${color_yellow}[!] Sistema detenido por el usuario.${color_reset}\n"
  printf "${color_green}✓ Ciclos completados: %d${color_reset}\n" "$CYCLES_COMPLETED"
  printf "Tiempo total de pausas activas: %d min\n" "$((CYCLES_COMPLETED * BREAK_MINUTES))"
  printf "Distribución de estímulos:\n"
  printf "  - movilidad:  %d\n" "${CATEGORY_COUNTS[movilidad]}"
  printf "  - metabolico: %d\n" "${CATEGORY_COUNTS[metabolico]}"
  printf "  - superior:   %d\n" "${CATEGORY_COUNTS[superior]}"
  printf "  - cardio:     %d\n" "${CATEGORY_COUNTS[cardio]}"
  printf "  - core:       %d\n" "${CATEGORY_COUNTS[core]}"
  printf "  - full_body:  %d\n" "${CATEGORY_COUNTS[full_body]}"
  printf "\nBuen trabajo. Esto sí suma para glucosa, postura y energía.\n\n"
  exit 0
}
trap cleanup SIGINT TERM

send_alert() {
  local title="$1"
  local message="$2"
  local voice_text="$3"

  if [[ "$USE_NOTIFICATIONS" -eq 1 ]]; then
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null
  fi

  if [[ "$USE_VOICE" -eq 1 ]]; then
    say -v "$VOICE_NAME" "$voice_text" >/dev/null 2>&1 &
  fi
}

run_timer() {
  local seconds=$1
  local label="$2"
  local color="$3"

  hide_cursor
  while (( seconds > 0 )); do
    local m=$((seconds / 60))
    local s=$((seconds % 60))
    printf "\r\033[K${color}[%s]${color_reset} Tiempo restante: ${color_white}%02d:%02d${color_reset}" "$label" "$m" "$s"
    sleep 1
    ((seconds--))
  done
  printf "\r\033[K"
  show_cursor
}

run_short_beep() {
  printf "\a"
}

contains_cycle_bias() {
  local cycle_num=$1
  local c
  for c in "${POST_MEAL_BIAS_CYCLES[@]}"; do
    [[ "$c" -eq "$cycle_num" ]] && return 0
  done
  return 1
}

# ------------------------------------------------------------------------------
# 4) BASE DE DATOS DE RUTINAS
#    Cada rutina carga:
#    - ROUTINE_CATEGORY
#    - ROUTINE_NAME
#    - ROUTINE_OBJECTIVE
#    - ROUTINE_INTENSITY
#    - ROUTINE_BEST_FOR
#    - EX_NAMES[]
#    - EX_DURS[]
#    - EX_CUES[]
#    - EX_MISTAKES[]
# ------------------------------------------------------------------------------
load_routine() {
  local id="$1"

  ROUTINE_CATEGORY=""
  ROUTINE_NAME=""
  ROUTINE_OBJECTIVE=""
  ROUTINE_INTENSITY=""
  ROUTINE_BEST_FOR=""
  EX_NAMES=()
  EX_DURS=()
  EX_CUES=()
  EX_MISTAKES=()

  case "$id" in
    movilidad_1)
      ROUTINE_CATEGORY="movilidad"
      ROUTINE_NAME="Reset Postural de Escritorio"
      ROUTINE_OBJECTIVE="Descomprimir columna, hombros y cadera tras sedestación prolongada."
      ROUTINE_INTENSITY="baja"
      ROUTINE_BEST_FOR="ideal al inicio del día o cuando estás rígido mental/físicamente"
      EX_NAMES=(
        "Rotación torácica de pie"
        "Gato-vaca de pie con manos en muslos"
        "Estiramiento flexor de cadera"
        "Deslizamiento de pared / apertura de pecho"
      )
      EX_DURS=(60 60 90 90)
      EX_CUES=(
        "Gira desde el torso, pelvis estable, respiración lenta."
        "Redondea y luego extiende la espalda sin dolor, movimiento fluido."
        "Da un paso atrás, mete pelvis suave, siente el frente de la cadera."
        "Pega antebrazos o manos a pared si puedes, abre pecho sin elevar hombros."
      )
      EX_MISTAKES=(
        "No fuerces cuello ni gires desde rodillas."
        "No colapses zona lumbar."
        "No arquees demasiado la espalda baja."
        "No encogerte de hombros."
      )
      ;;
    movilidad_2)
      ROUTINE_CATEGORY="movilidad"
      ROUTINE_NAME="Movilidad de Recuperación Neural"
      ROUTINE_OBJECTIVE="Bajar rigidez, recuperar rango de movimiento y reducir fatiga mental."
      ROUTINE_INTENSITY="baja"
      ROUTINE_BEST_FOR="ideal al final del día o después de mucho foco sentado"
      EX_NAMES=(
        "Marcha suave con brazos amplios"
        "Círculos lentos de hombros"
        "Bisagra de cadera sin peso"
        "Inclinación lateral de pie"
      )
      EX_DURS=(60 60 90 90)
      EX_CUES=(
        "Camina sin prisa, mueve brazos amplio y respira nasal si puedes."
        "Haz círculos grandes pero controlados, adelante y atrás."
        "Empuja cadera atrás con espalda neutra, vuelve a subir."
        "Alarga costado sin colapsar el otro lado."
      )
      EX_MISTAKES=(
        "No trotar ni tensarte."
        "No mover hombros con tirones."
        "No redondear espalda."
        "No girar el tronco en exceso."
      )
      ;;
    metabolico_1)
      ROUTINE_CATEGORY="metabolico"
      ROUTINE_NAME="Reset Metabólico de Piernas"
      ROUTINE_OBJECTIVE="Aumentar captación de glucosa usando grandes grupos musculares del tren inferior."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="excelente después de comer o cuando llevas mucho rato sentado"
      EX_NAMES=(
        "Sentadillas controladas a silla"
        "Elevación de talones"
        "Soleus push-ups sentado"
        "Marcha vigorosa en el lugar"
      )
      EX_DURS=(60 60 90 90)
      EX_CUES=(
        "Baja con control, toca silla si hace falta, sube empujando el suelo."
        "Súbete a puntas con pausa arriba, baja lento."
        "Sentado, pies al suelo, eleva talones rápido y repetido."
        "Rodillas activas, braceo natural, ritmo sostenido."
      )
      EX_MISTAKES=(
        "No dejar que rodillas colapsen hacia adentro."
        "No rebotar abajo."
        "No levantar puntas; solo talones."
        "No inclinarte demasiado hacia atrás."
      )
      ;;
    metabolico_2)
      ROUTINE_CATEGORY="metabolico"
      ROUTINE_NAME="Glúteo-Femoral Anti-Sedestación"
      ROUTINE_OBJECTIVE="Activar glúteos, femorales y sóleo para combatir el impacto metabólico de estar sentado."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="muy útil en jornadas largas y como bloque postprandial"
      EX_NAMES=(
        "Bisagra de cadera"
        "Sentadilla isométrica parcial"
        "Soleus push-ups"
        "Caminata rápida por la habitación"
      )
      EX_DURS=(60 60 120 60)
      EX_CUES=(
        "Lleva cadera atrás, tronco firme, peso repartido."
        "Sostén media sentadilla con abdomen firme."
        "Repite elevación de talones sentado sin parar."
        "Camina rápido, hombros sueltos, respiración rítmica."
      )
      EX_MISTAKES=(
        "No redondear espalda."
        "No bajar tanto que pierdas técnica."
        "No despegar puntas."
        "No convertirlo en paseo lento."
      )
      ;;
    superior_1)
      ROUTINE_CATEGORY="superior"
      ROUTINE_NAME="Activación de Tren Superior"
      ROUTINE_OBJECTIVE="Estimular empuje, estabilidad escapular y circulación en torso superior."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="útil cuando sientes hombros caídos y torso apagado"
      EX_NAMES=(
        "Flexiones en escritorio"
        "Retracción escapular de pie"
        "Fondos en silla estable"
        "Brazos en cruz con círculos"
      )
      EX_DURS=(60 60 60 120)
      EX_CUES=(
        "Cuerpo en bloque, manos firmes, pecho hacia el escritorio."
        "Aprieta omóplatos atrás y abajo durante 2 segundos."
        "Usa silla sin ruedas, rango corto si es necesario."
        "Brazos extendidos, círculos pequeños y constantes."
      )
      EX_MISTAKES=(
        "No hundir la zona lumbar."
        "No subir hombros hacia orejas."
        "No usar silla inestable."
        "No balancear el cuerpo."
      )
      ;;
    cardio_1)
      ROUTINE_CATEGORY="cardio"
      ROUTINE_NAME="Ignición Cardio Ligera"
      ROUTINE_OBJECTIVE="Elevar pulso de forma corta para mejorar flujo sanguíneo, energía y control glucémico."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="especialmente útil después de comer o al sentir sueño mental"
      EX_NAMES=(
        "Jumping jacks sin salto"
        "Rodillas altas suaves"
        "Shadowboxing"
        "Caminata de descarga"
      )
      EX_DURS=(90 60 90 60)
      EX_CUES=(
        "Paso lateral rápido, brazos arriba y abajo con ritmo."
        "Sube rodillas cómodo, sin impacto brusco."
        "Golpes al aire rápidos con abdomen activo."
        "Reduce pulsaciones caminando y respirando profundo."
      )
      EX_MISTAKES=(
        "No convertirlo en impacto agresivo."
        "No encoger hombros."
        "No bloquear codos al golpear."
        "No quedarte quieto de golpe."
      )
      ;;
    core_1)
      ROUTINE_CATEGORY="core"
      ROUTINE_NAME="Resiliencia Lumbo-Pélvica"
      ROUTINE_OBJECTIVE="Mejorar estabilidad central y aliviar tensión de la zona baja tras estar sentado."
      ROUTINE_INTENSITY="baja-moderada"
      ROUTINE_BEST_FOR="cuando sientes zona lumbar cargada o postura colapsada"
      EX_NAMES=(
        "Plancha inclinada en escritorio"
        "Elevación alterna de rodillas sentado"
        "Contracción isométrica de glúteos"
        "Alcance lateral de pie"
      )
      EX_DURS=(60 60 90 90)
      EX_CUES=(
        "Cuerpo recto, abdomen activo, cuello neutro."
        "Sube una rodilla a la vez sin inclinarte mucho."
        "Aprieta glúteos 5 segundos y suelta."
        "Alarga costado y controla el retorno."
      )
      EX_MISTAKES=(
        "No colgarte de hombros."
        "No encorvarte al subir rodillas."
        "No aguantar el aire."
        "No girar el torso."
      )
      ;;
    full_body_1)
      ROUTINE_CATEGORY="full_body"
      ROUTINE_NAME="Activación Total de 5 Minutos"
      ROUTINE_OBJECTIVE="Mover todo el cuerpo con carga baja-moderada sin romper demasiado el flujo cognitivo."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="cuando quieres un bloque completo y eficiente"
      EX_NAMES=(
        "Sentadilla + alcance al frente"
        "Flexión en escritorio"
        "Marcha rápida con braceo"
        "Bisagra de cadera"
      )
      EX_DURS=(75 60 90 75)
      EX_CUES=(
        "Baja y al subir alcanza al frente, ritmo continuo."
        "Mantén cuerpo alineado."
        "Marcha viva pero sostenible."
        "Cadera atrás, abdomen firme."
      )
      EX_MISTAKES=(
        "No perder alineación de rodillas."
        "No arquear espalda."
        "No hacerlo tan intenso que te ahogue."
        "No redondear lumbar."
      )
      ;;
    minimal_reset)
      ROUTINE_CATEGORY="movilidad"
      ROUTINE_NAME="Versión Mínima de Día Malo"
      ROUTINE_OBJECTIVE="Romper sedentarismo con fricción casi cero cuando no quieres hacer nada."
      ROUTINE_INTENSITY="baja"
      ROUTINE_BEST_FOR="días malos, fatiga mental alta o trabajo muy exigente"
      EX_NAMES=(
        "Marcha suave"
        "Elevación de talones"
        "Apertura de pecho"
      )
      EX_DURS=(60 60 60)
      EX_CUES=(
        "Solo muévete sin pensarlo demasiado."
        "Sube y baja controlado."
        "Abre pecho y respira profundo."
      )
      EX_MISTAKES=(
        "No quedarte inmóvil."
        "No rebotar."
        "No tensar cuello."
      )
      ;;
    intense_1)
      ROUTINE_CATEGORY="full_body"
      ROUTINE_NAME="Versión Intensa de Día Bueno"
      ROUTINE_OBJECTIVE="Aumentar demanda cardiovascular y muscular sin pasar de 5 minutos."
      ROUTINE_INTENSITY="alta"
      ROUTINE_BEST_FOR="días buenos, energía alta y sin dolor"
      EX_NAMES=(
        "Sentadilla rápida controlada"
        "Flexiones en escritorio rápidas"
        "Rodillas altas"
        "Shadowboxing rápido"
      )
      EX_DURS=(75 60 75 90)
      EX_CUES=(
        "Ritmo vivo, técnica limpia."
        "Rango cómodo pero dinámico."
        "Braceo fuerte, tronco estable."
        "Golpes rápidos sin perder postura."
      )
      EX_MISTAKES=(
        "No sacrificar técnica por velocidad."
        "No colapsar cintura."
        "No exagerar impacto."
        "No contener respiración."
      )
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

# ------------------------------------------------------------------------------
# 5) IMPRESIÓN DE RUTINA
# ------------------------------------------------------------------------------
print_routine_ui() {
  local id="$1"
  load_routine "$id" || return 1

  printf "\n${color_cyan}============================================================${color_reset}\n"
  printf "${color_white}⚡ MICRO-RUTINA:${color_reset} ${color_yellow}%s${color_reset}\n" "$ROUTINE_NAME"
  printf "${color_cyan}============================================================${color_reset}\n"
  printf "${color_magenta}Categoría:${color_reset} %s\n" "$ROUTINE_CATEGORY"
  printf "${color_blue}Objetivo:${color_reset}  %s\n" "$ROUTINE_OBJECTIVE"
  printf "${color_green}Intensidad:${color_reset} %s\n" "$ROUTINE_INTENSITY"
  printf "${color_green}Mejor momento:${color_reset} %s\n" "$ROUTINE_BEST_FOR"
  printf "${color_cyan}Total:${color_reset} %d min\n\n" "$BREAK_MINUTES"

  local i
  for (( i=1; i<=${#EX_NAMES[@]}; i++ )); do
    printf "${color_white}%d.${color_reset} %s ${color_yellow}(%ss)${color_reset}\n" "$i" "${EX_NAMES[$i]}" "${EX_DURS[$i]}"
    printf "   Cómo: %s\n" "${EX_CUES[$i]}"
    if [[ "$SHOW_MISTAKES" -eq 1 ]]; then
      printf "   Evita: %s\n" "${EX_MISTAKES[$i]}"
    fi
    printf "\n"
  done
}

# ------------------------------------------------------------------------------
# 6) EJECUCIÓN GUIADA DE LA RUTINA
# ------------------------------------------------------------------------------
run_guided_routine() {
  local id="$1"
  load_routine "$id" || return 1

  local total=0
  local i
  for (( i=1; i<=${#EX_DURS[@]}; i++ )); do
    (( total += EX_DURS[$i] ))
  done

  printf "${color_green}Iniciando rutina guiada (%ds total).${color_reset}\n\n" "$total"
  sleep 1

  for (( i=1; i<=${#EX_NAMES[@]}; i++ )); do
    run_short_beep
    printf "${color_cyan}→ Ahora:${color_reset} %s ${color_yellow}(%ss)${color_reset}\n" "${EX_NAMES[$i]}" "${EX_DURS[$i]}"
    printf "  Cómo: %s\n" "${EX_CUES[$i]}"
    if [[ "$SHOW_MISTAKES" -eq 1 ]]; then
      printf "  Evita: %s\n" "${EX_MISTAKES[$i]}"
    fi
    run_timer "${EX_DURS[$i]}" "${EX_NAMES[$i]}" "${color_green}"
    printf "\n"
  done
}

# ------------------------------------------------------------------------------
# 7) LÓGICA DE SELECCIÓN
# ------------------------------------------------------------------------------
desired_phase_category() {
  local cycle_number="$1"
  local phase_index=$(( ((cycle_number - 1) % ${#PHASE_SEQUENCE[@]}) + 1 ))
  echo "${PHASE_SEQUENCE[$phase_index]}"
}

mode_allowed_routines() {
  case "$MODE" in
    minimal)
      echo "minimal_reset movilidad_1 movilidad_2"
      ;;
    intense)
      echo "intense_1 full_body_1 metabolico_1 cardio_1 superior_1"
      ;;
    *)
      echo "${ROUTINES[*]}"
      ;;
  esac
}

routine_matches_mode() {
  local id="$1"
  local allowed=( ${(z)$(mode_allowed_routines)} )
  local item
  for item in "${allowed[@]}"; do
    [[ "$item" == "$id" ]] && return 0
  done
  return 1
}

pick_routine() {
  local next_cycle="$1"
  local preferred_category
  preferred_category="$(desired_phase_category "$next_cycle")"

  local candidate_ids=()
  local id

  # Si el ciclo coincide con sesgo postprandial, preferimos metabolico/cardio
  if contains_cycle_bias "$next_cycle"; then
    preferred_category="metabolico"
  fi

  # 1) Intentar categoría preferida sin repetir categoría previa
  for id in "${ROUTINES[@]}"; do
    routine_matches_mode "$id" || continue
    load_routine "$id" || continue

    if [[ "$ROUTINE_CATEGORY" == "$preferred_category" && "$ROUTINE_CATEGORY" != "$LAST_CATEGORY" ]]; then
      candidate_ids+=("$id")
    fi
  done

  # 2) Si no hay, aceptar cualquier categoría distinta a la anterior
  if (( ${#candidate_ids[@]} == 0 )); then
    for id in "${ROUTINES[@]}"; do
      routine_matches_mode "$id" || continue
      load_routine "$id" || continue

      if [[ "$ROUTINE_CATEGORY" != "$LAST_CATEGORY" ]]; then
        candidate_ids+=("$id")
      fi
    done
  fi

  # 3) Último recurso: cualquiera válida por modo
  if (( ${#candidate_ids[@]} == 0 )); then
    for id in "${ROUTINES[@]}"; do
      routine_matches_mode "$id" || continue
      candidate_ids+=("$id")
    done
  fi

  local chosen_index=$((RANDOM % ${#candidate_ids[@]} + 1))
  local chosen_id="${candidate_ids[$chosen_index]}"
  load_routine "$chosen_id" || return 1

  LAST_CATEGORY="$ROUTINE_CATEGORY"
  LAST_ROUTINE_ID="$chosen_id"
  echo "$chosen_id"
}

# ------------------------------------------------------------------------------
# 8) ARGUMENTOS
# ------------------------------------------------------------------------------
parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      -t|--test)
        TEST_MODE=1
        WORK_SECONDS=10
        BREAK_SECONDS=10
        ;;
      --minimal)
        MODE="minimal"
        ;;
      --intense)
        MODE="intense"
        ;;
      --silent)
        USE_VOICE=0
        ;;
      --no-notify)
        USE_NOTIFICATIONS=0
        ;;
      --voice)
        shift
        [[ -n "$1" ]] && VOICE_NAME="$1"
        ;;
      *)
        ;;
    esac
    shift
  done
}

# ------------------------------------------------------------------------------
# 9) PANTALLA INICIAL
# ------------------------------------------------------------------------------
show_banner() {
  clear
  printf "${color_green}"
  echo " __  __ _                 _                    _    "
  echo "|  \/  (_) ___ _ __ ___  | |__  _ __ ___  __ _| | __"
  echo "| |\/| | |/ __| '__/ _ \ | '_ \| '__/ _ \/ _\` | |/ /"
  echo "| |  | | | (__| | | (_) || |_) | | |  __/ (_| |   < "
  echo "|_|  |_|_|\___|_|  \___/ |_.__/|_|  \___|\__,_|_|\_\\"
  printf "${color_reset}\n"

  printf "Sistema iniciado en modo: ${color_yellow}%s${color_reset}\n" "$MODE"
  printf "Trabajo: ${color_white}%d min${color_reset} | Pausa: ${color_white}%d min${color_reset}\n" "$WORK_MINUTES" "$BREAK_MINUTES"
  if [[ "$TEST_MODE" -eq 1 ]]; then
    printf "${color_yellow}[MODO TEST]${color_reset} tiempos reducidos para probar\n"
  fi
  printf "Voz: %s | Notificaciones: %s\n" "$USE_VOICE" "$USE_NOTIFICATIONS"
  printf "Presiona ${color_red}Ctrl+C${color_reset} para salir.\n\n"
  printf "Sugerencia T2D: si acabas de comer, no saltes la pausa. Prioriza bloques metabólicos/cardio.\n\n"
}

# ------------------------------------------------------------------------------
# 10) MAIN LOOP
# ------------------------------------------------------------------------------
main() {
  parse_args "$@"
  show_banner

  while true; do
    local next_cycle=$((CYCLES_COMPLETED + 1))

    printf "${color_blue}▶ Iniciando bloque de trabajo profundo #%d...${color_reset}\n" "$next_cycle"
    run_timer "$WORK_SECONDS" "TRABAJO" "$color_blue"

    local routine_id
    routine_id="$(pick_routine "$next_cycle")" || {
      printf "${color_red}Error seleccionando rutina.${color_reset}\n"
      exit 1
    }

    load_routine "$routine_id" || exit 1

    send_alert \
      "¡Pausa activa!" \
      "Toca: $ROUTINE_NAME. Revisa la terminal." \
      "Hora de moverse. Toca $ROUTINE_NAME"

    clear
    print_routine_ui "$routine_id"
    run_guided_routine "$routine_id"

    (( CYCLES_COMPLETED++ ))
    (( CATEGORY_COUNTS[$ROUTINE_CATEGORY]++ ))

    if [[ "$ANNOUNCE_NEXT_WORK" -eq 1 ]]; then
      send_alert \
        "Fin de la pausa" \
        "Ciclo $CYCLES_COMPLETED completado. Vuelve al trabajo." \
        "Buen trabajo. Volvemos a concentrarnos."
    fi

    clear
    printf "${color_green}✓ Ciclo %d completado.${color_reset}\n" "$CYCLES_COMPLETED"
    printf "Último bloque: %s [%s]\n\n" "$ROUTINE_NAME" "$ROUTINE_CATEGORY"
  done
}

main "$@"

