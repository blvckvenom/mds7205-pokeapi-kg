#!/usr/bin/env bash
# Pipeline de carga PokeAPI -> Neo4j (property graph) para el proyecto MDS7205.
# Levanta Neo4j 5 en Docker, monta los CSV del clon como import dir, corre los .cypher
# en orden y verifica. Idempotente: borra y recrea el contenedor en cada corrida.
#
#   bash load_all.sh
#
# UI: http://localhost:7474 (sin auth)  ·  bolt: localhost:7687
set -euo pipefail

PIPE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$PIPE")"
CSV="$ROOT/pokeapi/data/v2/csv"
NAME="neo4j-pokeapi"

# Solo las tablas que carga el pipeline (las demas del repo no se usan). Se copian al
# import dir interno del contenedor con docker cp despues de arrancar: asi se evita que
# el entrypoint de Neo4j (que hace chown del import dir) toque archivos del host.
TABLES=(pokemon pokemon_species moves abilities types items egg_groups generations
  regions locations location_areas stats pokemon_types pokemon_abilities pokemon_stats
  pokemon_moves encounters pokemon_egg_groups type_efficacy pokemon_evolution
  natures versions pokemon_forms
  pokemon_species_names move_names item_names ability_names type_names location_names
  region_names generation_names nature_names version_names pokemon_form_names)

echo ">> limpiando contenedor previo (si existe)"
docker rm -f -v "$NAME" >/dev/null 2>&1 || true   # -v se lleva el volumen anonimo del rebuild anterior

echo ">> levantando Neo4j 5 + GDS (puertos 7474 UI / 7687 bolt)"
docker run -d --name "$NAME" \
  -p 7474:7474 -p 7687:7687 \
  -e NEO4J_AUTH=none \
  -e NEO4J_PLUGINS='["graph-data-science"]' \
  -e NEO4J_dbms_security_procedures_unrestricted='gds.*' \
  -e NEO4J_dbms_security_procedures_allowlist='gds.*' \
  -e NEO4J_server_memory_heap_max__size=2G \
  -e NEO4J_server_memory_pagecache_size=1G \
  -v "$PIPE":/pipeline:ro \
  neo4j:5 >/dev/null

echo ">> esperando a que Neo4j acepte conexiones..."
for i in $(seq 1 60); do
  if docker exec "$NAME" cypher-shell "RETURN 1;" >/dev/null 2>&1; then
    echo "   listo (intento $i)"; ok=1; break
  fi
  sleep 3
done
[ "${ok:-}" = 1 ] || { echo "ERROR: Neo4j no respondio"; docker logs --tail 40 "$NAME"; exit 1; }

echo ">> copiando CSV usados al import dir del contenedor"
for t in "${TABLES[@]}"; do docker cp "$CSV/$t.csv" "$NAME:/var/lib/neo4j/import/$t.csv"; done

run() { echo ">> $1"; docker exec -i "$NAME" cypher-shell --format plain -f "/pipeline/$1"; }

run 01_constraints.cypher
run 02_nodes.cypher
run 03_relationships.cypher
run 04_derived.cypher
run 05_scale.cypher

echo ">> verificacion"
docker exec -i "$NAME" cypher-shell --format plain -f /pipeline/verify.cypher

echo ">> LISTO. Consultas en pipeline/queries.cypher (Browser http://localhost:7474, sin auth)"
