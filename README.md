# SFC + DISM Full Health Checker (100% natif)

Outil PowerShell avancé pour l’analyse, la réparation et le reporting de l’intégrité Windows via DISM et SFC.  
Génère des rapports filtrés (TXT + HTML triable) et un résumé statistique, avec nettoyage automatique des anciens rapports.

## Fonctionnalités

- Exécution DISM CheckHealth, ScanHealth, RestoreHealth et SFC /scannow
- Analyse et filtrage des logs CBS/DISM selon patterns critiques (corrupt, failed, repaired…)
- Génération de rapports horodatés (TXT et HTML triable) sur le bureau
- Résumé statistique (succès, avertissements, erreurs)
- Nettoyage automatique des anciens rapports (>7 jours)
- Mode lecture seule si non exécuté en administrateur (aucune modification système)

## Utilisation

- **En administrateur** : toutes les opérations (analyse, réparation, prompts interactifs, reboot)
- **Sans droits admin** : lecture/analyse/rapport uniquement, aucune réparation
- Pour exécuter sans modifier la politique globale :
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\CheckSfc_Dism.ps1
