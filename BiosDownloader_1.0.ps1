<#
.SYNOPSIS
    Baixa e organiza atualizacoes de BIOS/Firmware a partir do
    Microsoft Update Catalog.

.DESCRIPTION
    Automatiza a coleta de atualizacoes de BIOS/UEFI disponibilizadas
    pela Microsoft Update Catalog, extrai apenas o arquivo de firmware
    do pacote .cab e organiza o resultado para uso posterior.

    Fluxo de execucao:

        1. Solicita, opcionalmente, o Part Number da placa.
        2. Descobre os GUIDs de BIOS/UEFI do sistema com fallback em
           tres fontes, na seguinte ordem de prioridade:
               a) Gerenciador de Dispositivos (classe System Firmware)
               b) Registro: HKLM:\SYSTEM\CurrentControlSet\Control\FirmwareResources
               c) Pasta: C:\Windows\Firmware
        3. Garante a presenca do modulo MSCatalogLTS, instalando-o
           caso necessario.
        4. Baixa cada pacote .cab em pasta temporaria.
        5. Extrai o conteudo do .cab e filtra o firmware por extensao
           conhecida e por tamanho minimo configuravel.
        6. Copia o firmware para a pasta final com o padrao de nome:
               {PartNumber}_{GUID}_BIOS_{versao}{extensao}
           Caso o Part Number nao seja informado, o prefixo e omitido.
        7. Compacta cada firmware individualmente em .zip, mantendo o
           binario original na mesma pasta.
        8. Remove todos os arquivos temporarios (.cab, pastas de
           extracao e diretorios de trabalho).

.PARAMETER PartNumber
    Part Number da placa-mae (ex.: LA-L181P). Solicitado
    interativamente no inicio da execucao. Opcional.

.NOTES
    Requisitos:
        - Windows 10 ou Windows 11
        - PowerShell 5.1 ou superior
        - Execucao como Administrador
        - Modulo MSCatalogLTS (instalado automaticamente)
        - 7-Zip instalado em C:\Program Files\7-Zip\7z.exe (opcional;
          caso ausente, o script utiliza Compress-Archive nativo)

    Autor       : Eng. Marco Aurelio Machado
    Projeto     : Marco Notebooks
    Versao      : 1.0
    Data        : Setembro de 2026
    Licenca     : MIT (uso livre por conta e risco do usuario)

.EXAMPLE
    .\BiosDownloader_1.0.ps1

    Executa o fluxo completo de forma interativa. Sera solicitado o
    Part Number da placa e, em seguida, todo o processo ocorre de
    forma automatica.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\BiosDownloader_1.0.ps1

    Executa o script ignorando a politica de execucao definida no
    sistema, sem alterar a configuracao permanente.

.LINK
    https://github.com/<seu-usuario>/<seu-repositorio>
#>

#Requires -RunAsAdministrator
#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ----------------------------------------------------------------------------
# Configuracao
# ----------------------------------------------------------------------------

# Extensoes reconhecidas como firmware de BIOS/UEFI.
$EXTENSOES_FIRMWARE = @(
    '.bin', '.fd', '.rom', '.cap', '.fl1', '.fl2', '.fl3', '.hex', '.img'
)

# Tamanho minimo (em bytes) para que um arquivo seja considerado firmware.
# Valor padrao: 3 MB. Nao existem firmwares de BIOS modernos menores que isso.
$TAMANHO_MINIMO_FIRMWARE = 3MB

# Caminho do executavel do 7-Zip. Caso nao exista, o script utiliza
# o cmdlet nativo Compress-Archive como fallback.
$SETEZIP = 'C:\Program Files\7-Zip\7z.exe'

# ClassGuid da classe "System Firmware" do Windows. Utilizado para
# isolar o dispositivo de BIOS/UEFI durante a consulta PnP.
$CLASSGUID_SYSTEM_FIRMWARE = '{f2e7dd72-6468-4e36-b6f1-6488f42c1b52}'

# Pasta raiz onde os arquivos serao armazenados.
$ROOT_PATH = 'C:\BIOS_Downloads'

# ----------------------------------------------------------------------------
# Funcoes de saida
# ----------------------------------------------------------------------------

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
}

function Write-Info { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Gray }
function Write-OK   { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Red }

