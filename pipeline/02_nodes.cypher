// Carga de NODOS (entidades). Una tabla CSV = un label. MERGE por id para idempotencia.
// Las columnas escalares quedan como propiedades del nodo; las FK se vuelven relaciones
// en 03_relationships.cypher. Los CSV se leen desde el import dir montado (file:///).

// Pokemon (1350): incluye formas; is_default marca la forma canonica de la especie.
LOAD CSV WITH HEADERS FROM 'file:///pokemon.csv' AS row
MERGE (p:Pokemon {id: toInteger(row.id)})
SET p.identifier      = row.identifier,
    p.species_id      = toInteger(row.species_id),
    p.height          = toInteger(row.height),
    p.weight          = toInteger(row.weight),
    p.base_experience = toInteger(row.base_experience),
    p.is_default      = row.is_default = '1';

// Species (1025): evolves_from es la self-FK que arma la jerarquia recursiva de evolucion.
LOAD CSV WITH HEADERS FROM 'file:///pokemon_species.csv' AS row
MERGE (s:Species {id: toInteger(row.id)})
SET s.identifier         = row.identifier,
    s.generation_id      = toInteger(row.generation_id),
    s.evolution_chain_id = toInteger(row.evolution_chain_id),
    s.gender_rate        = toInteger(row.gender_rate),
    s.capture_rate       = toInteger(row.capture_rate),
    s.base_happiness     = toInteger(row.base_happiness),
    s.is_baby            = row.is_baby = '1',
    s.is_legendary       = row.is_legendary = '1',
    s.is_mythical        = row.is_mythical = '1',
    s.evolves_from       = CASE row.evolves_from_species_id WHEN '' THEN null
                           ELSE toInteger(row.evolves_from_species_id) END;

// Move (937)
LOAD CSV WITH HEADERS FROM 'file:///moves.csv' AS row
MERGE (m:Move {id: toInteger(row.id)})
SET m.identifier      = row.identifier,
    m.generation_id   = toInteger(row.generation_id),
    m.type_id         = toInteger(row.type_id),
    m.power           = toInteger(row.power),
    m.pp              = toInteger(row.pp),
    m.accuracy        = toInteger(row.accuracy),
    m.priority        = toInteger(row.priority),
    m.damage_class_id = toInteger(row.damage_class_id);

// Ability (371)
LOAD CSV WITH HEADERS FROM 'file:///abilities.csv' AS row
MERGE (a:Ability {id: toInteger(row.id)})
SET a.identifier = row.identifier, a.generation_id = toInteger(row.generation_id);

// Type (21: 19 de batalla incl. stellar, mas unknown y shadow)
LOAD CSV WITH HEADERS FROM 'file:///types.csv' AS row
MERGE (t:Type {id: toInteger(row.id)})
SET t.identifier = row.identifier, t.generation_id = toInteger(row.generation_id);

// Item (2176)
LOAD CSV WITH HEADERS FROM 'file:///items.csv' AS row
MERGE (i:Item {id: toInteger(row.id)})
SET i.identifier = row.identifier, i.cost = toInteger(row.cost), i.category_id = toInteger(row.category_id);

// EggGroup (15): id 13 = ditto (comodin), id 15 = no-eggs (no cria).
LOAD CSV WITH HEADERS FROM 'file:///egg_groups.csv' AS row
MERGE (e:EggGroup {id: toInteger(row.id)}) SET e.identifier = row.identifier;

// Generation (9)
LOAD CSV WITH HEADERS FROM 'file:///generations.csv' AS row
MERGE (g:Generation {id: toInteger(row.id)})
SET g.identifier = row.identifier, g.main_region_id = toInteger(row.main_region_id);

// Region (11)
LOAD CSV WITH HEADERS FROM 'file:///regions.csv' AS row
MERGE (r:Region {id: toInteger(row.id)}) SET r.identifier = row.identifier;

// Location (1096)
LOAD CSV WITH HEADERS FROM 'file:///locations.csv' AS row
MERGE (l:Location {id: toInteger(row.id)})
SET l.identifier = row.identifier, l.region_id = toInteger(row.region_id);

// LocationArea (1246)
LOAD CSV WITH HEADERS FROM 'file:///location_areas.csv' AS row
MERGE (la:LocationArea {id: toInteger(row.id)})
SET la.identifier = row.identifier, la.location_id = toInteger(row.location_id);

// Stat (9: los 6 de batalla, accuracy, evasion y special legacy de gen 1)
LOAD CSV WITH HEADERS FROM 'file:///stats.csv' AS row
MERGE (s:Stat {id: toInteger(row.id)}) SET s.identifier = row.identifier;
