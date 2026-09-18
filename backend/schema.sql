-- HAL — Schéma PostgreSQL
-- Inspiré IFLA-LRM (œuvre / expression / manifestation / item)
-- Version 1.0 — 2026-09-18

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- Recherche floue

-- ─────────────────────────────────────────────────────────────────────────────
-- AGENTS (personnes et collectivités)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE agent (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nom             TEXT NOT NULL,
    prenom          TEXT,
    type            TEXT DEFAULT 'personne' CHECK (type IN ('personne', 'collectivite')),
    dates_vie       TEXT,              -- "1950-2020" ou "né en 1975"
    identifiant_bnf TEXT UNIQUE,       -- ARK BnF : ark:/12148/cb...
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_agent_nom ON agent USING gin(nom gin_trgm_ops);

-- ─────────────────────────────────────────────────────────────────────────────
-- ŒUVRES (niveau abstrait — IFLA-LRM Work)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE oeuvre (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    titre_uniforme  TEXT NOT NULL,
    type_document   TEXT NOT NULL DEFAULT 'LIVRE'
                    CHECK (type_document IN ('LIVRE','BD','MANGA','DVD','JEU','CD','PERIODIQUE','AUTRE')),
    genre           TEXT,
    public_vise     TEXT CHECK (public_vise IN ('Bébé','Enfant','Jeune','Ado','Adulte','Tout public')),
    date_creation   TEXT,              -- année de création originale
    identifiant_bnf TEXT,              -- ARK BnF de l'œuvre
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- Relation œuvre ↔ agent
CREATE TABLE oeuvre_agent (
    oeuvre_id       UUID REFERENCES oeuvre(id) ON DELETE CASCADE,
    agent_id        UUID REFERENCES agent(id) ON DELETE CASCADE,
    role            TEXT DEFAULT 'auteur'
                    CHECK (role IN ('auteur','illustrateur','traducteur','directeur',
                                    'scenariste','dessinateur','compositeur','autre')),
    PRIMARY KEY (oeuvre_id, agent_id, role)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- MANIFESTATIONS (éditions — IFLA-LRM Manifestation)
-- C'est le niveau "notice bibliographique" classique
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE manifestation (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    oeuvre_id       UUID REFERENCES oeuvre(id) ON DELETE SET NULL,

    -- Identification
    isbn            TEXT,
    ean             TEXT UNIQUE,       -- EAN13 (= ISBN13 sans tirets)
    issn            TEXT,              -- périodiques

    -- Description principale
    titre           TEXT NOT NULL,
    sous_titre      TEXT,
    mention_edition TEXT,              -- "2e édition revue et corrigée"

    -- Série
    serie           TEXT,
    tome            TEXT,              -- TEXT car peut être "HS", "0", "1bis"...
    collection      TEXT,

    -- Publication
    editeur         TEXT,
    lieu_edition    TEXT DEFAULT 'Paris',
    date_publication TEXT,             -- "2024" ou "2024-03-15"
    pays_edition    TEXT DEFAULT 'FR',
    langue          TEXT DEFAULT 'fre',

    -- Classification
    dewey           TEXT,
    dewey_libelle   TEXT,
    mots_cles       TEXT[],

    -- Description physique
    description_physique TEXT,         -- "245 p. ; 24 cm"
    support         TEXT DEFAULT 'papier',

    -- Enrichissement IA/API
    resume          TEXT,
    image_url       TEXT,
    score_confiance REAL DEFAULT 0.0 CHECK (score_confiance BETWEEN 0 AND 1),
    sources_enrichissement TEXT[],     -- ['bnf', 'google_books', 'open_library']
    date_enrichissement TIMESTAMPTZ,

    -- Métadonnées
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Index pour la recherche
CREATE INDEX idx_manifestation_titre    ON manifestation USING gin(titre gin_trgm_ops);
CREATE INDEX idx_manifestation_ean      ON manifestation(ean);
CREATE INDEX idx_manifestation_isbn     ON manifestation(isbn);
CREATE INDEX idx_manifestation_serie    ON manifestation(serie);
CREATE INDEX idx_manifestation_dewey    ON manifestation(dewey);
CREATE UNIQUE INDEX idx_manifestation_ean_unique ON manifestation(ean) WHERE ean IS NOT NULL;

-- Full-text search
ALTER TABLE manifestation ADD COLUMN fts TSVECTOR
    GENERATED ALWAYS AS (
        to_tsvector('french',
            coalesce(titre,'') || ' ' ||
            coalesce(sous_titre,'') || ' ' ||
            coalesce(serie,'') || ' ' ||
            coalesce(editeur,'') || ' ' ||
            coalesce(resume,'') || ' ' ||
            coalesce(array_to_string(mots_cles,' '),'')
        )
    ) STORED;

CREATE INDEX idx_manifestation_fts ON manifestation USING gin(fts);

-- ─────────────────────────────────────────────────────────────────────────────
-- EXEMPLAIRES (items physiques — IFLA-LRM Item)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE exemplaire (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    manifestation_id    UUID NOT NULL REFERENCES manifestation(id) ON DELETE RESTRICT,

    -- Localisation
    site                TEXT NOT NULL,
    cote                TEXT,
    localisation        TEXT,          -- "Rayon A3", "Réserve", "Périodiques"

    -- Identification physique
    code_barre          TEXT UNIQUE,
    rfid_uid            TEXT UNIQUE,   -- UID du tag NFC/RFID
    rfid_encode_le      TIMESTAMPTZ,

    -- État
    statut              TEXT DEFAULT 'disponible'
                        CHECK (statut IN ('disponible','en_pret','reserve',
                                          'en_traitement','perdu','retire','desherbe')),

    -- Acquisition
    date_acquisition    DATE,
    prix                DECIMAL(10,2),
    fournisseur_id      UUID,          -- FK vers fournisseur (module acquisitions)
    panier_item_id      UUID,          -- FK vers commande d'origine

    -- Statistiques prêts
    nb_prets            INTEGER DEFAULT 0,
    date_dernier_pret   DATE,

    -- Métadonnées
    created_at          TIMESTAMPTZ DEFAULT now(),
    updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_exemplaire_manifestation ON exemplaire(manifestation_id);
CREATE INDEX idx_exemplaire_site          ON exemplaire(site);
CREATE INDEX idx_exemplaire_statut        ON exemplaire(statut);
CREATE INDEX idx_exemplaire_cote          ON exemplaire(cote);

-- ─────────────────────────────────────────────────────────────────────────────
-- ADHÉRENTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE adherent (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Données personnelles (RGPD)
    nom             TEXT NOT NULL,
    prenom          TEXT,
    date_naissance  DATE,
    email           TEXT UNIQUE,
    telephone       TEXT,
    adresse         TEXT,
    code_postal     TEXT,
    ville           TEXT,
    -- Abonnement
    site_principal  TEXT NOT NULL,
    code_barre      TEXT UNIQUE,
    date_inscription DATE DEFAULT CURRENT_DATE,
    date_expiration  DATE,
    statut          TEXT DEFAULT 'actif' CHECK (statut IN ('actif','expire','suspendu')),
    categorie       TEXT DEFAULT 'adulte',
    -- RGPD
    consentement_email BOOLEAN DEFAULT FALSE,
    date_consentement  TIMESTAMPTZ,
    -- Métadonnées
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- PRÊTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE pret (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    exemplaire_id   UUID NOT NULL REFERENCES exemplaire(id),
    adherent_id     UUID NOT NULL REFERENCES adherent(id),
    site            TEXT NOT NULL,
    date_pret       DATE NOT NULL DEFAULT CURRENT_DATE,
    date_retour_prevu DATE NOT NULL,
    date_retour_effectif DATE,
    statut          TEXT DEFAULT 'en_cours' CHECK (statut IN ('en_cours','rendu','en_retard','perdu')),
    nb_renouvellements INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_pret_exemplaire ON pret(exemplaire_id);
CREATE INDEX idx_pret_adherent   ON pret(adherent_id);
CREATE INDEX idx_pret_statut     ON pret(statut);
CREATE INDEX idx_pret_date       ON pret(date_pret);

-- ─────────────────────────────────────────────────────────────────────────────
-- RÉSERVATIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE reservation (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    manifestation_id UUID NOT NULL REFERENCES manifestation(id),
    adherent_id     UUID NOT NULL REFERENCES adherent(id),
    site            TEXT NOT NULL,
    date_reservation TIMESTAMPTZ DEFAULT now(),
    date_expiration  TIMESTAMPTZ,
    statut          TEXT DEFAULT 'en_attente'
                    CHECK (statut IN ('en_attente','disponible','retirée','annulée','expirée')),
    position_file   INTEGER
);

-- ─────────────────────────────────────────────────────────────────────────────
-- MODULE ACQUISITIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE fournisseur (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nom             TEXT NOT NULL,
    email           TEXT,
    format_commande TEXT DEFAULT 'PDF' CHECK (format_commande IN ('PDF','CSV','EDI','EMAIL')),
    remise          REAL DEFAULT 0 CHECK (remise BETWEEN 0 AND 1),
    delai_livraison INTEGER DEFAULT 7,
    compte_client   TEXT,
    actif           BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE budget (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rayon           TEXT NOT NULL,
    site            TEXT NOT NULL,
    annee           INTEGER NOT NULL,
    montant_alloue  DECIMAL(10,2) NOT NULL,
    notes           TEXT,
    UNIQUE(rayon, site, annee)
);

CREATE TABLE panier (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nom             TEXT,
    responsable     TEXT NOT NULL,
    rayon           TEXT,
    site            TEXT,
    fournisseur_id  UUID REFERENCES fournisseur(id),
    statut          TEXT DEFAULT 'brouillon'
                    CHECK (statut IN ('brouillon','validé','commandé',
                                      'partiellement_reçu','reçu','annulé')),
    date_creation   TIMESTAMPTZ DEFAULT now(),
    date_commande   TIMESTAMPTZ,
    date_reception  TIMESTAMPTZ,
    notes           TEXT
);

CREATE TABLE panier_item (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    panier_id       UUID NOT NULL REFERENCES panier(id) ON DELETE CASCADE,
    manifestation_id UUID REFERENCES manifestation(id),
    -- Si la manifestation n'existe pas encore en base (nouveau titre)
    isbn_temp       TEXT,
    titre_temp      TEXT,
    auteur_temp     TEXT,
    editeur_temp    TEXT,
    -- Commande
    quantite        INTEGER NOT NULL DEFAULT 1,
    prix_unitaire   DECIMAL(10,2),
    statut          TEXT DEFAULT 'en_attente'
                    CHECK (statut IN ('en_attente','commandé','reçu','annulé')),
    qte_recue       INTEGER DEFAULT 0,
    date_reception  TIMESTAMPTZ,
    note            TEXT
);

-- ─────────────────────────────────────────────────────────────────────────────
-- RÈGLES DE COTE (configurables par site)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE regle_cote (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    site            TEXT NOT NULL,
    type_document   TEXT,
    genre           TEXT,
    public_vise     TEXT,
    modele          TEXT NOT NULL,     -- '{TYPE}/{AUTEUR_3}/{TOME}'
    exemple         TEXT,
    priorite        INTEGER DEFAULT 10
);

-- ─────────────────────────────────────────────────────────────────────────────
-- FRÉQUENTATION
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE frequentation (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    date            DATE NOT NULL,
    site            TEXT NOT NULL,
    nb_entrees      INTEGER NOT NULL DEFAULT 0,
    source          TEXT DEFAULT 'import',
    UNIQUE(date, site)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- SITES (configuration réseau)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE site (
    code            TEXT PRIMARY KEY,  -- 'ARC', 'TES', 'GUJ', 'TEI'
    nom             TEXT NOT NULL,
    adresse         TEXT,
    telephone       TEXT,
    email           TEXT,
    horaires        JSONB,
    actif           BOOLEAN DEFAULT TRUE
);

-- Données initiales COBAS
INSERT INTO site VALUES
  ('ARC', 'Médiathèque d''Arcachon (MAAT)', '1 Esplanade de Lattre de Tassigny, 33120 Arcachon', NULL, NULL, NULL, TRUE),
  ('TES', 'Médiathèque de La Teste-de-Buch', NULL, NULL, NULL, NULL, TRUE),
  ('GUJ', 'Médiathèque de Gujan-Mestras', NULL, NULL, NULL, NULL, TRUE),
  ('TEI', 'Médiathèque du Teich', NULL, NULL, NULL, NULL, TRUE);

-- ─────────────────────────────────────────────────────────────────────────────
-- DÉSHERBAGE
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE desherbage (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    exemplaire_id   UUID REFERENCES exemplaire(id),
    manifestation_id UUID REFERENCES manifestation(id),
    titre_snapshot  TEXT,
    motif           TEXT NOT NULL,
    score_ioupi     INTEGER,           -- 0-5
    operateur       TEXT,
    date_decision   DATE DEFAULT CURRENT_DATE,
    statut          TEXT DEFAULT 'proposé' CHECK (statut IN ('proposé','validé','effectué','annulé'))
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGERS : mise à jour automatique de updated_at
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_manifestation_updated_at
    BEFORE UPDATE ON manifestation
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_exemplaire_updated_at
    BEFORE UPDATE ON exemplaire
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_adherent_updated_at
    BEFORE UPDATE ON adherent
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER : mise à jour nb_prets sur exemplaire après retour
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION sync_nb_prets()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.date_retour_effectif IS NOT NULL AND OLD.date_retour_effectif IS NULL THEN
        UPDATE exemplaire
        SET nb_prets = nb_prets + 1,
            date_dernier_pret = NEW.date_retour_effectif::date
        WHERE id = NEW.exemplaire_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pret_retour
    AFTER UPDATE ON pret
    FOR EACH ROW EXECUTE FUNCTION sync_nb_prets();
