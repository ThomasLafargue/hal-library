# HAL — Décisions Architecturales Fondamentales
> Décisions définitives — 2026-07-22

---

## 1. ZÉRO ABONNEMENT
- Pas d'ORB, Electre, Nedap, CoLibris
- BnF SRU + Google Books + Open Library (tous gratuits)
- RFID ISO 15693 standard, tags à 0.25€, Web NFC Android natif
- Auto-hébergé, Docker Compose

## 2. TABLETTES + SCANNETTES UNIQUEMENT
- Android avec NFC ISO 15693 intégré
- Clavier Bluetooth pour administration
- Scannette Bluetooth (HID) pour codes-barres
- PWA installable, fonctionne offline

## 3. TOUT INTÉGRÉ
Un seul outil : SIGB + OPAC + base bibliographique + acquisitions

## 4. ACHATS DIRECTS AUX LIBRAIRES
- HAL génère PDF et envoie email directement
- Aucun intermédiaire (pas d'ORB)
- Mollat Bordeaux et tout autre libraire : relation directe

## 5. OPEN SOURCE
AGPL-3.0, GitHub public

---

## HARDWARE NÉCESSAIRE

| Équipement | Modèle recommandé | Prix |
|-----------|------------------|------|
| Tablette Android | Samsung Galaxy Tab A9+ | ~280€ |
| Clavier Bluetooth | Logitech K480 | ~50€ |
| Scannette Bluetooth | Tera D5100 | ~60€ |
| Imprimante étiquettes | Brother QL-820NWBc | ~200€ |
| Tags RFID ISO 15693 | Standard, non propriétaire | ~0.25€/u |

C'est tout. Pas d'encodeur RFID, pas de borne, pas de PC fixe.

---

## RFID — WEB NFC API

```javascript
// Écriture depuis Chrome Android — zéro matériel supplémentaire
async function encoderDocument(identifiant, site) {
  const ndef = new NDEFReader();
  await ndef.write({
    records: [{ recordType: "url", data: `hal://doc/${identifiant}?site=${site}` }]
  });
}
```

Tags ISO 15693 : compatibles tous portiques antivol standard.
AFI 0x07 = sécurisé, AFI 0xC2 = prêt autorisé.

---

## BASE BIBLIOGRAPHIQUE — SOURCES GRATUITES

| Source | Notices | Coût |
|--------|---------|------|
| BnF SRU | 15M notices françaises | Gratuit |
| Google Books | Mondial | Gratuit (quota) |
| Open Library | 30M notices | Gratuit |
| Sudoc | Universitaire FR | Gratuit |
| Base HAL locale | Croît avec l'usage | Gratuit |

Principe d'accumulation : chaque ISBN traité est stocké en local.
Après 2 ans, la base répond sans appel externe pour 95% des cas.

---

## CE QU'ON NE FAIT PAS

| Hors périmètre | Raison |
|----------------|--------|
| ORB | Remplacé par achats directs intégrés |
| Nedap / prestataire RFID | Web NFC standard suffit |
| Electre | BnF + Google Books + accumulation |
| Postes fixes | Tablettes uniquement |
| App store native | PWA suffit |
| Abonnements | Zéro dépendance externe |
