"""ML basico sobre el grafo PokeAPI (Hito 2). Dos objetivos consultados desde Python:

  1. Clasificacion de tipo primario  -> features = 6 stats base + conteo de moves por tipo.
  2. Link prediction de compatibilidad de crianza, con DOS encuadres:
       2a) topologico: COMPATIBLE es una union de cliques solapadas (cada egg group es un clique;
           ~27% de especies esta en 2 grupos y los puentea), asi que la prediccion por
           vecindario es casi perfecta y dice mas del grafo que del modelo.
       2b) por atributos fenotipicos (stats, tipo, generacion): la tarea predictiva real, no trivial.

Corre con: python3 analysis/ml.py  (requiere el grafo cargado por load_all.sh)
"""
import os
import math
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from neo4j import GraphDatabase
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score, StratifiedKFold, train_test_split
from sklearn.metrics import roc_auc_score, average_precision_score, roc_curve, confusion_matrix, ConfusionMatrixDisplay

IMG = os.path.join(os.path.dirname(__file__), "img")
os.makedirs(IMG, exist_ok=True)
RNG = np.random.default_rng(42)
driver = GraphDatabase.driver("bolt://localhost:7687", auth=None)


def df(q):
    """Ejecuta Cypher contra el grafo y devuelve un DataFrame."""
    with driver.session() as s:
        return pd.DataFrame([r.data() for r in s.run(q)])


# ===================== 1. CLASIFICACION DE TIPO =====================
print("=" * 60, "\n1. CLASIFICACION DE TIPO PRIMARIO\n", "=" * 60)
stats = df("""
MATCH (p:Pokemon {is_default:true})-[r:HAS_STAT]->(s:Stat)
RETURN p.id AS pokemon, s.identifier AS stat, r.base_stat AS v
""").pivot_table(index="pokemon", columns="stat", values="v", fill_value=0)

movetypes = df("""
MATCH (p:Pokemon {is_default:true})-[:CAN_LEARN]->(m:Move)-[:MOVE_TYPE]->(t:Type)
WITH p, t, count(DISTINCT m) AS c
RETURN p.id AS pokemon, 'mt_' + t.identifier AS movetype, c
""").pivot_table(index="pokemon", columns="movetype", values="c", fill_value=0)

label = df("""
MATCH (p:Pokemon {is_default:true})-[r:HAS_TYPE {slot:1}]->(t:Type)
RETURN p.id AS pokemon, t.identifier AS tipo
""").set_index("pokemon")["tipo"]

X = stats.join(movetypes, how="left").fillna(0)
data = X.join(label, how="inner").dropna(subset=["tipo"])
y = data["tipo"]; Xm = data.drop(columns="tipo")
print(f"dataset: {Xm.shape[0]} pokemon, {Xm.shape[1]} features, {y.nunique()} clases")

clf = RandomForestClassifier(n_estimators=400, random_state=42, n_jobs=-1)
cv = StratifiedKFold(5, shuffle=True, random_state=42)
scores = cross_val_score(clf, Xm, y, cv=cv, scoring="accuracy")
print(f"accuracy 5-fold CV: {scores.mean():.3f} +/- {scores.std():.3f}  (baseline mayoritaria: {y.value_counts(normalize=True).max():.3f})")

# Contraste honesto: solo con las 6 stats base (sin conteos de move-type) la accuracy se desploma.
# Confirma que la senal fuerte viene del movepool, correlacionado con el tipo casi por construccion
# (un pokemon de fuego aprende muchos moves de fuego, efecto STAB), no del fenotipo de stats.
stat_cols = [c for c in Xm.columns if not c.startswith("mt_")]
scores_stats = cross_val_score(clf, Xm[stat_cols], y, cv=cv, scoring="accuracy")
print(f"accuracy solo con stats base: {scores_stats.mean():.3f} (vs {scores.mean():.3f} con stats + move-types)")

Xtr, Xte, ytr, yte = train_test_split(Xm, y, test_size=0.25, stratify=y, random_state=42)
clf.fit(Xtr, ytr)
labels_sorted = sorted(y.unique())
cm = confusion_matrix(yte, clf.predict(Xte), labels=labels_sorted)
fig, ax = plt.subplots(figsize=(9, 8))
ConfusionMatrixDisplay(cm, display_labels=labels_sorted).plot(ax=ax, xticks_rotation=70, colorbar=False, cmap="Blues")
ax.set_title("Clasificacion de tipo primario - matriz de confusion (holdout)")
plt.tight_layout(); plt.savefig(f"{IMG}/type_confusion.png", dpi=110); plt.close()
imp = pd.Series(clf.feature_importances_, index=Xm.columns).sort_values(ascending=False)
print("top 8 features:", ", ".join(f"{k}={v:.3f}" for k, v in imp.head(8).items()))

# ===================== 2. LINK PREDICTION CRIANZA =====================
print("\n" + "=" * 60, "\n2. LINK PREDICTION - COMPATIBILIDAD DE CRIANZA\n", "=" * 60)
ed = df("MATCH (a:Species)-[:COMPATIBLE]->(b:Species) RETURN a.id AS a, b.id AS b")
nodes = sorted(set(ed.a) | set(ed.b))
edge_set = {(min(a, b), max(a, b)) for a, b in zip(ed.a, ed.b)}
pos = np.array(list(edge_set))
print(f"grafo crianza: {len(nodes)} nodos, {len(pos)} aristas positivas")
pos_tr, pos_te = train_test_split(pos, test_size=0.2, random_state=42)
train_edges = {(min(a, b), max(a, b)) for a, b in pos_tr}