# ----------------------------------------------------------------------------
# Funcao: descoberta dos GUIDs de BIOS/UEFI com fallback
# ----------------------------------------------------------------------------

function Get-FirmwareGuids {
    <#
    .SYNOPSIS
        Retorna os GUIDs de BIOS/UEFI do sistema.

    .DESCRIPTION
        Consulta tres fontes em ordem de prioridade e retorna assim que
        obtiver ao menos um GUID valido. As fontes sao:

            1. Gerenciador de Dispositivos (classe System Firmware)
            2. Registro: FirmwareResources
            3. Pasta: C:\Windows\Firmware

    .OUTPUTS
        System.String[] - Lista de GUIDs normalizados (maiusculo, sem chaves).
    #>
    $guids = @()

    # -- Fonte 1: PnP (System Firmware) --------------------------------------
    Write-Info 'Fonte 1: Gerenciador de Dispositivos (System Firmware)...'
    try {
        $pnpFirmware = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
                       Where-Object { $_.ClassGuid -eq $CLASSGUID_SYSTEM_FIRMWARE }

        if ($pnpFirmware) {
            foreach ($dev in $pnpFirmware) {
                if ($dev.PNPDeviceID -and $dev.PNPDeviceID -match 'UEFI\\RES_\{(.+?)\}') {
                    $g = $Matches[1].ToUpper()
                    if ($guids -notcontains $g) {
                        $guids += $g
                        Write-Info "  [PnP] $g"
                    }
                }
            }
        }

        if ($guids.Count -gt 0) {
            Write-OK "  Fonte 1 retornou $($guids.Count) GUID(s)."
            return $guids
        }
        Write-Warn '  Fonte 1 nao retornou GUIDs. Tentando proxima fonte...'
    } catch {
        Write-Warn "  Erro na Fonte 1: $_"
    }

    # -- Fonte 2: Registro ---------------------------------------------------
    Write-Info 'Fonte 2: Registro (FirmwareResources)...'
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\FirmwareResources'
    if (Test-Path $regPath) {
        try {
            $regGuids = Get-ChildItem $regPath -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty PSChildName
            if ($regGuids) {
                foreach ($g in $regGuids) {
                    $gLimpo = ($g -replace '^\{|\}$', '').ToUpper()
                    if ($guids -notcontains $gLimpo) {
                        $guids += $gLimpo
                        Write-Info "  [Registro] $gLimpo"
                    }
                }
            }
        } catch {
            Write-Warn "  Erro na Fonte 2: $_"
        }
    } else {
        Write-Warn '  Chave FirmwareResources nao encontrada.'
    }

    if ($guids.Count -gt 0) {
        Write-OK "  Fonte 2 retornou $($guids.Count) GUID(s)."
        return $guids
    }
    Write-Warn '  Fonte 2 nao retornou GUIDs. Tentando proxima fonte...'

    # -- Fonte 3: C:\Windows\Firmware ----------------------------------------
    Write-Info 'Fonte 3: Pasta C:\Windows\Firmware...'
    $firmwarePath = 'C:\Windows\Firmware'
    if (Test-Path $firmwarePath) {
        try {
            $folderGuids = Get-ChildItem $firmwarePath -Directory -ErrorAction SilentlyContinue |
                           Select-Object -ExpandProperty Name
            if ($folderGuids) {
                foreach ($g in $folderGuids) {
                    $gLimpo = ($g -replace '^\{|\}$', '').ToUpper()
                    if ($guids -notcontains $gLimpo) {
                        $guids += $gLimpo
                        Write-Info "  [Pasta] $gLimpo"
                    }
                }
            }
        } catch {
            Write-Warn "  Erro na Fonte 3: $_"
        }
    } else {
        Write-Warn "  Pasta $firmwarePath nao encontrada."
    }

    return $guids | Sort-Object -Unique | Where-Object {
        $_ -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    }
}

# ----------------------------------------------------------------------------
# Funcao: compactacao individual de um arquivo
# ----------------------------------------------------------------------------

