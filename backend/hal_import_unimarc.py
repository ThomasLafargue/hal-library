"""
hal_import_unimarc.py — Importeur UNIMARC pour HAL
Importe un fichier .mrc (ISO 2709) dans la base PostgreSQL de HAL.

Usage :
    python hal_import_unimarc.py <fichier.mrc> [--site ARC]
    python hal_import_unimarc.py imports/*.mrc --site TES --dry-run

Adapté du parser MAAT Arcachon (actualisercatalogue.py)
Compatible exports Decalog/Koha/PMB/Syrtis
"""

import os
import sys
import re
import argparse
import hashlib
from datetime import datetime
from pathlib import Path

import psycopg2
import psycopg2.extras

# ─────────────────────────────────────────────────────────────────────────────
# CONNEXION POSTGRESQL
# ─────────────────────────────────────────────────────────────────────────────
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://hal:hal_secret@localhost:5432/hal")


def get_conn():
    return psycopg2.connect(DATABASE_URL)


# ─────────────────────────────────────────────────────────────────────────────
# PARSER UNIMARC (ISO 2709)
# ─────────────────────────────────────────────────────────────────────────────
class ChampUnimarc:
    def __init__(self, tag, indicateurs, sous_champs):
        self.tag = tag
        self.indicateurs = indicateurs
        self.sous_champs = sous_champs  # dict { code : [valeurs] }

    def get(self, code, defaut=None):
        vals = self.sous_champs.get(code, [])
        return vals[0] if vals else defaut

    def get_all(self, code):
        return self.sous_champs.get(code, [])


def parser_notice_unimarc(data_bytes):
    """Parse une notice UNIMARC ISO 2709 en liste de ChampUnimarc."""
    try:
        data = data_bytes.decode('utf-8', errors='replace')
    except Exception:
        data = data_bytes.decode('latin-1', errors='replace')

    if len(data) < 24:
        return None, []

    # En-tête (leader)
    longueur_totale = int(data[0:5])
    base_donnees = int(data[12:17])

    # Répertoire (champs 24 à base_donnees-1)
    repertoire = data[24:base_donnees - 1]
    nb_champs = len(repertoire) // 12
    zone_donnees = data[base_donnees:]

    champs = []
    for i in range(nb_champs):
        entree = repertoire[i*12:(i+1)*12]
        tag = entree[0:3]
        longueur = int(entree[3:7])
        debut = int(entree[7:12])

        contenu = zone_donnees[debut:debut + longueur - 1]  # sans le séparateur

        if tag < '010':
            # Champs fixes (001-009)
            champs.append(ChampUnimarc(tag, '  ', {'_': [contenu]}))
            continue

        if len(contenu) < 2:
            continue

        indicateurs = contenu[0:2]
        sous_champs_bruts = contenu[2:].split('\x1f')

        sous_champs = {}
        for sc in sous_champs_bruts:
            if len(sc) < 1:
                continue
            code = sc[0]
            valeur = sc[1:].strip()
            if valeur:
                sous_champs.setdefault(code, []).append(valeur)

        champs.append(ChampUnimarc(tag, indicateurs, sous_champs))

    return data, champs


def lire_notices_mrc(chemin_fichier):
    """Lit un fichier .mrc et retourne une liste de (bytes notice, champs)."""
    notices = []
    with open(chemin_fichier, 'rb') as f:
        while True:
            # Lire les 5 premiers octets pour connaître la longueur
            header = f.read(5)
            if not header or len(header) < 5:
                break
            try:
                longueur = int(header)
            except ValueError:
                break

            # Lire le reste de la notice
            reste = f.read(longueur - 5)
            data_bytes = header + reste

            _, champs = parser_notice_unimarc(data_bytes)
            if champs:
                notices.append(champs)

    return notices


