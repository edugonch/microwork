#!/usr/bin/env zsh

# ==============================================================================
# MICROBREAK T2D PRO - TERMINAL AUTOMATION (macOS + Zsh)
# 60 min trabajo + 5 min pausa activa
# Con soporte opcional para push-up board y ab wheel
# ==============================================================================

emulate -L zsh

# ------------------------------------------------------------------------------
# 1) CONFIGURACIÓN DEL USUARIO
# ------------------------------------------------------------------------------
WORK_MINUTES=60
BREAK_MINUTES=5

USE_VOICE=1
USE_NOTIFICATIONS=1
VOICE_NAME="Mónica"
SHOW_MISTAKES=1
ANNOUNCE_NEXT_WORK=1

# Modos:
# normal | minimal | intense
MODE="normal"

# Equipo:
# 1 = incluir push-up board / ab wheel
# 0 = solo ejercicios sin equipo
USE_EQUIPMENT=1

TEST_MODE=0

# Sesgo metabólico post-comida
POST_MEAL_BIAS_CYCLES=(2 4 6)

# Límites diarios recomendados para no fatigar demasiado
MAX_EQUIPMENT_UPPER_PER_DAY=2
MAX_EQUIPMENT_CORE_PER_DAY=1

# ------------------------------------------------------------------------------
# 2) VARIABLES INTERNAS
# ------------------------------------------------------------------------------
WORK_SECONDS=$((WORK_MINUTES * 60))
BREAK_SECONDS=$((BREAK_MINUTES * 60))
CYCLES_COMPLETED=0
LAST_CATEGORY=""
LAST_ROUTINE_ID=""

