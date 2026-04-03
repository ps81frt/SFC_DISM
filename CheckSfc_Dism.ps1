# ======================================
# Script : SFC + DISM Full Health Checker (100% natif)
# Auteur : ps81frt
# Version : 1.1
# GitHub  : https://github.com/ps81frt/SFC_DISM
# Date    : 2026-04-03
# License : MIT License
# ======================================
#
# Description :
#   Vérification et réparation avancée de l'intégrité Windows via DISM et SFC.
#   Filtrage et synthèse des logs CBS/DISM selon patterns critiques (corrupt, failed, repaired...).
#   Génération d'un rapport horodaté (TXT + HTML triable) sur le bureau, avec résumé statistique.
#   Nettoyage automatique des anciens rapports (>7 jours).
#
# Usage :
#   - Exécution en administrateur : toutes les opérations (analyse, réparation, prompts interactifs, reboot).
#   - Exécution SANS droits administrateur : AUCUNE réparation, AUCUNE modification système, lecture/analyse/rapport UNIQUEMENT.
#   - Pour exécuter ce script sans modifier la politique globale :
#
#       Ouvrez PowerShell en mode administrateur (ou non admin pour lecture seule), puis :
#       Set-ExecutionPolicy RemoteSigned -Scope Process -Force
#       .\CheckSfc_Dism.ps1
#
# Prérequis :
#   - Windows 10/11, PowerShell 5+, droits admin pour la réparation.
#
# Limitations :
#   - Analyse basée sur patterns, ne remplace pas un audit manuel approfondi.
#   - Les erreurs internes DISM/SFC non bloquantes sont signalées mais non bloquantes.
# ======================================

# ----------- Config -----------
$CBSLog       = "C:\Windows\Logs\CBS\CBS.log"
$timestamp    = (Get-Date -Format "yyyyMMdd_HHmmss")
$FilteredLog  = "$env:USERPROFILE\Desktop\CBS_SFC_DISM_Report_$timestamp.txt"
$HtmlReport   = "$env:USERPROFILE\Desktop\CBS_SFC_DISM_Report_$timestamp.html"
$Patterns     = "corrupt|repaired|restored|cannot repair|failed|abort"

# ----------- Nettoyage anciens rapports (> 7 jours) -----------
$reportPattern = "$env:USERPROFILE\Desktop\CBS_SFC_DISM_Report_*"
$daysToKeep    = 7
Get-ChildItem -Path $reportPattern -File |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$daysToKeep) } |
    Remove-Item -Force

# ----------- 0 Vérifier droits admin -----------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Exécutez ce script en tant qu'administrateur pour que SFC/DISM fonctionnent correctement."
}

# ----------- 1 DISM CheckHealth & ScanHealth -----------
Write-Host "`n🔹 Vérification DISM CheckHealth..." -ForegroundColor Cyan
$checkResult = Dism /Online /Cleanup-Image /CheckHealth 2>&1
Write-Host "🔹 DISM CheckHealth terminé, analyse DISM ScanHealth en cours..." -ForegroundColor Cyan
$scanResult  = Dism /Online /Cleanup-Image /ScanHealth 2>&1
Write-Host "$(Get-Date -Format 'HH:mm:ss') 🔹 ScanHealth terminé." -ForegroundColor Cyan

# ----------- 2 Analyse résultats DISM -----------
$errorsDetected = ($scanResult + $checkResult) | Select-String -Pattern $Patterns

if ($errorsDetected.Count -eq 0) {
    Write-Host "`n✅ Aucun problème détecté par DISM. RestoreHealth pas nécessaire." -ForegroundColor Green
    $launchRestore = $false
} else {
    Write-Host "`n⚠️  Corruption détectée ou réparation possible." -ForegroundColor Yellow
    $launchRestore = $true
}

