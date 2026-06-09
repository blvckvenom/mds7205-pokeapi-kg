// Relaciones DERIVADAS: materializan las tres estructuras "interesantes" del grafo.

// 1) EVOLVES_TO: jerarquia recursiva. La self-FK evolves_from apunta al padre;
//    creamos la arista padre -> hijo.
MATCH (child:Species) WHERE child.evolves_from IS NOT NULL
MATCH (parent:Species {id: child.evolves_from})
MERGE (parent)-[:EVOLVES_TO]->(child);

// Condiciones de evolucion REIFICADAS: cada fila de pokemon_evolution es un nodo
// :EvolutionCondition colgado del hijo via EVOLVES_VIA. 42 especies tienen mas de una
// condicion (triggers alternativos; ej. Eevee evoluciona a Leafeon por piedra o por cercania
// a una roca), asi que reificar evita perderlas: en una sola arista solo sobreviviria la ultima.
LOAD CSV WITH HEADERS FROM 'file:///pokemon_evolution.csv' AS row
MATCH (child:Species {id: toInteger(row.evolved_species_id)})
CREATE (child)-[:EVOLVES_VIA]->(c:EvolutionCondition {id: toInteger(row.id)})
SET c.trigger       = toInteger(row.evolution_trigger_id),
    c.min_level     = CASE row.minimum_level     WHEN '' THEN null ELSE toInteger(row.minimum_level)     END,
    c.trigger_item  = CASE row.trigger_item_id   WHEN '' THEN null ELSE toInteger(row.trigger_item_id)   END,
    c.held_item     = CASE row.held_item_id      WHEN '' THEN null ELSE toInteger(row.held_item_id)      END,
    c.time_of_day   = CASE row.time_of_day       WHEN '' THEN null ELSE row.time_of_day                  END,
    c.known_move    = CASE row.known_move_id      WHEN '' THEN null ELSE toInteger(row.known_move_id)     END,
    c.min_happiness = CASE row.minimum_happiness  WHEN '' THEN null ELSE toInteger(row.minimum_happiness) END,
    c.gender        = CASE row.gender_id          WHEN '' THEN null ELSE toInteger(row.gender_id)         END,
    c.location      = CASE row.location_id        WHEN '' THEN null ELSE toInteger(row.location_id)       END;

// 2) SUPER_EFFECTIVE: subgrafo dirigido de ventaja de tipo (factor 200). Tiene CICLOS
//    (ej. fighting->dark->psychic->fighting) y self-loops (dragon, ghost).
MATCH (a:Type)-[r:EFFECTIVENESS]->(b:Type) WHERE r.factor = 200
MERGE (a)-[:SUPER_EFFECTIVE]->(b);

// 3) COMPATIBLE: grafo N-a-N de crianza. Dos especies son compatibles si comparten un
//    egg group, excluyendo ditto (13) y no-eggs (15) que distorsionan comunidad/centralidad.
//    Arista no dirigida representada como un solo COMPATIBLE con id(a) < id(b).
//    Necesaria para las proyecciones GDS de P4 y P5.
MATCH (a:Species)-[:IN_EGG_GROUP]->(g:EggGroup)<-[:IN_EGG_GROUP]-(b:Species)
WHERE id(a) < id(b) AND NOT g.id IN [13, 15]
MERGE (a)-[:COMPATIBLE]->(b);
