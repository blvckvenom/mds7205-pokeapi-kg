"""Experimentos ML integrados: comparación tabular vs features de grafo y link prediction.

Salida: guarda figuras en `analysis/img/` y muestra métricas en consola (en español).
"""
import os
import numpy as np
import pandas as pd
from neo4j import GraphDatabase
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import StratifiedKFold, train_test_split, cross_val_predict
from sklearn.metrics import roc_auc_score, average_precision_score
import matplotlib.pyplot as plt

IMG = os.path.join(os.path.dirname(__file__), "img")
os.makedirs(IMG, exist_ok=True)
driver = GraphDatabase.driver("bolt://localhost:7687", auth=None)

def df(q):
    with driver.session() as s:
        return pd.DataFrame([r.data() for r in s.run(q)])


def experiment_viability():
    print("-- Experimento 1: Predicción de viabilidad competitiva (OU) --")
    stats = df("""
MATCH (p:Pokemon {is_default:true})-[r:HAS_STAT]->(s:Stat)
RETURN p.id AS id, s.identifier AS stat, r.base_stat AS v
""").pivot_table(index="id", columns="stat", values="v", fill_value=0)
    stats["bst"] = stats.sum(axis=1)

    meta = df("""
MATCH (p:Pokemon {is_default:true})-[:IS_SPECIES]->(sp:Species)
OPTIONAL MATCH (p)-[:CAN_LEARN]->(mv:Move)
WITH p, sp, count(DISTINCT mv) AS movepool
OPTIONAL MATCH (p)-[:HAS_ABILITY]->(ab:Ability)
WITH p, sp, movepool, count(DISTINCT ab) AS n_abil
OPTIONAL MATCH (p)-[tm:TEAMMATE_OF]->(:Pokemon)
RETURN p.id AS id, movepool, n_abil, count(DISTINCT tm) AS tm_count
""").set_index("id")

    graph_feats = df("""
MATCH (p:Pokemon {is_default:true})-[:IS_SPECIES]->(sp:Species)
OPTIONAL MATCH (p)-[tm:TEAMMATE_OF]->(t:Pokemon)
OPTIONAL MATCH (p)-[:RUNS_MOVE]->(mv:Move)
OPTIONAL MATCH (p)<-[:CHECKED_BY]-(q:Pokemon)
WITH p.id AS id,
     count(DISTINCT t) AS teammates_count,
     avg(COALESCE(tm.pct, 0.0)) AS mean_tm_pct,
     count(DISTINCT mv) AS runs_move_count,
     count(DISTINCT q) AS checked_by_count
RETURN id, teammates_count, mean_tm_pct, runs_move_count, checked_by_count
""").set_index("id")

    label = df("""
MATCH (p:Pokemon {is_default:true})-[:IS_SPECIES]->(sp:Species)
RETURN p.id AS id, CASE WHEN EXISTS { (sp)<-[:IS_SPECIES]-(:Pokemon)-[:USED_IN]->(:Format {tier:'gen9ou'}) } THEN 1 ELSE 0 END AS in_ou
""").set_index("id")

    D = stats.join([meta, graph_feats, label], how='inner').fillna(0)
    y = D['in_ou'].astype(int)
    cols_base = ['bst']
    cols_mid = list(stats.columns) + ['movepool', 'n_abil']
    cols_full = cols_mid + ['teammates_count', 'mean_tm_pct', 'runs_move_count', 'checked_by_count']

    def auc_cv(X, y, seed=42):
        clf = RandomForestClassifier(n_estimators=200, random_state=seed, n_jobs=-1)
        proba = cross_val_predict(clf, X, y, cv=StratifiedKFold(5, shuffle=True, random_state=seed), method='predict_proba')[:,1]
        return roc_auc_score(y, proba), average_precision_score(y, proba)

    ab, ap = auc_cv(D[cols_base], y)
    am, apm = auc_cv(D[cols_mid], y)
    af, apf = auc_cv(D[cols_full], y)
    print(f"Baseline (BST): AUC={ab:.3f} AP={ap:.3f}")
    print(f"+ Features de movepool/abilities: AUC={am:.3f} AP={apm:.3f}")
    print(f"+ Features de grafo competitivo: AUC={af:.3f} AP={apf:.3f}")

    clf = RandomForestClassifier(n_estimators=200, random_state=42, n_jobs=-1)
    clf.fit(D[cols_full], y)
    importances = pd.Series(clf.feature_importances_, index=cols_full).sort_values(ascending=False)
    fig, ax = plt.subplots(figsize=(8, 5))
    importances.head(12).plot.bar(ax=ax)
    ax.set_title('Importancia de features (viabilidad competitive)')
    ax.set_ylabel('Importancia')
    fig.tight_layout()
    fig.savefig(os.path.join(IMG, 'viability_feature_importance.png'))
    plt.close(fig)


