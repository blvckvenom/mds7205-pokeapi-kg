// Verificacion post-carga: conteos y las tres estructuras interesantes.
MATCH (n) UNWIND labels(n) AS l RETURN l AS label, count(*) AS nodos ORDER BY nodos DESC;

MATCH ()-[r]->() RETURN type(r) AS relacion, count(*) AS aristas ORDER BY aristas DESC;

// Estructura 1: ciclo dirigido de largo 3 en el type chart.
MATCH p=(t:Type)-[:SUPER_EFFECTIVE*3]->(t)
RETURN [x IN nodes(p) | x.identifier] AS ciclo_tipos LIMIT 1;

// Estructura 1b: self-loops (tipos fuertes contra si mismos).
MATCH (t:Type)-[:SUPER_EFFECTIVE]->(t) RETURN collect(t.identifier) AS self_loops;

// Estructura 2: vecinos de crianza de pikachu sobre el grafo COMPATIBLE (el mismo que usan P4/P5).
MATCH (s:Species {identifier:'pikachu'})-[:COMPATIBLE]-(o:Species)
RETURN count(DISTINCT o) AS vecinos_crianza_pikachu;

// Estructura 3: maxima profundidad de cadena evolutiva (en saltos).
MATCH p=(r:Species)-[:EVOLVES_TO*]->(h:Species)
WHERE NOT (:Species)-[:EVOLVES_TO]->(r) AND NOT (h)-[:EVOLVES_TO]->(:Species)
RETURN max(length(p)) AS max_saltos_evolucion;
