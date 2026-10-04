# Edit timeline interchange

File > Export Premiere EDL or Export Final Cut Pro XML exports the current derived Edit timeline, including the current Estimates setting. The formats are also available in Edit Exports. No account or network is required.

These are timing guides, not a media conform. The model does not yet provide resolvable media assets for edit clips. EDL uses unique offline placeholder reels; FCPXML uses named gaps. Estimated segments are labelled Estimated; all others are labelled Placeholder. No footage, board image, audio, transition, source trim, or effect is transferred. Authored timeline duration is preserved, rounded to frame boundaries. Project data is not changed by generation.

Both formats currently use 24 fps non-drop-frame and start at zero. FCPXML describes a 1920x1080 sequence. Cumulative boundaries are rounded once, avoiding independent-duration rounding drift. Empty, invalid, noncontiguous, sub-frame, 1000-event or 24-hour timelines are rejected. Untimed scenes are omitted and counted in the save dialog. EDL replaces non-ASCII characters with question marks; FCPXML retains Unicode.

Import the .edl in Premiere at 24 fps; expect offline placeholders. Import the .fcpxml using Final Cut Pro's XML import; expect named gaps. Replace placeholders with media manually. Actual imports into those applications have not been verified on this Mac.

Validation: 226 Swift tests, 37 Python checks and 14 importer self-tests passed. New checks cover frame continuity, timecode rollover, XML escaping/structure, empty and invalid input, and event limits.

References:
- https://developer.apple.com/documentation/professional-video-applications/document-type-definition
- https://developer.apple.com/documentation/professional-video-applications/creating-fcpxml-documents
- https://helpx.adobe.com/archive/en/premiere-pro/cc/2015/premiere_pro_reference.pdf
