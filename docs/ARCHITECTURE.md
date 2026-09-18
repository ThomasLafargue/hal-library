# HAL — Architecture Complète du SIGB
> Document de référence technique — 2026-09-18

---

## VUE D'ENSEMBLE

```
┌─────────────────────────────────────────────────────────────┐
│                        TABLETTES (PWA)                       │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │  HAL Desk    │  │  HAL Buy     │  │  HAL Search       │  │
│  │  (agents)    │  │  (achat)     │  │  (OPAC public)    │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬──────────┘  │
└─────────┼────────────────┼─────────────────────┼─────────────┘
          │                │                     │
          ▼                ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI — REST API                         │
│                                                              │
│  /circulation  /catalogue  /acquisitions  /opac  /stats      │
│                                                              │
│  Auth JWT  ·  Rate limiting  ·  Cache Redis                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL                                 │
│                                                              │
│  oeuvre · agent · manifestation · exemplaire                 │
│  adherent · pret · reservation · panier · budget             │
│  frequentation · site · regle_cote                           │
└─────────────────────────────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌─────────────────────┐    ┌────────────────────────┐
│  Redis (cache)       │    │  Jobs asyncrones        │
│                     │    │  · Enrichissement ISBN  │
│  · ISBN lookups     │    │  · Alertes retards      │
│  · Sessions         │    │  · Rapport annuel       │
│  · Search cache     │    │  · Stats quotidiennes   │
└─────────────────────┘    └────────────────────────┘
```

---

## 1. MODULE CIRCULATION (HAL Desk)

### 1.1 Prêt — flux complet

```
Agent scanne la carte adhérent
         ↓
HAL charge le profil :
  - Nom, prénom, catégorie, site
  - Quota restant (ex: 5 docs / 21 jours)
  - Retards en cours ? → BLOQUER si oui
  - Réservations à retirer ?
         ↓
Agent scanne les documents (code-barres ou RFID)
         ↓
Pour chaque document :
  - Vérifier statut = 'disponible'
  - Vérifier durée prêt selon catégorie adhérent × type document
  - Calculer date retour prévue
         ↓
[VALIDER LE PRÊT]
  - INSERT INTO pret (exemplaire_id, adherent_id, date_retour_prevue)
  - UPDATE exemplaire SET statut = 'en_pret'
  - Tag RFID : AFI 0x07 → 0xC2 (sécurité désactivée)
  - Impression reçu (optionnel)
```

### 1.2 Retour — flux complet

```
Agent scanne le document (n'importe quel site)
         ↓
HAL identifie : quelle notice ? quel pret en cours ?
         ↓
Calcul retard :
  date_retour_effectif > date_retour_prevue ?
  → OUI : calculer nb jours de retard, appliquer règle site
  → NON : retour normal
         ↓
[VALIDER LE RETOUR]
  - UPDATE pret SET date_retour_effectif = now(), statut = 'rendu'
  - UPDATE exemplaire SET statut = 'disponible', nb_prets = nb_prets + 1
  - Tag RFID : AFI 0xC2 → 0x07 (sécurité réactivée)
         ↓
Vérifier réservations en attente sur ce titre :
  - OUI → notifier l'adhérent par email/SMS
          UPDATE exemplaire SET statut = 'reserve'
  - NON → document disponible en rayon
```

### 1.3 Renouvellement

```
Adhérent demande renouvellement (guichet ou OPAC)
         ↓
Vérifications :
  - Pas de réservation en attente sur ce titre
  - Pas déjà renouvelé MAX fois (configurable : 2 par défaut)
  - Pas de retard sur ce document
         ↓
[RENOUVELER]
  - UPDATE pret SET
      date_retour_prevue = date_retour_prevue + duree_pret,
      nb_renouvellements = nb_renouvellements + 1
```

### 1.4 Gestion des retards (job nocturne 23h)

```python
# Tourne chaque nuit
SELECT p.*, a.email, a.telephone, m.titre
FROM pret p
JOIN exemplaire e ON e.id = p.exemplaire_id
JOIN manifestation m ON m.id = e.manifestation_id
JOIN adherent a ON a.id = p.adherent_id
WHERE p.statut = 'en_cours'
  AND p.date_retour_prevue < CURRENT_DATE
  AND p.date_retour_effectif IS NULL

→ UPDATE pret SET statut = 'en_retard'
→ Envoyer email de rappel (J+1, J+8, J+15)
→ Bloquer nouveaux prêts si retard > 21 jours (configurable)
```

