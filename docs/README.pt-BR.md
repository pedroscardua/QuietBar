# QuietBar

App nativo para macOS que fica na barra superior e reproduz uma mistura de dez camadas de ruído, sem navegador ou conexão durante o uso.

Clique no ícone de onda para abrir o painel compacto: reproduzir/pausar, volume, preset, movimento e timer. **Abrir controles** mostra todas as opções. O painel usa Liquid Glass no macOS 26 e material translúcido do sistema nas versões anteriores.

## Instalar a partir do código

Requer Swift/Clang com SDK do macOS 26 (Xcode 26 ou Command Line Tools equivalentes). O alvo mínimo de execução é macOS 13, ainda sem validação em máquinas com macOS 13–25. Python 3 é necessário para os testes.

```sh
git clone https://github.com/pedroscardua/my-noise.git
cd my-noise
./build.sh
open build/QuietBar.app
```

Para instalar, arraste `build/QuietBar.app` para Aplicativos. Encerre outra instância do QuietBar antes de abrir esta. Os binários de [Releases](https://github.com/pedroscardua/my-noise/releases) não possuem notarização Apple; o macOS pode bloquear o download. A compilação local é a opção recomendada.

## Uso

- Ajuste as dez camadas de graves a agudos e o volume geral.
- Salve presets ou importe/exporte JSON. Um preset importado precisa ser salvo para entrar na lista.
- Ative movimento suave e ajuste velocidade, largura estéreo e compressor.
- Escolha 15, 30, 60 ou 90 minutos no timer. O volume diminui por três segundos antes de pausar.
- Fechar a janela mantém o som. O app inicia pausado e não aparece no Dock.

A edição pública usa **ruído próprio**, gerado na compilação. A importação de links White Noise & Co copia ajustes, não áudios: o resultado soa diferente do myNoise. A edição pessoal anterior usa outra pasta de preferências, para preservar seus presets.

Os arquivos de áudio ocupam aproximadamente 131 MiB em disco e são lidos em buffers. O consumo de RAM depende do sistema e não equivale ao tamanho dos arquivos.

Configurações: `~/Library/Application Support/QuietBar-OpenSource/state.json`. Sem telemetria, contas ou servidor. Licença [MIT](../LICENSE).

Para contribuir, consulte [CONTRIBUTING](../CONTRIBUTING.md). Documentação técnica e fluxo de releases estão em inglês.
