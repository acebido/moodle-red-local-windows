# =============================================================================
#  Moodle con HTTPS en la red local: entrar desde otros equipos (Windows 11 con IIS)
#  Acebido · José Luis Díaz
# =============================================================================
#  Para el Moodle instalado con los scripts de github.com/acebido/instalar-moodle-windows
#  (sitio de IIS «Moodle», código en C:\moodle y PHP en C:\php), con o sin HTTPS
#  (el de github.com/acebido/https-moodle-windows, en https://localhost).
#
#  Qué hace:
#   1. Crea un certificado para el nombre del ordenador en la red (<nombre>.local),
#      válido 5 años. Lo crea el propio Windows: no se descarga ni se paga nada.
#   2. Lo añade a los certificados de confianza de este ordenador.
#   3. Lo pone en el puerto 443 (HTTPS) del sitio «Moodle» de IIS.
#   4. Hace que quien entre por http:// pase solo a https://<nombre>.local.
#   5. Cambia la dirección de Moodle en config.php y en los enlaces de los cursos.
#   6. Mira el cortafuegos y el tipo de red, y deja el certificado en un fichero .cer
#      para instalarlo en los demás equipos (Windows, Mac, Android, iPhone).
#
#  Formas de usarlo:
#   .\activar_red_local.ps1                 Moodle en https://<nombre-del-ordenador>.local
#   .\activar_red_local.ps1 -Nombre 192.168.1.35
#                                           con otro nombre o con la IP del ordenador
#   .\activar_red_local.ps1 -Deshacer       vuelve a https://localhost (solo este ordenador)
#
#  Cómo se ejecuta: PowerShell COMO ADMINISTRADOR, en esta carpeta
#  (o doble clic en abrir-powershell-aqui.cmd y después la orden).
# =============================================================================
param([switch]$Deshacer, [string]$Nombre)

$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host 'Abre PowerShell como administrador y vuelve a ejecutar el script.' -ForegroundColor Red; exit 1 }
# PHP escribe en UTF-8: sin esto, la consola enseña «├ëxito» en vez de «Éxito».
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$CODE     = 'C:\moodle'
$CFGF     = "$CODE\config.php"
$PHP      = 'C:\php\php.exe'
$SITIO    = 'Moodle'
$REDIR    = 'Moodle - redireccion a HTTPS'
$CARPETA  = 'C:\inetpub\moodle-redireccion'
$REGLA    = 'Moodle HTTPS (red local)'
$AQUI     = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

Write-Host '== Comprobaciones ==' -ForegroundColor Cyan
Write-Host '   Mira que Moodle, PHP y el sitio «Moodle» de IIS estén donde los dejaron los scripts de instalación.' -ForegroundColor Gray
foreach ($f in @($CFGF, $PHP)) {
  if (-not (Test-Path $f)) { Write-Host "  No existe $f. Este script es para el Moodle instalado con los scripts de instalar-moodle-windows." -ForegroundColor Red; exit 1 } }
Import-Module WebAdministration
if (-not (Get-Website -Name $SITIO -ErrorAction SilentlyContinue)) {
  Write-Host "  No existe el sitio «$SITIO» en IIS." -ForegroundColor Red; exit 1 }

# La dirección que tiene ahora Moodle en config.php.
function LeeWwwroot($fichero) {
  if ((Get-Content $fichero -Raw) -match "\`$CFG->wwwroot\s*=\s*'([^']+)'") { return $Matches[1].TrimEnd('/') }
  return $null
}
$WWW = LeeWwwroot $CFGF
if (-not $WWW) { Write-Host '  No encuentro $CFG->wwwroot en config.php.' -ForegroundColor Red; exit 1 }
$uri = [Uri]$WWW
if ($uri.AbsolutePath -ne '/' -or -not $uri.IsDefaultPort) {
  Write-Host "  La dirección de Moodle es ${WWW}: este script solo sirve para direcciones sin puerto ni carpeta (http://localhost)." -ForegroundColor Red; exit 1 }
$ACTUAL = $uri.Host
Write-Host "  dirección actual de Moodle: $WWW"

