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
    lib = root / "crates/project/src/lib.rs"
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
    replace(lib,
        """            name,
            label,
            start,
""",
        """            name,
            otio_screenplayos: None,
            label,
            start,
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
    test = root / "crates/interchange/tests/it/otio.rs"
    test.write_text(test.read_text() + r'''

#[test]
fn screenplayos_namespace_survives_native_project_and_otio_roundtrip() {
    let digest = "a".repeat(64);
    let doc = serde_json::json!({
        "OTIO_SCHEMA": "Timeline.1", "name": "Synthetic",
        "tracks": {"OTIO_SCHEMA": "Stack.1", "children": [{
            "OTIO_SCHEMA": "Track.1", "name": "Picture", "kind": "Video",
            "children": [{
                "OTIO_SCHEMA": "Clip.2", "name": "generated",
                "source_range": {
                    "OTIO_SCHEMA": "TimeRange.1",
                    "start_time": {"OTIO_SCHEMA": "RationalTime.1", "value": 0, "rate": 24},
                    "duration": {"OTIO_SCHEMA": "RationalTime.1", "value": 48, "rate": 24}
                },
                "media_references": {"DEFAULT_MEDIA": {
                    "OTIO_SCHEMA": "ExternalReference.1", "target_url": "Board Images/generated.png"
                }},
                "active_media_reference_key": "DEFAULT_MEDIA",
                "metadata": {"screenplayos": {
                    "occurrence_id": "00000000-0000-0000-0000-000000000011",
                    "scene_id": "00000000-0000-0000-0000-000000000012",
                    "shot_id": "00000000-0000-0000-0000-000000000013",
                    "board_id": "00000000-0000-0000-0000-000000000014",
                    "take_id": "00000000-0000-0000-0000-000000000015",
                    "generation_job_id": "00000000-0000-0000-0000-000000000016",
                    "media_sha256": digest,
                    "prompt_sha256": digest
                }}
            }]
        }]}
    });
    let bytes = serde_json::to_vec(&doc).unwrap();
    let (imported, _) = import(&bytes, Format::Otio, None).unwrap();
    let sequence = imported.sequences[0];
    let clip = &imported.project.sequence(sequence).unwrap().video_tracks[0].items[0];
    let external = clip.otio_screenplayos.clone().expect("import must preserve external provenance");
    assert_eq!(external, doc["tracks"]["children"][0]["children"][0]["metadata"]["screenplayos"]);
    let serialized = serde_json::to_value(clip).unwrap();
    let reopened: filmcraft_project::TrackItem = serde_json::from_value(serialized).unwrap();
    assert_eq!(reopened.otio_screenplayos, Some(external.clone()));
    // Project-level serde is the closest model-layer analog of saving and
    // reopening an editor project; executable file I/O is a separate gate.
    let project_bytes = serde_json::to_vec(&imported.project).unwrap();
    let reopened_project: filmcraft_project::Project =
        serde_json::from_slice(&project_bytes).unwrap();
    let reopened_clip = &reopened_project.sequence(sequence).unwrap().video_tracks[0].items[0];
    assert_eq!(reopened_clip.otio_screenplayos, Some(external.clone()));
    let (exported, _) = filmcraft_interchange::export(
        &imported.project, sequence, Format::Otio, &ExportOptions::default()
    ).unwrap();
    let returned: serde_json::Value = serde_json::from_slice(&exported).unwrap();
    assert_eq!(
        returned["tracks"]["children"][0]["children"][0]["metadata"]["screenplayos"],
        external
    );

    // Reject unbounded or malformed external metadata while still importing the clip.
    for invalid in [
        serde_json::json!({"payload": "x".repeat(4097)}),
        serde_json::json!(["not", "an", "object"]),
        serde_json::Value::Null,
    ] {
        let mut changed = doc.clone();
        changed["tracks"]["children"][0]["children"][0]["metadata"]["screenplayos"] = invalid;
        let (reimported, _) = import(&serde_json::to_vec(&changed).unwrap(), Format::Otio, None).unwrap();
        let seq = reimported.sequences[0];
        let item = &reimported.project.sequence(seq).unwrap().video_tracks[0].items[0];
        assert!(item.otio_screenplayos.is_none(), "invalid provenance must not be persisted");
    }

    // Multiple timeline occurrences may refer to the same generated Take.
    // The Take and generation fingerprints remain shared, but each
    // occurrence retains a separate stable editorial identity.
    let mut multi = doc.clone();
    let first = multi["tracks"]["children"][0]["children"][0].clone();
    let mut second = first.clone();
    second["name"] = serde_json::json!("generated second occurrence");
    second["metadata"]["screenplayos"]["occurrence_id"] =
        serde_json::json!("00000000-0000-0000-0000-000000000021");
    multi["tracks"]["children"][0]["children"].as_array_mut().unwrap().push(second);
    let (multi_import, _) =
        import(&serde_json::to_vec(&multi).unwrap(), Format::Otio, None).unwrap();
    let multi_seq = multi_import.sequences[0];
    let multi_items = &multi_import.project.sequence(multi_seq).unwrap().video_tracks[0].items;
    assert_eq!(multi_items.len(), 2);
    let left = multi_items[0].otio_screenplayos.as_ref().unwrap();
    let right = multi_items[1].otio_screenplayos.as_ref().unwrap();
    assert_ne!(left["occurrence_id"], right["occurrence_id"]);
    assert_eq!(left["take_id"], right["take_id"]);
    assert_eq!(left["generation_job_id"], right["generation_job_id"]);
    assert_eq!(left["media_sha256"], right["media_sha256"]);
    assert_eq!(left["prompt_sha256"], right["prompt_sha256"]);

    let (multi_export, _) =
        filmcraft_interchange::export(&multi_import.project, multi_seq, Format::Otio, &ExportOptions::default()).unwrap();
    let multi_return: serde_json::Value = serde_json::from_slice(&multi_export).unwrap();
    let returned_clips = multi_return["tracks"]["children"][0]["children"].as_array().unwrap();
    assert_eq!(returned_clips.len(), 2);
    assert_ne!(
        returned_clips[0]["metadata"]["screenplayos"]["occurrence_id"],
        returned_clips[1]["metadata"]["screenplayos"]["occurrence_id"]
    );
    assert_eq!(
        returned_clips[0]["metadata"]["screenplayos"]["take_id"],
        returned_clips[1]["metadata"]["screenplayos"]["take_id"]
    );
}
''')
    print("Applied narrow ScreenplayOS OTIO provenance experiment to FilmCraft source.")

if __name__ == "__main__":
    main()