# ----------- 3 Confirmation RestoreHealth -----------
if ($launchRestore) {
    $restoreConfirm = Read-Host "⚠️  Lancer DISM RestoreHealth ? (O/N)"
    if ($restoreConfirm -match "^[Oo]") {
        Write-Host "🔹 Lancement DISM RestoreHealth..." -ForegroundColor Cyan
        Dism /Online /Cleanup-Image /RestoreHealth

        $rebootConfirm = Read-Host "`n⚠️  Redémarrer maintenant ? (O/N)"
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

# ----------- 4 Lancer SFC -----------
$runSfc = Read-Host "⚠️  Voulez-vous lancer SFC /scannow maintenant ? (O/N)"
if ($runSfc -match "^[Oo]") {
    Write-Host "`n🔹 Lancement SFC /scannow..." -ForegroundColor Cyan
    sfc /scannow
} else {
    Write-Host "`n🔹 SFC /scannow non lancé (mode lecture seule)." -ForegroundColor Yellow
}

# ----------- 5 Filtrage CBS + DISM -----------
$DISMLog = "C:\Windows\Logs\DISM\dism.log"
Write-Host "`n🔹 Filtrage CBS + DISM pour terminal et TXT..." -ForegroundColor Cyan

$CBSFiltered  = if (Test-Path $CBSLog)  { Select-String -Path $CBSLog  -Pattern $Patterns } else { Write-Warning "CBS.log introuvable";  @() }
$DISMFiltered = if (Test-Path $DISMLog) { Select-String -Path $DISMLog -Pattern $Patterns } else { Write-Warning "dism.log introuvable"; @() }

$AllFiltered  = @()
$AllFiltered += $CBSFiltered  | ForEach-Object { [PSCustomObject]@{ Source = "CBS";  Line = $_.Line } }
$AllFiltered += $DISMFiltered | ForEach-Object { [PSCustomObject]@{ Source = "DISM"; Line = $_.Line } }

# Affichage terminal
$AllFiltered | ForEach-Object { Write-Host "[$($_.Source)] $($_.Line)" }

# Sauvegarde TXT
$AllFiltered | ForEach-Object { "[{0}] {1}" -f $_.Source, $_.Line } | Out-File -Encoding UTF8 $FilteredLog

# ----------- 6 Résumé terminal -----------
$ErrorCount   = ($AllFiltered | Where-Object { $_.Line -match "cannot repair|failed|abort" }).Count
$WarningCount = ($AllFiltered | Where-Object { $_.Line -match "corrupt" }).Count
$SuccessCount = ($AllFiltered | Where-Object { $_.Line -match "repaired|restored" }).Count
$TotalCount   = $AllFiltered.Count
Write-Host "`n🔹 Résumé :" -ForegroundColor Cyan
Write-Host "   ✅ Succès         : $SuccessCount" -ForegroundColor Green
Write-Host "   ⚠️   Avertissements : $WarningCount" -ForegroundColor Yellow
Write-Host "   ❌ Erreurs        : $ErrorCount"   -ForegroundColor Red
Write-Host "   Total lignes      : $TotalCount`n"

# ----------- 7 Parsing lignes pour HTML -----------
$parsed = $AllFiltered | ForEach-Object {
    $line = $_.Line
    if ($line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\s*([^ ]+)\s+([^ ]+)\s+(.*)$') {
        [PSCustomObject]@{ Date = $matches[1]; Level = $matches[2]; Source = $_.Source; Message = $matches[4] }
    } elseif ($line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\s*([^ ]+)\s+(.*)$') {
        [PSCustomObject]@{ Date = $matches[1]; Level = $matches[2]; Source = $_.Source; Message = $matches[3] }
    } else {
        [PSCustomObject]@{ Date = ""; Level = ""; Source = $_.Source; Message = $line }
    }
}

# ----------- Fonction HtmlEncode -----------
function HtmlEncode {
    param($text)
    try   { return [System.Net.WebUtility]::HtmlEncode($text) }
    catch { try { return [System.Web.HttpUtility]::HtmlEncode($text) } catch { return $text } }
}

# ----------- Variables rapport -----------
$hostname   = $env:COMPUTERNAME
$reportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ----------- 8 Génération HTML -----------
$HtmlHeader = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SFC·DISM Report — $timestamp</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --bg:      #0d1117;
  --surf:    #161b22;
  --surf2:   #1c2128;
  --border:  #30363d;
  --text:    #c9d1d9;
  --muted:   #8b949e;
  --cyan:    #58a6ff;
  --green:   #3fb950;
  --yellow:  #d29922;
  --red:     #f85149;
  --purple:  #bc8cff;
  --font:    'Cascadia Code', Consolas, 'Courier New', monospace;
}
body { font-family: var(--font); background: var(--bg); color: var(--text); font-size: 13px; line-height: 1.5; min-height: 100vh; }
a { color: var(--cyan); text-decoration: none; }
a:hover { text-decoration: underline; }

/* Top bar */
.top-bar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 10px 24px; background: var(--surf); border-bottom: 1px solid var(--border);
  flex-wrap: wrap; gap: 8px; position: sticky; top: 0; z-index: 100;
}
.brand { font-size: 14px; font-weight: 700; color: var(--cyan); letter-spacing: .05em; }
.ver-badge {
  display: inline-block; padding: 1px 8px; border-radius: 20px;
  border: 1px solid var(--border); font-size: 11px; color: var(--muted); margin-left: 8px;
}
.top-right { display: flex; align-items: center; gap: 16px; color: var(--muted); font-size: 12px; }
.gh-link {
  display: inline-flex; align-items: center; gap: 5px; padding: 4px 10px;
  border: 1px solid var(--border); border-radius: 6px; font-size: 12px; color: var(--text);
  background: var(--surf2); transition: border-color .15s, color .15s;
}
.gh-link:hover { border-color: var(--cyan); color: var(--cyan); text-decoration: none; }

