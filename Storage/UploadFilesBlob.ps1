# Generate eight sample file types and upload them using the signed-in Azure CLI account.
# Usage: ./UploadFilesBlob.ps1 ACCOUNT CONTAINER [OUTPUT_DIR]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string]$Container,

    [Parameter(Position = 2)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command az -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required.'
}
$Python = Get-Command python3, python -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $Python) {
    throw 'Python 3 (python3 or python) is required.'
}

$Generator = @'
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

account, container = sys.argv[1:3]
directory = Path(sys.argv[3]) if len(sys.argv) == 4 else Path(tempfile.mkdtemp(prefix="blob-samples-"))
directory = directory.resolve()

def office_document(kind, part, content):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml",
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            f'<Override PartName="/{part}" ContentType="application/vnd.openxmlformats-officedocument.{kind}.main+xml"/>'
            + ('<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' if kind == "spreadsheetml.sheet" else "")
            + '</Types>')
        archive.writestr("_rels/.rels",
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="{part}"/>'
            '</Relationships>')
        archive.writestr(part, content)
        if kind == "spreadsheetml.sheet":
            archive.writestr("xl/_rels/workbook.xml.rels",
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
                '</Relationships>')
            archive.writestr("xl/worksheets/sheet1.xml",
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                '<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Dummy sample</t></is></c></row></sheetData>'
                '</worksheet>')
    return buffer.getvalue()

stream = b"BT /F1 12 Tf 72 720 Td (Dummy sample) Tj ET\n"
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"endstream",
]
pdf = bytearray(b"%PDF-1.4\n")
offsets = [0]
for number, obj in enumerate(objects, 1):
    offsets.append(len(pdf))
    pdf.extend(f"{number} 0 obj\n".encode() + obj + b"\nendobj\n")
xref = len(pdf)
pdf.extend(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode())
for offset in offsets[1:]:
    pdf.extend(f"{offset:010d} 00000 n \n".encode())
pdf.extend(f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())

files = {
    "docx": (office_document("wordprocessingml.document", "word/document.xml",
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body><w:p><w:r><w:t>Dummy sample</w:t></w:r></w:p></w:body></w:document>'),
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
    "xlsx": (office_document("spreadsheetml.sheet", "xl/workbook.xml",
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sample" sheetId="1" r:id="rId1"/></sheets></workbook>'),
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
    "pdf": (pdf, "application/pdf"),
    "txt": (b"Dummy sample\n", "text/plain"),
    "csv": (b"id,name\n1,Dummy sample\n", "text/csv"),
    "json": (b'{"id": 1, "name": "Dummy sample"}\n', "application/json"),
    "xml": (b'<?xml version="1.0"?><sample><id>1</id><name>Dummy sample</name></sample>\n', "application/xml"),
    "html": (b'<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Sample</title></head><body><p>Dummy sample</p></body></html>\n', "text/html"),
}

try:
    directory.mkdir(parents=True, exist_ok=True)
    for extension in files:
        path = directory / f"sample.{extension}"
        if path.exists() or path.is_symlink():
            sys.exit(f"Error: refusing to replace {path}. Choose a different output directory.")
    for extension, (content, _) in files.items():
        with (directory / f"sample.{extension}").open("xb") as output:
            output.write(content)
    print(f"Generated eight sample files in {directory}", flush=True)
    for extension, (_, content_type) in files.items():
        name = f"sample.{extension}"
        subprocess.run([
            "az", "storage", "blob", "upload",
            "--account-name", account, "--container-name", container,
            "--auth-mode", "login", "--name", name,
            "--file", str(directory / name), "--content-type", content_type,
            "--overwrite", "false", "--only-show-errors", "--output", "none",
        ], check=True)
        print(f"Uploaded {name}", flush=True)
except (OSError, subprocess.CalledProcessError) as error:
    sys.exit(f"Error: generation or upload failed: {error}. Local files are retained in {directory}.")
'@

$PythonArgs = @('-', $Account, $Container)
if ($PSBoundParameters.ContainsKey('OutputDir')) {
    $PythonArgs += $OutputDir
}
$Generator | & $Python.Source @PythonArgs
if ($LASTEXITCODE -ne 0) {
    throw "Sample generation or upload failed (exit code $LASTEXITCODE)."
}
