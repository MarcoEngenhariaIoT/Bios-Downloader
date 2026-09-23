# BiosDownloader

Ferramenta em PowerShell para baixar e organizar automaticamente atualizacoes de BIOS/UEFI a partir do Microsoft Update Catalog.

## Descricao

O BiosDownloader automatiza a coleta de atualizacoes de BIOS/UEFI publicadas pela Microsoft para o hardware em que o script e executado. O firmware e extraido do pacote `.cab`, renomeado segundo um padrao previsivel e compactado individualmente em `.zip`, mantendo o binario original na mesma pasta.

O objetivo e oferecer um processo reproduzivel de obtencao e organizacao de firmware, evitando busca manual no catalogo e reduzindo o risco de erro na escolha do pacote.

## Recursos

- Descoberta automatica dos GUIDs de BIOS/UEFI do sistema, com fallback em tres fontes independentes.
- Filtro pelo ClassGuid da classe `System Firmware`, isolando o firmware da placa-mae de outros dispositivos (audio, video, etc.).
- Filtro por extensao conhecida de firmware (`.bin`, `.fd`, `.rom`, `.cap`, `.fl1`, `.fl2`, `.fl3`, `.hex`, `.img`).
- Filtro por tamanho minimo configuravel, descartando arquivos que nao correspondem a firmware de BIOS.
- Padronizacao do nome do arquivo final no formato `{PartNumber}_{GUID}_BIOS_{versao}{extensao}`.
- Compactacao individual de cada firmware em `.zip`, preservando o binario original.
- Limpeza automatica de arquivos temporarios ao final da execucao.
- Compatibilidade com 7-Zip (se instalado) e fallback nativo para `Compress-Archive`.

## Requisitos

- Windows 10 ou Windows 11
- PowerShell 5.1 ou superior
- Execucao como Administrador
- Conexao com a internet
- (Opcional) 7-Zip instalado em `C:\Program Files\7-Zip\7z.exe`

O modulo `MSCatalogLTS` e instalado automaticamente na primeira execucao, caso ausente.

## Instalacao

Nao ha instalacao. Basta clonar o repositorio ou baixar o arquivo `.ps1`.

```powershell
git clone https://github.com/<seu-usuario>/BiosDownloader.git
```

## Uso

1. Abra o PowerShell como Administrador.
2. Navegue ate a pasta do script.
3. Execute:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\BiosDownloader_1.0.ps1
```

Sera solicitado o Part Number da placa. Caso nao seja informado, os arquivos serao nomeados apenas com GUID, identificador `BIOS` e versao.

## Estrutura de saida

Os arquivos sao armazenados em `C:\BIOS_Downloads`, respeitando a seguinte estrutura:

```
C:\BIOS_Downloads\
    {GUID}\
        binarios\
            {PartNumber}_{GUID}_BIOS_{versao}.fd
            {PartNumber}_{GUID}_BIOS_{versao}.fd.zip
            ...
```

## Parametros de configuracao

As principais variaveis ajustaveis estao no inicio do script:

| Variavel                   | Descricao                                                          | Valor padrao |
|----------------------------|--------------------------------------------------------------------|--------------|
| `$EXTENSOES_FIRMWARE`      | Extensoes reconhecidas como firmware                               | Lista fixa   |
| `$TAMANHO_MINIMO_FIRMWARE` | Tamanho minimo para considerar um arquivo como firmware            | `3MB`        |
| `$SETEZIP`                 | Caminho do executavel do 7-Zip                                     | `C:\Program Files\7-Zip\7z.exe` |
| `$ROOT_PATH`               | Pasta raiz de destino                                              | `C:\BIOS_Downloads` |

## Fluxo de execucao

```
Etapa 0 - Leitura do Part Number (opcional)
Etapa 1 - Descoberta dos GUIDs de BIOS/UEFI
Etapa 2 - Verificacao/instalacao do modulo MSCatalogLTS
Etapa 3 - Download, extracao, renomeacao e compactacao
Etapa 4 - Limpeza de arquivos temporarios
Resumo  - Consolidacao dos resultados
```

## Limitacoes

- O script depende da disponibilidade do Microsoft Update Catalog e do modulo `MSCatalogLTS`.
- O filtro por tamanho minimo pode descartar firmwares legitimos em plataformas mais antigas. O limite e ajustavel no topo do script.
- O script nao realiza a instalacao do firmware. Apenas baixa e organiza os arquivos.

## Aviso

Este software e fornecido "como esta", sem garantias de qualquer natureza. O uso e de inteira responsabilidade do usuario. A atualizacao de firmware de BIOS/UEFI e uma operacao critica e pode inutilizar o equipamento em caso de falha. Certifique-se de que o arquivo obtido corresponde exatamente ao modelo do seu equipamento antes de qualquer procedimento de atualizacao.

## Licenca

Distribuido sob a licenca MIT. Consulte o arquivo `LICENSE` para mais detalhes.

## Autor

Eng. Marco Aurelio Machado
Projeto Marco Notebooks