def experiment_link_prediction():
    print("-- Experimento 2: Link prediction (COMPATIBLE) --")
    ed = df("MATCH (a:Species)-[:COMPATIBLE]->(b:Species) RETURN a.id AS a, b.id AS b")
    nodes = sorted(set(ed.a) | set(ed.b))
    edge_set = {(min(a, b), max(a, b)) for a, b in zip(ed.a, ed.b)}
    nl = np.array(nodes)

    sfeat = df("""
MATCH (s:Species)<-[:IS_SPECIES]-(p:Pokemon {is_default:true})-[r:HAS_STAT]->(st:Stat)
RETURN s.id AS sid, st.identifier AS stat, r.base_stat AS v
""").pivot_table(index='sid', columns='stat', values='v', fill_value=0)
    smeta = df("MATCH (s:Species) OPTIONAL MATCH (s)<-[:IS_SPECIES]-(:Pokemon {is_default:true})-[:HAS_TYPE {slot:1}]->(t:Type) RETURN s.id AS sid, s.generation_id AS gen, t.identifier AS ptype").set_index('sid')
    topo = df("""
MATCH (s:Species)
OPTIONAL MATCH (s)-[:COMPATIBLE]-(neigh:Species)
RETURN s.id AS sid,
       count(DISTINCT neigh) AS compat_degree,
       size([(s)-[:COMPATIBLE]-(x:Species)-[:COMPATIBLE]-(s) | 1]) AS compat_triangles
""").set_index('sid')

    def sample_neg(k, rng):
        out=set()
        while len(out)<k:
            u,v=rng.choice(nl,2,replace=False)
            e=(int(min(u,v)),int(max(u,v)))
            if e not in edge_set:
                out.add(e)
        return np.array(list(out))

    def attr_feats(pairs):
        rows=[]
        for u,v in pairs:
            diffs = list(np.abs(sfeat.loc[u].values - sfeat.loc[v].values))
            tu = smeta.loc[u,'ptype'] if u in smeta.index else None
            tv = smeta.loc[v,'ptype'] if v in smeta.index else None
            same_type = 1.0 if (pd.notna(tu) and tu==tv) else 0.0
            same_gen = 1.0 if (u in smeta.index and v in smeta.index and smeta.loc[u,'gen']==smeta.loc[v,'gen']) else 0.0
            compat_degree_u = topo.loc[u,'compat_degree'] if u in topo.index else 0.0
            compat_degree_v = topo.loc[v,'compat_degree'] if v in topo.index else 0.0
            compat_triangles_u = topo.loc[u,'compat_triangles'] if u in topo.index else 0.0
            compat_triangles_v = topo.loc[v,'compat_triangles'] if v in topo.index else 0.0
            rows.append(diffs+[same_type,same_gen, compat_degree_u, compat_degree_v, compat_triangles_u, compat_triangles_v])
        return np.array(rows,dtype=float)

    rng = np.random.default_rng(42)
    pos = np.array(list(edge_set))
    neg = sample_neg(len(pos), rng)
    pos_tr,pos_te = train_test_split(pos, test_size=0.25, random_state=42)
    neg_tr,neg_te = train_test_split(neg, test_size=0.25, random_state=42)

    Xtr = np.vstack([attr_feats(pos_tr), attr_feats(neg_tr)])
    ytr = np.r_[np.ones(len(pos_tr)), np.zeros(len(neg_tr))]
    Xte = np.vstack([attr_feats(pos_te), attr_feats(neg_te)])
    yte = np.r_[np.ones(len(pos_te)), np.zeros(len(neg_te))]

    m = RandomForestClassifier(n_estimators=300, random_state=42, n_jobs=-1).fit(Xtr, ytr)
    p = m.predict_proba(Xte)[:,1]
    print(f"AUC (atributos fenotípicos): {roc_auc_score(yte,p):.3f} AP: {average_precision_score(yte,p):.3f}")


if __name__ == '__main__':
    experiment_viability()
    experiment_link_prediction()
    print('Experimentos completados. Figuras y resultados en', IMG)