/* Cards */
.cards { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; padding: 20px 24px 0; }
@media (max-width: 680px) { .cards { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 360px) { .cards { grid-template-columns: 1fr; } }
.card {
  background: var(--surf); border: 1px solid var(--border); border-radius: 8px;
  padding: 16px 18px; display: flex; flex-direction: column; gap: 6px;
  transition: border-color .15s;
}
.card:hover { border-color: var(--muted); }
.card .num { font-size: 32px; font-weight: 700; line-height: 1; }
.card .lbl { font-size: 11px; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); }
.card.total   { border-left: 3px solid var(--cyan);   } .card.total   .num { color: var(--cyan);   }
.card.success { border-left: 3px solid var(--green);  } .card.success .num { color: var(--green);  }
.card.warning { border-left: 3px solid var(--yellow); } .card.warning .num { color: var(--yellow); }
.card.error   { border-left: 3px solid var(--red);    } .card.error   .num { color: var(--red);    }

/* Meta bar */
.meta-bar {
  display: flex; gap: 20px; flex-wrap: wrap;
  padding: 10px 24px; color: var(--muted); font-size: 12px;
  border-top: 1px solid var(--border); border-bottom: 1px solid var(--border); margin-top: 16px;
}

/* Toolbar */
.toolbar { display: flex; align-items: center; gap: 12px; padding: 14px 24px 8px; flex-wrap: wrap; }
.search-wrap { position: relative; flex: 1; max-width: 400px; min-width: 180px; }
.search-wrap svg { position: absolute; left: 10px; top: 50%; transform: translateY(-50%); color: var(--muted); pointer-events: none; }
.toolbar input {
  width: 100%; background: var(--surf); border: 1px solid var(--border);
  color: var(--text); font-family: var(--font); font-size: 13px;
  padding: 7px 12px 7px 32px; border-radius: 6px; outline: none; transition: border-color .15s;
}
.toolbar input:focus { border-color: var(--cyan); }
.toolbar input::placeholder { color: var(--muted); }
.row-count { font-size: 12px; color: var(--muted); white-space: nowrap; }

/* Table */
.table-wrap { padding: 0 24px 24px; overflow-x: auto; }
table { width: 100%; border-collapse: collapse; min-width: 640px; }
thead tr { position: sticky; top: 41px; z-index: 9; }
th {
  background: var(--surf2); color: var(--muted); font-size: 11px;
  text-transform: uppercase; letter-spacing: .08em;
  padding: 9px 12px; text-align: left;
  border-bottom: 2px solid var(--border); white-space: nowrap;
  user-select: none; cursor: pointer; transition: color .15s;
}
th:hover { color: var(--text); }
th.sorted-asc  .si::after { content: ' ▲'; color: var(--cyan); }
th.sorted-desc .si::after { content: ' ▼'; color: var(--cyan); }
.si { font-size: 10px; color: var(--border); }
td {
  padding: 7px 12px; border-bottom: 1px solid var(--surf2);
  vertical-align: top;
}
td.td-date    { white-space: nowrap; color: var(--muted); font-size: 12px; min-width: 145px; }
td.td-level   { white-space: nowrap; min-width: 90px; }
td.td-source  { white-space: nowrap; min-width: 70px; }
td.td-msg     { word-break: break-word; }
tr:hover td   { background: var(--surf2); }
tr.row-error   td { background: rgba(248,81,73,.05);  }
tr.row-warning td { background: rgba(210,153,34,.05); }
tr.row-success td { background: rgba(63,185,80,.05);  }
tr.row-error:hover   td { background: rgba(248,81,73,.10);  }
tr.row-warning:hover td { background: rgba(210,153,34,.10); }
tr.row-success:hover td { background: rgba(63,185,80,.10);  }

