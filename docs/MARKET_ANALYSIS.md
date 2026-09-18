# HAL — Analyse du Marché et des Concurrents
> Synthèse des articles Archimag + analyse terrain — 2026-09-18

---

## SIGNAL LE PLUS FORT : L'ARTICLE D'ARCHIMAG (JUIN 2026)

**"Les SIGB sont-ils solubles dans l'IA ?"** — Cédric Limousin, formateur IA, Archimag n°394

C'est l'article le plus important pour HAL. Un expert de la profession valide exactement
ce qu'on est en train de construire. Extraits clés :

> *"Depuis quelques mois, il est possible de prendre un fichier Excel issu d'une base
> de données, de le copier sur son ordinateur, puis d'envoyer un e-mail au dit PC afin
> de lui demander de créer votre premier SIGB. Comptez une petite dizaine de minutes."*

> *"Il y a quelque chose de magique à voir votre interface aller chercher une clé API
> à la BnF dans son environnement, interroger la base, vérifier qu'elle ne trouve pas
> ce qu'elle veut et aller fouiller Wikipédia et des sites d'éditeurs pour cataloguer
> quinze jeux sortis le mois dernier en se basant simplement sur une liste de
> code-barres. Le tout sans hallucinations."*

> *"Comptez une quarantaine d'euros par mois, la moitié une fois que votre architecture
> est bien en place et bien documentée."*

**Le "SaaSpocalypse"** : Les éditeurs de logiciels par abonnement ont perdu 2 000 milliards
de dollars en bourse en quelques mois. Le marché comprend que l'IA va rendre les SaaS
obsolètes pour les cas d'usage simples. Les SIGB sont exactement dans cette zone de danger.

**Ce que l'expert dit qu'on "ne fait pas encore"** — et que HAL va faire :
> *"Allons plus loin : si ledit bot a accès au code du logiciel et peut le modifier,
> pourquoi ne pas lui donner aussi les clés de la base ?"*

C'est exactement l'architecture d'agent de HAL : l'IA accède directement à la base,
exécute des requêtes, crée des notices, gère les acquisitions — sans interface graphique
intermédiaire pour les tâches complexes.

---

## CARTOGRAPHIE DES CONCURRENTS

### SYRTIS SID — Tech'Advantage (Rueil-Malmaison)
*Source : syrtis.fr + Archimag*