# La dirección que va a tener: <nombre-del-ordenador>.local, la que se indique o, al deshacer, localhost.
# Con .local la encuentran Windows, Mac, iPhone y Android sin tocar el router (mDNS); el nombre a secas
# solo lo encuentran otros Windows.
$RedLocal = -not $Deshacer
if ($Deshacer) { $NOMBRE = 'localhost' }
elseif ($Nombre) { $NOMBRE = $Nombre.ToLower() }
else { $NOMBRE = "$($env:COMPUTERNAME.ToLower()).local" }
$ES_IP = $NOMBRE -match '^\d{1,3}(\.\d{1,3}){3}$'

# Ejecuta un script de PHP sin que los avisos de PHP por la salida de errores corten el script.
# Con -Resumen solo enseña las líneas de progreso (la búsqueda y sustitución escribe cada consulta SQL).
function Php($guion, [string[]]$argumentos, [switch]$Resumen) {
  $ErrorActionPreference = 'Continue'
  & $PHP $guion @argumentos 2>&1 | ForEach-Object {
    $l = "$_"
    if (-not $Resumen -or $l -match '^\s*(\+\+|==|!!!|Error|PHP |Fatal|Warning|Notice|Default exception)') { Write-Host "  $l" } }
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { Write-Host "  PHP ha dado un error con $(Split-Path $guion -Leaf): mira los mensajes de arriba." -ForegroundColor Red; exit 1 }
}
# Cambia los enlaces guardados en los cursos (solo si la dirección cambia).
function Reemplaza($de, $a) {
  if ($de -eq $a) { return }
  $args2 = @("--search=$de", "--replace=$a", '--non-interactive')
  if ($a.Length -gt $de.Length) { $args2 += '--shorten' }   # Moodle solo recorta si un texto no cabe en su campo
  Write-Host "  enlaces: $de → $a"
  Php "$CODE\public\admin\tool\replace\cli\replace.php" $args2 -Resumen
}
# Pone la dirección en config.php (copia antes, escribe aparte y luego copia).
function CambiaConfig($url) {
  if (-not (Test-Path "$CFGF.antes-https")) { Copy-Item $CFGF "$CFGF.antes-https" }
  $nuevo = (Get-Content $CFGF -Raw) -replace "(\`$CFG->wwwroot\s*=\s*')[^']*'", ('${1}' + $url + "'")
  [IO.File]::WriteAllText("$CFGF.nuevo", $nuevo)
  Copy-Item "$CFGF.nuevo" $CFGF -Force; Remove-Item "$CFGF.nuevo"
  # PHP guarda config.php en su caché (OPcache) hasta 60 s: sin reiniciar IIS, Moodle seguiría unos
  # segundos con la dirección vieja y mandaría al navegador a ella.
  & iisreset /noforce 2>&1 | Out-Null
}
# Los certificados que crea este script (nombre descriptivo «Moodle …» y firmados por sí mismos).
function CertificadosNuestros($almacen) {
  Get-ChildItem $almacen | Where-Object { $_.FriendlyName -like 'Moodle *' -and $_.Issuer -eq $_.Subject }
}

# =============================================================================
if ($Deshacer) {
  Write-Host '== Volver a https://localhost ==' -ForegroundColor Cyan
  Write-Host '   Quita la regla del cortafuegos y los .cer de esta carpeta; después rehace los pasos con localhost.' -ForegroundColor Gray
  if (Get-NetFirewallRule -DisplayName $REGLA -ErrorAction SilentlyContinue) { Remove-NetFirewallRule -DisplayName $REGLA; Write-Host '  quitada la regla del cortafuegos' }
  Get-ChildItem $AQUI -Filter 'certificado-moodle-*.cer' -ErrorAction SilentlyContinue | Remove-Item
  Write-Host '  (los demás equipos pueden borrar el certificado que instalaron: ya no sirve)'
}

if ($RedLocal) {
  Write-Host "  modo red local: Moodle pasará a https://$NOMBRE" -ForegroundColor Yellow
  if ($ES_IP) { Write-Host '  ojo: si el router le da otra IP a este ordenador, habrá que repetirlo. Mejor el nombre del ordenador o una IP fija.' -ForegroundColor Yellow }
}