typeset -A CATEGORY_COUNTS
CATEGORY_COUNTS=(
  movilidad 0
  metabolico 0
  superior 0
  cardio 0
  core 0
  full_body 0
  equipment_upper 0
  equipment_core 0
)

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
  push_board_1
  ab_wheel_1
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
  show_cursor
  printf "\n\n${color_yellow}[!] Sistema detenido por el usuario.${color_reset}\n"
  printf "${color_green}✓ Ciclos completados: %d${color_reset}\n" "$CYCLES_COMPLETED"
  printf "Tiempo total de pausas activas: %d min\n" "$((CYCLES_COMPLETED * BREAK_MINUTES))"
  printf "\nDistribución de estímulos:\n"
  printf "  - movilidad:        %d\n" "${CATEGORY_COUNTS[movilidad]}"
  printf "  - metabolico:       %d\n" "${CATEGORY_COUNTS[metabolico]}"
  printf "  - superior:         %d\n" "${CATEGORY_COUNTS[superior]}"
  printf "  - cardio:           %d\n" "${CATEGORY_COUNTS[cardio]}"
  printf "  - core:             %d\n" "${CATEGORY_COUNTS[core]}"
  printf "  - full_body:        %d\n" "${CATEGORY_COUNTS[full_body]}"
  printf "  - equipo superior:  %d\n" "${CATEGORY_COUNTS[equipment_upper]}"
  printf "  - ab wheel/core:    %d\n" "${CATEGORY_COUNTS[equipment_core]}"
  printf "\nBuen trabajo. Esto sí suma para glucosa, postura, fuerza y energía.\n\n"
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
  local countdown_words=(cinco cuatro tres dos uno)

  hide_cursor
  while (( seconds > 0 )); do
    local m=$((seconds / 60))
    local s=$((seconds % 60))
    printf "\r\033[K${color}[%s]${color_reset} Tiempo restante: ${color_white}%02d:%02d${color_reset}" "$label" "$m" "$s"

    if [[ "$USE_VOICE" -eq 1 ]] && (( seconds <= 5 && seconds >= 1 )); then
      say -v "$VOICE_NAME" "${countdown_words[$((6 - seconds))]}" >/dev/null 2>&1 &
    fi

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
      ROUTINE_BEST_FOR="inicio del día o rigidez física/mental"
      EX_NAMES=("Rotación torácica de pie" "Gato-vaca de pie" "Estiramiento flexor de cadera" "Apertura de pecho en pared")
      EX_DURS=(60 60 90 90)
      EX_CUES=("Gira desde el torso, pelvis estable." "Redondea y extiende espalda sin dolor." "Paso atrás, pelvis suave hacia adentro." "Abre pecho sin subir hombros.")
      EX_MISTAKES=("No fuerces cuello." "No colapses lumbar." "No arquees de más." "No encogerte.")
      ;;

    movilidad_2)
      ROUTINE_CATEGORY="movilidad"
      ROUTINE_NAME="Movilidad de Recuperación Neural"
      ROUTINE_OBJECTIVE="Bajar rigidez y reducir fatiga mental."
      ROUTINE_INTENSITY="baja"
      ROUTINE_BEST_FOR="final del día o después de mucho foco"
      EX_NAMES=("Marcha suave" "Círculos lentos de hombros" "Bisagra de cadera sin peso" "Inclinación lateral")
      EX_DURS=(60 60 90 90)
      EX_CUES=("Camina suave y respira." "Círculos grandes controlados." "Cadera atrás, espalda neutra." "Alarga costado.")
      EX_MISTAKES=("No trotar." "No dar tirones." "No redondear espalda." "No girar el torso.")
      ;;

    metabolico_1)
      ROUTINE_CATEGORY="metabolico"
      ROUTINE_NAME="Reset Metabólico de Piernas"
      ROUTINE_OBJECTIVE="Aumentar captación de glucosa usando tren inferior."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="después de comer o tras mucho rato sentado"
      EX_NAMES=("Sentadillas controladas a silla" "Elevación de talones" "Soleus push-ups sentado" "Marcha vigorosa")
      EX_DURS=(60 60 90 90)
      EX_CUES=("Baja controlado, toca silla si hace falta." "Pausa arriba, baja lento." "Eleva talones sentado sin parar." "Braceo activo.")
      EX_MISTAKES=("Rodillas no colapsan." "No rebotes." "No levantes puntas." "No te inclines atrás.")
      ;;

    metabolico_2)
      ROUTINE_CATEGORY="metabolico"
      ROUTINE_NAME="Glúteo-Femoral Anti-Sedestación"
      ROUTINE_OBJECTIVE="Activar glúteos, femorales y sóleo."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="jornadas largas o bloque postprandial"
      EX_NAMES=("Bisagra de cadera" "Sentadilla isométrica parcial" "Soleus push-ups" "Caminata rápida")
      EX_DURS=(60 60 120 60)
      EX_CUES=("Cadera atrás, tronco firme." "Media sentadilla con abdomen activo." "Talones suben y bajan sentado." "Camina con intención.")
      EX_MISTAKES=("No redondear espalda." "No bajes demasiado." "No despegar puntas." "No pasear lento.")
      ;;

    superior_1)
      ROUTINE_CATEGORY="superior"
      ROUTINE_NAME="Activación de Tren Superior"
      ROUTINE_OBJECTIVE="Estimular empuje, escápulas y circulación superior."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="hombros caídos o torso apagado"
      EX_NAMES=("Flexiones en escritorio" "Retracción escapular" "Fondos en silla estable" "Brazos en cruz con círculos")
      EX_DURS=(60 60 60 120)
      EX_CUES=("Cuerpo en bloque." "Omóplatos atrás y abajo." "Silla sin ruedas." "Círculos pequeños constantes.")
      EX_MISTAKES=("No hundir lumbar." "No subir hombros." "No silla inestable." "No balancearte.")
      ;;

    cardio_1)
      ROUTINE_CATEGORY="cardio"
      ROUTINE_NAME="Ignición Cardio Ligera"
      ROUTINE_OBJECTIVE="Elevar pulso sin impacto fuerte."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="después de comer o sueño mental"
      EX_NAMES=("Jumping jacks sin salto" "Rodillas altas suaves" "Shadowboxing" "Caminata de descarga")
      EX_DURS=(90 60 90 60)
      EX_CUES=("Paso lateral rápido." "Rodillas cómodas." "Golpes al aire con abdomen activo." "Baja pulsaciones.")
      EX_MISTAKES=("No impacto agresivo." "No encoger hombros." "No bloquear codos." "No detenerte de golpe.")
      ;;

    core_1)
      ROUTINE_CATEGORY="core"
      ROUTINE_NAME="Resiliencia Lumbo-Pélvica"
      ROUTINE_OBJECTIVE="Estabilidad central y alivio lumbar."
      ROUTINE_INTENSITY="baja-moderada"
      ROUTINE_BEST_FOR="zona lumbar cargada"
      EX_NAMES=("Plancha inclinada en escritorio" "Elevación alterna de rodillas sentado" "Contracción isométrica de glúteos" "Alcance lateral")
      EX_DURS=(60 60 90 90)
      EX_CUES=("Cuerpo recto." "Sube una rodilla a la vez." "Aprieta 5s y suelta." "Alarga costado.")
      EX_MISTAKES=("No colgarte." "No encorvarte." "No aguantar aire." "No girar torso.")
      ;;

    full_body_1)
      ROUTINE_CATEGORY="full_body"
      ROUTINE_NAME="Activación Total de 5 Minutos"
      ROUTINE_OBJECTIVE="Mover todo el cuerpo sin romper el flujo cognitivo."
      ROUTINE_INTENSITY="moderada"
      ROUTINE_BEST_FOR="bloque completo y eficiente"
      EX_NAMES=("Sentadilla + alcance" "Flexión en escritorio" "Marcha rápida" "Bisagra de cadera")
      EX_DURS=(75 60 90 75)
      EX_CUES=("Baja y alcanza al subir." "Cuerpo alineado." "Ritmo vivo." "Cadera atrás.")
      EX_MISTAKES=("No colapsar rodillas." "No arquear espalda." "No ahogarte." "No redondear lumbar.")
      ;;

    push_board_1)
      ROUTINE_CATEGORY="equipment_upper"
      ROUTINE_NAME="Push Board - Fuerza de Torso"
      ROUTINE_OBJECTIVE="Aumentar tensión mecánica en pecho, tríceps, hombros y estabilidad escapular usando barras/push-up board."
      ROUTINE_INTENSITY="moderada-alta"
      ROUTINE_BEST_FOR="días con buena energía; máximo 2 veces al día"
      EX_NAMES=(
        "Push-ups con barras, agarre cómodo"
        "Descanso activo de hombros"
        "Push-ups lentas con pausa abajo"
        "Plancha alta en barras"
        "Marcha suave de recuperación"
      )
      EX_DURS=(60 30 60 90 60)
      EX_CUES=(
        "Manos firmes, cuerpo en línea, baja hasta rango cómodo."
        "Sacude brazos, respira y relaja cuello."
        "Baja en 3 segundos, pausa 1 segundo, sube controlado."
        "Codos extendidos sin bloquear, abdomen firme, cuello neutro."
        "Camina suave para bajar tensión y volver al trabajo."
      )
      EX_MISTAKES=(
        "No hundir cintura ni sacar cuello hacia adelante."
        "No quedarte tenso."
        "No colapsar hombros."
        "No dejar caer la pelvis."
        "No volver sentado de golpe."
      )
      ;;

    ab_wheel_1)
      ROUTINE_CATEGORY="equipment_core"
      ROUTINE_NAME="Ab Wheel - Core Seguro"
      ROUTINE_OBJECTIVE="Fortalecer core anterior, anti-extensión y control lumbo-pélvico sin exceder volumen."
      ROUTINE_INTENSITY="alta técnica"
      ROUTINE_BEST_FOR="solo si no hay dolor lumbar; máximo 1 vez al día"
      EX_NAMES=(
        "Ab wheel parcial desde rodillas"
        "Descanso / respiración"
        "Ab wheel parcial controlado"
        "Plancha inclinada o en suelo"
        "Child pose o descarga lumbar suave"
      )
      EX_DURS=(45 30 45 90 90)
      EX_CUES=(
        "Desde rodillas, rueda solo hasta donde mantengas abdomen firme."
        "Respira, relaja hombros, prepara el segundo set."
        "Costillas abajo, glúteos activos, regreso controlado."
        "Mantén línea recta, abdomen firme, respiración constante."
        "Siéntate hacia talones y respira lento."
      )
      EX_MISTAKES=(
        "No dejar que la espalda baja se arquee."
        "No apurarte."
        "No ir más lejos de tu control."
        "No aguantar la respiración."
        "No forzar si hay dolor lumbar."
      )
      ;;

    minimal_reset)
      ROUTINE_CATEGORY="movilidad"
      ROUTINE_NAME="Versión Mínima de Día Malo"
      ROUTINE_OBJECTIVE="Romper sedentarismo con fricción casi cero."
      ROUTINE_INTENSITY="baja"
      ROUTINE_BEST_FOR="fatiga mental alta"
      EX_NAMES=("Marcha suave" "Elevación de talones" "Apertura de pecho")
      EX_DURS=(60 60 60)
      EX_CUES=("Muévete sin pensarlo." "Sube y baja controlado." "Abre pecho y respira.")
      EX_MISTAKES=("No quedarte inmóvil." "No rebotar." "No tensar cuello.")
      ;;

    intense_1)
      ROUTINE_CATEGORY="full_body"
      ROUTINE_NAME="Versión Intensa de Día Bueno"
      ROUTINE_OBJECTIVE="Aumentar demanda cardiovascular y muscular."
      ROUTINE_INTENSITY="alta"
      ROUTINE_BEST_FOR="días buenos, energía alta y sin dolor"
      EX_NAMES=("Sentadilla rápida controlada" "Flexiones rápidas en escritorio" "Rodillas altas" "Shadowboxing rápido")
      EX_DURS=(75 60 75 90)
      EX_CUES=("Ritmo vivo, técnica limpia." "Rango cómodo." "Braceo fuerte." "Golpes rápidos.")
      EX_MISTAKES=("No sacrificar técnica." "No colapsar cintura." "No exagerar impacto." "No contener respiración.")
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
# 6) EJECUCIÓN GUIADA
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
# 7) SELECCIÓN INTELIGENTE
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
      if [[ "$USE_EQUIPMENT" -eq 1 ]]; then
        echo "intense_1 full_body_1 metabolico_1 cardio_1 superior_1 push_board_1 ab_wheel_1"
      else
        echo "intense_1 full_body_1 metabolico_1 cardio_1 superior_1"
      fi
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