### 1.5 Quotas et durées (configurables par site)

```sql
-- Règles de prêt par catégorie d'adhérent × type de document
CREATE TABLE regle_pret (
    site           TEXT NOT NULL,
    categorie_ad   TEXT NOT NULL,  -- 'adulte', 'enfant', 'etudiant'
    type_document  TEXT NOT NULL,  -- 'LIVRE', 'DVD', 'JEU'...
    nb_max         INTEGER DEFAULT 5,
    duree_jours    INTEGER DEFAULT 21,
    nb_renouvellements_max INTEGER DEFAULT 2,
    PRIMARY KEY (site, categorie_ad, type_document)
);
```

---

## 2. MODULE RÉSERVATIONS

### 2.1 Réserver depuis l'OPAC (lecteur)

```
Lecteur connecté cherche un titre
Document = "En prêt" ou "Indisponible"
         ↓
[Réserver ce titre]
  - INSERT INTO reservation (manifestation_id, adherent_id, site)
  - position_file = COUNT(réservations actives sur ce titre) + 1
  - Email de confirmation : "Votre réservation est enregistrée (position 3)"
```

### 2.2 Notification disponibilité

```
Dès qu'un prêt est rendu ET qu'il y a une réservation :
  - La 1ère réservation en file passe à 'disponible'
  - Email/SMS automatique : "Votre réservation est disponible jusqu'au [date]"
  - UPDATE exemplaire SET statut = 'reserve'
  - Si non retiré sous 5 jours : passe à l'adhérent suivant
```

### 2.3 File d'attente

```sql
-- Vue file d'attente en temps réel
CREATE VIEW file_attente AS
SELECT
    r.id,
    m.titre,
    a.nom || ' ' || a.prenom AS adherent,
    r.site,
    r.date_reservation,
    r.statut,
    ROW_NUMBER() OVER (PARTITION BY r.manifestation_id ORDER BY r.date_reservation) AS position,
    COUNT(e.id) FILTER (WHERE e.statut = 'disponible') AS exemplaires_disponibles
FROM reservation r
JOIN manifestation m ON m.id = r.manifestation_id
JOIN adherent a ON a.id = r.adherent_id
LEFT JOIN exemplaire e ON e.manifestation_id = r.manifestation_id AND e.site = r.site
WHERE r.statut IN ('en_attente', 'disponible')
GROUP BY r.id, m.titre, a.nom, a.prenom, r.site, r.date_reservation, r.statut;
```

---

## 3. BASE BIBLIOGRAPHIQUE

### 3.1 Structure IFLA-LRM simplifiée

```
ŒUVRE (Work)
  Un Harry Potter — concept abstrait
    ↓
MANIFESTATION (Edition)
  Harry Potter T.1 — Gallimard Jeunesse 2017 — ISBN 978...
  Harry Potter T.1 — Folio SF 2022 — ISBN 978...
    ↓
EXEMPLAIRE (Item)
  Barcode 300042 — Arcachon — Rayon A3 — Disponible
  Barcode 300043 — La Teste — En prêt
```

### 3.2 Enrichissement automatique (job background)

```
Nouvelles manifestations sans enrichissement :
  SELECT * FROM manifestation
  WHERE date_enrichissement IS NULL
    AND ean IS NOT NULL
  LIMIT 100

Pour chaque ISBN :
  1. BnF SRU      → titre, auteur, dewey, résumé (gratuit, illimité)
  2. Google Books  → couverture, résumé (gratuit, quota)
  3. Open Library  → fallback (gratuit, illimité)

Mise à jour :
  UPDATE manifestation SET
    dewey = ..., resume = ..., image_url = ...,
    score_confiance = 0.9,
    sources_enrichissement = ARRAY['bnf'],
    date_enrichissement = now()
```

### 3.3 Import UNIMARC COBAS (4 sites)

L'import initial depuis les exports Decalog des 4 médiathèques COBAS
donne la masse critique de notices :

```
Export Arcachon  → ~44 000 notices  → site ARC
Export La Teste  → ~XX 000 notices  → site TES
Export Gujan     → ~XX 000 notices  → site GUJ
Export Le Teich  → ~XX 000 notices  → site TEI

Déduplication par EAN/ISBN → base consolidée
Enrichissement BnF sur les notices sans Dewey/résumé
```

### 3.4 Recherche full-text

PostgreSQL + extension `pg_trgm` + colonne `fts TSVECTOR` :

