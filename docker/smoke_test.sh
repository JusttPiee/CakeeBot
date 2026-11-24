#!/usr/bin/env bash
# Checks a built image without any keys. Needs Docker and sudo (GitHub Actions has both).
# Usage: bash docker/smoke_test.sh <image>
set -euo pipefail

image="$1"
data="$(mktemp -d)"
trap 'sudo rm -rf "$data"' EXIT
sudo chown 1234:1234 "$data"

# An ordinary user who may only write to /data
in_image() { docker run --rm --user 1234:1234 -v "$data:/data" "$@"; }
fail() { echo "FAILED: $1"; exit 1; }

echo "== the bot starts and asks for its token"
if output="$(in_image "$image" 2>&1)"; then fail "it did not stop without a token"; fi
echo "$output"
grep -q "Missing DISCORD_BOT_TOKEN" <<< "$output" || fail "wrong message"
sudo test -d "$data/logs" || fail "no logs in the data folder"
sudo test -f "$data/badwords.txt" || fail "bad words were not copied"

echo "== programs"
in_image "$image" node -e 'const [a, b] = process.versions.node.split("."); console.log(process.version); process.exit(a > 22 || (a == 22 && b >= 12) ? 0 : 1)'
in_image "$image" yt-dlp --version
in_image "$image" ffmpeg -version > /dev/null
in_image -w /app/music "$image" node -e 'import("@discordjs/voice")'

echo "== files"
in_image "$image" test -f /app/web/dist/index.html || fail "the web UI is missing"
for path in .env memory logs settings.json ai_config.txt prompts/personality.txt; do
  if in_image "$image" test -e "/app/$path"; then fail "$path is in the image"; fi
done

echo "== time zone"
offset="$(in_image -e TZ=Australia/Melbourne "$image" ruby -e 'print Time.now.utc_offset')"
[[ "$offset" == 36000 || "$offset" == 39600 ]] || fail "wrong time zone offset: $offset"

echo "All checks passed."