routine_allowed_by_equipment_limits() {
  local id="$1"
  load_routine "$id" || return 1

  if [[ "$ROUTINE_CATEGORY" == "equipment_upper" ]]; then
    [[ "$USE_EQUIPMENT" -eq 1 ]] || return 1
    (( CATEGORY_COUNTS[equipment_upper] < MAX_EQUIPMENT_UPPER_PER_DAY )) || return 1
  fi

  if [[ "$ROUTINE_CATEGORY" == "equipment_core" ]]; then
    [[ "$USE_EQUIPMENT" -eq 1 ]] || return 1
    (( CATEGORY_COUNTS[equipment_core] < MAX_EQUIPMENT_CORE_PER_DAY )) || return 1
  fi

  return 0
}

pick_routine() {
  local next_cycle="$1"
  local preferred_category
  preferred_category="$(desired_phase_category "$next_cycle")"

  local candidate_ids=()
  local id

  if contains_cycle_bias "$next_cycle"; then
    preferred_category="metabolico"
  fi

  # Cada 5 ciclos, si hay equipo y no se ha usado mucho, meter fuerza con equipo
  if [[ "$USE_EQUIPMENT" -eq 1 ]] && (( next_cycle % 5 == 0 )); then
    preferred_category="equipment_upper"
  fi

  # Cada 7 ciclos, si hay equipo y no se ha usado ab wheel, meter core avanzado
  if [[ "$USE_EQUIPMENT" -eq 1 ]] && (( next_cycle % 7 == 0 )); then
    preferred_category="equipment_core"
  fi

  for id in "${ROUTINES[@]}"; do
    routine_matches_mode "$id" || continue
    routine_allowed_by_equipment_limits "$id" || continue
    load_routine "$id" || continue

    if [[ "$ROUTINE_CATEGORY" == "$preferred_category" && "$ROUTINE_CATEGORY" != "$LAST_CATEGORY" ]]; then
      candidate_ids+=("$id")
    fi
  done

  if (( ${#candidate_ids[@]} == 0 )); then
    for id in "${ROUTINES[@]}"; do
      routine_matches_mode "$id" || continue
      routine_allowed_by_equipment_limits "$id" || continue
      load_routine "$id" || continue

      if [[ "$ROUTINE_CATEGORY" != "$LAST_CATEGORY" ]]; then
        candidate_ids+=("$id")
      fi
    done
  fi

  if (( ${#candidate_ids[@]} == 0 )); then
    for id in "${ROUTINES[@]}"; do
      routine_matches_mode "$id" || continue
      routine_allowed_by_equipment_limits "$id" || continue
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
      --equipment)
        USE_EQUIPMENT=1
        ;;
      --no-equipment)
        USE_EQUIPMENT=0
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

  printf "Modo: ${color_yellow}%s${color_reset}\n" "$MODE"
  printf "Equipo: ${color_yellow}%s${color_reset}\n" "$USE_EQUIPMENT"
  printf "Trabajo: ${color_white}%d min${color_reset} | Pausa: ${color_white}%d min${color_reset}\n" "$WORK_MINUTES" "$BREAK_MINUTES"

  if [[ "$TEST_MODE" -eq 1 ]]; then
    printf "${color_yellow}[MODO TEST]${color_reset} tiempos reducidos para probar\n"
  fi

  printf "Voz: %s | Notificaciones: %s | Voice name: %s\n" "$USE_VOICE" "$USE_NOTIFICATIONS" "$VOICE_NAME"
  printf "Presiona ${color_red}Ctrl+C${color_reset} para salir.\n\n"
  printf "Sugerencia T2D: si acabas de comer, no saltes la pausa. Prioriza bloques metabólicos/cardio.\n"
  printf "Equipo: push-up board máximo %d veces/día; ab wheel máximo %d vez/día.\n\n" "$MAX_EQUIPMENT_UPPER_PER_DAY" "$MAX_EQUIPMENT_CORE_PER_DAY"
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
