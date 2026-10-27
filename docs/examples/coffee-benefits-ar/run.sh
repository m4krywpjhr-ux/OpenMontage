#!/usr/bin/env bash
# Renders the three Arabic "فوائد القهوة" versions with the MoneyPrinterTurbo skill helper.
# Requires PEXELS_API_KEY (or MPT_PEXELS_API_KEY) in the environment.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MPT="$HOME/MoneyPrinterTurbo"
SKILL_DIR="${SKILL_DIR:-$HERE/.mpt-skill}"
export MPT_PEXELS_API_KEY="${MPT_PEXELS_API_KEY:-${PEXELS_API_KEY:?set PEXELS_API_KEY}}"

[ -f "$MPT/cli.py" ] || git clone --depth 1 https://github.com/harry0703/MoneyPrinterTurbo.git "$MPT"
mkdir -p "$SKILL_DIR"
[ -f "$SKILL_DIR/mpt_agent.py" ] || curl -sSfL -o "$SKILL_DIR/mpt_agent.py" \
  https://raw.githubusercontent.com/harry0703/MoneyPrinterTurbo/main/docs/skill/mpt_agent.py
(cd "$MPT" && uv sync --frozen -q)

# Cloud sandboxes intercept TLS; Edge TTS pins certifi, so trust the proxy CA there too.
if [ -f /root/.ccr/ca-bundle.crt ]; then
  CERTS="$(cd "$MPT" && uv run python -c 'import certifi; print(certifi.where())')"
  grep -q "$(sed -n 2p /root/.ccr/ca-bundle.crt)" "$CERTS" || cat /root/.ccr/ca-bundle.crt >> "$CERTS"
fi

# Arabic subtitle fonts (OFL, Google Fonts).
for f in "tajawal/Tajawal-Bold.ttf:Tajawal-Bold.ttf" "changa/Changa%5Bwght%5D.ttf:Changa.ttf" \
         "notonaskharabic/NotoNaskhArabic%5Bwght%5D.ttf:NotoNaskhArabic.ttf"; do
  [ -f "$MPT/resource/fonts/${f##*:}" ] || curl -sSfL -o "$MPT/resource/fonts/${f##*:}" \
    "https://raw.githubusercontent.com/google/fonts/main/ofl/${f%%:*}"
done

mkdir -p "$HERE/renders"
count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$HERE/versions.json")
for i in $(seq 0 $((count - 1))); do
  mapfile -t ARGS < <(python3 - "$HERE/versions.json" "$i" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))[int(sys.argv[2])]
args = [v["name"], "--video-script", v["script"], "--video-terms", v["terms"],
        "--voice-name", v["voice"], "--font-name", v["font"], "--video-aspect", "9:16",
        "--video-language", "ar", "--bgm-type", "random", "--bgm-volume", "0.15", *v["extra_args"]]
print("\n".join(args))
PY
  )
  name="${ARGS[0]}"
  echo "== rendering $name"
  out=$(cd "$SKILL_DIR" && uv run --no-project --python 3.11 python mpt_agent.py \
        --subject "فوائد القهوة" -- "${ARGS[@]:1}")
  video=$(sed -n 's/^VIDEO_FILE=//p' <<<"$out" | head -1)
  cp "$video" "$HERE/renders/coffee-$name.mp4"
  echo "   -> $HERE/renders/coffee-$name.mp4"
done
