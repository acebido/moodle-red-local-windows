# Moodle con HTTPS en la red local (Windows 11)

Script del canal de Acebido (José Luis Díaz) para entrar con **candado** en tu Moodle desde los
otros ordenadores y móviles de la misma red (casa o aula). Gratis: el certificado lo crea el propio
Windows.

Es la continuación de **[https-moodle-windows](https://github.com/acebido/https-moodle-windows)**,
que pone Moodle en **https://localhost**. Ese certificado solo sirve en tu ordenador; aquí Moodle pasa
a usar el nombre del ordenador en la red: **https://&lt;nombre-del-ordenador&gt;.local**. Sirve también
para un Moodle que todavía esté en http://localhost.

Pensado para el Moodle que dejan los scripts de
**[instalar-moodle-windows](https://github.com/acebido/instalar-moodle-windows)**: sitio de IIS
«Moodle», código en `C:\moodle` y PHP en `C:\php`.

## 📄 Guía

**[Guía en PDF](Guia-Red-Local-Moodle-Windows.pdf)**: con el script y paso a paso a mano, cómo
instalar el certificado en Windows, Mac, Android e iPhone, los problemas más habituales, cómo volver
atrás y cuánto ordenador hace falta para una clase.

## Cómo se ejecuta

1. En esta página, botón verde **Code → Download ZIP** y descomprímelo.
2. **Doble clic en `abrir-powershell-aqui.cmd`** y acepta el aviso de Windows: abre PowerShell
   como administrador, ya colocado en la carpeta y con el script permitido.
3. Escribe y pulsa Intro:

   ```powershell
   .\activar_red_local.ps1
   ```

4. Al acabar te dice la dirección (**https://&lt;nombre&gt;.local**) y deja en la carpeta el fichero
   `certificado-moodle-<nombre>.local.cer`. Instálalo en cada equipo que vaya a entrar (la guía
   explica cómo en Windows, Mac, Android e iPhone) y entra en esa dirección: sale el candado.

No pregunta nada y tarda menos de un minuto. Debajo de cada paso, en gris, explica qué hace, y
termina con una **comprobación** en verde (bien) o en rojo (con el motivo).

**¿Por qué `.local`?** Con `.local`, los demás equipos encuentran el tuyo por su cuenta, sin tocar el
router: Windows, Mac, iPhone y la mayoría de Android. El nombre a secas solo lo encuentran otros
Windows. Si algún equipo no lo encuentra, usa la IP del ordenador (y pide que sea fija en el router):

```powershell
.\activar_red_local.ps1 -Nombre 192.168.1.35
```

## Qué hace

| Paso | Qué hace |
|---|---|
| 1. Certificado | Crea con Windows un certificado para `<nombre>.local`, `<nombre>` y `localhost`, válido 5 años |
| 2. Confianza | Lo añade a las *Entidades de certificación raíz de confianza* de este ordenador |
| 3. HTTPS en IIS | Pone ese certificado en el puerto **443** del sitio «Moodle» |
| 4. De http a https | El sitio «Moodle - redireccion a HTTPS» manda cada visita a la misma página en `https://<nombre>.local` |
| 5. Moodle | Cambia `$CFG->wwwroot` en `config.php` (copia en `config.php.antes-https`) y los enlaces de los cursos, y vacía las cachés |
| 6. Red local | Abre los puertos 80 y 443 en el cortafuegos, avisa si la red está marcada como **pública** y exporta el certificado a un `.cer` (solo la parte pública: se puede repartir) |

## A mano: las órdenes

Para quien siga la guía paso a paso (como en el vídeo). Cada una es **una sola línea**: cópiala con
el botón de la derecha, pégala en **Terminal (Administrador)** y pulsa Intro.

Paso 1 · El nombre del ordenador (la dirección será ese nombre en minúsculas + `.local`):

```powershell
hostname
```

Paso 2 · Crear el certificado (vale tal cual en cualquier ordenador):

```powershell
New-SelfSignedCertificate -DnsName "$($env:COMPUTERNAME.ToLower()).local", $env:COMPUTERNAME.ToLower(), localhost -CertStoreLocation Cert:\LocalMachine\My -FriendlyName "Moodle red local" -NotAfter (Get-Date).AddYears(5)
```

Paso 3 · Certificados del equipo:

```powershell
certlm.msc
```

Pasos 4 y 5 · Administrador de IIS (destino de la redirección: `https://<nombre>.local$S$Q`):

```powershell
inetmgr
```

Paso 6 · La dirección de Moodle, reiniciar IIS, enlaces de los cursos y cachés (cambia `pc-aula` por
tu nombre):

```powershell
notepad C:\moodle\config.php
```

```powershell
iisreset
```

```powershell
C:\php\php.exe C:\moodle\public\admin\tool\replace\cli\replace.php --search=https://localhost --replace=https://pc-aula.local --shorten --non-interactive
```

```powershell
C:\php\php.exe C:\moodle\admin\cli\purge_caches.php
```

Paso 7 · Cortafuegos y exportar el certificado al Escritorio:

```powershell
wf.msc
```

```powershell
Get-ChildItem Cert:\LocalMachine\My | Where-Object FriendlyName -eq 'Moodle red local' | Export-Certificate -FilePath "$([Environment]::GetFolderPath('Desktop'))\certificado-moodle.cer"
```

## Volver a https://localhost

```powershell
.\activar_red_local.ps1 -Deshacer
```

Moodle vuelve a **https://localhost** (solo este ordenador), quita la regla del cortafuegos y los
`.cer` de la carpeta. En los otros equipos puedes borrar el certificado que instalaste.

## ¿Y abrir los puertos del router para entrar desde internet?

No lo recomendamos para un Moodle de pruebas en casa o en el aula. En cuanto un servidor web está en
internet llegan bots, en horas, que prueban contraseñas y buscan fallos sin actualizar. Además, quien
entrara en ese ordenador estaría dentro de tu red. El certificado de aquí tampoco sirve desde fuera.

Para entrar desde fuera **sin abrir ningún puerto**: **Tailscale** (gratis, solo entra quien invites) o
**Cloudflare Tunnel** (gratis, con un dominio). Para alumnado de verdad, un alojamiento o un servidor de
Moodle. Si aun así lo abres: solo los puertos 80 y 443 (nunca 3306, 445 ni 3389), MFA en Moodle, todo
actualizado y un ordenador dedicado con copias de seguridad. Más detalle en el capítulo 7 de la guía.

## ¿Ordenador compartido?

Si en el ordenador con Moodle entran otras personas con su propia cuenta de Windows, protégelo con
`proteger_moodle.ps1`, de [https-moodle-windows](https://github.com/acebido/https-moodle-windows).

---
Acebido · Formación · Tecnología · Futuro — José Luis Díaz.
Moodle es software libre (GPLv3) de Moodle HQ; las marcas citadas pertenecen a sus titulares.