function Compress-SingleFile {
    <#
    .SYNOPSIS
        Compacta um unico arquivo em .zip, mantendo o original.

    .DESCRIPTION
        Utiliza 7-Zip quando disponivel; caso contrario, utiliza o
        cmdlet nativo Compress-Archive.

    .PARAMETER FilePath
        Caminho completo do arquivo a ser compactado.

    .OUTPUTS
        System.String - Caminho completo do .zip gerado.
    #>
    param([Parameter(Mandatory)][string]$FilePath)

    $zipPath = "$FilePath.zip"

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $SETEZIP) {
        & $SETEZIP a "$zipPath" "$FilePath" -mx=5 -mmt=4 -tzip | Out-Null
    } else {
        Compress-Archive -Path $FilePath -DestinationPath $zipPath -Force
    }

    return $zipPath
}

# ----------------------------------------------------------------------------
# ETAPA 0 - Part Number
# ----------------------------------------------------------------------------

Write-Section 'ETAPA 0/5 - Part Number da placa'

Write-Host '  Informe o Part Number da placa (ex.: LA-L181P).' -ForegroundColor Gray
Write-Host '  Pressione ENTER sem digitar nada para seguir sem o Part Number.' -ForegroundColor DarkGray
$partNumber = Read-Host '  Part Number'

if ([string]::IsNullOrWhiteSpace($partNumber)) {
    $partNumber = ''
    Write-Warn 'Nenhum Part Number informado. Os arquivos serao nomeados apenas com GUID + BIOS + versao.'
} else {
    $partNumber = $partNumber.Trim()
    Write-OK "Part Number definido: $partNumber"
}

# ----------------------------------------------------------------------------
# ETAPA 1 - Descoberta dos GUIDs
# ----------------------------------------------------------------------------

Write-Section 'ETAPA 1/5 - Procurando GUIDs de BIOS/UEFI'

$guids = Get-FirmwareGuids

if (-not $guids -or $guids.Count -eq 0) {
    Write-Warn 'Nenhum GUID de firmware valido encontrado neste sistema.'
    Read-Host 'Pressione ENTER para sair'
    exit 1
}

Write-OK "Total de $($guids.Count) GUID(s) valido(s) encontrado(s)."

# ----------------------------------------------------------------------------
# ETAPA 2 - Modulo MSCatalogLTS
# ----------------------------------------------------------------------------

Write-Section 'ETAPA 2/5 - Verificando modulo MSCatalogLTS'

if (Get-Module -ListAvailable -Name MSCatalogLTS) {
    Write-OK 'MSCatalogLTS ja esta instalado.'
} else {
    Write-Info 'Instalando MSCatalogLTS...'
    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-Module -Name MSCatalogLTS -Scope CurrentUser -Force -AllowClobber | Out-Null
        Write-OK 'MSCatalogLTS instalado com sucesso.'
    } catch {
        Write-Err "Falha ao instalar o MSCatalogLTS: $_"
        Read-Host 'Pressione ENTER para sair'
        exit 1
    }
}

Import-Module MSCatalogLTS -Force

# ----------------------------------------------------------------------------
# ETAPA 3 - Download, extracao, renomeacao e compactacao
# ----------------------------------------------------------------------------

Write-Section 'ETAPA 3/5 - Baixando, extraindo, renomeando e compactando'

Write-Info "Tamanho minimo aceito para firmware: $([math]::Round($TAMANHO_MINIMO_FIRMWARE / 1MB, 2)) MB"

if (-not (Test-Path $ROOT_PATH)) {
    New-Item -ItemType Directory -Path $ROOT_PATH -Force | Out-Null
}

$totalBins      = 0
$totalZips      = 0
$totalDownloads = 0
$totalErros     = 0
$totalIgnorados = 0

