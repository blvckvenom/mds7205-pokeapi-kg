"""Experimento ML integrado sin fuga de información.

Este script predice relaciones `TEAMMATE_OF` usando solo atributos propios de
los Pokémon y relaciones no derivadas directamente del uso competitivo. Guarda
un resumen reproducible en `analysis/ml_teammate_safe_results.json`.
"""
import json
import os

import numpy as np
import pandas as pd
from neo4j import GraphDatabase
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.model_selection import train_test_split


ROOT = os.path.dirname(__file__)
IMG = os.path.join(ROOT, "img")
RESULTS = os.path.join(ROOT, "ml_teammate_safe_results.json")
os.makedirs(IMG, exist_ok=True)

driver = GraphDatabase.driver("bolt://localhost:7687", auth=None)


def df(query):
    with driver.session() as session:
        return pd.DataFrame([r.data() for r in session.run(query)])


def jaccard(a, b):
    a = set(a)
    b = set(b)
    if not a and not b:
        return 0.0
    return len(a & b) / len(a | b)


def componentes_evolutivos():
    especies = df("""
MATCH (s:Species)
RETURN id(s) AS sid
""")
    padres = {int(r.sid): int(r.sid) for r in especies.itertuples()}

    def find(x):
        while padres[x] != x:
            padres[x] = padres[padres[x]]
            x = padres[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            padres[rb] = ra

    relaciones = df("""
MATCH (a:Species)-[:EVOLVES_TO]-(b:Species)
RETURN id(a) AS a, id(b) AS b
""")
    for r in relaciones.itertuples():
        union(int(r.a), int(r.b))
    return {sid: find(sid) for sid in padres}


def cargar_atributos():
    stats_raw = df("""
MATCH (p:Pokemon {is_default:true})-[r:HAS_STAT]->(s:Stat)
RETURN p.id AS id, p.identifier AS pokemon, s.identifier AS stat, r.base_stat AS valor
""")
    stats = stats_raw.pivot_table(index="id", columns="stat", values="valor", fill_value=0)
    stats["bst"] = stats.sum(axis=1)
    nombres = stats_raw.drop_duplicates("id").set_index("id")["pokemon"].to_dict()

    tipos = df("""
MATCH (p:Pokemon {is_default:true})
OPTIONAL MATCH (p)-[:HAS_TYPE]->(t:Type)
RETURN p.id AS id, collect(DISTINCT t.identifier) AS tipos
""").set_index("id")

    habilidades = df("""
MATCH (p:Pokemon {is_default:true})
OPTIONAL MATCH (p)-[:HAS_ABILITY]->(a:Ability)
RETURN p.id AS id, collect(DISTINCT a.identifier) AS habilidades
""").set_index("id")

    movimientos = df("""
MATCH (p:Pokemon {is_default:true})
OPTIONAL MATCH (p)-[:CAN_LEARN]->(m:Move)
RETURN p.id AS id, collect(DISTINCT id(m)) AS movimientos
""").set_index("id")

    especie = df("""
MATCH (p:Pokemon {is_default:true})-[:IS_SPECIES]->(s:Species)
RETURN p.id AS id, id(s) AS especie_id
""").set_index("id")

    comps = componentes_evolutivos()
    atributos = {}
    for pid in stats.index:
        atributos[int(pid)] = {
            "pokemon": nombres.get(pid, str(pid)),
            "stats": stats.loc[pid].drop("bst").astype(float).to_dict(),
            "bst": float(stats.loc[pid, "bst"]),
            "tipos": set(tipos.loc[pid, "tipos"]) if pid in tipos.index else set(),
            "habilidades": set(habilidades.loc[pid, "habilidades"]) if pid in habilidades.index else set(),
            "movimientos": set(movimientos.loc[pid, "movimientos"]) if pid in movimientos.index else set(),
            "linea_evolutiva": comps.get(int(especie.loc[pid, "especie_id"])) if pid in especie.index else None,
        }
    columnas_stats = [c for c in stats.columns if c != "bst"]
    return atributos, columnas_stats


def pares_positivos():
    edges = df("""
MATCH (a:Pokemon {is_default:true})-[:TEAMMATE_OF]-(b:Pokemon {is_default:true})
WHERE a.id < b.id
RETURN a.id AS a, b.id AS b
""")
    return {(int(r.a), int(r.b)) for r in edges.itertuples()}


def muestrear_negativos(candidatos, positivos, cantidad, rng):
    candidatos = np.array(sorted(candidatos), dtype=int)
    positivos = {tuple(sorted(p)) for p in positivos}
    max_intentos = cantidad * 200
    negativos = set()
    intentos = 0
    while len(negativos) < cantidad and intentos < max_intentos:
        a, b = rng.choice(candidatos, size=2, replace=False)
        par = tuple(sorted((int(a), int(b))))
        if par not in positivos:
            negativos.add(par)
        intentos += 1
    if len(negativos) < cantidad:
        raise RuntimeError("No se pudieron muestrear suficientes pares negativos.")
    return negativos


def construir_fila(a, b, atributos, columnas_stats):
    pa = atributos[a]
    pb = atributos[b]
    diffs = [abs(pa["stats"].get(c, 0.0) - pb["stats"].get(c, 0.0)) for c in columnas_stats]
    tipos_a = pa["tipos"]
    tipos_b = pb["tipos"]
    habilidades_a = pa["habilidades"]
    habilidades_b = pb["habilidades"]
    movimientos_a = pa["movimientos"]
    movimientos_b = pb["movimientos"]

    fila = {
        "bst_min": min(pa["bst"], pb["bst"]),
        "bst_max": max(pa["bst"], pb["bst"]),
        "diferencia_bst": abs(pa["bst"] - pb["bst"]),
        "diferencia_promedio_stats": float(np.mean(diffs)) if diffs else 0.0,
        "tipos_compartidos": len(tipos_a & tipos_b),
        "tipos_union": len(tipos_a | tipos_b),
        "mismo_perfil_tipo": 1.0 if tipos_a == tipos_b and tipos_a else 0.0,
        "habilidades_compartidas": len(habilidades_a & habilidades_b),
        "similitud_habilidades_jaccard": jaccard(habilidades_a, habilidades_b),
        "movimientos_compartidos_can_learn": len(movimientos_a & movimientos_b),
        "similitud_movepool_jaccard": jaccard(movimientos_a, movimientos_b),
        "movimientos_min": min(len(movimientos_a), len(movimientos_b)),
        "movimientos_max": max(len(movimientos_a), len(movimientos_b)),
        "misma_linea_evolutiva": 1.0
        if pa["linea_evolutiva"] is not None and pa["linea_evolutiva"] == pb["linea_evolutiva"]
        else 0.0,
    }
    for c, d in zip(columnas_stats, diffs):
        fila[f"diferencia_{c}"] = d
    return fila


def evaluar_bloque(datos, columnas, nombre):
    X = datos[columnas]
    y = datos["label"].astype(int)
    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=0.25,
        random_state=42,
        stratify=y,
    )
    modelo = RandomForestClassifier(
        n_estimators=300,
        min_samples_leaf=5,
        random_state=42,
        n_jobs=-1,
        class_weight="balanced",
    )
    modelo.fit(X_train, y_train)
    probas = modelo.predict_proba(X_test)[:, 1]
    return {
        "bloque": nombre,
        "modelo": "RandomForestClassifier",
        "variables": columnas,
        "n_variables": len(columnas),
        "auc": round(float(roc_auc_score(y_test, probas)), 3),
        "ap": round(float(average_precision_score(y_test, probas)), 3),
        "train_positivos": int(y_train.sum()),
        "train_negativos": int((y_train == 0).sum()),
        "test_positivos": int(y_test.sum()),
        "test_negativos": int((y_test == 0).sum()),
    }


