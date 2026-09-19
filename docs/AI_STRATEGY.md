# HAL — Outils IA et Stratégie
> Spécification des composants IA — 2026-09-18

---

## PRINCIPE : IA NATIVE, PAS IA EN OPTION

Chez HAL, l'IA n'est pas un module qu'on ajoute en bout de chaîne.
Elle est dans l'architecture depuis le premier jour.
Chaque tâche répétitive est automatisée. Chaque décision est guidée par les données.

---

## LES 8 COMPOSANTS IA

### 1. CLAUDE API — Le cerveau central
*Anthropic · Pay-per-use · Pas d'abonnement*

Le modèle de langage principal de HAL. Il intervient partout :

**OPAC conversationnel**
```
Lecteur : "je cherche un livre pour ma nièce de 9 ans qui adore les chevaux"
Claude  : analyse l'intention → traduit en requête SQL →
          sélectionne 5 titres disponibles → explique pourquoi
```

**Catalogage assisté**
```
Agent scanne un ISBN non trouvé dans BnF/Google Books
Claude : "Je vois un livre de littérature jeunesse de 2023.
          Voici une notice complète basée sur la couverture.
          Proposez-vous Dewey 843 (littérature française) ?"
```

**Désherbage guidé**
```
HAL : "Ce livre a 0 prêt depuis 4 ans, est en mauvais état,
       et son contenu date de 1987. Score IOUPI : 4/5.
       Je recommande le retrait. Confirmer ?"
```

**Rapport annuel automatique**
```
Direction : "Génère le rapport annuel 2026 format Ministère de la Culture"
HAL       : génère le document complet avec les vraies données de la base
```

---

### 2. PGVECTOR — Recherche sémantique
*Extension PostgreSQL · Open source · Gratuit*

```sql
-- Ajouter pgvector à PostgreSQL
CREATE EXTENSION vector;

-- Stocker l'embedding de chaque notice
ALTER TABLE manifestation ADD COLUMN embedding vector(1536);

-- Recherche sémantique : "trouver des livres similaires"
SELECT titre, 1 - (embedding <=> $1) AS similarite
FROM manifestation
WHERE embedding IS NOT NULL
ORDER BY embedding <=> $1
LIMIT 10;
```

**Ce que ça change concrètement :**
- "J'ai aimé Harry Potter" → trouve Narnia, Percy Jackson, Eragon
- "un polar sombre avec une femme détective" → trouve Millenium, Connelly, Slaughter
- Zéro mots-clés nécessaires — la requête en français naturel suffit
- Recommandations "vous aimerez aussi" dans l'OPAC

**Job d'embeddings (tourne en background) :**
```python
# Générer les embeddings pour toutes les notices
async def generer_embedding(notice):
    texte = f"{notice.titre} {notice.serie} {notice.auteurs} {notice.resume} {notice.mots_cles}"
    embedding = await anthropic.embeddings.create(
        model="voyage-large-2",  # Voyage AI (partenaire Anthropic)
        input=texte
    )
    await db.update_embedding(notice.id, embedding)
```

---

### 3. CLAUDE VISION — Catalogage par photo
*Anthropic · Intégré dans Claude API*

Pointer la caméra de la tablette sur n'importe quel document → notice créée.

**Flux :**
```
Agent ouvre HAL Desk → "Cataloguer par photo"
    ↓
Prend une photo de la couverture avec la tablette
    ↓
Claude Vision analyse l'image :
  - Lit le titre (même manuscrit, même oblique)
  - Identifie l'auteur
  - Lit l'ISBN si visible
  - Détecte le genre (BD, roman, documentaire...)
  - Estime le public visé
    ↓
HAL complète avec BnF/Google Books si ISBN trouvé
    ↓
Notice proposée à l'agent pour validation
```

**Cas d'usage critiques :**
- Fonds anciens sans code-barres ni ISBN
- ISBN partiellement effacé ou abîmé
- Documents en langues étrangères (arabe, japonais pour les mangas)
- Dons non catalogués

---

### 4. WHISPER — Recherche vocale
*OpenAI · Open source · Gratuit · Tourne en local*

```
"HAL, est-ce que vous avez One Piece tome 5 ?"
         ↓ Whisper transcrit en texte
"HAL, est-ce que vous avez One Piece tome 5 ?"
         ↓ Claude interprète et cherche
"Oui, One Piece tome 5 est disponible à Arcachon, rayon Manga, cote MAN/ONE/5"
```

**Installation locale (zéro coût, zéro envoi externe) :**
```bash
pip install openai-whisper
# Modèle medium (meilleur pour le français)
whisper audio.wav --model medium --language fr
```

**Pourquoi c'est critique pour Arcachon :**
60.5% de la population a plus de 60 ans. Le clavier n'est pas leur outil naturel.
La voix l'est. Whisper + Claude = interface vocale complète.

---

### 5. SPACY — NLP français
*Open source · Gratuit · Tourne en local*

Traitement automatique du texte français pour le catalogage.

```python
import spacy
nlp = spacy.load("fr_core_news_lg")

# Normalisation des noms d'auteurs
def normaliser_auteur(texte_brut):
    # "J.K. Rowling" → "Rowling, Joanne"
    # "Antoine de Saint-Exupéry" → "Saint-Exupéry, Antoine de"
    doc = nlp(texte_brut)
    persons = [ent.text for ent in doc.ents if ent.label_ == "PER"]
    return persons

# Détection de série dans les titres
def detecter_serie(titre):
    # "One Piece - Tome 1 : À l'aube d'une grande aventure"
    # → série: "One Piece", tome: "1"
    patterns = [
        r'(.+?)\s*[-–]\s*[Tt]ome\s*(\d+)',
        r'(.+?)\s*T\.?\s*(\d+)',
        r'(.+?)\s*[Vv]ol\.?\s*(\d+)',
    ]
    ...
```

