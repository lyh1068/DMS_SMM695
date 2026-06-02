from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Dict, Iterator

SCRIPT_DIR = Path(__file__).resolve().parent
FCP_ROOT = SCRIPT_DIR.parent
DEFAULT_MONGO_URI = "mongodb://mongo:mongo@localhost:27017/?authSource=admin"
DEFAULT_PYPI_JSON = FCP_ROOT / "data" / "pypi_items.json"
DEFAULT_OSV_JSON = FCP_ROOT / "data" / "vulnerabilities.json"


def normalize_package_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower().strip()


def iter_json_array(path: Path, *, chunk_size: int = 1024 * 128) -> Iterator[Dict[str, Any]]:
    decoder = json.JSONDecoder()
    buffer = ""
    position = 0
    in_array = False

    with path.open("r", encoding="utf-8") as handle:
        while True:
            chunk = handle.read(chunk_size)
            eof = chunk == ""
            if chunk:
                buffer += chunk

            while True:
                while position < len(buffer) and buffer[position].isspace():
                    position += 1

                if not in_array:
                    if position >= len(buffer):
                        break
                    if buffer[position] != "[":
                        raise ValueError(f"Expected top-level JSON array in {path}")
                    in_array = True
                    position += 1
                    continue

                while position < len(buffer) and buffer[position].isspace():
                    position += 1

                if position >= len(buffer):
                    break

                if buffer[position] == ",":
                    position += 1
                    continue

                if buffer[position] == "]":
                    return

                try:
                    item, end_position = decoder.raw_decode(buffer, position)
                except json.JSONDecodeError:
                    if eof:
                        raise
                    break

                if not isinstance(item, dict):
                    raise ValueError(f"Expected object items inside top-level array in {path}")
                yield item
                position = end_position

            if eof:
                break

            if position > 0:
                buffer = buffer[position:]
                position = 0


def prepare_pypi_document(document: Dict[str, Any]) -> Dict[str, Any]:
    info = document.get("info") or {}
    package_name = info.get("name") or document.get("package_name")
    if not isinstance(package_name, str) or not package_name.strip():
        raise ValueError("PyPI document is missing info.name")

    prepared = dict(document)
    prepared["_id"] = normalize_package_name(package_name)
    prepared["package_name"] = package_name
    return prepared


def prepare_osv_document(document: Dict[str, Any]) -> Dict[str, Any]:
    package_name = document.get("package")
    if not isinstance(package_name, str) or not package_name.strip():
        raise ValueError("OSV document is missing package")

    prepared = dict(document)
    prepared["_id"] = f"{str(document.get('source') or 'osv')}:{normalize_package_name(package_name)}"
    return prepared


def load_array_file(path: Path, collection: Any, prepare_document) -> int:
    total = 0
    for document in iter_json_array(path):
        prepared = prepare_document(document)
        collection.replace_one({"_id": prepared["_id"]}, prepared, upsert=True)
        total += 1
    return total


def main() -> int:
    parser = argparse.ArgumentParser(description="Load released JSON arrays into raw MongoDB collections")
    parser.add_argument("--mongo-uri", default=DEFAULT_MONGO_URI)
    parser.add_argument("--database", default="ssc_course_project")
    parser.add_argument("--pypi-collection", default="raw_pypi_package")
    parser.add_argument("--osv-collection", default="raw_osv_package")
    parser.add_argument("--pypi-json", default=str(DEFAULT_PYPI_JSON))
    parser.add_argument("--osv-json", default=str(DEFAULT_OSV_JSON))
    parser.add_argument("--drop-existing", action="store_true")
    args = parser.parse_args()

    from pymongo import MongoClient

    client = MongoClient(args.mongo_uri)
    database = client[args.database]
    pypi_collection = database[args.pypi_collection]
    osv_collection = database[args.osv_collection]

    if args.drop_existing:
        pypi_collection.delete_many({})
        osv_collection.delete_many({})

    pypi_count = load_array_file(Path(args.pypi_json), pypi_collection, prepare_pypi_document)
    osv_count = load_array_file(Path(args.osv_json), osv_collection, prepare_osv_document)

    print(f"Loaded {pypi_count} PyPI package documents into {args.database}.{args.pypi_collection}")
    print(f"Loaded {osv_count} OSV package documents into {args.database}.{args.osv_collection}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
