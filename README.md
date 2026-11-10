<a id="readme-en"></a>
# LazMinimap — Form Designer & Code Editor MiniMap for Lazarus IDE

<p align="center">
  <b>🇺🇸 English</b> &nbsp;|&nbsp; <a href="#readme-pt">🇧🇷 Português</a>
</p>

[![License: Modified LGPL](https://img.shields.io/badge/License-Modified%20LGPL-blue.svg)](https://www.gnu.org/licenses/lgpl-2.1.html)
[![Lazarus: 2.2+](https://img.shields.io/badge/Lazarus-2.2%2B-blue.svg)](https://www.lazarus-ide.org/)
[![Target: Windows | Linux | macOS](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-green.svg)](https://www.lazarus-ide.org/)

**LazMinimap** is a comprehensive IDE extension (IDE Package) for **Lazarus IDE (Free Pascal / FPC)** that integrates two modern and fluid minimaps, inspired by the Delphi and VS Code developer experience:

1. **Code Editor MiniMap**: Vertical source code minimap docked to the right edge of the source editor (`TSynEdit`).
2. **Form Designer MiniMap**: Form designer minimap featuring Full HD 1080p scale preview and 4-corner docking.

---

## 1. Code Editor MiniMap

Automatically activated when editing source code (**Code** tab):

- **Real-Time Syntax-Highlighted Miniature**:
  - Renders proportional lines and blocks of code mirroring document structure.
  - Recognizes and colors keywords (`unit`, `procedure`, `begin`, `end`, etc.), comments (`//`, `{$...}`), strings, numbers, and types/classes.
- **Translucent Viewport Rectangle**:
  - High-visibility transparent viewport highlighting the exact lines currently visible on screen (`TopLine` to `TopLine + LinesInWindow`).
  - Hover feedback with dynamic border highlighting.
- **Adjustable Zoom & Scale**:
  - Top zoom control bar (`-` / `+`, Fit, 1x, 2x, 4x, up to 8x).
  - Easily fit the entire unit on screen or zoom in for fine-grained navigation.
- **Interactive Navigation**:
  - **Click or Drag**: Click on any line of the minimap or drag the viewport slider to scroll through code instantly.
  - **Mouse Wheel**: Scrolling over the minimap smoothly scrolls the code editor.
- **Context Menu**:
  - Right-click the code minimap to adjust width (80px, 110px default, 140px, 180px), toggle render modes, or hide.

---

## 2. Form Designer MiniMap

Automatically activated when designing forms (**Form** tab / F12):

- **Real Full HD (1080p) Scale Reference**:
  - Displays a 1080p reference canvas (`1920x1080`).
  - Forms are drawn proportionally, allowing you to instantly assess real-world screen coverage on standard 1080p monitors.
  - Header displays form name, pixel dimensions, and percentage coverage (e.g. `Form1 [890x411] (46%x38%)`).
- **Dynamic Control Rendering**:
  - Faithful thumbnails of visual controls (`TPanel`, `TButton`, `TEdit`, `TLabel`, `TDBGrid`, `TPageControl`, etc.) and clean badges for non-visual components (`TTimer`, `TOpenDialog`, `TDataSource`).
  - Highlight and resize handles on the currently selected component.
- **Interactive Component Selection**:
  - Clicking any control on the minimap instantly selects that component in both the Form Designer and Object Inspector.
  - Dynamic tooltip/hint when hovering over controls.
- **Flexible Docking & Detachable Mode**:
  - **4-Corner Docking**:
    - Bottom-Left (Default)
    - Bottom-Right
    - Top-Left
    - Top-Right
  - **Free-Floating Mode**: Drag via title bar to position anywhere over the designer canvas.
  - **Collapse/Expand (`-` / `+`)**: Quickly collapse into a compact 20px header with a single click.

---

## 📦 Installation in Lazarus IDE

1. Open **Lazarus IDE**.
2. Go to **Package** > **Open Package File (.lpk)...**.
3. Select `lazarus_minimap_ide.lpk`.
4. Click **Compile**, then **Use** > **Install**.
5. Confirm rebuilding the Lazarus IDE when prompted.
6. Done! When toggling between Code and Form (`F12`), each respective minimap will appear automatically.

---

## 📄 License

Distributed under the Modified LGPL / GPL license terms standard for Lazarus components.

---
<br/>

<a id="readme-pt"></a>
# LazMinimap - Form Designer & Code Editor MiniMap para Lazarus IDE

<p align="center">
  <a href="#readme-en">🇺🇸 English</a> &nbsp;|&nbsp; <b>🇧🇷 Português</b>
</p>

[![License: Modified LGPL](https://img.shields.io/badge/License-Modified%20LGPL-blue.svg)](https://www.gnu.org/licenses/lgpl-2.1.html)
[![Lazarus: 2.2+](https://img.shields.io/badge/Lazarus-2.2%2B-blue.svg)](https://www.lazarus-ide.org/)
[![Target: Windows | Linux | macOS](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-green.svg)](https://www.lazarus-ide.org/)

**LazMinimap** é uma extensão completa (IDE Package) para a IDE do **Lazarus (Free Pascal)** que integra dois mini-mapas modernos e fluidos, inspirados na experiência do Delphi e VS Code:

1. **Code Editor MiniMap**: Mini-mapa de código-fonte vertical fixado na lateral direita do editor de código (`TSynEdit`).
2. **Form Designer MiniMap**: Mini-mapa do designer de formulários com proporção Full HD 1080p e docking nos 4 cantos.

---

## 1. Code Editor MiniMap (Mini-mapa do Editor de Código)

Ativado automaticamente quando você está editando código-fonte (aba **Código**):

- **Miniatura em Tempo Real com Destaque de Sintaxe**:
  - Renderiza blocos e linhas proporcionais de código simulando as linhas do documento.
  - Reconhecimento e coloração de palavras-chave (`unit`, `procedure`, `begin`, `end`, etc.), comentários (`//`, `{$...}`), strings e tipos/classes.
- **Retângulo de Viewport Translúcido**:
  - Destaque transparente com bordas nítidas representando com precisão as linhas visíveis na tela (`TopLine` até `TopLine + LinesInWindow`).
  - Realce dinâmico ao passar o mouse sobre a área do viewport.
- **Zoom & Escala Ajustáveis**:
  - Barra superior de controle de Zoom (`-` / `+`, Fit, 1x, 2x, 4x, até 8x).
  - Permite visualizar a unit inteira na tela (Fit) ou aproximar até 8x para navegação precisa.
- **Navegação Interativa**:
  - **Clique ou Arraste**: Clique em qualquer linha do mini-mapa ou arraste a barra de viewport para rolar o código instantaneamente.
  - **Roda do Mouse (Wheel)**: Rolar o scroll sobre o mini-mapa move o editor de código.
- **Menu de Contexto**:
  - Clique com botão direito no mini-mapa de código para ajustar a largura (80px, 110px padrão, 140px, 180px), alternar modo de renderização ou ocultar.

---

## 2. Form Designer MiniMap (Mini-mapa do Designer de Formulários)

Ativado automaticamente quando você está desenhando o formulário (aba **Formulário**):

- **Escala Real comparada a 1080p (Full HD)**:
  - O mini-mapa exibe uma área de referência Full HD (`1920x1080`).
  - O formulário é desenhado proporcionalmente, permitindo visualizar instantaneamente o tamanho real do form em um monitor 1080p.
  - Exibe no cabeçalho o nome, dimensões em pixels e porcentagem ocupada (ex: `Form1 [890x411] (46%x38%)`).
- **Desenho Dinâmico de Controles**:
  - Renderiza miniaturas fiéis dos controles visuais (`TPanel`, `TButton`, `TEdit`, `TLabel`, `TDBGrid`, `TPageControl`, etc.) e ícones para componentes não-visuais (`TTimer`, `TOpenDialog`, `TDataSource`).
  - Destaque com alças de dimensionamento no componente atualmente selecionado.
- **Seleção Interativa**:
  - Clicar em qualquer controle na miniatura seleciona instantaneamente o componente no Form Designer e no Object Inspector da IDE.
  - Tooltip/Hint dinâmico ao passar o mouse sobre os componentes.
- **Ancoragem Flexível e Modo Destacável**:
  - **Ancoragem nos 4 Cantos**:
    - Canto Inferior Esquerdo (Padrão)
    - Canto Inferior Direito
    - Canto Superior Esquerdo
    - Canto Superior Direito
  - **Modo Livre**: Arraste pela barra de título para posicionar livremente o mini-mapa dentro da área do designer.
  - **Recolher/Expandir (`-` / `+`)**: Recolhe para uma barra compacta de 20px com apenas um clique.

---

## 📦 Instalação no Lazarus

1. Abra a IDE do Lazarus.
2. Acesse o menu **Pacote (Package)** > **Abrir arquivo de pacote (.lpk)**.
3. Selecione o arquivo `lazarus_minimap_ide.lpk`.
4. Clique em **Compilar** e em seguida **Usar** > **Instalar**.
5. Confirme a recompilação da IDE do Lazarus.
6. Pronto! Ao alternar entre Código e Formulário (F12), cada mini-mapa correspondente aparecerá automaticamente.

---

## 📄 Licença

Distribuído sob a licença Modified LGPL / GPL comum aos componentes do Lazarus.