# ─────────────────────────────────────────────────────────────────────────────
# EXTRACTION DES DONNÉES UNIMARC
# ─────────────────────────────────────────────────────────────────────────────
def extraire_notice(champs_list):
    """Extrait les données bibliographiques d'une liste de champs UNIMARC."""
    champs = {c.tag: c for c in champs_list}
    champs_multi = {}
    for c in champs_list:
        champs_multi.setdefault(c.tag, []).append(c)

    def get(tag, code, defaut=None):
        c = champs.get(tag)
        return c.get(code) if c else defaut

    def get_all(tag, code):
        result = []
        for c in champs_multi.get(tag, []):
            result.extend(c.get_all(code))
        return result

    # ── EAN / ISBN ──────────────────────────────────────────────────────────
    ean = None
    isbn = None

    # 010 = ISBN
    isbn_raw = get('010', 'a')
    if isbn_raw:
        isbn_clean = re.sub(r'[^0-9X]', '', isbn_raw.upper())
        if len(isbn_clean) == 13:
            ean = isbn_clean
            isbn = isbn_clean
        elif len(isbn_clean) == 10:
            isbn = isbn_clean
            # Convertir ISBN-10 → EAN-13
            ean = '978' + isbn_clean[:-1]

    # 073 = EAN (code-barres produit)
    ean_raw = get('073', 'a')
    if ean_raw and not ean:
        ean = re.sub(r'[^0-9]', '', ean_raw)
        if len(ean) != 13:
            ean = None

    # Identifiant interne si pas d'EAN
    id_interne = get('001', '_')

    # ── TITRE ───────────────────────────────────────────────────────────────
    titre = get('200', 'a', '')
    sous_titre = get('200', 'e')

    # Mention de partie (tome)
    mention_partie = get('200', 'h')  # "tome 1"
    titre_partie = get('200', 'i')   # "Les pouvoirs animaux"

    # ── SÉRIE ────────────────────────────────────────────────────────────────
    serie = None
    tome = None

    # 225 = collection/série
    serie_225 = get('225', 'a')
    tome_225 = get('225', 'v')

    # 500 = titre uniforme (peut contenir la série)
    serie_500 = get('500', 'a')

    # 410 = série
    serie_410 = get('410', 't')
    tome_410 = get('410', 'v')

    serie = serie_410 or serie_500 or serie_225
    tome = tome_410 or tome_225 or mention_partie

    # Normalisation du tome (extraire juste le numéro)
    if tome:
        m = re.search(r'(\d+)', tome)
        if m:
            tome = m.group(1)

    # ── AUTEURS ──────────────────────────────────────────────────────────────
    auteurs = []

    # 700 = auteur principal (personne)
    for c in champs_multi.get('700', []):
        nom = c.get('a', '')
        prenom = c.get('b', '')
        nom_complet = f"{nom}, {prenom}".strip(', ') if prenom else nom
        if nom_complet:
            auteurs.append({'nom': nom, 'prenom': prenom, 'role': 'auteur'})

    # 701 = co-auteur
    for c in champs_multi.get('701', []):
        nom = c.get('a', '')
        prenom = c.get('b', '')
        if nom:
            auteurs.append({'nom': nom, 'prenom': prenom, 'role': 'auteur'})

    # 702 = contributeur (illustrateur, traducteur...)
    ROLES_702 = {'730': 'traducteur', '440': 'illustrateur', '400': 'auteur',
                 '650': 'scenariste', '600': 'dessinateur'}
    for c in champs_multi.get('702', []):
        nom = c.get('a', '')
        prenom = c.get('b', '')
        code_role = c.get('4', '400')
        role = ROLES_702.get(code_role, 'autre')
        if nom:
            auteurs.append({'nom': nom, 'prenom': prenom, 'role': role})

    # 710 = collectivité auteur
    for c in champs_multi.get('710', []):
        nom = c.get('a', '')
        if nom:
            auteurs.append({'nom': nom, 'prenom': None, 'role': 'auteur', 'type': 'collectivite'})

    # ── ÉDITEUR ───────────────────────────────────────────────────────────────
    editeur = get('210', 'c')
    lieu_edition = get('210', 'a', 'Paris')
    date_publication = get('210', 'd')
    if date_publication:
        m = re.search(r'(\d{4})', date_publication)
        date_publication = m.group(1) if m else date_publication

    # ── COLLECTION ────────────────────────────────────────────────────────────
    collection = get('225', 'a')

    # ── DEWEY ─────────────────────────────────────────────────────────────────
    dewey = None
    dewey_libelle = None
    for c in champs_multi.get('676', []):
        dewey = c.get('a')
        if dewey:
            break
    # Fallback 686
    if not dewey:
        dewey = get('686', 'a')

    # Libellé Dewey depuis 676$b ou 610
    dewey_libelle = get('676', 'b') or get('610', 'a')

    # ── MOTS-CLÉS ─────────────────────────────────────────────────────────────
    mots_cles = []
    for tag in ['600', '601', '602', '605', '606', '607', '608', '610']:
        for c in champs_multi.get(tag, []):
            for code in ['a', 'b', 'x', 'y', 'z']:
                mots_cles.extend(c.get_all(code))

    # ── DESCRIPTION PHYSIQUE ──────────────────────────────────────────────────
    desc_physique = get('215', 'a')
    if desc_physique:
        pages = get('215', 'c')
        if pages:
            desc_physique = f"{desc_physique} ; {pages}"

    # ── TYPE DE DOCUMENT ──────────────────────────────────────────────────────
    type_doc = 'LIVRE'
    leader_type = None  # sera extrait du leader si disponible

    # Heuristique sur le titre/genre
    if serie and any(w in (serie or '').lower() for w in ['manga', 'naruto', 'one piece', 'dragon ball']):
        type_doc = 'MANGA'
    elif any(w in titre.lower() for w in ['dvd', 'blu-ray', 'film']):
        type_doc = 'DVD'
    elif any(w in titre.lower() for w in ['jeu', 'puzzle', 'lego']):
        type_doc = 'JEU'

    # ── LANGUE ────────────────────────────────────────────────────────────────
    langue = get('101', 'a', 'fre')

    # ── RÉSUMÉ ────────────────────────────────────────────────────────────────
    resume = get('330', 'a')

    return {
        'ean': ean,
        'isbn': isbn,
        'id_interne': id_interne,
        'titre': titre or '(titre inconnu)',
        'sous_titre': sous_titre,
        'serie': serie,
        'tome': tome,
        'collection': collection,
        'auteurs': auteurs,
        'editeur': editeur,
        'lieu_edition': lieu_edition,
        'date_publication': date_publication,
        'dewey': dewey,
        'dewey_libelle': dewey_libelle,
        'mots_cles': list(set(mots_cles))[:20],  # max 20
        'description_physique': desc_physique,
        'langue': langue,
        'resume': resume,
        'type_document': type_doc,
    }


