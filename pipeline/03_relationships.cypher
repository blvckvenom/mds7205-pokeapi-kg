// Carga de RELACIONES. Las tablas-puente N-a-N con columnas extra se vuelven
// relaciones CON PROPIEDADES (la ventaja nativa del property graph): CAN_LEARN,
// ENCOUNTERED_IN, HAS_TYPE, HAS_ABILITY, HAS_STAT cargan atributos en la arista.

// Pokemon -> Species
LOAD CSV WITH HEADERS FROM 'file:///pokemon.csv' AS row
MATCH (p:Pokemon {id: toInteger(row.id)})
MATCH (s:Species {id: toInteger(row.species_id)})
MERGE (p)-[:IS_SPECIES]->(s);

// Pokemon -[HAS_TYPE {slot}]-> Type (2115)
LOAD CSV WITH HEADERS FROM 'file:///pokemon_types.csv' AS row
MATCH (p:Pokemon {id: toInteger(row.pokemon_id)})
MATCH (t:Type {id: toInteger(row.type_id)})
MERGE (p)-[r:HAS_TYPE]->(t) SET r.slot = toInteger(row.slot);

// Pokemon -[HAS_ABILITY {is_hidden, slot}]-> Ability (2928)
LOAD CSV WITH HEADERS FROM 'file:///pokemon_abilities.csv' AS row
MATCH (p:Pokemon {id: toInteger(row.pokemon_id)})
MATCH (a:Ability {id: toInteger(row.ability_id)})
MERGE (p)-[r:HAS_ABILITY]->(a) SET r.is_hidden = row.is_hidden = '1', r.slot = toInteger(row.slot);

// Pokemon -[HAS_STAT {base_stat, effort}]-> Stat (8100)
LOAD CSV WITH HEADERS FROM 'file:///pokemon_stats.csv' AS row
MATCH (p:Pokemon {id: toInteger(row.pokemon_id)})
MATCH (s:Stat {id: toInteger(row.stat_id)})
MERGE (p)-[r:HAS_STAT]->(s) SET r.base_stat = toInteger(row.base_stat), r.effort = toInteger(row.effort);

// Move -> Type
LOAD CSV WITH HEADERS FROM 'file:///moves.csv' AS row
WITH row WHERE row.type_id <> ''
MATCH (m:Move {id: toInteger(row.id)})
MATCH (t:Type {id: toInteger(row.type_id)})
MERGE (m)-[:MOVE_TYPE]->(t);

// Species -[IN_EGG_GROUP]-> EggGroup (1304): tabla-puente que arma el grafo de crianza.
LOAD CSV WITH HEADERS FROM 'file:///pokemon_egg_groups.csv' AS row
MATCH (s:Species {id: toInteger(row.species_id)})
MATCH (e:EggGroup {id: toInteger(row.egg_group_id)})
MERGE (s)-[:IN_EGG_GROUP]->(e);

// Species -> Generation
LOAD CSV WITH HEADERS FROM 'file:///pokemon_species.csv' AS row
WITH row WHERE row.generation_id <> ''
MATCH (s:Species {id: toInteger(row.id)})
MATCH (g:Generation {id: toInteger(row.generation_id)})
MERGE (s)-[:IN_GENERATION]->(g);

// Location -> Region
LOAD CSV WITH HEADERS FROM 'file:///locations.csv' AS row
WITH row WHERE row.region_id <> ''
MATCH (l:Location {id: toInteger(row.id)})
MATCH (r:Region {id: toInteger(row.region_id)})
MERGE (l)-[:IN_REGION]->(r);

// LocationArea -> Location
LOAD CSV WITH HEADERS FROM 'file:///location_areas.csv' AS row
MATCH (la:LocationArea {id: toInteger(row.id)})
MATCH (l:Location {id: toInteger(row.location_id)})
MERGE (la)-[:IN_LOCATION]->(l);

// Type -[EFFECTIVENESS {factor}]-> Type (324): grafo dirigido completo de efectividad.
// factor 0=inmune, 50=poco eficaz, 100=neutro, 200=super eficaz.
LOAD CSV WITH HEADERS FROM 'file:///type_efficacy.csv' AS row
MATCH (a:Type {id: toInteger(row.damage_type_id)})
MATCH (b:Type {id: toInteger(row.target_type_id)})
MERGE (a)-[r:EFFECTIVENESS]->(b) SET r.factor = toInteger(row.damage_factor);

// Pokemon -[CAN_LEARN {level, method, version_group, ord}]-> Move (618511).
// CREATE (no MERGE) a proposito: es un MULTIGRAFO, el mismo par (pokemon, move) se repite
// con distinto nivel/metodo/version (75% de los pares son multi-arista). Batched con
// CALL IN TRANSACTIONS para no agotar memoria (cypher-shell 5.x lo corre en autocommit).
LOAD CSV WITH HEADERS FROM 'file:///pokemon_moves.csv' AS row
CALL {
  WITH row
  MATCH (p:Pokemon {id: toInteger(row.pokemon_id)})
  MATCH (m:Move {id: toInteger(row.move_id)})
  CREATE (p)-[:CAN_LEARN {
    level:         toInteger(row.level),
    method:        toInteger(row.pokemon_move_method_id),
    version_group: toInteger(row.version_group_id),
    ord:           toInteger(row.order)
  }]->(m)
} IN TRANSACTIONS OF 20000 ROWS;

// Los encuentros (69427) NO se cargan aca como arista directa: se reifican como nodos-evento
// :Encounter en 05_scale.cypher (relacion n-aria con sus atributos nivel/version/slot).
