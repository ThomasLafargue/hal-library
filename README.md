# HAL — Hub d'Accès à la Lecture

> *"I'm sorry Dave, I can't do that."*
> HAL, lui, fait tout ce qu'on lui demande.

**Le premier SIGB conçu nativement avec l'IA, dans un esprit Apple.**

---

## Ce que c'est

HAL est un système intégré de gestion de bibliothèque (SIGB) open source, conçu pour que n'importe qui puisse gérer une bibliothèque sans formation technique.

Tout est dans un seul outil :
- 📚 **Catalogue** — notices enrichies automatiquement (BnF, Google Books, Open Library)
- 🔍 **OPAC** — recherche publique conversationnelle ("j'ai 8 ans et j'aime les dragons")
- 🔄 **Circulation** — prêts, retours, réservations sur tablette
- 🛒 **Acquisitions** — paniers, commandes directes aux libraires, réception, RFID
- 📊 **Statistiques** — tableaux de bord, rapport annuel en 1 clic

## Ce que ce n'est pas

- ❌ Pas d'abonnement
- ❌ Pas de prestataire RFID
- ❌ Pas d'Electre, pas d'ORB, pas de plateforme intermédiaire
- ❌ Pas de postes fixes

## Comment ça fonctionne

**Tablettes Android + scannettes Bluetooth.**
C'est tout le matériel nécessaire.

HAL tourne en PWA (Progressive Web App) sur tablette Android.
Le RFID utilise le NFC intégré des tablettes (ISO 15693, standard universel).
Les étiquettes s'impriment en Bluetooth sur une Brother QL.
Les commandes partent par email directement au libraire.

## Stack technique

```
Backend   Python + FastAPI
Frontend  Next.js 14 + Tailwind CSS (PWA)
Base      PostgreSQL auto-hébergé
RFID      Web NFC API (Chrome Android, ISO 15693)
Biblio    BnF SRU + Google Books + Open Library (gratuits)
Email     SMTP standard
Deploy    Docker Compose (une commande)
```

## Démarrage

```bash
git clone https://github.com/ThomasLafargue/hal-library
cd hal-library
cp .env.example .env
docker compose up
# HAL est accessible sur http://localhost:3000
```

## Déploiement de référence

[Médiathèque d'Arcachon (MAAT)](https://github.com/ThomasLafargue/mediatheque-arcachon) — réseau COBAS, 4 sites, 44 000+ documents.

## Licence

AGPL-3.0 — open source, contributions bienvenues.

---

*Initié en juillet 2026 par Thomas Lafargue, MAAT Arcachon.*