**Ce qu'ils font bien :**
- Seul SIGB natif IFLA-LRM (nouveau standard bibliographique)
- Web 3.0, linked open data, export RDF
- Multiformat : MARC, DC, XML, EAD, ONIX, RDF, CSV
- RFID HF & UHF, SIP2
- Clients prestigieux : Radio France, Conseils Départementaux, villes...
- Responsive web (pas d'app native mais accessible sur tablette)

**Ce qu'ils ne font pas :**
- Aucune IA native mentionnée (ni sur le site, ni dans les articles)
- Pas de mode tablette-first optimisé
- Pas d'acquisitions intégrées type e-commerce
- Pas open source

**Positionnement HAL vs Syrtis** :
Syrtis est le concurrent le plus avancé techniquement. HAL doit s'aligner sur
IFLA-LRM (incontournable) et surpasser sur l'IA et l'UX tablette.

---

### AUREXUS — Récolement et catalogage IA
*Source : Archimag, août 2026 — Bibliothèque de Lille*

**Le signal :** La bibliothèque de Lille vient de confier à un prestataire externe
(AureXus) le récolement de 24 000 ouvrages et le catalogage de 14 000 titres absents
de son SIGB. Un prestataire, pas son SIGB.

**Conclusion pour HAL :** Si même les grandes bibliothèques externalisent le catalogage
et le récolement IA, c'est que leurs SIGB ne le font pas. HAL intègre ces fonctions
nativement, sans prestataire payant.

**Medusa Récolement + Medusa Catalogage** : ce que HAL doit avoir en standard :
- Récolement assisté par scan + IA (comparaison physique vs base)
- Catalogage automatique depuis liste de codes-barres
- Cartographie des fonds manquants

---

### AXIELL QURIA
*Source : axiell.com/fr + Archimag, juin 2024*

- SIGB SaaS suédois, déployé dans 45 pays
- Nouvelle génération : cloud-native, API-first
- Fort en Scandinavie, UK, Australie
- Prix : premium, vise grandes bibliothèques et réseaux
- IA : annoncée mais superficielle (recherche en langage naturel)

**Positionnement HAL vs Axiell** :
Axiell est le concurrent international. HAL est open source, francophone, et 10x
moins cher. L'IA de HAL est profonde là où Axiell a un chatbot basique.

---

### KOHA / PMB (open source)
- Koha : 15 000 installations mondiales, solide mais complexe
- PMB : francophone, bien implanté mais maintenance aléatoire
- Aucun des deux n'a d'IA native
- Installation Koha : compte 1 à 3 jours avec un prestataire

**Positionnement HAL vs Koha/PMB** :
HAL s'installe en 10 minutes (Docker Compose). L'IA est native.
La cible initiale : les bibliothèques qui hésitent entre Koha (complexe) et Decalog (cher).

---

### DECALOG (leader français)
- ~30% du marché lecture publique française
- Propriétaire, fermé, cher (5 000 à 25 000 €/an)
- Interface datée malgré les mises à jour cosmétiques
- Aucune IA native — décoration de recherche en langage naturel seulement
- Export UNIMARC : compatible avec la migration vers HAL

**Positionnement HAL vs Decalog** :
Decalog est la cible principale. Les bibliothèques qui renouvellent leur contrat
Decalog sont la cible idéale : elles ont les données (exportables UNIMARC), elles
connaissent la douleur, elles sont prêtes à changer.

---

## CE QUE HAL FAIT QUE PERSONNE NE FAIT

| Fonctionnalité | HAL | Syrtis | Axiell | Koha | Decalog |
|----------------|-----|--------|--------|------|---------|
| IA native profonde | ✅ | ❌ | ⚠️ | ❌ | ❌ |
| Tablette-first PWA | ✅ | ⚠️ | ⚠️ | ❌ | ❌ |
| Zéro abonnement | ✅ | ❌ | ❌ | ✅ | ❌ |
| Acquisitions e-commerce | ✅ | ❌ | ❌ | ❌ | ❌ |
| RFID sans prestataire | ✅ | ⚠️ | ⚠️ | ❌ | ❌ |
| Récolement IA intégré | ✅ | ❌ | ❌ | ❌ | ❌ |
| Catalogage depuis codes-barres | ✅ | ⚠️ | ❌ | ❌ | ❌ |
| Open source | ✅ | ❌ | ❌ | ✅ | ❌ |
| Installation < 10 min | ✅ | ❌ | ❌ | ❌ | ❌ |
| Recherche conversationnelle | ✅ | ❌ | ⚠️ | ❌ | ❌ |
| IFLA-LRM natif | 🔜 | ✅ | ⚠️ | ⚠️ | ❌ |

---

## OPPORTUNITÉS IDENTIFIÉES

### 1. Le "SaaSpocalypse" crée une fenêtre
Les bibliothèques vont questionner leurs abonnements. HAL arrive au bon moment
avec une alternative crédible, open source, sans abonnement.

### 2. L'IA en bibliothèque est attendue mais pas encore là
Les bibliothécaires lisent Archimag, ils savent que l'IA peut automatiser le
catalogage, les acquisitions, le récolement. Aucun SIGB ne le fait vraiment.
HAL le fait.

### 3. AureXus valide le marché du catalogage IA
Si Lille paie un prestataire pour cataloguer 14 000 titres, c'est qu'il y a
un problème non résolu. HAL le résout nativement.

### 4. IFLA-LRM est incontournable
Le nouveau standard bibliographique (IFLA-LRM, RDA-FR) est adopté. Seul Syrtis
l'implémente vraiment. HAL doit le faire dès le départ — c'est un critère de
légitimité professionnelle.

### 5. La migration depuis Decalog est possible
Decalog exporte en UNIMARC. HAL importe UNIMARC. Les données ne sont pas
prisonnières. Un script de migration peut être automatisé.

---

## POINTS DE VIGILANCE POUR HAL

### IFLA-LRM — obligation normative
Le nouveau modèle bibliographique (International Federation of Library Associations
Library Reference Model) est désormais la norme. Il restructure la façon dont
on modélise les œuvres, expressions, manifestations, items (FRBR).
**HAL doit l'implémenter dès le départ** pour être pris au sérieux par les
bibliothécaires professionnels.

### SIP2 — protocole d'interopérabilité
Le protocole SIP2 (Standard Interchange Protocol) est utilisé par les portiques
antivol, les automates de prêt, les systèmes de sécurité. HAL doit le supporter
pour être compatible avec les équipements existants.

### RGPD — données adhérents
La gestion des adhérents nécessite une architecture RGPD stricte : consentement,
droit à l'oubli, portabilité, durées de conservation. C'est une contrainte légale
non négociable.

### Marchés publics
Les bibliothèques publiques passent leurs marchés en appel d'offres. HAL doit
anticiper les critères typiques : hébergement France/UE, support en français,
documentation, références clients, clause de réversibilité.

---

## STRATÉGIE DE DÉPLOIEMENT

### Phase 1 : Prouver avec MAAT Arcachon
Déployer HAL complet sur le réseau COBAS (4 sites, 44 000 documents).
C'est la référence. Chaque fonctionnalité est testée en conditions réelles.

### Phase 2 : Convaincre 3-5 bibliothèques pionnières
Cibler des bibliothèques qui renouvellent Decalog ou qui cherchent une alternative
à Koha. Offrir le déploiement gratuit contre du feedback.

### Phase 3 : BBF 2027
La conférence des bibliothèques (Bibliothèques, Bibliothécaires de France) est
le moment pour présenter HAL à la profession. Un projet concret, des références,
une démo live.

### Phase 4 : Communauté open source
GitHub, documentation, forum, contributions. Le modèle économique : HAL Cloud
(hébergement géré) et HAL Pro (support et formations).

---

*Analyse réalisée le 2026-09-18 — Sources : Archimag, syrtis.fr, axiell.com*
