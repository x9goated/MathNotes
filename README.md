# MathNotes

Appli iPad de prise de notes pour les maths, à l'Apple Pencil.

- `MathNotes.swiftpm/` : le code (s'ouvre aussi dans Swift Playgrounds sur l'iPad).
- `project.yml` + `.github/workflows/build-ipa.yml` : compilation dans le cloud (GitHub Actions) → `MathNotes.ipa`.

## Obtenir le .ipa

Chaque `git push` sur `main` lance la compilation (ou onglet **Actions → Build IPA → Run workflow**).
Quand elle est verte : ouvre le run → section **Artifacts** → télécharge `MathNotes-ipa` → dézippe → `MathNotes.ipa`.

## Installer sur l'iPad avec Sideloadly (Windows)

Une seule fois :
1. Installer **iTunes** et **iCloud** en version *site web d'Apple* (pas celles du Microsoft Store — les désinstaller si besoin).
2. Installer **Sideloadly** depuis sideloadly.io.
3. Brancher l'iPad en USB → sur l'iPad, **Se fier à cet ordinateur**.

À chaque installation :
1. Glisser `MathNotes.ipa` dans Sideloadly, choisir l'iPad, entrer son identifiant Apple, **Start**.
2. Première fois seulement, sur l'iPad :
   - **Réglages → Général → VPN et gestion de l'appareil** → faire confiance à son identifiant Apple ;
   - **Réglages → Confidentialité et sécurité → Mode développeur** → activer, redémarrer.

## Limites du compte Apple gratuit

- L'appli expire au bout de **7 jours** : relancer l'installation (ou activer le rafraîchissement automatique de Sideloadly, PC et iPad sur le même Wi-Fi).
- 3 applis installées ainsi en même temps au maximum.
- Les notes restent sur l'iPad tant qu'on réinstalle **par-dessus** (sans supprimer l'appli).