/* Badges */
.badge { display: inline-block; padding: 2px 8px; border-radius: 20px; font-size: 11px; font-weight: 600; }
.b-err  { background: rgba(248,81,73,.18);  color: #f85149; border: 1px solid rgba(248,81,73,.35); }
.b-warn { background: rgba(210,153,34,.18); color: #e3b341; border: 1px solid rgba(210,153,34,.35); }
.b-ok   { background: rgba(63,185,80,.18);  color: #56d364; border: 1px solid rgba(63,185,80,.35); }
.b-info { background: rgba(88,166,255,.12); color: #79c0ff; border: 1px solid rgba(88,166,255,.25); }
.b-neu  { background: rgba(139,148,158,.12); color: var(--muted); border: 1px solid rgba(139,148,158,.25); }

.src-cbs  { color: #79c0ff; font-weight: 600; }
.src-dism { color: #d2a8ff; font-weight: 600; }
.msg-err  { color: #f85149; }
.msg-warn { color: #e3b341; }
.msg-ok   { color: #56d364; }

.no-data { text-align: center; padding: 56px 24px; color: var(--muted); }
.no-data .icon { font-size: 36px; display: block; margin-bottom: 10px; }

/* Footer */
footer {
  display: flex; justify-content: space-between; align-items: center;
  flex-wrap: wrap; gap: 8px; padding: 12px 24px;
  border-top: 1px solid var(--border); color: var(--muted); font-size: 11px;
}
</style>
<script>
var _sc = -1, _sd = 1;
function sortTable(n) {
  var tbody = document.querySelector('#rt tbody');
  var rows  = Array.from(tbody.querySelectorAll('tr.dr'));
  _sd = (_sc === n) ? -_sd : 1;
  _sc = n;
  rows.sort(function(a,b){
    var A = a.cells[n].innerText.trim(), B = b.cells[n].innerText.trim();
    var da = Date.parse(A), db = Date.parse(B);
    if (!isNaN(da) && !isNaN(db)) return (da - db) * _sd;
    return A.localeCompare(B, 'fr', {numeric: true}) * _sd;
  });
  rows.forEach(function(r){ tbody.appendChild(r); });
  document.querySelectorAll('th').forEach(function(th,i){
    th.classList.remove('sorted-asc','sorted-desc');
    if (i === n) th.classList.add(_sd === 1 ? 'sorted-asc' : 'sorted-desc');
  });
}
function filterTable() {
  var q   = document.getElementById('si').value.toLowerCase();
  var rows = document.querySelectorAll('#rt tbody tr.dr');
  var vis = 0;
  rows.forEach(function(r){
    var show = r.innerText.toLowerCase().indexOf(q) !== -1;
    r.style.display = show ? '' : 'none';
    if (show) vis++;
  });
  var nd = document.getElementById('nd');
  if (nd) nd.style.display = vis === 0 ? '' : 'none';
  document.getElementById('rc').textContent = vis + ' / ' + rows.length + ' entrées';
}
window.addEventListener('load', filterTable);
</script>
</head>
<body>

<div class="top-bar">
  <div>
    <span class="brand">⚙ SFC·DISM Checker</span>
    <span class="ver-badge">v1.1</span>
  </div>
  <div class="top-right">
    <span>Auteur : <strong style="color:var(--text)">ps81frt</strong></span>
    <a class="gh-link" href="https://github.com/ps81frt/SFC_DISM" target="_blank">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38l-.01-1.49c-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48l-.01 2.2c0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
      GitHub
    </a>
    <span>MIT License</span>
  </div>
</div>

<div class="cards">
  <div class="card total">
    <span class="num">$TotalCount</span>
    <span class="lbl">Total entrées</span>
  </div>
  <div class="card success">
    <span class="num">$SuccessCount</span>
    <span class="lbl">✅ Succès</span>
  </div>
  <div class="card warning">
    <span class="num">$WarningCount</span>
    <span class="lbl">⚠️ Avertissements</span>
  </div>
  <div class="card error">
    <span class="num">$ErrorCount</span>
    <span class="lbl">❌ Erreurs</span>
  </div>
</div>

<div class="meta-bar">
  <span>🖥 $hostname</span>
  <span>📅 $reportDate</span>
  <span>📂 CBS.log · dism.log</span>
  <span>🔍 Patterns : corrupt · repaired · restored · cannot repair · failed · abort</span>
</div>

<div class="toolbar">
  <div class="search-wrap">
    <svg width="14" height="14" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2"><circle cx="8.5" cy="8.5" r="5.5"/><line x1="13" y1="13" x2="18" y2="18"/></svg>
    <input type="text" id="si" placeholder="Filtrer les entrées..." oninput="filterTable()">
  </div>
  <span class="row-count" id="rc"></span>
</div>

<div class="table-wrap">
<table id="rt">
  <thead>
    <tr>
      <th onclick="sortTable(0)">Date <span class="si"></span></th>
      <th onclick="sortTable(1)">Niveau <span class="si"></span></th>
      <th onclick="sortTable(2)">Source <span class="si"></span></th>
      <th onclick="sortTable(3)">Message <span class="si"></span></th>
    </tr>
  </thead>
  <tbody>
"@

# ----------- Body HTML -----------
$HtmlBody = ""
foreach ($entry in $parsed) {
    # Classe de ligne et badge de niveau
    if ($entry.Message -match "cannot repair|failed|abort") {
        $rowClass  = "row-error"
        $msgClass  = "msg-err"
        $lvlBadge  = if ($entry.Level) { "<span class='badge b-err'>$($entry.Level)</span>" } else { "<span class='badge b-err'>ERROR</span>" }
    } elseif ($entry.Message -match "corrupt") {
        $rowClass  = "row-warning"
        $msgClass  = "msg-warn"
        $lvlBadge  = if ($entry.Level) { "<span class='badge b-warn'>$($entry.Level)</span>" } else { "<span class='badge b-warn'>WARN</span>" }
    } elseif ($entry.Message -match "repaired|restored") {
        $rowClass  = "row-success"
        $msgClass  = "msg-ok"
        $lvlBadge  = if ($entry.Level) { "<span class='badge b-ok'>$($entry.Level)</span>" } else { "<span class='badge b-ok'>OK</span>" }
    } else {
        $rowClass  = ""
        $msgClass  = ""
        $lvlBadge  = if ($entry.Level) { "<span class='badge b-neu'>$($entry.Level)</span>" } else { "" }
    }

    $srcClass = if ($entry.Source -eq "CBS") { "src-cbs" } else { "src-dism" }
    $encMsg   = HtmlEncode $entry.Message

    $HtmlBody += "<tr class='dr $rowClass'>
<td class='td-date'>$($entry.Date)</td>
<td class='td-level'>$lvlBadge</td>
<td class='td-source'><span class='$srcClass'>$($entry.Source)</span></td>
<td class='td-msg'><span class='$msgClass'>$encMsg</span></td>
</tr>`n"
}

$HtmlFooter = @"
    <tr id="nd" style="display:none"><td colspan="4" class="no-data"><span class="icon">🔍</span>Aucune entrée ne correspond au filtre.</td></tr>
  </tbody>
</table>
</div>

<footer>
  <span>SFC·DISM Checker v1.1 — <a href="https://github.com/ps81frt/SFC_DISM" target="_blank">github.com/ps81frt/SFC_DISM</a> — MIT License</span>
  <span>Auteur : <strong>ps81frt</strong> · $reportDate</span>
</footer>
</body>
</html>
"@

$HtmlHeader + $HtmlBody + $HtmlFooter | Out-File -Encoding UTF8 $HtmlReport

# ----------- 9 Sortie finale -----------
Write-Host "`n🔹 Rapport TXT  : $FilteredLog" -ForegroundColor Cyan
Write-Host "🔹 Rapport HTML : $HtmlReport"  -ForegroundColor Cyan
Write-Host "`n✅ Terminé. Analyse complète.`n" -ForegroundColor Green