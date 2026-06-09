// Las 9 consultas del proyecto. Cada una explota una capacidad de grafo que un
// SELECT/JOIN no resuelve limpio: ciclos, paths variables, comunidades, centralidad.
// P4, P5 y P6 usan la libreria GDS (gds.*). El resto es Cypher puro.
// Correr una por una en el Browser (http://localhost:7474) o con cypher-shell.

// P1: ciclos en el type chart (triadas de super-efectividad). Ciclos dirigidos de largo 3.
MATCH path = (t:Type)-[:SUPER_EFFECTIVE*3]->(t)
RETURN [n IN nodes(path) | n.identifier] AS ciclo LIMIT 25;
// self-loops (tipos fuertes contra si mismos): MATCH (t:Type)-[:SUPER_EFFECTIVE]->(t) RETURN t.identifier;

// P2: linajes evolutivos completos por recursion, de la raiz a la hoja.
MATCH p = (raiz:Species)-[:EVOLVES_TO*]->(hoja:Species)
WHERE NOT (:Species)-[:EVOLVES_TO]->(raiz) AND NOT (hoja)-[:EVOLVES_TO]->(:Species)
RETURN [n IN nodes(p) | n.identifier] AS linaje, length(p) AS saltos
ORDER BY saltos DESC, linaje LIMIT 15;

// P3: condiciones de cada evolucion de Eevee, reificadas como nodos EvolutionCondition.
// Eevee tiene 8 evoluciones con triggers distintos; Leafeon y Glaceon traen mas de una
// condicion (piedra o cercania a una roca), por eso se colectan todas.
MATCH (eevee:Species {identifier:'eevee'})-[:EVOLVES_TO]->(evo:Species)-[:EVOLVES_VIA]->(c:EvolutionCondition)
RETURN evo.identifier AS evolucion,
       collect({trigger:c.trigger, nivel:c.min_level, item:c.trigger_item,
                hora:c.time_of_day, felicidad:c.min_happiness, lugar:c.location}) AS condiciones
ORDER BY evolucion;

// P4: comunidades de crianza con Louvain (GDS). El drop idempotente deja re-correr sin
// reiniciar la sesion (el catalogo GDS es global y sobrevive entre consultas).
CALL gds.graph.drop('breeding', false) YIELD graphName;
CALL gds.graph.project('breeding', 'Species', {COMPATIBLE: {orientation: 'UNDIRECTED'}});
CALL gds.louvain.stream('breeding') YIELD nodeId, communityId
RETURN communityId, count(*) AS tam,
       collect(gds.util.asNode(nodeId).identifier)[..6] AS muestra
ORDER BY tam DESC LIMIT 12;

// P5: especies puente por betweenness (GDS). Reusa la proyeccion 'breeding': corre P4 antes.
CALL gds.betweenness.stream('breeding') YIELD nodeId, score
RETURN gds.util.asNode(nodeId).identifier AS especie, round(score) AS score
ORDER BY score DESC LIMIT 15;

// P6: centralidad ofensiva de tipos con PageRank ponderado por factor de dano (GDS).
CALL gds.graph.drop('typechart', false) YIELD graphName;
CALL gds.graph.project('typechart', 'Type', {EFFECTIVENESS: {properties: 'factor'}});
CALL gds.pageRank.stream('typechart', {relationshipWeightProperty: 'factor'}) YIELD nodeId, score
RETURN gds.util.asNode(nodeId).identifier AS tipo, score ORDER BY score DESC LIMIT 10;

// P7: pares de pokemon con mas movimientos aprendibles en comun. CAN_LEARN es multigrafo (el
// mismo par pokemon-move se repite por version/metodo), asi que se deduplica a pares distintos
// antes del self-join; si no, enumera E^2 combinaciones y explota. El maximo real es ~164
// (mew/arceus, porque Mew aprende casi todo).
MATCH (p:Pokemon)-[:CAN_LEARN]->(m:Move)
WHERE p.is_default
WITH DISTINCT m, p
WITH m, collect(p) AS aprendices
UNWIND aprendices AS a UNWIND aprendices AS b
WITH a, b WHERE a.id < b.id
WITH a, b, count(*) AS comunes WHERE comunes > 120
RETURN a.identifier AS pokemon_a, b.identifier AS pokemon_b, comunes
ORDER BY comunes DESC LIMIT 20;

// P8: areas con mas biodiversidad (mas especies distintas), sobre los encuentros reificados.
// ~45% de las LocationArea no traen identifier propio, asi que se cae al nombre de la Location padre.
MATCH (la:LocationArea)<-[:AT_AREA]-(:Encounter)<-[:HAS_ENCOUNTER]-(p:Pokemon)-[:IS_SPECIES]->(s:Species)
OPTIONAL MATCH (la)-[:IN_LOCATION]->(loc:Location)
WITH la, loc, count(DISTINCT s) AS biodiversidad
RETURN coalesce(la.identifier, loc.identifier, toString(la.id)) AS area, biodiversidad
ORDER BY biodiversidad DESC LIMIT 15;

// P9: salto de stats totales en cada paso evolutivo (recursion mas agregacion sobre el camino).
MATCH (a:Species)-[:EVOLVES_TO]->(b:Species)
MATCH (pa:Pokemon {is_default:true})-[:IS_SPECIES]->(a)
MATCH (pb:Pokemon {is_default:true})-[:IS_SPECIES]->(b)
MATCH (pa)-[s1:HAS_STAT]->(st:Stat)<-[s2:HAS_STAT]-(pb)
WITH a.identifier AS de, b.identifier AS hacia, sum(s2.base_stat - s1.base_stat) AS delta
RETURN de, hacia, delta ORDER BY delta DESC LIMIT 20;
