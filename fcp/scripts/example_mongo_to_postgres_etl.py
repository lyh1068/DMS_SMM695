from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Any, Dict, Iterable, Optional, Tuple

SCRIPT_DIR = Path(__file__).resolve().parent
FCP_ROOT = SCRIPT_DIR.parent
DEFAULT_MONGO_URI = "mongodb://mongo:mongo@localhost:27017/?authSource=admin"
DEFAULT_SCHEMA_SQL = FCP_ROOT / "sql" / "postgres_dim_package_example.sql"


def normalize_package_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower().strip()


def build_dim_package_row(document: Dict[str, Any]) -> Tuple[str, Optional[str]]:
    info = document.get("info") or {}
    package_name = info.get("name") or document.get("package_name")
    if not isinstance(package_name, str) or not package_name.strip():
        raise ValueError("PyPI document is missing a package name")

    author_email = info.get("author_email")
    if author_email is not None and not isinstance(author_email, str):
        author_email = str(author_email)
    return str(package_name), author_email


def ensure_schema(connection: Any, schema_sql_path: Path) -> None:
    sql_text = schema_sql_path.read_text(encoding="utf-8")
    with connection.cursor() as cursor:
        cursor.execute(sql_text)
    connection.commit()


def truncate_dim_package(connection: Any, schema_name: str = "ssc") -> None:
    with connection.cursor() as cursor:
        cursor.execute(f"TRUNCATE TABLE {schema_name}.dim_package RESTART IDENTITY CASCADE")
    connection.commit()


def upsert_dim_package(
    connection: Any,
    package_name: str,
    author_email: Optional[str],
    *,
    schema_name: str = "ssc",
) -> int:
    normalized_name = normalize_package_name(package_name)
    with connection.cursor() as cursor:
        cursor.execute(
            f"""
            INSERT INTO {schema_name}.dim_package (
                package_name,
                normalized_package_name,
                author_email
            )
            VALUES (%s, %s, %s)
            ON CONFLICT (normalized_package_name)
            DO UPDATE SET
                package_name = EXCLUDED.package_name,
                author_email = EXCLUDED.author_email
            RETURNING package_key
            """,
            (package_name, normalized_name, author_email),
        )
        package_key = int(cursor.fetchone()[0])
    connection.commit()
    return package_key


def run_example_etl(
    pypi_documents: Iterable[Dict[str, Any]],
    connection: Any,
    *,
    schema_sql_path: Optional[Path] = None,
    truncate_target: bool = False,
    schema_name: str = "ssc",
) -> None:
    if schema_sql_path is not None:
        ensure_schema(connection, schema_sql_path)
    if truncate_target:
        truncate_dim_package(connection, schema_name)

    for document in pypi_documents:
        package_name, author_email = build_dim_package_row(document)
        upsert_dim_package(connection, package_name, author_email, schema_name=schema_name)


def main() -> int:
    parser = argparse.ArgumentParser(description="Example ETL from MongoDB raw package documents into a PostgreSQL dim_package table")
    parser.add_argument("--mongo-uri", default=DEFAULT_MONGO_URI)
    parser.add_argument("--mongo-database", default="ssc_course_project")
    parser.add_argument("--pypi-collection", default="raw_pypi_package")
    parser.add_argument("--postgres-dsn", default="postgresql://postgres:postgres@localhost:5432/ssc_course_project")
    parser.add_argument(
        "--schema-sql",
        default=str(DEFAULT_SCHEMA_SQL),
    )
    parser.add_argument("--truncate-target", action="store_true")
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    from pymongo import MongoClient
    import psycopg

    mongo_client = MongoClient(args.mongo_uri)
    mongo_database = mongo_client[args.mongo_database]
    pypi_cursor = mongo_database[args.pypi_collection].find({})

    if args.limit is not None:
        pypi_cursor = pypi_cursor.limit(args.limit)

    with psycopg.connect(args.postgres_dsn) as connection:
        run_example_etl(
            pypi_cursor,
            connection,
            schema_sql_path=Path(args.schema_sql),
            truncate_target=args.truncate_target,
        )

    print("Loaded MongoDB raw package documents into the PostgreSQL dim_package example table")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