# =============================================================================
Write-Host '== 1. Certificado ==' -ForegroundColor Cyan
Write-Host "   Crea con Windows un certificado para $NOMBRE, válido 5 años. Gratis y sin descargar nada." -ForegroundColor Gray
# Lo que va dentro del certificado: el nombre (o la IP) y, siempre, localhost.
$san = @()
if ($ES_IP) { $san += "IPAddress=$NOMBRE" } else { $san += "DNS=$NOMBRE" }
if ($NOMBRE -like '*.local') { $san += "DNS=$($NOMBRE -replace '\.local$','')" }   # también el nombre a secas (otros Windows)
if ($NOMBRE -ne 'localhost') { $san += 'DNS=localhost' }
$cert = CertificadosNuestros Cert:\LocalMachine\My |
        Where-Object { $_.FriendlyName -eq "Moodle $NOMBRE" -and $_.NotAfter -gt (Get-Date).AddDays(30) } |
        Select-Object -First 1
if ($cert) { Write-Host "  ya existía (caduca el $($cert.NotAfter.ToString('dd-MM-yyyy')))" }
else {
  $cert = New-SelfSignedCertificate -Subject "CN=$NOMBRE" -TextExtension @("2.5.29.17={text}$($san -join '&')") `
          -CertStoreLocation Cert:\LocalMachine\My -FriendlyName "Moodle $NOMBRE" -NotAfter (Get-Date).AddYears(5) `
          -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256
  Write-Host "  creado para: $(($san -replace '^(DNS|IPAddress)=','') -join ', ') (caduca el $($cert.NotAfter.ToString('dd-MM-yyyy')))"
}

Write-Host '== 2. Certificado de confianza ==' -ForegroundColor Cyan
Write-Host '   Lo añade a las «Entidades de certificación raíz de confianza» de este ordenador: así el navegador no avisa.' -ForegroundColor Gray
if (Test-Path "Cert:\LocalMachine\Root\$($cert.Thumbprint)") { Write-Host '  ya era de confianza' }
else {
  $cer = Join-Path $env:TEMP 'moodle-https.cer'
  Export-Certificate -Cert $cert -FilePath $cer | Out-Null
  Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
  Remove-Item $cer
  # El .cer no lleva el nombre descriptivo: se le pone para poder reconocerlo (y borrarlo con -Deshacer).
  (Get-Item "Cert:\LocalMachine\Root\$($cert.Thumbprint)").FriendlyName = "Moodle $NOMBRE"
  Write-Host '  añadido'
}

Write-Host '== 3. HTTPS en IIS (puerto 443) ==' -ForegroundColor Cyan
Write-Host '   Añade al sitio «Moodle» el puerto 443, el de HTTPS, con el certificado.' -ForegroundColor Gray
$otro = Get-WebBinding -Port 443 | Where-Object { $_.ItemXPath -notmatch "name='$SITIO'" }
if ($otro) { Write-Host '  Otro sitio de IIS ya usa el puerto 443: quítaselo en el Administrador de IIS y vuelve a ejecutar el script.' -ForegroundColor Red; exit 1 }
if (-not (Get-WebBinding -Name $SITIO -Protocol https -Port 443)) {
  $ocupa = Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -ne 4 } | Select-Object -First 1
  if ($ocupa) {
    $prog = (Get-Process -Id $ocupa.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    Write-Host "  El puerto 443 lo usa otro programa ($prog). Ciérralo y vuelve a ejecutar el script." -ForegroundColor Red; exit 1 }
  New-WebBinding -Name $SITIO -Protocol https -Port 443 -IPAddress '*'
}
$ssl = 'IIS:\SslBindings\0.0.0.0!443'
if ((Test-Path $ssl) -and (Get-Item $ssl).Thumbprint -ne $cert.Thumbprint) { Remove-Item $ssl }
if (-not (Test-Path $ssl)) { (Get-WebBinding -Name $SITIO -Protocol https -Port 443).AddSslCertificate($cert.Thumbprint, 'My') }
# Si antes había otro certificado nuestro (por ejemplo el de localhost), ya no se usa: fuera.
foreach ($almacen in 'Cert:\LocalMachine\My', 'Cert:\LocalMachine\Root') {
  CertificadosNuestros $almacen | Where-Object { $_.Thumbprint -ne $cert.Thumbprint } | Remove-Item }
