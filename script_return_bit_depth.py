#!/usr/bin/env python3

# Filename: script_return_bit_depth.py

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Analysiert eine Video-Datei und bewertet Codec, Quelle, Auflösung, Bitrate,
Quality Factor, Farbtiefe und Dateigröße nach einem einheitlichen Bewertungsschema."""

import argparse
import re
from pathlib import Path

from movie_analysis.movie_analyser import FFMPEGAnalyser


__author__ = "tg4nd4lf"
__version__ = "2.0"

# ---------------------------------------------------------------------------
# Terminal-Farben
# ---------------------------------------------------------------------------

RED    = "\033[91m"
YELLOW = "\033[93m"
GREEN  = "\033[92m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

RATING_COLORS = {
    "Schlecht":   RED    + "Schlecht"   + RESET,
    "Akzeptabel": YELLOW + "Akzeptabel" + RESET,
    "Gut":        GREEN  + "Gut"        + RESET,
    "Sehr gut":   CYAN   + "Sehr gut"   + RESET,
}


def colorize(rating: str | None) -> str:
    return RATING_COLORS.get(rating, rating or "")


# ---------------------------------------------------------------------------
# Quellen-Erkennung (aus Dateiname)
# ---------------------------------------------------------------------------

_SOURCE_PATTERNS: list[tuple[str, str]] = [
    ("Sehr gut",   r"web[-.]?dl|blu[-.]?ray|bdrip|bdremux|remux"),
    ("Gut",        r"webrip"),
    ("Akzeptabel", r"dvdrip|dvdscr|hdrip|hdtv"),
    ("Schlecht",   r"cam\b|(?<!\w)ts(?!\w)|(?<!\w)tc(?!\w)|telesync|telecine"),
]


def detect_source(filename: str) -> tuple[str | None, str]:
    lower = filename.lower()
    for rating, pattern in _SOURCE_PATTERNS:
        match = re.search(pattern, lower)
        if match:
            return rating, match.group(0).upper().replace("-", "-")
    return None, "Unbekannt"


# ---------------------------------------------------------------------------
# Codec-Bewertung
# ---------------------------------------------------------------------------

_CODEC_MAP: dict[str, tuple[str, str]] = {
    "h264":        ("Akzeptabel", "H.264 / x264"),
    "hevc":        ("Gut",        "H.265 / x265"),
    "av1":         ("Sehr gut",   "AV1"),
    "vp9":         ("Gut",        "VP9"),
    "mpeg2video":  ("Schlecht",   "MPEG-2"),
    "mpeg4":       ("Schlecht",   "MPEG-4 / XviD"),
    "divx":        ("Schlecht",   "DivX"),
    "xvid":        ("Schlecht",   "XviD"),
}


def rate_codec(codec_name: str, bit_depth: int | None) -> tuple[str, str]:
    rating, display = _CODEC_MAP.get(codec_name.lower(), ("Akzeptabel", codec_name))
    if codec_name.lower() == "hevc":
        if bit_depth == 10:
            rating, display = "Sehr gut", "H.265 / x265 (10-bit)"
        else:
            rating, display = "Gut", "H.265 / x265 (8-bit)"
    return rating, display


# ---------------------------------------------------------------------------
# Auflösungs-Bewertung
# ---------------------------------------------------------------------------

def rate_resolution(width: int, height: int) -> tuple[str, str]:
    if height >= 2160 or width >= 3840:
        return "Sehr gut",   "2160p (4K UHD)"
    if height >= 1080:
        return "Gut",        "1080p (Full HD)"
    if height >= 720:
        return "Akzeptabel", "720p (HD)"
    return "Schlecht",       f"{height}p (SD)"


# ---------------------------------------------------------------------------
# Bitrate-Bewertung (codec-abhängig)
# ---------------------------------------------------------------------------

def rate_bitrate(bitrate_kbps: float, codec_name: str) -> str:
    efficient = codec_name.lower() in ("hevc", "av1", "vp9")
    if efficient:
        if bitrate_kbps > 6000:   return "Sehr gut"
        if bitrate_kbps >= 3000:  return "Gut"
        if bitrate_kbps >= 1000:  return "Akzeptabel"
        return "Schlecht"
    else:
        if bitrate_kbps > 10000:  return "Sehr gut"
        if bitrate_kbps >= 5000:  return "Gut"
        if bitrate_kbps >= 2000:  return "Akzeptabel"
        return "Schlecht"


# ---------------------------------------------------------------------------
# Quality Factor  Qf = bitrate_bps / (width × height × fps)
# ---------------------------------------------------------------------------

def calc_quality_factor(bitrate_kbps: float, width: int, height: int, fps: float) -> float:
    return (bitrate_kbps * 1000) / (width * height * fps)


def rate_quality_factor(qf: float) -> str:
    if qf > 0.15:   return "Sehr gut"
    if qf >= 0.10:  return "Gut"
    if qf >= 0.05:  return "Akzeptabel"
    return "Schlecht"


# ---------------------------------------------------------------------------
# Farbtiefe-Bewertung
# ---------------------------------------------------------------------------

def rate_bit_depth(bit_depth: int, hdr: bool) -> tuple[str, str]:
    if bit_depth >= 10 and hdr:
        return "Sehr gut",   f"{bit_depth}-bit HDR"
    if bit_depth >= 10:
        return "Gut",        f"{bit_depth}-bit SDR"
    if bit_depth == 8:
        return "Akzeptabel", "8-bit SDR"
    return "Schlecht",       f"{bit_depth}-bit"


# ---------------------------------------------------------------------------
# Dateigröße pro Stunde (Näherung für 1080p-Vergleich)
# ---------------------------------------------------------------------------

def rate_size_per_hour(file_size_bytes: int, duration_seconds: float) -> str:
    hours = duration_seconds / 3600
    gb_per_hour = (file_size_bytes / (1024 ** 3)) / hours
    if gb_per_hour > 6:   return "Sehr gut"
    if gb_per_hour >= 3:  return "Gut"
    if gb_per_hour >= 1:  return "Akzeptabel"
    return "Schlecht"


# ---------------------------------------------------------------------------
# HDR-Erkennung
# ---------------------------------------------------------------------------

_HDR_TRANSFERS = {"smpte2084", "arib-std-b67", "smpte428"}
_HDR_PRIMARIES = {"bt2020", "bt2020nc", "bt2020c"}


def detect_hdr(color_transfer: str, color_primaries: str) -> bool:
    return color_transfer in _HDR_TRANSFERS or color_primaries in _HDR_PRIMARIES


# ---------------------------------------------------------------------------
# Ausgabe-Hilfsfunktionen
# ---------------------------------------------------------------------------

def fmt_size(size_bytes: int) -> str:
    gb = size_bytes / (1024 ** 3)
    if gb >= 1:
        return f"{gb:.2f} GB"
    return f"{size_bytes / (1024 ** 2):.1f} MB"


def fmt_duration(seconds: float) -> str:
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    if h:
        return f"{h}h {m:02d}m {s:02d}s"
    return f"{m}m {s:02d}s"


def fmt_audio_channels(channels: int) -> str:
    if channels == 1:  return "1.0 (Mono)"
    if channels == 2:  return "2.0 (Stereo)"
    if channels == 6:  return "5.1"
    if channels == 8:  return "7.1"
    return str(channels)


def print_row(label: str, value: str, rating: str | None = None) -> None:
    line = f"  {BOLD}{label:<22}{RESET} {value}"
    if rating:
        line += f"   [{colorize(rating)}]"
    print(line)


# ---------------------------------------------------------------------------
# Hauptprogramm
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analysiert eine Video-Datei und bewertet die Qualität."
    )
    parser.add_argument("input_path", type=Path, help="Pfad zur MKV-/MP4-/AVI-Datei")
    args = parser.parse_args()
    input_path: Path = args.input_path

    try:
        analyser = FFMPEGAnalyser()
        metadata_raw = analyser.get_movie_metadata(movie_path=input_path)
        video_meta, audio_meta = analyser.parse_movie_metadata(movie_metadata_raw=metadata_raw)

        hdr = detect_hdr(video_meta["color_transfer"], video_meta["color_primaries"])

        # Codec
        codec_rating, codec_display = rate_codec(video_meta["codec_name"], video_meta["bit_depth"])

        # Quelle
        source_rating, source_label = detect_source(input_path.name)

        # Auflösung
        w, h = video_meta["width"], video_meta["height"]
        if w and h:
            res_rating, res_label = rate_resolution(w, h)
            res_str = f"{res_label}  ({w}×{h})"
        else:
            res_rating, res_str = None, "Unbekannt"

        # Bitrate
        bitrate = video_meta["bitrate_kbps"]
        if bitrate:
            bitrate_rating = rate_bitrate(bitrate, video_meta["codec_name"])
            bitrate_str = f"{bitrate:,.0f} kbps"
        else:
            bitrate_rating, bitrate_str = None, "Unbekannt"

        # Quality Factor
        fps = video_meta["fps"]
        if bitrate and w and h and fps:
            qf = calc_quality_factor(bitrate, w, h, fps)
            qf_rating = rate_quality_factor(qf)
            qf_str = f"{qf:.4f}"
        else:
            qf_rating, qf_str = None, "Unbekannt"

        # Farbtiefe
        bd = video_meta["bit_depth"]
        if bd:
            bd_rating, bd_label = rate_bit_depth(bd, hdr)
        else:
            bd_rating, bd_label = None, "Unbekannt"

        # Dateigröße
        file_size = video_meta["file_size_bytes"]
        duration  = video_meta["duration_seconds"]
        size_str  = fmt_size(file_size) if file_size else "Unbekannt"
        if file_size and duration:
            size_rating = rate_size_per_hour(file_size, duration)
            hours = duration / 3600
            gb_per_hour = (file_size / (1024 ** 3)) / hours
            size_str += f"  ({gb_per_hour:.2f} GB/h)"
        else:
            size_rating = None

        # Ausgabe
        sep = "─" * 60
        print()
        print(f"  {BOLD}{sep}{RESET}")
        print(f"  {BOLD}Film-Qualitätsanalyse{RESET}")
        print(f"  {BOLD}{sep}{RESET}")
        print()

        print_row("Datei:",           input_path.name)
        print_row("Größe:",           size_str,                             size_rating)
        print_row("Laufzeit:",        fmt_duration(duration) if duration else "Unbekannt")
        print()
        print_row("Codec:",           codec_display,                        codec_rating)
        print_row("Quelle:",          source_label,                         source_rating)
        print_row("Auflösung:",       res_str,                              res_rating)
        print_row("Bitrate (Video):", bitrate_str,                          bitrate_rating)
        print_row("Quality Factor:",  qf_str,                               qf_rating)
        print_row("Farbtiefe:",       bd_label,                             bd_rating)

        if hdr:
            hdr_label = video_meta["color_transfer"] or "HDR"
            print_row("HDR:",         hdr_label)

        if video_meta.get("pix_fmt"):
            print_row("Pixel-Format:", video_meta["pix_fmt"])

        if audio_meta.get("codec_name"):
            a_info = audio_meta["codec_name"].upper()
            if audio_meta.get("channels"):
                a_info += f"  {fmt_audio_channels(audio_meta['channels'])}"
            if audio_meta.get("bitrate_kbps"):
                a_info += f"  @ {audio_meta['bitrate_kbps']:,.0f} kbps"
            print_row("Audio:",       a_info)

        if fps:
            print_row("Framerate:",   f"{fps} fps")

        print()
        print(f"  {BOLD}{sep}{RESET}")
        print(f"  Legende:  "
              f"{colorize('Schlecht')}  "
              f"{colorize('Akzeptabel')}  "
              f"{colorize('Gut')}  "
              f"{colorize('Sehr gut')}")
        print()

    except FileNotFoundError:
        print("Fehler: ffprobe nicht gefunden. Bitte ffmpeg/ffprobe installieren.")
        raise SystemExit(1)
    except subprocess.CalledProcessError as err:
        print(f"Fehler beim Lesen der Datei: {err.stderr.strip()}")
        raise SystemExit(1)
    except Exception as err:
        print(f"Fehler: {err}")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
