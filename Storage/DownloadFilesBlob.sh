#!/bin/sh
# List and download blobs; requires Python 3 and a container SAS URL with Read/List permissions.
# Usage: AZURE_STORAGE_CONTAINER_URL='https://ACCOUNT.blob.core.windows.net/CONTAINER?SAS' sh DownloadFilesBlob.sh
# export AZURE_STORAGE_CONTAINER_URL='https://ACCOUNT.blob.core.windows.net/CONTAINER?YOUR_SAS_TOKEN'
# sh DownloadFilesBlob.sh
# Downloads go to ./downloads (override with AZURE_STORAGE_DOWNLOAD_DIR).
# Existing matching files are replaced only after a successful download.
set -eu

: "${AZURE_STORAGE_CONTAINER_URL:?Set AZURE_STORAGE_CONTAINER_URL to your container SAS URL}"
export AZURE_STORAGE_CONTAINER_URL

python3 - <<'PY'
import os
from pathlib import Path
import shutil
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

url = urllib.parse.urlsplit(os.environ["AZURE_STORAGE_CONTAINER_URL"])
if url.scheme != "https" or not url.netloc or not url.path.strip("/"):
    sys.exit("Error: provide an HTTPS container SAS URL.")

query = [
    (key, value)
    for key, value in urllib.parse.parse_qsl(url.query, keep_blank_values=True)
    if key not in {"restype", "comp", "marker"}
]
download_query = urllib.parse.urlencode(query)
query.extend([("restype", "container"), ("comp", "list")])
download_dir = Path(os.environ.get("AZURE_STORAGE_DOWNLOAD_DIR", "downloads")).resolve()
marker = ""

try:
    while True:
        page_query = query + ([("marker", marker)] if marker else [])
        page_url = urllib.parse.urlunsplit(
            url._replace(query=urllib.parse.urlencode(page_query), fragment="")
        )
        with urllib.request.urlopen(page_url, timeout=60) as response:
            root = ET.parse(response).getroot()
        if root.tag != "EnumerationResults":
            sys.exit("Error: Azure did not return a blob listing.")
        for blob in root.findall("./Blobs/Blob"):
            name = blob.findtext("Name")
            if name is None:
                sys.exit("Error: Azure returned a blob without a name.")
            print(name, flush=True)
            if "\\" in name or any(part in {"", ".", ".."} for part in name.split("/")):
                sys.exit(f"Error: unsafe blob download path: {name!r}.")
            target = (download_dir / name).resolve()
            try:
                target.relative_to(download_dir)
            except ValueError:
                sys.exit(f"Error: blob path escapes the download directory: {name!r}.")
            target.parent.mkdir(parents=True, exist_ok=True)
            blob_url = urllib.parse.urlunsplit(
                url._replace(
                    path=url.path.rstrip("/") + "/" + urllib.parse.quote(name, safe="/"),
                    query=download_query,
                    fragment="",
                )
            )
            temporary_path = None
            try:
                with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output:
                    temporary_path = Path(output.name)
                    with urllib.request.urlopen(blob_url, timeout=60) as response:
                        shutil.copyfileobj(response, output)
                os.replace(temporary_path, target)
            finally:
                if temporary_path is not None:
                    temporary_path.unlink(missing_ok=True)
        marker = root.findtext("NextMarker") or ""
        if not marker:
            break
except urllib.error.HTTPError as error:
    sys.exit(
        f"Error: Azure returned HTTP {error.code}. "
        "Check the SAS signature, validity period, and Read/List (rl) permissions."
    )
except (urllib.error.URLError, OSError, ET.ParseError) as error:
    sys.exit(f"Error: could not list or download blobs ({type(error).__name__}).")
PY