# ─────────────────────────────────────────────────────────────────────────────
# IMPORT EN BASE
# ─────────────────────────────────────────────────────────────────────────────
def normaliser_nom(nom):
    """Normalise un nom d'agent pour la déduplication."""
    return re.sub(r'\s+', ' ', nom.strip().upper()) if nom else None


def upsert_agent(cur, nom, prenom=None, type_agent='personne'):
    """Insère ou récupère un agent. Retourne l'UUID."""
    nom_norm = normaliser_nom(nom)
    if not nom_norm:
        return None

    cur.execute("""
        INSERT INTO agent (nom, prenom, type)
        VALUES (%s, %s, %s)
        ON CONFLICT DO NOTHING
        RETURNING id
    """, (nom_norm, prenom, type_agent))
    row = cur.fetchone()
    if row:
        return row[0]

    # Récupérer l'existant
    cur.execute("SELECT id FROM agent WHERE nom = %s AND type = %s", (nom_norm, type_agent))
    row = cur.fetchone()
    return row[0] if row else None


def upsert_manifestation(cur, notice):
    """Insère ou met à jour une manifestation. Retourne l'UUID."""
    ean = notice.get('ean')
    isbn = notice.get('isbn')

    # Clé de déduplication : EAN > ISBN > hash(titre+editeur+date)
    if ean:
        cur.execute("SELECT id FROM manifestation WHERE ean = %s", (ean,))
    elif isbn:
        cur.execute("SELECT id FROM manifestation WHERE isbn = %s", (isbn,))
    else:
        # Déduplication par hash titre+éditeur+date
        cle = hashlib.md5(
            f"{notice['titre']}|{notice.get('editeur','')}|{notice.get('date_publication','')}".encode()
        ).hexdigest()
        cur.execute("SELECT id FROM manifestation WHERE isbn = %s", (f"HASH:{cle}",))

    row = cur.fetchone()
    if row:
        return row[0], False  # Existait déjà

    # Insertion
    cur.execute("""
        INSERT INTO manifestation (
            ean, isbn, titre, sous_titre, serie, tome, collection,
            editeur, lieu_edition, date_publication, langue,
            dewey, dewey_libelle, mots_cles,
            description_physique, resume
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s,
            %s, %s, %s,
            %s, %s
        )
        RETURNING id
    """, (
        ean, isbn or (f"HASH:{hashlib.md5(notice['titre'].encode()).hexdigest()}" if not ean else None),
        notice['titre'], notice.get('sous_titre'), notice.get('serie'), notice.get('tome'),
        notice.get('collection'), notice.get('editeur'), notice.get('lieu_edition', 'Paris'),
        notice.get('date_publication'), notice.get('langue', 'fre'),
        notice.get('dewey'), notice.get('dewey_libelle'),
        notice.get('mots_cles') or [],
        notice.get('description_physique'), notice.get('resume')
    ))
    row = cur.fetchone()
    return row[0], True  # Nouvelle