Write-Host '  el sitio «Moodle» escucha en https://, puerto 443'

Write-Host '== 4. De http:// a https:// ==' -ForegroundColor Cyan
Write-Host '   El puerto 80 lo atiende un sitio pequeño que solo manda cada visita a la misma página en https://.' -ForegroundColor Gray
if ((Get-WindowsOptionalFeature -Online -FeatureName IIS-HttpRedirect).State -ne 'Enabled') {
  Write-Host '  activando «Redirección HTTP» de IIS ...'
  Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpRedirect -All -NoRestart | Out-Null
}
if (Get-WebBinding -Name $SITIO -Protocol http -Port 80) {
  Get-WebBinding -Name $SITIO -Protocol http -Port 80 | Remove-WebBinding
  Write-Host '  el sitio «Moodle» deja el puerto 80' }
New-Item -ItemType Directory -Path $CARPETA -Force | Out-Null
# exactDestination="true" con $S$Q: IIS añade la página que se pedía ($S) y lo que va detrás del ? ($Q).
# (Con exactDestination="false" se pierde lo de detrás del ?: /course/view.php?id=1 acabaría en /course/view.php.)
# Found (302) y no Permanent (301): el navegador no la guarda para siempre, por si se deshace.
@"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <httpRedirect enabled="true" destination="https://$NOMBRE`$S`$Q" exactDestination="true" childOnly="false" httpResponseStatus="Found" />
  </system.webServer>
</configuration>
"@ | Set-Content -Path "$CARPETA\web.config" -Encoding UTF8
if (-not (Get-Website -Name $REDIR -ErrorAction SilentlyContinue)) {
  New-Website -Name $REDIR -Port 80 -PhysicalPath $CARPETA -ApplicationPool $SITIO -Force | Out-Null }
Start-Website -Name $REDIR
Write-Host "  sitio «$REDIR» en el puerto 80"

Write-Host '== 5. Moodle con https:// ==' -ForegroundColor Cyan
Write-Host '   Cambia la dirección en config.php y en los enlaces guardados en los cursos, y vacía las cachés.' -ForegroundColor Gray
if ($WWW -eq "https://$NOMBRE") { Write-Host "  config.php ya tenía https://$NOMBRE" }
else { CambiaConfig "https://$NOMBRE"; Write-Host "  config.php: https://$NOMBRE (copia en config.php.antes-https)" }
Reemplaza "https://$ACTUAL" "https://$NOMBRE"
Reemplaza "http://$ACTUAL"  "https://$NOMBRE"
Php "$CODE\admin\cli\purge_caches.php" @()
Write-Host '  cachés vaciadas'

