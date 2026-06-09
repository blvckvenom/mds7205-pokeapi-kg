// PASO DE ESCALA (Opciones A + C). Lleva el grafo de ~8k a ~130k nodos sin inventar datos:
//   A) nombres multilingues (11 idiomas) como nodos :Name colgados de su entidad
//   C) encuentros reificados como nodos-evento :Encounter (relacion n-aria reificada,
//      el patron que se vio en RDF para relaciones con mas de dos participantes)

// Constraints de las entidades nuevas (aceleran MATCH y evitan duplicados).
CREATE CONSTRAINT nature_id    IF NOT EXISTS FOR (n:Nature)      REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT version_id   IF NOT EXISTS FOR (n:Version)     REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT form_id      IF NOT EXISTS FOR (n:PokemonForm) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT encounter_id IF NOT EXISTS FOR (n:Encounter)   REQUIRE n.id IS UNIQUE;

// Entidades chicas extra (Nature 25, Version 49, PokemonForm 1578), para colgarles sus nombres.
LOAD CSV WITH HEADERS FROM 'file:///natures.csv' AS row
MERGE (n:Nature {id: toInteger(row.id)}) SET n.identifier = row.identifier;
LOAD CSV WITH HEADERS FROM 'file:///versions.csv' AS row
MERGE (v:Version {id: toInteger(row.id)}) SET v.identifier = row.identifier;
LOAD CSV WITH HEADERS FROM 'file:///pokemon_forms.csv' AS row
MERGE (f:PokemonForm {id: toInteger(row.id)}) SET f.identifier = row.identifier;

// --- A) Nodos :Name {text, lang}. lang = local_language_id (9=en, 7=es, 5=fr, 6=de, ...).
//        Una fila *_names = un nodo Name colgado de su entidad via HAS_NAME. ~52k nodos.
LOAD CSV WITH HEADERS FROM 'file:///pokemon_species_names.csv' AS row
MATCH (e:Species {id: toInteger(row.pokemon_species_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///move_names.csv' AS row
MATCH (e:Move {id: toInteger(row.move_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///item_names.csv' AS row
MATCH (e:Item {id: toInteger(row.item_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///ability_names.csv' AS row
MATCH (e:Ability {id: toInteger(row.ability_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///type_names.csv' AS row
MATCH (e:Type {id: toInteger(row.type_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///location_names.csv' AS row
MATCH (e:Location {id: toInteger(row.location_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///region_names.csv' AS row
MATCH (e:Region {id: toInteger(row.region_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///generation_names.csv' AS row
MATCH (e:Generation {id: toInteger(row.generation_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///nature_names.csv' AS row
MATCH (e:Nature {id: toInteger(row.nature_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///version_names.csv' AS row
MATCH (e:Version {id: toInteger(row.version_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.name, lang: toInteger(row.local_language_id)});

LOAD CSV WITH HEADERS FROM 'file:///pokemon_form_names.csv' AS row
WITH row WHERE row.form_name <> ''
MATCH (e:PokemonForm {id: toInteger(row.pokemon_form_id)})
CREATE (e)-[:HAS_NAME]->(:Name {text: row.form_name, lang: toInteger(row.local_language_id)});

// --- C) Encuentros reificados (69427 nodos-evento).
//        (Pokemon)-[:HAS_ENCOUNTER]->(:Encounter {nivel, version, slot})-[:AT_AREA]->(LocationArea).
LOAD CSV WITH HEADERS FROM 'file:///encounters.csv' AS row
CALL {
  WITH row
  MATCH (p:Pokemon {id: toInteger(row.pokemon_id)})
  MATCH (la:LocationArea {id: toInteger(row.location_area_id)})
  CREATE (p)-[:HAS_ENCOUNTER]->(:Encounter {
    id:        toInteger(row.id),
    version:   toInteger(row.version_id),
    slot:      toInteger(row.encounter_slot_id),
    min_level: toInteger(row.min_level),
    max_level: toInteger(row.max_level)
  })-[:AT_AREA]->(la)
} IN TRANSACTIONS OF 10000 ROWS;
