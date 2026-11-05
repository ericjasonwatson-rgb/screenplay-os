#!/usr/bin/env python3
"""Build/check synthetic DOCX fixtures using only Python's standard library.

Source XML and expected text are independently checked in. The generated JSON is
text-only and read directly by Swift tests from their checkout, without resources.
No Word installation, private input, network, or production extractor is used.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1] / "Tests/Fixtures/CampaignAgency"
SOURCE = ROOT / "source"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R = "http://schemas.openxmlformats.org/package/2006/relationships"
O = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
C = "http://schemas.openxmlformats.org/package/2006/content-types"
MAX_SOURCE_BYTES = 64 * 1024
MAX_OUTPUT_BYTES = 1024 * 1024
MAX_ARCHIVE_BYTES = 256 * 1024
MAX_PARTS = 16
MAX_TOTAL_PART_BYTES = 128 * 1024
MAX_XML_DEPTH = 32
MAX_XML_NODES = 4096


def read_local(path: Path, maximum: int) -> bytes:
    """Read a bounded regular local file; never follow a final symlink or FIFO.

    The CLI accepts no input paths and only uses files in this checkout. This is
    fixture tooling, not a filesystem sandbox against a malicious same-user actor.
    """
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
            raise ValueError(f"Fixture input is nonregular or oversized: {path.name}")
        data = source.read(maximum + 1)
        if len(data) > maximum:
            raise ValueError(f"Fixture input grew beyond its limit: {path.name}")
    return data


def parse_xml(data: bytes) -> ET.Element:
    """Bounded UTF-8 fixture parsing without DTDs, entities or external loading."""
    if len(data) > MAX_SOURCE_BYTES:
        raise ValueError("Fixture XML exceeds its byte limit")
    text = data.decode("utf-8")
    lowered = text.lower()
    if "\x00" in text or "<!doctype" in lowered or "<!entity" in lowered:
        raise ValueError("Fixture XML cannot contain NUL, DTDs or entity declarations")
    logical = text.removeprefix("\ufeff")
    if "<?xml" in lowered:
        declaration = re.match(r"<\?xml\s[^?]{0,1000}\?>", logical, re.IGNORECASE)
        if declaration is None or "<?xml" in logical[declaration.end():].lower():
            raise ValueError("Fixture XML declaration is misplaced or too long")
        for encoding in re.findall(r"encoding\s*=\s*['\"]([^'\"]+)['\"]", declaration[0], re.IGNORECASE):
            if encoding.lower() != "utf-8":
                raise ValueError("Fixture XML must declare UTF-8")
    parser = ET.XMLPullParser(events=("start", "end"))
    root = None
    depth = nodes = 0
    for offset in range(0, len(data), 1024):
        parser.feed(data[offset:offset + 1024])
        for event, element in parser.read_events():
            if event == "start":
                root = element if root is None else root
                depth += 1
                nodes += 1
                if depth > MAX_XML_DEPTH or nodes > MAX_XML_NODES:
                    raise ValueError("Fixture XML exceeds its depth or node limit")
            else:
                depth -= 1
    parser.close()
    if root is None or depth:
        raise ValueError("Fixture XML has no complete root")
    return root


def check_parts(parts: dict[str, bytes]) -> None:
    if not 0 < len(parts) <= MAX_PARTS or sum(map(len, parts.values())) > MAX_TOTAL_PART_BYTES:
        raise ValueError("Fixture archive exceeds its member or total byte limit")
    for name, data in parts.items():
        if (not name or name.startswith("/") or "\\" in name
                or any(part in ("", ".", "..") for part in name.split("/"))
                or len(name.encode()) > 256 or len(data) > MAX_SOURCE_BYTES):
            raise ValueError("Fixture archive has an unsafe member name or size")


def reference_archive(data: bytes) -> dict[str, bytes]:
    """Decode only bounded in-memory test archives. Never extract files to disk."""
    if len(data) > MAX_ARCHIVE_BYTES:
        raise ValueError("Fixture archive exceeds its byte limit")
    with zipfile.ZipFile(io.BytesIO(data)) as check:
        members = check.infolist()
        if not 0 < len(members) <= MAX_PARTS or sum(item.file_size for item in members) > MAX_TOTAL_PART_BYTES:
            raise ValueError("Fixture archive declares too much content")
        if len({item.filename for item in members}) != len(members):
            raise ValueError("Fixture archive has duplicate members")
        decoded = {}
        for member in members:
            if member.file_size > MAX_SOURCE_BYTES or member.compress_type not in (0, 8):
                raise ValueError("Fixture archive member is oversized or unsupported")
            with check.open(member) as source:
                value = source.read(MAX_SOURCE_BYTES + 1)
            if len(value) != member.file_size:
                raise ValueError("Fixture archive member size disagrees")
            decoded[member.filename] = value
    check_parts(decoded)
    return decoded


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fixed_deflate(data: bytes) -> bytes:
    """One deterministic fixed-Huffman literal block, independent of zlib version.

    This is real ZIP method 8/raw DEFLATE, without compressor heuristics. It covers
    the native inflater path; existing low-level tests cover dynamic backrefs.
    """
    if len(data) > MAX_SOURCE_BYTES:
        raise ValueError("Fixture DEFLATE input exceeds its byte limit")
    output = bytearray()
    accumulator = count = 0

    def bits(value: int, width: int) -> None:
        nonlocal accumulator, count
        accumulator |= value << count
        count += width
        while count >= 8:
            output.append(accumulator & 255)
            accumulator >>= 8
            count -= 8

    bits(0b011, 3)  # BFINAL=1, BTYPE=01, least-significant bit first.
    for symbol in (*data, 256):
        if symbol <= 143:
            code, width = 0x30 + symbol, 8
        elif symbol <= 255:
            code, width = 0x190 + symbol - 144, 9
        else:
            code, width = symbol - 256, 7
        # Huffman codes are transmitted most-significant bit first.
        bits(int(f"{code:0{width}b}"[::-1], 2), width)
    if count:
        output.append(accumulator)
    result = bytes(output)
    reference = zlib.decompressobj(-15)
    decoded = reference.decompress(result, len(data) + 1)
    if decoded != data or not reference.eof or reference.unused_data or reference.unconsumed_tail:
        raise ValueError("Fixed DEFLATE reference decode disagrees")
    return result


def archive(parts: dict[str, bytes], method: int) -> bytes:
    """Contiguous regular entries with fixed DOS dates, CRCs and no extra fields."""
    check_parts(parts)
    if method not in (0, 8):
        raise ValueError("Only stored or raw-DEFLATE fixture entries are supported")
    local, central = bytearray(), bytearray()
    for name, data in parts.items():
        name_bytes = name.encode("utf-8")
        payload = fixed_deflate(data) if method == 8 else data
        crc, offset = zlib.crc32(data), len(local)
        local += struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0, method, 0, 33,
                             crc, len(payload), len(data), len(name_bytes), 0)
        local += name_bytes + payload
        central += struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 0x0314, 20, 0,
                               method, 0, 33, crc, len(payload), len(data),
                               len(name_bytes), 0, 0, 0, 0, 0o100644 << 16, offset)
        central += name_bytes
    end = struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(parts), len(parts),
                      len(central), len(local), 0)
    result = bytes(local + central + end)
    if len(result) > MAX_ARCHIVE_BYTES:
        raise ValueError("Generated fixture archive exceeds its byte limit")
    return result


def package(document: bytes, revision: int = 1) -> dict[str, bytes]:
    parts = {
        "[Content_Types].xml": f'''<Types xmlns="{C}">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>'''.encode(),
        "_rels/.rels": f'''<Relationships xmlns="{R}">
<Relationship Id="rDocument" Type="{O}/officeDocument" Target="word/document.xml"/>
<Relationship Id="rCore" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>'''.encode(),
        "docProps/core.xml": f'''<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Synthetic Test Author</dc:creator><dc:title>Fictional agency corpus</dc:title><cp:revision>{revision}</cp:revision></cp:coreProperties>'''.encode(),
        "word/_rels/document.xml.rels": f'''<Relationships xmlns="{R}">
<Relationship Id="rHeader" Type="{O}/header" Target="header1.xml"/>
<Relationship Id="rStyles" Type="{O}/styles" Target="styles.xml"/>
</Relationships>'''.encode(),
        "word/document.xml": document,
        "word/header1.xml": f'''<w:hdr xmlns:w="{W}"><w:p><w:r><w:t>FICTIONAL HEADER ONLY: not body evidence</w:t></w:r></w:p></w:hdr>'''.encode(),
        "word/styles.xml": f'''<w:styles xmlns:w="{W}"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>'''.encode(),
    }
    return parts


def reference_body(document: bytes) -> str:
    """Small independent fixture oracle, not a reimplementation of native policy.

    Accepted fixture bodies contain ordinary sequential paragraphs/table cells.
    Fail if authoring accidentally adds structures this reference does not model.
    """
    root = parse_xml(document)
    body = root.find(f"{{{W}}}body")
    if body is None:
        raise ValueError("Missing fixture body")
    allowed = {"body", "p", "r", "t", "br", "tab", "tbl", "tblPr", "tblW", "tr",
               "tc", "tcPr", "tcW", "sectPr", "pgSz", "headerReference"}
    for element in body.iter():
        if element.tag not in {f"{{{W}}}{name}" for name in allowed}:
            raise ValueError(f"Unsupported accepted fixture structure: {element.tag}")
    paragraphs = []
    for paragraph in body.iter(f"{{{W}}}p"):
        text = []
        for element in paragraph.iter():
            if element.tag == f"{{{W}}}t":
                text.append(element.text or "")
            elif element.tag == f"{{{W}}}br":
                text.append("\n")
            elif element.tag == f"{{{W}}}tab":
                text.append("\t")
        paragraphs.append("".join(text))
    return "\n\n".join(paragraphs)


def accepted(name: str, source: str, method: int = 0, revision: int = 1) -> dict:
    document = read_local(SOURCE / f"{source}.xml", MAX_SOURCE_BYTES)
    expected = read_local(SOURCE / f"{source}.expected.txt", MAX_SOURCE_BYTES)
    if reference_body(document).encode() != expected:
        raise ValueError(f"Authored expected text disagrees with XML in {source}")
    parts = package(document, revision)
    data = archive(parts, method)
    if reference_archive(data) != parts:
        raise ValueError(f"Independent ZIP decode disagrees in {name}")
    for member in parts.values():
        parse_xml(member)
    return {
        "name": name, "filename": f"{name}.docx", "source": source,
        "compressionMethod": method, "originalBase64": base64.b64encode(data).decode(),
        "originalSHA256": digest(data), "expectedText": expected.decode(),
        "extractedSHA256": digest(expected), "expectedLineCount": len(expected.decode().split("\n")),
        "expectedFailure": None,
    }


def rejected(name: str, parts: dict[str, bytes], failure: str, transform=None) -> dict:
    data = archive(parts, 0)
    if transform is not None:
        data = transform(data)
    return {"name": name, "filename": f"{name}.docx", "source": "brief-v1",
            "compressionMethod": 0, "originalBase64": base64.b64encode(data).decode(),
            "originalSHA256": digest(data), "expectedText": None,
            "extractedSHA256": None, "expectedLineCount": None, "expectedFailure": failure}


def corpus() -> dict:
    fixtures = [accepted("brief-v1", "brief-v1"),
                accepted("deliverables-v1", "deliverables-v1", method=8),
                accepted("production-memo-v1", "production-memo-v1"),
                accepted("deliverables-v2", "deliverables-v2", method=8),
                accepted("deliverables-v2-metadata-only", "deliverables-v2", method=8, revision=2)]
    base = package(read_local(SOURCE / "brief-v1.xml", MAX_SOURCE_BYTES))
    features = {
        "tracked-change": '<w:p><w:ins w:id="1" w:author="Synthetic Reviewer"><w:r><w:t>Unaccepted 60-second request</w:t></w:r></w:ins></w:p>',
        "calculated-field": '<w:p><w:fldSimple w:instr="DATE"><w:r><w:t>2030-04-08</w:t></w:r></w:fldSimple></w:p>',
        "content-control": '<w:sdt><w:sdtContent><w:p><w:r><w:t>Pending scope control</w:t></w:r></w:p></w:sdtContent></w:sdt>',
        "alternate-content": '<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><mc:Fallback><w:p><w:r><w:t>Alternate deliverable</w:t></w:r></w:p></mc:Fallback></mc:AlternateContent>',
    }
    for name, feature in features.items():
        parts = dict(base)
        parts["word/document.xml"] = parts["word/document.xml"].replace(b"<w:sectPr>", feature.encode() + b"<w:sectPr>")
        fixtures.append(rejected(name, parts, "unsupportedContent"))
    parts = dict(base)
    parts["word/header1.xml"] = f'<w:hdr xmlns:w="{W}"><w:p><w:ins w:id="1"><w:r><w:t>Hidden revised terms</w:t></w:r></w:ins></w:p></w:hdr>'.encode()
    fixtures.append(rejected("tracked-change-in-header", parts, "unsupportedContent"))
    parts = dict(base)
    parts["word/_rels/document.xml.rels"] = parts["word/_rels/document.xml.rels"].replace(b"</Relationships>", f'<Relationship Id="rExternal" Type="{O}/hyperlink" Target="https://example.invalid/synthetic-reference" TargetMode="External"/></Relationships>'.encode())
    fixtures.append(rejected("external-hyperlink", parts, "externalRelationship"))
    parts = dict(base)
    parts["word/document.xml"] = parts["word/document.xml"].replace(b"</w:document>", b"</w:wrong>")
    fixtures.append(rejected("malformed-document-xml", parts, "unsafeXML"))
    parts = dict(base)
    parts["word/header1.xml"] = b'<w:hdr xmlns:w="' + W.encode() + b'"><w:p>'
    fixtures.append(rejected("malformed-header-xml", parts, "unsafeXML"))
    # Flip one stored body byte, leaving CRC metadata and lengths intact.
    def corrupt_crc(data):
        anchor = b"NORTHSTAR STUDIO"
        position = data.index(anchor)
        return data[:position] + b"X" + data[position + 1:]
    fixtures.append(rejected("corrupt-document-crc", base, "unsafeArchive", corrupt_crc))
    fixtures.append(rejected("truncated-archive", base, "unsafeArchive", lambda data: data[:-12]))
    fixtures.append(rejected("trailing-archive-bytes", base, "unsafeArchive", lambda data: data + b"UNREVIEWED TRAILING RECORD"))
    original_v2, metadata_v2 = fixtures[3], fixtures[4]
    if original_v2["expectedText"] != metadata_v2["expectedText"] or original_v2["originalSHA256"] == metadata_v2["originalSHA256"]:
        raise ValueError("Metadata-only revision must retain text but change original bytes")
    first = reference_archive(base64.b64decode(original_v2["originalBase64"], validate=True))
    second = reference_archive(base64.b64decode(metadata_v2["originalBase64"], validate=True))
    if first.keys() != second.keys():
        raise ValueError("Metadata-only revision changed member names")
    if [name for name in first if first[name] != second[name]] != ["docProps/core.xml"]:
        raise ValueError("Metadata-only revision changed unexpected members")
    return {"version": 1, "synthetic": True, "fixtureCount": len(fixtures), "fixtures": fixtures}


def render_line_map(data: dict) -> bytes:
    sections = ["Synthetic agency corpus: exact extracted line coordinates",
                "Empty lines are intentional. Escaped rendering makes whitespace explicit.", ""]
    for fixture in data["fixtures"]:
        if fixture["expectedText"] is not None:
            sections += [fixture["filename"], f"Extracted SHA-256: {fixture['extractedSHA256']}"]
            sections += [f"{i:>3}: {json.dumps(line, ensure_ascii=False)}"
                         for i, line in enumerate(fixture["expectedText"].split("\n"), 1)]
            sections += [""]
    return "\n".join(sections).encode()


class CheckerSafetyTests(unittest.TestCase):
    """Test the fixture tool's bounds, not the application's import behavior."""

    def test_xml_rejects_dtd_and_entity_before_parsing(self):
        for payload in (
            b'<!DOCTYPE root SYSTEM "https://example.invalid/never-fetch"><root/>',
            b'<!DOCTYPE root [<!ENTITY local SYSTEM "file:///never-read">]><root>&local;</root>',
            b'<!DOCTYPE root [<!ENTITY x "123"><!ENTITY y "&x;&x;&x;">]><root>&y;</root>',
            b'<!ENTITY x "123"><root/>',
        ):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                parse_xml(payload)

    def test_xml_rejects_non_utf8_and_misplaced_declarations(self):
        for payload in (
            '<root/>'.encode('utf-16'), b'<root>\x00</root>',
            b'<?xml version="1.0" encoding="ISO-8859-1"?><root/>',
            b'<?xml version="1.0" encoding="UTF-7"?><root/>',
            b' <?xml version="1.0"?><root/>',
            b'<?xml ' + b' ' * 1024 + b'?><root/>',
        ):
            with self.subTest(payload=payload[:80]), self.assertRaises(ValueError):
                parse_xml(payload)

    def test_xml_depth_nodes_size_and_malformed_input_are_rejected(self):
        for payload in (
            b'<r>' * (MAX_XML_DEPTH + 1) + b'</r>' * (MAX_XML_DEPTH + 1),
            b'<r>' + b'<n/>' * MAX_XML_NODES + b'</r>',
            b'<r>' + b'x' * MAX_SOURCE_BYTES + b'</r>',
            b'<r><broken></r>',
        ):
            with self.subTest(size=len(payload)), self.assertRaises((ValueError, ET.ParseError)):
                parse_xml(payload)

    def test_xml_accepts_exact_unicode_and_xml_escapes(self):
        root = parse_xml(b'<?xml version="1.0" encoding="UTF-8"?><r>Cafe\xcc\x81 &amp; test</r>')
        self.assertEqual(root.text.encode(), b'Cafe\xcc\x81 & test')

    def test_file_reader_rejects_symlink_fifo_directory_and_oversize(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            regular, link, fifo = root / 'source.xml', root / 'link.xml', root / 'pipe.xml'
            regular.write_bytes(b'<r/>')
            link.symlink_to(regular)
            os.mkfifo(fifo)
            self.assertEqual(read_local(regular, 4), b'<r/>')
            for path, limit in ((regular, 3), (link, 4), (fifo, 4), (root, 4)):
                with self.subTest(path=path.name), self.assertRaises((ValueError, OSError)):
                    read_local(path, limit)

    def test_archive_generator_rejects_limits_methods_and_unsafe_names(self):
        invalid = [({'safe.xml': b'x' * (MAX_SOURCE_BYTES + 1)}, 0),
                   ({f'{i}.xml': b'x' for i in range(MAX_PARTS + 1)}, 0),
                   ({f'{i}.xml': b'x' * MAX_SOURCE_BYTES for i in range(3)}, 0),
                   ({'safe.xml': b'<r/>'}, 99)]
        invalid += [({name: b'<r/>'}, 0) for name in ('../x', '/x', 'a//x', 'a/./x', 'a\\x')]
        for parts, method in invalid:
            with self.subTest(names=list(parts)), self.assertRaises(ValueError):
                archive(parts, method)

    def test_reference_archive_rejects_declared_bomb_before_inflation(self):
        data = bytearray(archive({'body.xml': b'<r/>'}, 0))
        central = data.index(b'PK\x01\x02')
        struct.pack_into('<I', data, central + 24, MAX_SOURCE_BYTES + 1)
        with self.assertRaises(ValueError):
            reference_archive(bytes(data))
        with self.assertRaises(ValueError):
            reference_archive(b'x' * (MAX_ARCHIVE_BYTES + 1))

    def test_reference_archive_detects_corruption_and_decodes_both_methods(self):
        parts = {'body.xml': b'<r>SYNTHETIC TEST MATERIAL.</r>'}
        for method in (0, 8):
            data = archive(parts, method)
            self.assertEqual(reference_archive(data), parts)
        data = archive(parts, 0).replace(b'SYNTHETIC', b'XYNTHETIC', 1)
        with self.assertRaises(zipfile.BadZipFile):
            reference_archive(data)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate exact checked-in output; never write")
    parser.add_argument("--self-test", action="store_true", help="Run local checker safety tests; never write corpus output")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CheckerSafetyTests))
        if not result.wasSuccessful():
            return 1
        if not args.check:
            return 0
    data = corpus()
    expected = {ROOT / "corpus.json": (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode(),
                ROOT / "expected-lines.txt": render_line_map(data)}
    failures = []
    for path, content in expected.items():
        if len(content) > MAX_OUTPUT_BYTES:
            raise ValueError("Generated fixture output exceeds its byte limit")
        if args.check:
            if not path.is_file() or read_local(path, MAX_OUTPUT_BYTES) != content:
                failures.append(str(path.relative_to(ROOT.parent.parent.parent)))
        else:
            if path.is_symlink() or (path.exists() and not path.is_file()):
                raise ValueError("Refusing to overwrite nonregular fixture output")
            path.write_bytes(content)
    if failures:
        print("Fixture output differs; regenerate with python3 Scripts/check-campaign-agency-fixtures.py:", file=sys.stderr)
        print("\n".join(failures), file=sys.stderr)
        return 1
    accepted_count = sum(item["expectedFailure"] is None for item in data["fixtures"])
    print(f"{'Checked' if args.check else 'Generated'} {len(data['fixtures'])} synthetic DOCX fixtures "
          f"({accepted_count} accepted, {len(data['fixtures']) - accepted_count} rejection cases).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
