// Constraints de unicidad por label. Crean un indice que acelera los MATCH de la
// carga de relaciones y evitan nodos duplicados al hacer MERGE.
CREATE CONSTRAINT pokemon_id      IF NOT EXISTS FOR (n:Pokemon)      REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT species_id      IF NOT EXISTS FOR (n:Species)      REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT move_id         IF NOT EXISTS FOR (n:Move)         REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT ability_id      IF NOT EXISTS FOR (n:Ability)      REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT type_id         IF NOT EXISTS FOR (n:Type)         REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT item_id         IF NOT EXISTS FOR (n:Item)         REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT egggroup_id     IF NOT EXISTS FOR (n:EggGroup)     REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT generation_id   IF NOT EXISTS FOR (n:Generation)   REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT region_id       IF NOT EXISTS FOR (n:Region)       REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT location_id     IF NOT EXISTS FOR (n:Location)     REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT locationarea_id IF NOT EXISTS FOR (n:LocationArea) REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT stat_id         IF NOT EXISTS FOR (n:Stat)         REQUIRE n.id IS UNIQUE;
CREATE CONSTRAINT evolcondition_id IF NOT EXISTS FOR (n:EvolutionCondition) REQUIRE n.id IS UNIQUE;
