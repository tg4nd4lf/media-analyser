import json
import subprocess
from pathlib import Path


class FFMPEGAnalyser:
    def get_movie_metadata(self, movie_path: Path) -> dict:
        cmd = [
            "ffprobe",
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            str(movie_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def parse_movie_metadata(self, movie_metadata_raw: dict) -> tuple[dict, dict]:
        streams = movie_metadata_raw.get("streams", [])
        fmt = movie_metadata_raw.get("format", {})

        video_stream = next((s for s in streams if s.get("codec_type") == "video"), {})
        audio_stream = next((s for s in streams if s.get("codec_type") == "audio"), {})

        duration = float(fmt.get("duration") or video_stream.get("duration") or 0)

        raw_bitrate = video_stream.get("bit_rate") or fmt.get("bit_rate")
        bitrate_kbps = int(raw_bitrate) / 1000 if raw_bitrate else None

        bit_depth = self._extract_bit_depth(video_stream)
        fps = self._parse_fps(video_stream.get("r_frame_rate", ""))

        video_meta = {
            "codec_name": video_stream.get("codec_name", ""),
            "codec_long_name": video_stream.get("codec_long_name", ""),
            "width": video_stream.get("width"),
            "height": video_stream.get("height"),
            "bit_depth": bit_depth,
            "pix_fmt": video_stream.get("pix_fmt", ""),
            "color_transfer": video_stream.get("color_transfer", ""),
            "color_primaries": video_stream.get("color_primaries", ""),
            "color_space": video_stream.get("color_space", ""),
            "fps": fps,
            "bitrate_kbps": bitrate_kbps,
            "duration_seconds": duration,
            "file_size_bytes": int(fmt.get("size", 0)),
        }

        audio_bitrate = audio_stream.get("bit_rate")
        audio_meta = {
            "codec_name": audio_stream.get("codec_name", ""),
            "channels": audio_stream.get("channels"),
            "sample_rate": audio_stream.get("sample_rate"),
            "bitrate_kbps": int(audio_bitrate) / 1000 if audio_bitrate else None,
        }

        return video_meta, audio_meta

    def _extract_bit_depth(self, video_stream: dict) -> int | None:
        bprs = video_stream.get("bits_per_raw_sample")
        if bprs and str(bprs) != "0":
            return int(bprs)
        pix_fmt = video_stream.get("pix_fmt", "")
        if "p10" in pix_fmt or "10le" in pix_fmt or "10be" in pix_fmt:
            return 10
        if "p12" in pix_fmt or "12le" in pix_fmt or "12be" in pix_fmt:
            return 12
        if pix_fmt in ("yuv420p", "yuv422p", "yuv444p", "yuvj420p", "yuvj422p"):
            return 8
        return None

    def _parse_fps(self, fps_str: str) -> float | None:
        if not fps_str or fps_str == "0/0":
            return None
        try:
            parts = fps_str.split("/")
            if len(parts) == 2:
                return round(int(parts[0]) / int(parts[1]), 3)
            return float(fps_str)
        except (ValueError, ZeroDivisionError):
            return None