**Cas d'usage :**
- Normalisation des noms d'auteurs importés depuis UNIMARC (incohérents d'un SIGB à l'autre)
- Détection automatique des séries dans les titres
- Extraction de mots-clés depuis les résumés
- Correction des fautes dans les notices importées

---

### 6. OLLAMA — Modèles locaux (confidentialité)
*Open source · Gratuit · Données 100% locales*

Pour les données sensibles qui ne doivent PAS quitter le réseau de la bibliothèque.

```bash
# Installer Ollama sur le serveur
curl -fsSL https://ollama.ai/install.sh | sh

# Télécharger Mistral (excellent en français)
ollama pull mistral

# Ou Llama 3.1 pour les tâches complexes
ollama pull llama3.1
```

**Utilisation dans HAL :**
```python
# Tâches sur données sensibles (adhérents, historiques) → Ollama local
import ollama

def analyser_lecteur_local(adherent_data):
    """Analyse le profil de lecture sans envoyer les données au cloud"""
    response = ollama.chat(model='mistral', messages=[{
        'role': 'user',
        'content': f"Analyse ce profil de lecteur anonymisé et suggère des genres : {adherent_data}"
    }])
    return response['message']['content']

# Tâches génériques (suggestions, OPAC) → Claude API cloud
```

**Règle :**
- Données adhérents / historiques prêts → Ollama local
- Recherche, catalogage, acquisitions → Claude API

---

### 7. CELERY + REDIS — Orchestration des jobs IA
*Open source · Gratuit*

Sans orchestration, les jobs IA bloquent l'application.
Celery gère les files d'attente des tâches longues.

```python
# tasks.py
from celery import Celery

app = Celery('hal', broker='redis://localhost:6379/0')

@app.task
def enrichir_notice(manifestation_id):
    """Enrichit une notice depuis BnF puis Google Books"""
    ...

@app.task
def generer_embedding(manifestation_id):
    """Génère et stocke l'embedding d'une notice"""
    ...

@app.task
def envoyer_alertes_retards():
    """Job nocturne — alertes retards"""
    ...

# Celery Beat — scheduler
CELERYBEAT_SCHEDULE = {
    'enrichissement-notices': {
        'task': 'tasks.enrichir_notices_batch',
        'schedule': 60.0,  # toutes les minutes
    },
    'alertes-retards': {
        'task': 'tasks.envoyer_alertes_retards',
        'schedule': crontab(hour=23, minute=0),  # 23h chaque jour
    },
    'stats-quotidiennes': {
        'task': 'tasks.calculer_stats',
        'schedule': crontab(hour=0, minute=0),  # minuit
    },
}
```

---

### 8. TESSERACT OCR — Lecture des anciens documents
*Open source · Gratuit · Tourne en local*

Pour les fonds patrimoniaux sans ISBN.

```python
import pytesseract
from PIL import Image

def lire_couverture(image_path):
    """Extrait le texte d'une couverture pour créer une notice"""
    img = Image.open(image_path)

    # OCR en français
    texte = pytesseract.image_to_string(img, lang='fra')

    # Passer à Claude pour structurer
    notice = claude.messages.create(
        model="claude-sonnet-4-6",
        messages=[{
            "role": "user",
            "content": f"Extrais titre, auteur, éditeur, année de ce texte de couverture : {texte}"
        }]
    )
    return notice
```

---

## STACK IA COMPLÈTE

```
Claude API (Anthropic)
  ├── Sonnet 4.6 : OPAC, catalogage, acquisitions, rapports
  ├── Opus 5     : tâches complexes (désherbage, analyse stratégique)
  └── Vision     : catalogage par photo, lecture couvertures

Voyage AI (embeddings)
  └── voyage-large-2 : embeddings notices → pgvector PostgreSQL

Whisper (OpenAI, local)
  └── medium FR : reconnaissance vocale OPAC + guichet

Ollama (local)
  ├── Mistral    : tâches sur données sensibles
  └── Llama 3.1  : tâches complexes offline

spaCy (local)
  └── fr_core_news_lg : NLP français, NER, normalisation

Tesseract (local)
  └── fra : OCR documents anciens

Celery + Redis
  └── Orchestration : enrichissement, alertes, stats, embeddings
```

---

## BUDGET IA ESTIMÉ (par mois)

| Composant | Usage estimé | Coût/mois |
|-----------|-------------|-----------|
| Claude Sonnet 4.6 | ~500K tokens/mois (OPAC + catalogage) | ~3€ |
| Claude Opus 5 | ~50K tokens/mois (tâches complexes) | ~5€ |
| Voyage AI (embeddings) | ~130K notices × 1536 dims (one-time) + MAJ | ~2€ |
| Ollama / Whisper / spaCy / Tesseract | Locaux | 0€ |
| **Total** | | **~10€/mois** |

*Pour une médiathèque : moins qu'un café par semaine.*

---

## ROADMAP IA

| Phase | Quand | IA déployée |
|-------|-------|-------------|
| 1 — OPAC | Semaines 3-6 | Claude API (recherche conversationnelle) |
| 2 — Enrichissement | Semaines 1-4 | Celery + BnF + Google Books |
| 3 — Embeddings | Semaines 5-8 | pgvector + Voyage AI |
| 4 — Vision | Semaines 9-12 | Claude Vision (catalogage photo) |
| 5 — Voix | Semaines 13-16 | Whisper local |
| 6 — Confidentialité | Semaines 15-18 | Ollama (données sensibles) |

---

*Dernière mise à jour : 2026-09-18*