def experiment_teammate_prediction_safe():
    print("-- Experimento sin fuga: predicción de relaciones TEAMMATE_OF --")
    atributos, columnas_stats = cargar_atributos()
    positivos = pares_positivos()
    positivos = {p for p in positivos if p[0] in atributos and p[1] in atributos}
    candidatos = sorted({x for par in positivos for x in par})
    rng = np.random.default_rng(42)
    negativos = muestrear_negativos(candidatos, positivos, len(positivos), rng)

    filas = []
    for a, b in sorted(positivos):
        fila = construir_fila(a, b, atributos, columnas_stats)
        fila["label"] = 1
        filas.append(fila)
    for a, b in sorted(negativos):
        fila = construir_fila(a, b, atributos, columnas_stats)
        fila["label"] = 0
        filas.append(fila)

    datos = pd.DataFrame(filas).fillna(0)
    columnas_baseline = ["bst_min", "bst_max", "diferencia_bst", "diferencia_promedio_stats"]
    columnas_tipos = columnas_baseline + ["tipos_compartidos", "tipos_union", "mismo_perfil_tipo"]
    columnas_movepool = columnas_baseline + [
        "movimientos_compartidos_can_learn",
        "similitud_movepool_jaccard",
        "movimientos_min",
        "movimientos_max",
    ]
    columnas_sin_fuga = sorted([c for c in datos.columns if c != "label"])

    resultados = [
        evaluar_bloque(datos, columnas_baseline, "Baseline de stats"),
        evaluar_bloque(datos, columnas_tipos, "Stats + tipos"),
        evaluar_bloque(datos, columnas_movepool, "Stats + movepool disponible"),
        evaluar_bloque(datos, columnas_sin_fuga, "Grafo base sin fuga"),
    ]

    resumen = {
        "pregunta": "¿Puede el grafo anticipar compatibilidad competitiva entre Pokémon usando solo información no derivada del uso competitivo?",
        "objetivo": "Predecir si un par de Pokémon tiene relación TEAMMATE_OF.",
        "fecha_generacion": pd.Timestamp.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "random_state": 42,
        "muestreo_negativos": "Pares no conectados por TEAMMATE_OF, muestreados dentro del universo de Pokémon que sí aparecen en alguna relación TEAMMATE_OF, balanceados 1:1 con los positivos.",
        "pares_positivos": len(positivos),
        "pares_negativos": len(negativos),
        "candidatos": len(candidatos),
        "modelo_principal": "RandomForestClassifier con random_state=42, n_estimators=300 y min_samples_leaf=5.",
        "variables_excluidas": [
            "TEAMMATE_OF como variable de entrada",
            "grado, PageRank o comunidades sobre TEAMMATE_OF",
            "USED_IN",
            "uso_smogon",
            "co_uso",
            "RUNS_MOVE cuando proviene de Smogon",
            "movimientos usados competitivamente",
        ],
        "resultados": resultados,
        "control_fuga": {
            "experimento": "Viabilidad OU con grafo competitivo",
            "auc": 0.986,
            "ap": 0.970,
            "uso": "Solo referencia metodológica; no se usa como evidencia predictiva principal.",
        },
    }

    with open(RESULTS, "w", encoding="utf-8") as f:
        json.dump(resumen, f, ensure_ascii=False, indent=2)

    print(f"Pares positivos: {len(positivos)}")
    print(f"Pares negativos: {len(negativos)}")
    for r in resultados:
        print(f"{r['bloque']}: AUC={r['auc']:.3f} AP={r['ap']:.3f}")
    print("Resultados guardados en", RESULTS)
    return resumen


if __name__ == "__main__":
    try:
        experiment_teammate_prediction_safe()
    finally:
        driver.close()