```sql
-- Recherche simple
SELECT m.*, COUNT(e.id) AS nb_exemplaires,
       COUNT(e.id) FILTER (WHERE e.statut = 'disponible') AS disponibles
FROM manifestation m
LEFT JOIN exemplaire e ON e.manifestation_id = m.id
WHERE fts @@ plainto_tsquery('french', 'harry potter')
   OR titre ILIKE '%harry potter%'
ORDER BY ts_rank(fts, plainto_tsquery('french', 'harry potter')) DESC
LIMIT 20;

-- Avec filtres
WHERE fts @@ plainto_tsquery('french', $1)
  AND (genre = $2 OR $2 IS NULL)
  AND (public_vise = $3 OR $3 IS NULL)
  AND e.site = $4
```

---

## 4. OPAC PUBLIC (HAL Search)

### 4.1 Architecture

```
Lecteur (navigateur tablette/mobile/PC)
         ↓ HTTPS
Next.js (SSR + PWA)
  - Server-side rendering pour le SEO (Google indexe le catalogue)
  - Cache Next.js pour les pages populaires
         ↓ API calls
FastAPI /opac/*
  - Routes publiques (pas d'auth)
  - Cache Redis 60s sur les résultats de recherche
         ↓
PostgreSQL (lecture seule pour l'OPAC)
```

### 4.2 Fonctionnalités OPAC V1

**Recherche** (sans connexion) :
- Mots-clés libres → full-text PostgreSQL
- Filtres : genre, public visé, type, site, disponibilité
- Recherche par ISBN (scan depuis mobile)
- Résultats avec couverture + disponibilité en temps réel

**Fiche document** :
- Couverture, résumé, auteurs, éditeur, Dewey
- Exemplaires : par site, statut (disponible/en prêt/réservé), cote
- Titres du même auteur / de la même série

**Recherche conversationnelle** (Claude API) :
- "j'ai 8 ans et j'aime les dragons"
- "un polar pour adulte avec une femme détective"
- HAL traduit en requête SQL et présente les résultats

**Avec connexion** (carte adhérent) :
- Mes prêts en cours + dates de retour
- Mes réservations + position dans la file
- Renouveler un prêt
- Réserver un titre indisponible
- Mon historique (optionnel, RGPD)

### 4.3 Disponibilité en temps réel

```sql
-- Vue disponibilité par titre et site
CREATE VIEW disponibilite AS
SELECT
    m.id AS manifestation_id,
    m.titre,
    e.site,
    COUNT(e.id) AS total_exemplaires,
    COUNT(e.id) FILTER (WHERE e.statut = 'disponible') AS disponibles,
    COUNT(e.id) FILTER (WHERE e.statut = 'en_pret') AS en_pret,
    COUNT(r.id) FILTER (WHERE r.statut = 'en_attente') AS en_attente_reservation,
    MIN(p.date_retour_prevue) FILTER (WHERE p.statut = 'en_cours') AS prochain_retour
FROM manifestation m
LEFT JOIN exemplaire e ON e.manifestation_id = m.id
LEFT JOIN pret p ON p.exemplaire_id = e.id AND p.statut = 'en_cours'
LEFT JOIN reservation r ON r.manifestation_id = m.id AND r.site = e.site
GROUP BY m.id, m.titre, e.site;
```

### 4.4 Authentification adhérent

```
Connexion OPAC :
  - Numéro de carte + date de naissance (ou code PIN)
  - Session JWT (expires 7 jours)
  - Pas de création de compte en ligne (inscription en médiathèque)

RGPD :
  - Données minimales collectées
  - Historique prêts : conservé 6 mois puis anonymisé
  - Droit à l'oubli : DELETE en cascade sur toutes les tables
```

---

## 5. JOBS ASYNCHRONES (Redis + Celery)

| Job | Fréquence | Action |
|-----|-----------|--------|
| Enrichissement notices | Continu | BnF → Google Books → OpenLibrary |
| Alertes retards | Nuit 23h | Email J+1, J+8, J+15 |
| Disponibilité réservations | À chaque retour | Notification email/SMS |
| Stats quotidiennes | Nuit 0h | Fréquentation, rotations |
| Rapport annuel | 1er janvier | Auto-généré format Ministère |
| Purge RGPD | 1er du mois | Anonymisation données > 6 mois |
| Sauvegarde base | Nuit 2h | pg_dump → stockage local |

---

## 6. API REST — ENDPOINTS PRINCIPAUX