def importer_fichier_mrc(chemin_fichier, site='ARC', dry_run=False):
    """Importe un fichier .mrc dans HAL."""
    chemin = Path(chemin_fichier)
    print(f"\n{'='*60}")
    print(f"Import : {chemin.name} → site {site}")
    print(f"{'='*60}")

    notices_raw = lire_notices_mrc(chemin_fichier)
    print(f"Notices lues : {len(notices_raw)}")

    if dry_run:
        print("(Mode simulation — aucune écriture)")
        for i, champs in enumerate(notices_raw[:5]):
            notice = extraire_notice(champs)
            print(f"  [{i+1}] {notice['titre'][:50]} — EAN:{notice.get('ean')} — {notice.get('editeur','?')}")
        return

    conn = get_conn()
    cur = conn.cursor()

    stats = {'nouvelles': 0, 'existantes': 0, 'erreurs': 0}
    debut = datetime.now()

    for i, champs in enumerate(notices_raw):
        try:
            notice = extraire_notice(champs)

            # Upsert manifestation
            manifestation_id, est_nouvelle = upsert_manifestation(cur, notice)

            if est_nouvelle:
                stats['nouvelles'] += 1

                # Agents
                for auteur in notice.get('auteurs', []):
                    agent_id = upsert_agent(
                        cur, auteur['nom'], auteur.get('prenom'),
                        auteur.get('type', 'personne')
                    )
                    # TODO : lier via oeuvre_agent quand l'oeuvre sera créée
            else:
                stats['existantes'] += 1

            # Commit par lots de 500
            if (i + 1) % 500 == 0:
                conn.commit()
                print(f"  {i+1}/{len(notices_raw)} — "
                      f"{stats['nouvelles']} nouvelles, {stats['existantes']} existantes", end='\r')

        except Exception as e:
            stats['erreurs'] += 1
            conn.rollback()
            if stats['erreurs'] <= 5:
                print(f"\n  ✗ Erreur notice {i+1} : {e}")

    conn.commit()
    cur.close()
    conn.close()

    duree = (datetime.now() - debut).seconds
    print(f"\n✓ Import terminé en {duree}s")
    print(f"  Nouvelles notices  : {stats['nouvelles']}")
    print(f"  Déjà en base       : {stats['existantes']}")
    print(f"  Erreurs            : {stats['erreurs']}")
    print(f"  Total traité       : {len(notices_raw)}")


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Importer un fichier UNIMARC dans HAL')
    parser.add_argument('fichiers', nargs='+', help='Fichier(s) .mrc à importer')
    parser.add_argument('--site', default='ARC',
                        choices=['ARC', 'TES', 'GUJ', 'TEI'],
                        help='Code du site (ARC=Arcachon, TES=La Teste, GUJ=Gujan, TEI=Le Teich)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Simulation sans écriture en base')

    args = parser.parse_args()

    for fichier in args.fichiers:
        if Path(fichier).exists():
            importer_fichier_mrc(fichier, site=args.site, dry_run=args.dry_run)
        else:
            print(f"✗ Fichier non trouvé : {fichier}")
