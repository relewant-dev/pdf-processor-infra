#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
EXAMPLE_FILE="${ROOT_DIR}/.env.example"

DEFAULT_QDRANT_STORAGE_DIR="/home/administrator/data/qdrant/storage"
DEFAULT_OLLAMA_DATA_DIR="/home/administrator/data/ollama"

QDRANT_STORAGE_DIR="${1:-${DEFAULT_QDRANT_STORAGE_DIR}}"
OLLAMA_DATA_DIR="${2:-${DEFAULT_OLLAMA_DATA_DIR}}"

if [[ -f "${ENV_FILE}" ]]; then
  cp "${ENV_FILE}" "${ENV_FILE}.bak"
else
  cp "${EXAMPLE_FILE}" "${ENV_FILE}"
fi

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

awk -v qdrant="${QDRANT_STORAGE_DIR}" -v ollama="${OLLAMA_DATA_DIR}" '
  BEGIN { seen_qdrant = 0; seen_ollama = 0 }
  /^QDRANT_STORAGE_DIR=/ { print "QDRANT_STORAGE_DIR=" qdrant; seen_qdrant = 1; next }
  /^OLLAMA_DATA_DIR=/ { print "OLLAMA_DATA_DIR=" ollama; seen_ollama = 1; next }
  { print }
  END {
    if (!seen_qdrant) print "QDRANT_STORAGE_DIR=" qdrant
    if (!seen_ollama) print "OLLAMA_DATA_DIR=" ollama
  }
' "${ENV_FILE}" > "${tmp_file}"

mv "${tmp_file}" "${ENV_FILE}"
trap - EXIT

printf 'Configured %s\n' "${ENV_FILE}"
printf 'QDRANT_STORAGE_DIR=%s\n' "${QDRANT_STORAGE_DIR}"
printf 'OLLAMA_DATA_DIR=%s\n' "${OLLAMA_DATA_DIR}"