```
# Catalogue (public)
GET  /opac/search?q=harry+potter&genre=Roman&site=ARC
GET  /opac/notices/{id}
GET  /opac/notices/{id}/disponibilite
GET  /opac/notices/{id}/serie

# Catalogue (agents authentifiés)
POST /catalogue/notices
PUT  /catalogue/notices/{id}
POST /catalogue/enrichir/{ean}

# Circulation (agents)
GET  /circulation/adherent/{code_barre}
POST /circulation/prets
PUT  /circulation/prets/{id}/retour
PUT  /circulation/prets/{id}/renouveler
GET  /circulation/retards

# Réservations
POST /opac/reservations           (lecteur)
GET  /opac/reservations/moi       (lecteur)
GET  /circulation/reservations    (agent)
PUT  /circulation/reservations/{id}/retrait

# Adhérents (agents)
GET  /adherents/{id}
POST /adherents
PUT  /adherents/{id}
DELETE /adherents/{id}            (RGPD — anonymise)

# Acquisitions (agents)
GET  /acquisitions/paniers
POST /acquisitions/paniers
POST /acquisitions/paniers/{id}/commander
POST /acquisitions/reception

# Stats (direction)
GET  /stats/frequentation?periode=2026
GET  /stats/rotation?site=ARC
GET  /stats/budget?annee=2026
GET  /stats/rapport-annuel?annee=2025
```

---

## 7. INTERFACE AGENTS (HAL Desk) — ÉCRANS

### Écran principal (tableau de bord du jour)
```
┌─────────────────────────────────────────────────┐
│  🔴 HAL · Arcachon                    Thomas ▾  │
├─────────────────────────────────────────────────┤
│  Aujourd'hui : 47 prêts · 23 retours · 3 retards│
├────────────────────┬────────────────────────────┤
│  📤 PRÊT           │  📥 RETOUR                 │
│  [Scanner carte]   │  [Scanner document]        │
├────────────────────┴────────────────────────────┤
│  ⚠ 3 réservations prêtes à retirer              │
│  ⚠ 2 documents en retard > 21 jours             │
└─────────────────────────────────────────────────┘
```

### Écran prêt (après scan carte)
```
┌─────────────────────────────────────────────────┐
│  👤 Martin Dupont                               │
│  Carte : ARC-2024-0042 · Adulte                 │
│  Quota : 3/5 documents                          │
│  ✓ Aucun retard                                 │
├─────────────────────────────────────────────────┤
│  Documents scannés :                            │
│  ┌───────────────────────────────────────────┐  │
│  │ ✓ Harry Potter T.1    21 jours → 09/10   │  │
│  │ ✓ Astérix T.40        21 jours → 09/10   │  │
│  └───────────────────────────────────────────┘  │
│  [+ Scanner un autre]     [✓ Valider le prêt]  │
└─────────────────────────────────────────────────┘
```

---

## 8. SÉCURITÉ ET RGPD

### Authentification
- Agents : JWT avec refresh token, rôles (admin/bibliothécaire/bénévole)
- Adhérents OPAC : numéro carte + date naissance
- API interne : HMAC entre services

### RGPD
- Données adhérents : chiffrées au repos (PostgreSQL encryption)
- Historique prêts : anonymisé après 6 mois
- Logs d'accès : 3 mois max
- Export données adhérent : endpoint `/adherents/{id}/export`
- Suppression compte : anonymisation (pas suppression — intégrité)

### Hébergement
- Serveur dédié OVH ou Scaleway (France, données en France)
- Sauvegarde quotidienne chiffrée
- HTTPS obligatoire (Let's Encrypt)

---

## 9. ROADMAP TECHNIQUE

| Phase | Durée | Contenu |
|-------|-------|---------|
| **0 — Fondations** | Semaines 1-2 | Docker, schéma PostgreSQL, import UNIMARC COBAS |
| **1 — OPAC V1** | Semaines 3-6 | Recherche publique, disponibilité, PWA mobile |
| **2 — Circulation V1** | Semaines 7-12 | Prêts, retours, adhérents, RFID |
| **3 — Réservations** | Semaines 11-14 | File d'attente, notifications email |
| **4 — Acquisitions** | Semaines 13-18 | Paniers, commandes, réception |
| **5 — Retards & stats** | Semaines 16-20 | Alertes, tableaux de bord, rapport annuel |
| **6 — Multi-sites** | Semaines 18-24 | Prêt inter-sites, consolidation COBAS |

---

*Ce document est la référence architecturale de HAL — 2026-09-18*
