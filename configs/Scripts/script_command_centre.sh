#!/usr/bin/env bash
# script_command_centre.sh — Ominty Scripts / Control Panel
# Scans subdirectories, shows a "Main Screen" of toolkits,
# and lets the user pick and run one script at a time.
#
# Version: 1.0

set -euo pipefail

# ---------- helpers ----------

has_cmd() { command -v "$1" >/dev/null 2>&1; }

die() {
  local msg="${1:-Unknown error}"
  if has_cmd zenity; then
    zenity --error --title="Ominty Scripts" --width=480 --no-markup \
      --text="$msg" || true
  else
    echo "ERROR: $msg" >&2
  fi
  exit 1
}

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
SCRIPT_BASENAME="$(basename -- "$SCRIPT_PATH")"

has_cmd zenity || die "Zenity is required but not installed."

# ---------- README description per toolkit ----------

get_toolkit_description() {
  local dir="$1"
  local readme="$dir/README.md"
  local line desc
  if [[ -f "$readme" ]]; then
    # Take the first non-empty, non-just-heading line
    while IFS= read -r line; do
      # skip empty lines
      [[ -z "$line" ]] && continue
      # trim leading Markdown heading markers
      line="${line### }"
      line="${line#### }"
      desc="$line"
      break
    done <"$readme"
  fi

  # Fallback
  [[ -z "${desc:-}" ]] && desc="No description available."
  # Trim to a reasonable length
  if (( ${#desc} > 120 )); then
    desc="${desc:0:117}..."
  fi
  printf '%s\n' "$desc"
}

# ---------- SCRIPT_NAME extraction per script ----------

get_script_label() {
  local file="$1"
  local line name
  # Look for a line like: SCRIPT_NAME="Something"
  # without sourcing the script
  while IFS= read -r line; do
    case "$line" in
      SCRIPT_NAME=*)
        # Remove leading SCRIPT_NAME= and quotes
        name="${line#SCRIPT_NAME=}"
        name="${name#\"}"
        name="${name%\"}"
        name="${name#\'}"
        name="${name%\'}"
        [[ -n "$name" ]] && { printf '%s\n' "$name"; return 0; }
        ;;
    esac
  done <"$file"

  # Fallback to basename
  printf '%s\n' "$(basename -- "$file")"
}

# ---------- scan toolkits (subdirectories) ----------

discover_toolkits() {
  # Outputs: "toolkit_name|description" per line
  local d name desc
  for d in "$SCRIPT_DIR"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename -- "$d")"

    # Ignore hidden dirs, and avoid including things like .git
    [[ "$name" == .* ]] && continue

    desc="$(get_toolkit_description "$d")"
    printf '%s|%s\n' "$name" "$desc"
  done
}

# ---------- scan scripts within a toolkit (non-recursive) ----------

discover_scripts_in_toolkit() {
  local toolkit_dir="$1"
  local f label
  for f in "$toolkit_dir"/*.sh; do
    [[ -e "$f" ]] || continue
    # Skip this hub script itself if someone put it inside a toolkit
    [[ "$(basename -- "$f")" == "$SCRIPT_BASENAME" ]] && continue
    [[ -f "$f" ]] || continue

    label="$(get_script_label "$f")"
    # Output: label|filename
    printf '%s|%s\n' "$label" "$(basename -- "$f")"
  done
}

# ---------- intro screen ----------

show_intro() {
  zenity --info --title="Ominty Scripts – Overview" --width=600 --no-markup \
    --text="Welcome to Ominty Scripts.

This tool acts as a control panel for your scripts.

How it works:
1. The hub scans its own folder for subdirectories.
2. Each subdirectory is treated as a toolkit (for example, backup-tools, restore-tools, LUSI, and so on).
3. Each toolkit should contain:
   • One or more .sh scripts.
   • A README.md file that briefly describes the toolkit.
4. You pick a toolkit from the main screen.
5. On the next screen, you choose a script from that toolkit to run.
6. After the script finishes, you are returned to the main screen.

Only one script is run at a time.

Click OK to open the main screen." || true
}

# ---------- main screen: pick toolkit ----------

choose_toolkit() {
  local tk_lines=() line name desc rows=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    tk_lines+=("$line")
  done < <(discover_toolkits)

  if [[ ${#tk_lines[@]} -eq 0 ]]; then
    die "No toolkits (subdirectories) found in:
$SCRIPT_DIR

Create one or more subdirectories with scripts and README.md files."
  fi

  # Build rows for Zenity: [name desc name desc ...]
  for line in "${tk_lines[@]}"; do
    name="${line%%|*}"
    desc="${line#*|}"
    rows+=("$name" "$desc")
  done

  local choice
  choice="$(zenity --list \
    --title="Ominty Scripts – Main Screen" \
    --width=780 --height=480 \
    --ok-label="Open toolkit" \
    --cancel-label="Quit" \
    --column="Toolkit" --column="Description" \
    "${rows[@]}" 2>/dev/null || echo "")"

  printf '%s\n' "$choice"
}

# ---------- script screen: pick script within toolkit ----------

choose_script_in_toolkit() {
  local toolkit_name="$1"
  local toolkit_dir="$SCRIPT_DIR/$toolkit_name"

  if [[ ! -d "$toolkit_dir" ]]; then
    die "Toolkit directory not found:
$toolkit_dir"
  fi

  local sc_lines=() line label file rows=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    sc_lines+=("$line")
  done < <(discover_scripts_in_toolkit "$toolkit_dir")

  if [[ ${#sc_lines[@]} -eq 0 ]]; then
    zenity --warning --title="No scripts found" --width=520 \
      --text="No .sh scripts were found in toolkit:

$toolkit_name

Place one or more .sh scripts inside:
$toolkit_dir" || true
    echo ""
    return 0
  fi

  # We keep parallel arrays of labels and filenames
  local LABELS=()
  local FILES=()

  for line in "${sc_lines[@]}"; do
    label="${line%%|*}"
    file="${line#*|}"
    LABELS+=("$label")
    FILES+=("$file")
  done

  # Build list of labels for Zenity (single-column list)
  local list_args=()
  for label in "${LABELS[@]}"; do
    list_args+=("$label")
  done

  local choice
  choice="$(zenity --list \
    --title="Toolkit: $toolkit_name – Choose script to run" \
    --width=620 --height=480 \
    --ok-label="Run" \
    --cancel-label="Back to main screen" \
    --column="Available actions" \
    "${list_args[@]}" 2>/dev/null || echo "")"

  # If user cancelled, return empty so caller knows to go back
  [[ -z "$choice" ]] && { echo ""; return 0; }

  # Map chosen label back to filename
  local i selected_file=""
  for i in "${!LABELS[@]}"; do
    if [[ "${LABELS[$i]}" == "$choice" ]]; then
      selected_file="${FILES[$i]}"
      break
    fi
  done

  if [[ -z "$selected_file" ]]; then
    zenity --error --title="Selection error" --width=420 \
      --text="Could not map the selected action to a script file.

Choice:
$choice" || true
    echo ""
    return 0
  fi

  printf '%s\n' "$selected_file"
}

# ---------- run selected script ----------

run_script() {
  local toolkit_name="$1"
  local script_file="$2"
  local full_path="$SCRIPT_DIR/$toolkit_name/$script_file"

  if [[ ! -f "$full_path" ]]; then
    zenity --error --title="Script not found" --width=480 \
      --text="The selected script no longer exists:

$full_path" || true
    return
  fi

  zenity --question --title="Run script?" --width=480 \
    --text="Do you want to run this script?

Toolkit: $toolkit_name
Script:  $script_file" || return

  if [[ -x "$full_path" ]]; then
    zenity --info --title="Running script" --width=480 \
      --text="Running:

$full_path

Please wait until the script finishes." || true
    "$full_path"
  else
    zenity --info --title="Running script via bash" --width=480 \
      --text="The script is not marked as executable.

It will be run using:

bash \"$full_path\"

Please wait until the script finishes." || true
    bash "$full_path"
  fi

  zenity --info --title="Script finished" --width=480 \
    --text="The script has finished.

Toolkit: $toolkit_name
Script:  $script_file

You will now return to the main screen." || true
}

# ---------- main loop ----------

show_intro

while true; do
  toolkit="$(choose_toolkit)"
  [[ -z "$toolkit" ]] && break  # user chose Quit

  script_choice="$(choose_script_in_toolkit "$toolkit")"
  [[ -z "$script_choice" ]] && continue  # go back to main screen

  run_script "$toolkit" "$script_choice"
  # After running, we loop back to show main screen again
done

exit 0