# adyacencia SOLO con aristas de entrenamiento (sin fuga del test a las features topologicas)
adj = {n: set() for n in nodes}
for a, b in train_edges:
    adj[a].add(b); adj[b].add(a)


def sample_random_negatives(k):
    """Muestrea k pares no-arista. Excluye contra TODAS las positivas (edge_set), no solo las
    de train, para no etiquetar como negativa una arista real que cayo en el test."""
    out = set(); nl = np.array(nodes)
    while len(out) < k:
        u, v = RNG.choice(nl, 2, replace=False)
        e = (int(min(u, v)), int(max(u, v)))
        if e not in edge_set:
            out.add(e)
    return np.array(list(out))


neg = sample_random_negatives(len(pos))
neg_tr, neg_te = train_test_split(neg, test_size=0.2, random_state=42)
y_tr = np.r_[np.ones(len(pos_tr)), np.zeros(len(neg_tr))]
y_te = np.r_[np.ones(len(pos_te)), np.zeros(len(neg_te))]


def topo_feats(pairs):
    """4 features de vecindario por par: common neighbors, Jaccard, Adamic-Adar, preferential
    attachment, calculadas sobre la adyacencia de entrenamiento."""
    rows = []
    for u, v in pairs:
        nu, nv = adj[u], adj[v]
        common = nu & nv; union = nu | nv
        cn = len(common)
        jac = cn / len(union) if union else 0.0
        aa = sum(1.0 / math.log(len(adj[w])) for w in common if len(adj[w]) > 1)
        pa = len(nu) * len(nv)
        rows.append([cn, jac, aa, pa])
    return np.array(rows, dtype=float)


m1 = RandomForestClassifier(n_estimators=300, random_state=42, n_jobs=-1)
m1.fit(np.vstack([topo_feats(pos_tr), topo_feats(neg_tr)]), y_tr)
p1 = m1.predict_proba(np.vstack([topo_feats(pos_te), topo_feats(neg_te)]))[:, 1]
auc1, ap1 = roc_auc_score(y_te, p1), average_precision_score(y_te, p1)
print(f"2a) topologico (CN/Jaccard/AA/PA): AUC={auc1:.3f}  AP={ap1:.3f}")
print("    -> casi perfecto: COMPATIBLE es union de cliques solapadas por egg group, el vecindario predice casi todo.")

sfeat = df("""
MATCH (s:Species)<-[:IS_SPECIES]-(p:Pokemon {is_default:true})-[r:HAS_STAT]->(st:Stat)
RETURN s.id AS sid, st.identifier AS stat, r.base_stat AS v
""").pivot_table(index="sid", columns="stat", values="v", fill_value=0)
smeta = df("""
MATCH (s:Species)
OPTIONAL MATCH (s)<-[:IS_SPECIES]-(:Pokemon {is_default:true})-[:HAS_TYPE {slot:1}]->(t:Type)
RETURN s.id AS sid, s.generation_id AS gen, t.identifier AS ptype
""").set_index("sid")


def attr_feats(pairs):
    """Por par: diffs absolutas de las 6 stats base, mismo tipo primario (0/1), misma generacion (0/1)."""
    rows = []
    for u, v in pairs:
        diffs = list(np.abs(sfeat.loc[u].values - sfeat.loc[v].values))
        tu, tv = smeta.loc[u, "ptype"], smeta.loc[v, "ptype"]
        same_type = 1.0 if (pd.notna(tu) and tu == tv) else 0.0
        same_gen = 1.0 if smeta.loc[u, "gen"] == smeta.loc[v, "gen"] else 0.0
        rows.append(diffs + [same_type, same_gen])
    return np.array(rows, dtype=float)


m2 = RandomForestClassifier(n_estimators=300, random_state=42, n_jobs=-1)
m2.fit(np.vstack([attr_feats(pos_tr), attr_feats(neg_tr)]), y_tr)
p2 = m2.predict_proba(np.vstack([attr_feats(pos_te), attr_feats(neg_te)]))[:, 1]
auc2, ap2 = roc_auc_score(y_te, p2), average_precision_score(y_te, p2)
print(f"2b) atributos (diffs de 6 stats + mismo tipo + misma generacion): AUC={auc2:.3f}  AP={ap2:.3f}")
print("    -> NO trivial: el egg group correlaciona con el fenotipo pero no esta determinado por el.")

plt.figure(figsize=(6, 5))
for p, auc, lab, c in [(p1, auc1, "topologico (cliques solapadas)", "#8172b3"),
                       (p2, auc2, "por atributos fenotipicos", "#c44e52")]:
    fpr, tpr, _ = roc_curve(y_te, p)
    plt.plot(fpr, tpr, color=c, label=f"{lab}: AUC={auc:.3f}")
plt.plot([0, 1], [0, 1], "--", color="gray")
plt.xlabel("FPR"); plt.ylabel("TPR"); plt.legend(loc="lower right")
plt.title("Link prediction crianza: topologia vs atributos")
plt.tight_layout(); plt.savefig(f"{IMG}/breeding_roc.png", dpi=110); plt.close()

print(f"\nFiguras en {IMG}/")
driver.close()
