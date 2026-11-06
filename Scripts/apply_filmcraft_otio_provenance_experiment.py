#!/usr/bin/env python3
"""Apply a minimal, source-anchored OTIO provenance experiment to FilmCraft v0.17.1.

This modifies only a temporary checkout of the upstream code. It does not
modify the upstream repository or imply a working/accepted FilmCraft patch.
"""
from pathlib import Path
import sys

def replace(path, before, after):
    data = path.read_text()
    count = data.count(before)
    if count != 1:
        raise SystemExit(f"Unsupported FilmCraft revision at {path}: expected 1 anchor, found {count}")
    path.write_text(data.replace(before, after))

def main():
    root = Path(sys.argv[1]).resolve(strict=True)
    track = root / "crates/project/src/track.rs"
    common = root / "crates/interchange/src/common.rs"
    otio = root / "crates/interchange/src/otio.rs"
    replace(track,
        """    pub name: String,
    pub label: Label,
""",
        """    pub name: String,
    /// Preserved, untrusted ScreenplayOS OTIO clip namespace; never executable.
    /// This is intentionally a narrow compatibility experiment.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub otio_screenplayos: Option<serde_json::Value>,
    pub label: Label,
""")
    replace(common,
        """            name: name.to_string(),
            label,
            start,
""",
        """            name: name.to_string(),
            otio_screenplayos: None,
            label,
            start,
""")
    replace(otio,
        """        let meta = json!({"filmcraft": {
            "label": it.label, "custom_label_color": it.custom_label_color, "link": it.link, "group": it.group, "effects": it.effects,
            "gain_db": it.gain_db, "scale_to_frame": it.scale_to_frame, "source_in_ticks": it.source_in.0,
            "duration_ticks": it.duration.0,
        }});
        let markers: Vec<Value>""",
        """        let mut meta = json!({"filmcraft": {
            "label": it.label, "custom_label_color": it.custom_label_color, "link": it.link, "group": it.group, "effects": it.effects,
            "gain_db": it.gain_db, "scale_to_frame": it.scale_to_frame, "source_in_ticks": it.source_in.0,
            "duration_ticks": it.duration.0,
        }});
        if let Some(external) = &it.otio_screenplayos {
            // Original provenance is retained for identity review, not trusted
            // as an authorization for new clips or automatic project changes.
            meta["screenplayos"] = external.clone();
        }
        let markers: Vec<Value>""")
    replace(otio,
        """        let meta = fc(c).cloned();
        self.apply_clip_meta(&mut ti, c, meta.as_ref());
        Some(ti)
""",
        """        let meta = fc(c).cloned();
        self.apply_clip_meta(&mut ti, c, meta.as_ref());
        // Bounded external provenance is copied into durable project storage.
        // Never accept unbounded nested metadata or a non-object value.
        if let Some(external) = c.get("metadata").and_then(|m| m.get("screenplayos"))
            && external.is_object()
            && serde_json::to_vec(external).is_ok_and(|raw| raw.len() <= 4096)
        {
            ti.otio_screenplayos = Some(external.clone());
        }
        Some(ti)
""")
    print("Applied narrow ScreenplayOS OTIO provenance experiment to FilmCraft source.")

if __name__ == "__main__":
    main()
