# ======================================
# Script : SFC + DISM Full Health Checker (100% natif)
# Auteur : ps81frt
# Date   : 2026-04-03
#
# Description :
#   Vérification et réparation avancée de l’intégrité Windows via DISM et SFC.
#   Filtrage et synthèse des logs CBS/DISM selon patterns critiques (corrupt, failed, repaired...).
#   Génération d’un rapport horodaté (TXT + HTML triable) sur le bureau, avec résumé statistique.
#   Nettoyage automatique des anciens rapports (>7 jours).
#
# Usage :
#   - Exécution en administrateur : toutes les opérations (analyse, réparation, prompts interactifs, reboot).
#   - Exécution SANS droits administrateur : AUCUNE réparation, AUCUNE modification système, lecture/analyse/rapport UNIQUEMENT.
#   - Pour exécuter ce script sans modifier la politique globale :
#
#       Ouvrez PowerShell en mode administrateur (ou non admin pour lecture seule), puis :
#       powershell -ExecutionPolicy Bypass -File .\CheckSfc_Dism.ps1
#
# Prérequis :
#   - Windows 10/11, PowerShell 5+, droits admin pour la réparation.
#
# Limitations :
#   - Analyse basée sur patterns, ne remplace pas un audit manuel approfondi.
#   - Les erreurs internes DISM/SFC non bloquantes sont signalées mais non bloquantes pour l’intégrité.
# ======================================

# ----------- Config -----------
$CBSLog       = "C:\Windows\Logs\CBS\CBS.log"
$timestamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$FilteredLog = "$env:USERPROFILE\Desktop\CBS_SFC_DISM_Report_$timestamp.txt"
$HtmlReport  = "$env:USERPROFILE\Desktop\CBS_SFC_DISM_Report_$timestamp.html"
$Patterns     = "corrupt|repaired|restored|cannot repair|failed|abort"

# ----------- Nettoyage anciens rapports (plus de 7 jours) -----------
$reportPattern = "$env:USERPROFILE\Desktop\CBS_SFC_DISM_Report_*"
$daysToKeep = 7
Get-ChildItem -Path $reportPattern -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$daysToKeep) } | Remove-Item -Force

# ----------- 0️ Vérifier droits admin -----------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Exécutez ce script en tant qu'administrateur (Admin) pour que SFC/DISM fonctionnent correctement."
    # On continue quand même, mais SFC peut échouer sans admin.
}

# ----------- 1️ DISM CheckHealth & ScanHealth -----------
Write-Host "`n🔹 Vérification DISM CheckHealth..." -ForegroundColor Cyan
$checkResult = Dism /Online /Cleanup-Image /CheckHealth 2>&1

Write-Host "🔹 DISM CheckHealth terminé, analyse DISM ScanHealth en cours..." -ForegroundColor Cyan
$scanResult = Dism /Online /Cleanup-Image /ScanHealth 2>&1

Write-Host "$(Get-Date -Format 'HH:mm:ss') 🔹 ScanHealth lancé..." -ForegroundColor Cyan

# ----------- 2️ Analyse résultats DISM -----------
$errorsDetected = ($scanResult + $checkResult) | Select-String -Pattern $Patterns

if ($errorsDetected.Count -eq 0) {
    Write-Host "`n✅ Aucun problème détecté par DISM. RestoreHealth pas nécessaire." -ForegroundColor Green
    $launchRestore = $false
} else {
    Write-Host "`n⚠️ Corruption détectée ou réparation possible." -ForegroundColor Yellow
    $launchRestore = $true
}

# ----------- 3️ Confirmation RestoreHealth -----------
if ($launchRestore) {
    $restoreConfirm = Read-Host "⚠️ Lancer DISM RestoreHealth ? (O/N)"
    if ($restoreConfirm -match "^[Oo]") {
        Write-Host "🔹 Lancement DISM RestoreHealth..." -ForegroundColor Cyan
        Dism /Online /Cleanup-Image /RestoreHealth

        $rebootConfirm = Read-Host "`n⚠️ Redémarrer maintenant ? (O/N)"
        if ($rebootConfirm -match "^[Oo]") {
            Write-Host "🔹 Redémarrage en cours..." -ForegroundColor Yellow
            Restart-Computer
            return
        } else {
            Write-Host "🔹 Redémarrage reporté." -ForegroundColor Yellow
        }
    } else {
        Write-Host "🔹 RestoreHealth annulé par l'utilisateur." -ForegroundColor Yellow
    }
}

# ----------- 4️ Lancer SFC -----------
$runSfc = Read-Host "⚠️ Voulez-vous lancer SFC /scannow maintenant ? (O/N)"

if ($runSfc -match "^[Oo]") {
    Write-Host "`n🔹 Lancement SFC /scannow..." -ForegroundColor Cyan
    sfc /scannow
} else {
    Write-Host "`n🔹 SFC /scannow non lancé (mode lecture seule)." -ForegroundColor Yellow
}

# ----------- 5️ Filtrage CBS + DISM avec Select-String -----------
$DISMLog = "C:\Windows\Logs\DISM\dism.log"

Write-Host "`n🔹 Filtrage CBS + DISM pour terminal et TXT..." -ForegroundColor Cyan

$CBSFiltered  = if (Test-Path $CBSLog)  { Select-String -Path $CBSLog  -Pattern $Patterns } else { Write-Warning "CBS.log introuvable"; @() }
$DISMFiltered = if (Test-Path $DISMLog) { Select-String -Path $DISMLog -Pattern $Patterns } else { Write-Warning "dism.log introuvable"; @() }

$AllFiltered = @()
$AllFiltered += $CBSFiltered  | ForEach-Object { [PSCustomObject]@{ Source="CBS";  Line=$_.Line } }
$AllFiltered += $DISMFiltered | ForEach-Object { [PSCustomObject]@{ Source="DISM"; Line=$_.Line } }