if ($RedLocal) {
  Write-Host '== 6. Red local ==' -ForegroundColor Cyan
  Write-Host '   Abre los puertos 80 y 443 en el cortafuegos y guarda el certificado para los otros equipos.' -ForegroundColor Gray
  if (-not (Get-NetFirewallRule -DisplayName $REGLA -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $REGLA -Direction Inbound -Protocol TCP -LocalPort 80,443 -Action Allow -Profile Private,Domain | Out-Null }
  Write-Host "  cortafuegos: regla «$REGLA» (puertos 80 y 443, redes privadas y de dominio)"
  # Al activar IIS, Windows suele abrir ya los puertos 80 y 443 en TODAS las redes (reglas «Servicios World Wide Web»).
  $todas = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -ErrorAction SilentlyContinue |
           Where-Object { $_.Profile -eq 'Any' -or "$($_.Profile)" -match 'Public' } |
           Get-NetFirewallPortFilter | Where-Object { $_.Protocol -eq 'TCP' -and (@($_.LocalPort) -contains '443') }
  $publicas = Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' }
  foreach ($red in $publicas) {
    if ($todas) {
      Write-Host "  ojo: la red «$($red.Name)» está marcada como PÚBLICA y Windows ya deja entrar a Moodle también por ella (lo abrió IIS)." -ForegroundColor Yellow
      Write-Host '  Funciona, pero no lo uses conectado a wifis públicas (bibliotecas, cafeterías…).' -ForegroundColor Yellow
      Write-Host '  Si es la red de tu casa o tu aula, márcala como privada:' -ForegroundColor Yellow
      Write-Host "     Set-NetConnectionProfile -InterfaceIndex $($red.InterfaceIndex) -NetworkCategory Private" -ForegroundColor Yellow
    } else {
      Write-Host "  ojo: la red «$($red.Name)» es PÚBLICA y por ella no entrará nadie. Si es la de tu casa o tu aula, márcala como privada:" -ForegroundColor Yellow
      Write-Host "     Set-NetConnectionProfile -InterfaceIndex $($red.InterfaceIndex) -NetworkCategory Private" -ForegroundColor Yellow
    }
  }
  $fichero = Join-Path $AQUI "certificado-moodle-$NOMBRE.cer"
  Export-Certificate -Cert $cert -FilePath $fichero | Out-Null
  Write-Host "  certificado para los otros equipos: $fichero"
  Write-Host '  En cada equipo que vaya a entrar: copia ese .cer y, en PowerShell de administrador:' -ForegroundColor Gray
  Write-Host "     Import-Certificate -FilePath .\certificado-moodle-$NOMBRE.cer -CertStoreLocation Cert:\LocalMachine\Root" -ForegroundColor Gray
  Write-Host '  (o doble clic en el .cer → Instalar certificado → Equipo local → «Entidades de certificación raíz de confianza»)' -ForegroundColor Gray
}

Write-Host '== Comprobación ==' -ForegroundColor Cyan
Write-Host '   Abre Moodle por https:// (con el certificado comprobado como lo haría el navegador) y prueba la redirección.' -ForegroundColor Gray
Start-Sleep 2
$bien = $true
try {
  $req = [Net.HttpWebRequest]::Create("https://$NOMBRE/login/index.php"); $req.AllowAutoRedirect = $false; $req.Timeout = 60000
  $r = $req.GetResponse(); $codigo = [int]$r.StatusCode; $r.Close()
  Write-Host "  OK: https://$NOMBRE responde ($codigo) con un certificado de confianza" -ForegroundColor Green
} catch { $bien = $false; Write-Host "  https://$NOMBRE no responde bien: $(if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message })" -ForegroundColor Red }
try {
  $req = [Net.HttpWebRequest]::Create("http://$NOMBRE/course/view.php?id=1"); $req.AllowAutoRedirect = $false; $req.Timeout = 30000
  $r = $req.GetResponse(); $destino = $r.Headers['Location']; $r.Close()
  if ($destino -eq "https://$NOMBRE/course/view.php?id=1") { Write-Host "  OK: http://$NOMBRE/course/view.php?id=1 pasa a $destino" -ForegroundColor Green }
  elseif ($destino -like "https://$NOMBRE*") { Write-Host "  http:// pasa a https://, pero a $destino (se esperaba la misma página)" -ForegroundColor Yellow }
  else { $bien = $false; Write-Host "  http:// no pasa a https:// (Location: $destino)" -ForegroundColor Red }
} catch { $bien = $false; Write-Host "  http://$NOMBRE no responde: $($_.Exception.Message)" -ForegroundColor Red }
if ($bien) {
  Write-Host "  Listo: abre https://$NOMBRE en el navegador. Si lo tenías abierto, ciérralo y vuelve a abrirlo." -ForegroundColor Green
  if ($RedLocal) { Write-Host "  Desde los otros equipos (con el certificado instalado): https://$NOMBRE" -ForegroundColor Green }
}
else { Write-Host '  Algo no ha ido bien: mira los mensajes de arriba. Para volver atrás:  .\activar_red_local.ps1 -Deshacer' -ForegroundColor Red; exit 1 }