foreach ($guid in $guids) {
    Write-Host ''
    Write-Host ('-' * 60) -ForegroundColor DarkGray
    Write-Host "  GUID: $guid" -ForegroundColor Yellow
    Write-Host ('-' * 60) -ForegroundColor DarkGray

    $pastaBins = Join-Path $ROOT_PATH "$guid\binarios"
    if (-not (Test-Path $pastaBins)) {
        New-Item -ItemType Directory -Path $pastaBins -Force | Out-Null
    }

    $pastaTemp = Join-Path $ROOT_PATH "_temp_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $pastaTemp -Force | Out-Null

    $guidLimpo = $guid -replace '^\{|\}$', ''

    if ([string]::IsNullOrWhiteSpace($partNumber)) {
        $prefixoNome = $guidLimpo
    } else {
        $prefixoNome = "$partNumber`_$guidLimpo"
    }

    Write-Info "Buscando por: $guidLimpo"
    Write-Info "Prefixo do nome: $prefixoNome"

    try {
        $updates = Get-MSCatalogUpdate -Search $guidLimpo -ErrorAction SilentlyContinue

        if ($null -eq $updates -or $updates.Count -eq 0) {
            Write-Warn 'Nenhuma atualizacao encontrada para este GUID.'
            continue
        }

        Write-OK "Encontradas $($updates.Count) atualizacoes no Catalogo."

        foreach ($update in $updates) {
            $versao = 'Desconhecida'
            if ($update.Title -match '(\d+\.\d+\.\d+\.\d+)') {
                $versao = $Matches[1]
            } elseif ($update.Title -match '\b(v\d+[\d\.]*)\b') {
                $versao = $Matches[1]
            }

            $jaExiste = $false
            foreach ($ext in $EXTENSOES_FIRMWARE) {
                $nomeTeste = "$prefixoNome`_BIOS_$versao$ext"
                if (Test-Path (Join-Path $pastaBins $nomeTeste)) {
                    $jaExiste = $true
                    break
                }
            }
            if ($jaExiste) {
                Write-Info "Versao $versao ja extraida. Pulando."
                continue
            }

            Write-Info "Processando versao: $versao..."

            $tempDl = Join-Path $pastaTemp 'dl'
            if (Test-Path $tempDl) { Remove-Item $tempDl -Recurse -Force }
            New-Item -ItemType Directory -Path $tempDl -Force | Out-Null

            try {
                $update | Save-MSCatalogUpdate -Destination $tempDl -ErrorAction Stop | Out-Null
                $cabFile = Get-ChildItem $tempDl -Filter '*.cab' -ErrorAction SilentlyContinue | Select-Object -First 1

                if (-not $cabFile) {
                    Write-Warn '  Nenhum .cab retornado para esta versao.'
                    continue
                }

                $totalDownloads++

                $tempExtraido = Join-Path $pastaTemp 'extraido'
                if (Test-Path $tempExtraido) { Remove-Item $tempExtraido -Recurse -Force }
                New-Item -ItemType Directory -Path $tempExtraido -Force | Out-Null

                & expand.exe "$($cabFile.FullName)" -F:* "$tempExtraido" | Out-Null

                $todosArquivos = Get-ChildItem $tempExtraido -File -Recurse -ErrorAction SilentlyContinue

                $candidatos = $todosArquivos | Where-Object {
                    $EXTENSOES_FIRMWARE -contains $_.Extension.ToLower()
                }

                $firmwares = $candidatos | Where-Object {
                    $_.Length -ge $TAMANHO_MINIMO_FIRMWARE
                }

                $descartados = $candidatos | Where-Object {
                    $_.Length -lt $TAMANHO_MINIMO_FIRMWARE
                }
                foreach ($d in $descartados) {
                    $tamKB = [math]::Round($d.Length / 1KB, 1)
                    Write-Info "  Ignorado (pequeno demais): $($d.Name) ($tamKB KB)"
                    $totalIgnorados++
                }

                if ($firmwares -and $firmwares.Count -gt 0) {
                    $firmwarePrincipal = $firmwares | Sort-Object Length -Descending | Select-Object -First 1
                    $extensaoOriginal  = $firmwarePrincipal.Extension.ToLower()

                    $nomeBin         = "$prefixoNome`_BIOS_$versao$extensaoOriginal"
                    $caminhoBinFinal = Join-Path $pastaBins $nomeBin

                    Copy-Item -Path $firmwarePrincipal.FullName -Destination $caminhoBinFinal -Force
                    $tamanhoMB = [math]::Round($firmwarePrincipal.Length / 1MB, 2)

                    Write-OK "  Firmware salvo: $nomeBin ($tamanhoMB MB)"
                    $totalBins++

                    try {
                        $zipGerado = Compress-SingleFile -FilePath $caminhoBinFinal
                        Write-OK "  Zip gerado: $(Split-Path $zipGerado -Leaf)"
                        $totalZips++
                    } catch {
                        Write-Warn "  Falha ao compactar ${nomeBin}: $_"
                    }
                } else {
                    Write-Warn '  Nenhum firmware valido dentro do .cab (extensao + tamanho).'
                    if ($todosArquivos) {
                        $nomes = ($todosArquivos | Select-Object -First 10 -ExpandProperty Name) -join ', '
                        Write-Warn "  Arquivos encontrados: $nomes"
                    }
                }
            } catch {
                Write-Err "  Erro ao processar versao $versao : $_"
                $totalErros++
            }
        }
    } catch {
        Write-Err "Erro ao processar GUID $guid : $_"
        $totalErros++
    } finally {
        if (Test-Path $pastaTemp) {
            Remove-Item $pastaTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------------------------
# ETAPA 4 - Limpeza de arquivos temporarios
# ----------------------------------------------------------------------------

Write-Section 'ETAPA 4/5 - Limpeza final'

$removidosCab    = 0
$removidosPastas = 0

foreach ($guid in $guids) {
    $pastaGuid = Join-Path $ROOT_PATH $guid
    if (-not (Test-Path $pastaGuid)) { continue }

    $cabsAntigos = Get-ChildItem $pastaGuid -Filter '*.cab' -File -ErrorAction SilentlyContinue
    foreach ($c in $cabsAntigos) {
        Remove-Item $c.FullName -Force -ErrorAction SilentlyContinue
        $removidosCab++
    }

    $pastaExtraidoAntiga = Join-Path $pastaGuid 'extraido'
    if (Test-Path $pastaExtraidoAntiga) {
        Remove-Item $pastaExtraidoAntiga -Recurse -Force -ErrorAction SilentlyContinue
        $removidosPastas++
    }

    $pastasTempDl = Get-ChildItem $pastaGuid -Directory -Filter 'temp*' -ErrorAction SilentlyContinue
    foreach ($pt in $pastasTempDl) {
        Remove-Item $pt.FullName -Recurse -Force -ErrorAction SilentlyContinue
        $removidosPastas++
    }
}

if ($removidosCab -gt 0 -or $removidosPastas -gt 0) {
    Write-Info "Removidos $removidosCab .cab e $removidosPastas pasta(s) temporaria(s) de execucoes anteriores."
} else {
    Write-Info 'Nada a limpar de execucoes anteriores.'
}

# ----------------------------------------------------------------------------
# RESUMO FINAL
# ----------------------------------------------------------------------------

Write-Section 'RESUMO FINAL'
Write-Host ''
Write-Host "  Pasta raiz           : $ROOT_PATH" -ForegroundColor White
Write-Host "  Part Number          : $(if ($partNumber) { $partNumber } else { '(nao informado)' })" -ForegroundColor White
Write-Host "  GUIDs processados    : $($guids.Count)" -ForegroundColor White
Write-Host "  Cabs baixados        : $totalDownloads" -ForegroundColor Green
Write-Host "  Firmwares salvos     : $totalBins" -ForegroundColor Green
Write-Host "  Zips gerados         : $totalZips" -ForegroundColor Green
Write-Host "  Ignorados (pequenos) : $totalIgnorados" -ForegroundColor Yellow
if ($totalErros -gt 0) {
    Write-Host "  Erros                : $totalErros" -ForegroundColor Red
}
Write-Host ''
Write-Host '  Arquivos disponiveis (bin + zip):' -ForegroundColor White
Write-Host ''

foreach ($guid in $guids) {
    $pastaBins = Join-Path $ROOT_PATH "$guid\binarios"
    if (-not (Test-Path $pastaBins)) { continue }

    Write-Host "  $guid" -ForegroundColor Yellow
    $arquivos = Get-ChildItem $pastaBins -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $EXTENSOES_FIRMWARE -contains $_.Extension.ToLower() -or $_.Extension.ToLower() -eq '.zip'
                } |
                Sort-Object Name

    if ($arquivos -and $arquivos.Count -gt 0) {
        foreach ($b in $arquivos) {
            $tam = [math]::Round($b.Length / 1MB, 2)
            Write-Host "    $($b.Name)  ($tam MB)" -ForegroundColor Gray
        }
    } else {
        Write-Host '    (nenhum arquivo)' -ForegroundColor DarkGray
    }
    Write-Host ''
}

Write-Host ''
Read-Host 'Pressione ENTER para sair'