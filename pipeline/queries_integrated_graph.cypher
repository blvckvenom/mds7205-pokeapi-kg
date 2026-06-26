// Consultas integradas PokeAPI + Smogon. Todas las explicaciones y comentarios están en español.

// A) Comunidades de crianza por egg groups
CALL gds.graph.drop('breeding', false) YIELD graphName;
CALL gds.graph.project('breeding', 'Species', {COMPATIBLE: {orientation:'UNDIRECTED'}});
CALL gds.louvain.stream('breeding') YIELD nodeId, communityId
RETURN communityId AS comunidad, count(*) AS tam,
       collect(gds.util.asNode(nodeId).identifier)[..8] AS muestra
ORDER BY tam DESC LIMIT 12;

// B) Especies puente en crianza (betweenness)
CALL gds.betweenness.stream('breeding') YIELD nodeId, score
RETURN gds.util.asNode(nodeId).identifier AS especie, score AS betweenness
ORDER BY betweenness DESC LIMIT 20;

// C) Similitud funcional por movepool (Jaccard)
MATCH (p:Pokemon {is_default:true})-[r:CAN_LEARN]->(m:Move)
MATCH (q:Pokemon {is_default:true})-[r2:CAN_LEARN]->(m2:Move)
WHERE p.id < q.id
WITH p, q,
     count(DISTINCT m) AS psize,
     count(DISTINCT m2) AS qsize,
     count(DISTINCT CASE WHEN m = m2 THEN m END) AS inter
WITH p.identifier AS poke_a, q.identifier AS poke_b, inter,
     (psize + qsize - inter) AS union_size,
     CASE WHEN (psize + qsize - inter) = 0 THEN 0.0 ELSE toFloat(inter) / (psize + qsize - inter) END AS jaccard
WHERE union_size > 0
RETURN poke_a, poke_b, inter, jaccard
ORDER BY jaccard DESC, inter DESC LIMIT 20;

// C2) Similitud funcional entre tipos distintos
MATCH (p:Pokemon {is_default:true})-[:HAS_TYPE]->(pt:Type)
WITH p, collect(DISTINCT pt.identifier) AS ptypes
MATCH (q:Pokemon {is_default:true})-[:HAS_TYPE]->(qt:Type)
WHERE q.id > p.id
WITH p, q, ptypes, collect(DISTINCT qt.identifier) AS qtypes
WHERE NONE(x IN ptypes WHERE x IN qtypes)
MATCH (p)-[:CAN_LEARN]->(m:Move)
MATCH (q)-[:CAN_LEARN]->(m2:Move)
WITH p, q, ptypes AS tipos_a, qtypes AS tipos_b,
     count(DISTINCT m) AS psize,
     count(DISTINCT m2) AS qsize,
     count(DISTINCT CASE WHEN m = m2 THEN m END) AS inter
WITH p.identifier AS poke_a, q.identifier AS poke_b, tipos_a, tipos_b, inter,
     (psize + qsize - inter) AS union_size,
     CASE WHEN (psize + qsize - inter) = 0 THEN 0.0 ELSE toFloat(inter) / (psize + qsize - inter) END AS jaccard
WHERE union_size > 0
RETURN poke_a, poke_b, tipos_a, tipos_b, inter, jaccard
ORDER BY jaccard DESC, inter DESC LIMIT 20;

// D) Centralidad ofensiva en el cuadro de tipos: PageRank ponderado
CALL gds.graph.drop('typechart', false) YIELD graphName;
CALL gds.graph.project('typechart', 'Type', {EFFECTIVENESS: {properties: 'factor'}});
CALL gds.pageRank.stream('typechart', {relationshipWeightProperty: 'factor'}) YIELD nodeId, score
RETURN gds.util.asNode(nodeId).identifier AS tipo, score
ORDER BY score DESC LIMIT 12;

// D2) Componentes fuertemente conectados en el grafo de efectividad
CALL gds.stronglyConnectedComponents.stream('typechart') YIELD nodeId, componentId
RETURN componentId, collect(gds.util.asNode(nodeId).identifier) AS tipos
ORDER BY size(tipos) DESC LIMIT 6;

// E) Comunidades competitivas reales en TEAMMATE_OF
CALL gds.graph.drop('teammates', false) YIELD graphName;
CALL gds.graph.project('teammates', 'Pokemon', {TEAMMATE_OF: {orientation:'UNDIRECTED'}});
CALL gds.louvain.stream('teammates') YIELD nodeId, communityId
RETURN communityId AS comunidad, size(collect(nodeId)) AS tam,
       collect(gds.util.asNode(nodeId).identifier)[..10] AS muestra
ORDER BY tam DESC LIMIT 8;

// F) Centralidad competitiva vs estructura base
CALL gds.pageRank.stream('teammates') YIELD nodeId, score AS pr_comp
WITH gds.util.asNode(nodeId) AS p, pr_comp
MATCH (p)-[:IS_SPECIES]->(sp:Species)
OPTIONAL MATCH (sp)-[:COMPATIBLE]-(x:Species)
WITH p.identifier AS pokemon, pr_comp, count(DISTINCT x) AS compat_degree
RETURN pokemon, pr_comp, compat_degree
ORDER BY pr_comp DESC LIMIT 20;

// G1) Meta-path: Pokemon -> Move -> Type -> Move -> Pokemon
MATCH p = (a:Pokemon {is_default:true})-[:CAN_LEARN]->(:Move)-[:MOVE_TYPE]->(:Type)<-[:MOVE_TYPE]-(:Move)<-[:CAN_LEARN]-(b:Pokemon {is_default:true})
WHERE a.identifier <> b.identifier
RETURN a.identifier AS origen, b.identifier AS destino, length(p) AS saltos
LIMIT 20;

// G2) Meta-path: Pokemon -> Species -> EggGroup -> Species -> Pokemon
MATCH p = (a:Pokemon {is_default:true})-[:IS_SPECIES]->(:Species)-[:IN_EGG_GROUP]->(:EggGroup)<-[:IN_EGG_GROUP]-(:Species)<-[:IS_SPECIES]-(b:Pokemon {is_default:true})
WHERE a.identifier <> b.identifier
RETURN a.identifier AS origen, b.identifier AS destino, length(p) AS saltos
LIMIT 20;

// H1) Preparación para link prediction: vecinos comunes en COMPATIBLE
MATCH (a:Species)-[:COMPATIBLE]-(b:Species)
WHERE id(a) < id(b)
RETURN a.identifier AS a, b.identifier AS b,
       size((a)-[:COMPATIBLE]-(:Species)-[:COMPATIBLE]-(b)) AS vecinos_comunes
ORDER BY vecinos_comunes DESC LIMIT 20;

// H2) Preparación para link prediction: grado de compatibilidad de especie
MATCH (s:Species)
RETURN s.identifier AS especie, size((s)-[:COMPATIBLE]-(:Species)) AS grado_compat
ORDER BY grado_compat DESC LIMIT 20;
