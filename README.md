# BiosDownloader

Ferramenta em PowerShell para baixar e organizar automaticamente atualizações de BIOS/UEFI a partir do Microsoft Update Catalog.

## Descrição

O BiosDownloader automatiza a coleta de atualizações de BIOS/UEFI publicadas pela Microsoft para o hardware em que o script é executado. O firmware é extraído do pacote `.cab`, renomeado segundo um padrão previsível e compactado individualmente em `.zip`, mantendo o binário original na mesma pasta.

O objetivo é oferecer um processo reproduzível de obtenção e organização de firmware, evitando busca manual no catálogo e reduzindo o risco de erro na escolha do pacote.

## Recursos

- Descoberta automática dos GUIDs de BIOS/UEFI do sistema, com fallback em três fontes independentes.
- Filtro pelo ClassGuid da classe `System Firmware`, isolando o firmware da placa-mãe de outros dispositivos (áudio, vídeo, etc.).
- Filtro por extensão conhecida de firmware (`.bin`, `.fd`, `.rom`, `.cap`, `.fl1`, `.fl2`, `.fl3`, `.hex`, `.img`).
- Filtro por tamanho mínimo configurável, descartando arquivos que não correspondem a firmware de BIOS.
- Padronização do nome do arquivo final no formato `{PartNumber}_{GUID}_BIOS_{versão}{extensão}`.
- Compactação individual de cada firmware em `.zip`, preservando o binário original.
- Limpeza automática de arquivos temporários ao final da execução.
- Compatibilidade com 7-Zip (se instalado) e fallback nativo para `Compress-Archive`.

## Requisitos

- Windows 10 ou Windows 11
- PowerShell 5.1 ou superior
- Execução como Administrador
- Conexão com a internet
- (Opcional) 7-Zip instalado em `C:\Program Files\7-Zip\7z.exe`

O módulo `MSCatalogLTS` é instalado automaticamente na primeira execução, caso ausente.

## Instalação

Não há instalação. Basta clonar o repositório ou baixar o arquivo `.ps1`.

```powershell
git clone https://github.com/<seu-usuario>/BiosDownloader.git
```

## Uso

1. Abra o PowerShell como Administrador.
2. Navegue até a pasta do script.
3. Execute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\BiosDownloader_1.0.ps1
```

Será solicitado o Part Number da placa. Caso não seja informado, os arquivos serão nomeados apenas com GUID, identificador `BIOS` e versão.

## Estrutura de saída

Os arquivos são armazenados em `C:\BIOS_Downloads`, respeitando a seguinte estrutura:

```
C:\BIOS_Downloads\
    {GUID}\
        binarios\
            {PartNumber}_{GUID}_BIOS_{versão}.fd
            {PartNumber}_{GUID}_BIOS_{versão}.fd.zip
            ...
```

## Parâmetros de configuração

As principais variáveis ajustáveis estão no início do script:

| Variável                   | Descrição                                                          | Valor padrão |
|----------------------------|--------------------------------------------------------------------|--------------|
| `$EXTENSOES_FIRMWARE`      | Extensões reconhecidas como firmware                               | Lista fixa   |
| `$TAMANHO_MINIMO_FIRMWARE` | Tamanho mínimo para considerar um arquivo como firmware            | `3MB`        |
| `$SETEZIP`                 | Caminho do executável do 7-Zip                                     | `C:\Program Files\7-Zip\7z.exe` |
| `$ROOT_PATH`               | Pasta raiz de destino                                              | `C:\BIOS_Downloads` |

## Fluxo de execução

```
Etapa 0 - Leitura do Part Number (opcional)
Etapa 1 - Descoberta dos GUIDs de BIOS/UEFI
Etapa 2 - Verificação/instalação do módulo MSCatalogLTS
Etapa 3 - Download, extração, renomeação e compactação
Etapa 4 - Limpeza de arquivos temporários
Resumo  - Consolidação dos resultados
```

## Limitações

- O script depende da disponibilidade do Microsoft Update Catalog e do módulo `MSCatalogLTS`.
- O filtro por tamanho mínimo pode descartar firmwares legítimos em plataformas mais antigas. O limite é ajustável no topo do script.
- O script não realiza a instalação do firmware. Apenas baixa e organiza os arquivos.

## Aviso

Este software é fornecido "como está", sem garantias de qualquer natureza. O uso é de inteira responsabilidade do usuário. A atualização de firmware de BIOS/UEFI é uma operação crítica e pode inutilizar o equipamento em caso de falha. Certifique-se de que o arquivo obtido corresponde exatamente ao modelo do seu equipamento antes de qualquer procedimento de atualização.

## Licença

Distribuído sob a licença MIT. Consulte o arquivo `LICENSE` para mais detalhes.

## Autor

Eng. Marco Aurélio Machado
Projeto Marco Notebooks