# Affichage terminal
$AllFiltered | ForEach-Object { Write-Host "[$($_.Source)] $($_.Line)" }

# Sauvegarde TXT
$AllFiltered | ForEach-Object { "[{0}] {1}" -f $_.Source, $_.Line } | Out-File -Encoding UTF8 $FilteredLog

# ----------- 6️ Résumé terminal -----------
# 6️⃣ Résumé terminal
$ErrorCount   = ($AllFiltered | Where-Object { $_.Line -match "cannot repair|failed|abort" }).Count
$WarningCount = ($AllFiltered | Where-Object { $_.Line -match "corrupt" }).Count
$SuccessCount = ($AllFiltered | Where-Object { $_.Line -match "repaired|restored" }).Count
Write-Host "`n🔹 Résumé terminal :" -ForegroundColor Cyan
Write-Host "   ✅ Succès : $SuccessCount" -ForegroundColor Green
Write-Host "   ⚠️  Avertissements : $WarningCount" -ForegroundColor Yellow
Write-Host "   ❌ Erreurs : $ErrorCount" -ForegroundColor Red
Write-Host "   Total lignes filtrées : $($FilteredLines.Count)`n"

# ----------- 7️ Génération HTML triable -----------
$parsed = $AllFiltered | ForEach-Object {
    $line = $_.Line
    if ($line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\s*([^ ]+)\s+([^ ]+)\s+(.*)$') {
        [PSCustomObject]@{
            Date    = $matches[1]
            Level   = $matches[2]
            Source  = $_.Source
            Message = $matches[4]
        }
    }
    elseif ($line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\s*([^ ]+)\s+(.*)$') {
        [PSCustomObject]@{
            Date    = $matches[1]
            Level   = $matches[2]
            Source  = $_.Source
            Message = $matches[3]
        }
    }
    else {
        [PSCustomObject]@{
            Date    = ""
            Level   = ""
            Source  = $_.Source
            Message = $line
        }
    }
}
$HtmlHeader = @"
<html>
<head>
<style>
body { font-family: Consolas, monospace; background-color: #1e1e1e; color: #cccccc; padding: 20px; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #444; padding: 8px; text-align: left; }
th { background-color: #333; color: #fff; cursor: pointer; }
th:hover { background-color: #444; }
tr:nth-child(even) { background-color: #2a2a2a; }
tr:nth-child(odd) { background-color: #1f1f1f; }
.error { color: #ff5555; font-weight: bold; }
.warning { color: #ffaa00; font-weight: bold; }
.success { color: #55ff55; font-weight: bold; }
.summary { font-weight: bold; margin-bottom: 15px; }
</style>
<script>
function sortTable(n) {
  var table = document.getElementById('reportTable');
  if (!table) return;
  var tbody = table.querySelector('tbody');
  if (!tbody) return;

  var rows = Array.from(tbody.querySelectorAll('tr'));
  var asc = table.getAttribute('data-sort-col') != n || table.getAttribute('data-sort-dir') == 'desc';

  rows.sort(function(a,b){
    var A = a.cells[n].innerText.trim();
    var B = b.cells[n].innerText.trim();
    var da = Date.parse(A), db = Date.parse(B);
    if(!isNaN(da) && !isNaN(db)) { A = da; B = db; }
    var na = parseFloat(A), nb = parseFloat(B);
    if(!isNaN(na) && !isNaN(nb)) { A = na; B = nb; }
    if (A < B) return asc ? -1 : 1;
    if (A > B) return asc ? 1 : -1;
    return 0;
  });

  rows.forEach(r => tbody.appendChild(r));
  table.setAttribute('data-sort-col', n);
  table.setAttribute('data-sort-dir', asc ? 'asc' : 'desc');
}
</script>
<title>CBS / SFC / DISM Report</title>
</head>
<body>
<h2>CBS / SFC / DISM Report</h2>
<div class='summary'>
   ✅ Succès : $SuccessCount &nbsp;&nbsp; ⚠️ Avertissements : $WarningCount &nbsp;&nbsp; ❌ Erreurs : $ErrorCount
</div>
<table id='reportTable' data-sort-col='' data-sort-dir=''>
  <thead>
    <tr>
        <th onclick="sortTable(0)">Date</th>
        <th onclick="sortTable(1)">Level</th>
        <th onclick="sortTable(2)">Source</th>
        <th onclick="sortTable(3)">Message</th>
    </tr>
  </thead>
  <tbody>
"@

$HtmlBody = ""
foreach ($entry in $parsed) {
    if ($entry.Message -match "cannot repair|failed|abort") { $class="error" }
    elseif ($entry.Message -match "corrupt") { $class="warning" }
    elseif ($entry.Message -match "repaired|restored") { $class="success" }
    else { $class="" }

    $HtmlBody += "<tr>
<td>$($entry.Date)</td>
<td>$($entry.Level)</td>
<td>$($entry.Source)</td>
<td><span class='$class'>$([System.Web.HttpUtility]::HtmlEncode($entry.Message))</span></td>
</tr>`n"
}

$HtmlFooter = @"
  </tbody>
</table>
</body>
</html>
"@

$HtmlHeader + $HtmlBody + $HtmlFooter | Out-File -Encoding UTF8 $HtmlReport

# ----------- 8️ Final Terminal Output -----------
Write-Host "`n🔹 Rapport TXT : $FilteredLog" -ForegroundColor Cyan
Write-Host "🔹 Rapport HTML : $HtmlReport" -ForegroundColor Cyan
Write-Host "`n🔹 Terminé. ✅ Analyse complète`n" -ForegroundColor Green