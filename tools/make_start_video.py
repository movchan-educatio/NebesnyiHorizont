"""Transcode the intro clip to Ogg Theora for Godot's VideoStreamPlayer.

Godot 4 can only play Ogg Theora video, so this Blender script loads the
source movie into the Video Sequence Editor and renders it back out as a
.ogv file. Run with:

  blender --background --factory-startup --python tools/make_start_video.py

Output:
  <project>/assets/video/start_loop.ogv
"""
from __future__ import annotations

import os
from pathlib import Path

import bpy

SCRIPT = Path(__file__).resolve()
PROJECT = SCRIPT.parent.parent
WORKSPACE = PROJECT.parent
OUT_DIR = PROJECT / "assets" / "video"
OUT_BASE = OUT_DIR / "start_loop"

MP4_CANDIDATES = sorted(WORKSPACE.glob("*.mp4"))


def find_source() -> Path:
    if not MP4_CANDIDATES:
        raise SystemExit("[start-video] no .mp4 found in workspace")
    return MP4_CANDIDATES[0]


def sequences(editor):
    if hasattr(editor, "strips"):
        return editor.strips
    return editor.sequences


def main() -> None:
    source = find_source()
    print(f"[start-video] source: {source}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    scene = bpy.context.scene
    scene.sequence_editor_create()
    editor = scene.sequence_editor
    strips = sequences(editor)

    for existing in list(strips):
        strips.remove(existing)

    strip = strips.new_movie("intro", str(source), channel=1, frame_start=1)
    scene.frame_start = 1
    scene.frame_end = max(1, int(strip.frame_final_duration))
    scene.render.fps = 24
    scene.render.fps_base = 1.0
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.ffmpeg.format = "OGG"
    scene.render.ffmpeg.codec = "THEORA"
    scene.render.ffmpeg.constant_rate_factor = "HIGH"
    try:
        scene.render.ffmpeg.audio_codec = "VORBIS"
    except Exception as error:  # pragma: no cover - depends on build
        print(f"[start-video] audio codec not set: {error}")
    scene.render.filepath = str(OUT_BASE)
    print(f"[start-video] frames: {scene.frame_start}..{scene.frame_end}")

    bpy.ops.render.render(animation=True)
    produced = OUT_BASE.with_suffix(".ogv")
    print(f"[start-video] output: {produced} exists={produced.exists()}")
    if produced.exists():
        print(f"[start-video] size: {produced.stat().st_size}")


main()
