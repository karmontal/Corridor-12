#!/usr/bin/env bash
# Downloads the Higgsfield-generated art (assets/art/) and sounds (assets/audio/) and shrinks them for the phone.
# The cloud container cannot reach the Higgsfield CDN, so the "Fetch assets" workflow runs this and commits
# the results. The game draws plain shapes and stays silent for any file that is missing.
# Needs curl, ffmpeg and python3 with Pillow.
set -euo pipefail
cd "$(dirname "$0")/.."
base="https://d8j0ntlcm91z4.cloudfront.net/user_2zPmXEx9JaamGUwb4ZkXMQA3WpR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p assets/art assets/audio

picture() {  # out .jpg, CDN name, max size
	curl -fsSL -o "$tmp/src.png" "$base/$2"
	python3 -c "from PIL import Image; im = Image.open('$tmp/src.png').convert('RGB'); im.thumbnail(($3, $3)); im.save('$1', quality=85)"
	echo "$1"
}

icon() {  # out .png with transparency, CDN name, size; crops to the drawn part first
	curl -fsSL -o "$tmp/src.png" "$base/$2"
	python3 - "$tmp/src.png" "$1" "$3" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
box = im.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox()
if box is None or box == (0, 0, im.width, im.height):
    print("warning: no transparent background in", sys.argv[2])
else:
    im = im.crop(box)
side = max(im.width, im.height)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
n = int(sys.argv[3])
square.resize((n, n), Image.LANCZOS).save(sys.argv[2])
EOF
	echo "$1"
}

sound() {  # out .ogg, CDN name, optional ffmpeg filter, optional channel count
	curl -fsSL -o "$tmp/src" "$base/$2"
	ffmpeg -loglevel error -y -i "$tmp/src" -vn -ac "${4:-1}" -ar 44100 ${3:+-af "$3"} -c:a libvorbis -q:a 4 "$1"
	echo "$1"
}

# Pictures (gpt_image_2_5, high quality).
picture assets/art/menu_bg.jpg hf_20261013_210700_cf575fbc-07ab-4b79-964f-52d07a0b1f01.png 1600  # convoy at dawn
picture assets/art/map_bg.jpg hf_20261013_210658_04a010e3-a02d-45a7-b276-1c5e0b771a44.png 1600  # top-down terrain
picture assets/art/event.jpg hf_20261013_210659_06893d8d-5589-4e8b-b580-74012fcd428d.png 900  # dispatcher's desk
picture assets/art/end_bg.jpg hf_20261013_210659_816e8cdc-76e0-48ea-8625-bef04af4f473.png 1600  # arrival at sunset
icon assets/art/warehouse.png hf_20261013_210659_579461fe-ba65-4495-8080-d641685050db.png 192
icon assets/art/checkpoint.png hf_20261013_210658_9c04aa7c-df39-4006-a0c1-b23f6d463479.png 192
icon assets/art/district.png hf_20261013_210659_2486550b-1852-41d6-bbc3-3fe1f3ee22a3.png 192
icon assets/art/truck.png hf_20261013_210658_1c95c2d8-1f7a-4698-a2a0-a3ada5154357.png 128

# Sound effects (mirelo_text_to_audio) and music (sonilo_music).
sound assets/audio/tap.ogg hf_20261013_210714_45cd1e97-bfb5-4ef0-af8f-a969c281ca1f.mp3
sound assets/audio/engine.ogg hf_20261013_210714_09a26b14-7c65-47ea-bd8a-cf3968062dc0.mp3
sound assets/audio/load.ogg hf_20261013_210714_db89a8c4-bb20-4604-ae35-185cc76bfe82.mp3
sound assets/audio/radio.ogg hf_20261013_210714_477bc564-461c-4333-9553-ba6757bc24da.mp3
sound assets/audio/success.ogg hf_20261013_210714_4937ade4-ef20-40f7-a33d-1c8ca67dd40c.mp3
sound assets/audio/alarm.ogg hf_20261013_210714_cc530b27-9679-4631-b011-2aa6ade1646b.mp3
sound assets/audio/card.ogg hf_20261013_210714_44d09be6-c1a6-4b70-a919-1089bd126612.mp3
sound assets/audio/stars.ogg hf_20261013_210714_127a50b8-0269-42b4-b047-89cd6d2255db.mp3
sound assets/audio/error.ogg hf_20261013_210714_1e9d9f6b-4fb5-4b07-bf2c-fc1a234abeb4.mp3
sound assets/audio/music_plan.ogg hf_20261013_210714_257e6a84-1451-4b58-be7b-a99970f606e3.m4a "afade=t=in:d=1.5" 2
sound assets/audio/music_menu.ogg hf_20261013_210714_f13be6ce-7f19-4926-90a2-7675810b8df0.m4a "afade=t=in:d=1.5" 2
