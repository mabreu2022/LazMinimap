# LazMinimap - Form Designer & Code Editor MiniMap para Lazarus IDE

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
  - Destaque claro representando com precisão as linhas visíveis na tela (`TopLine` até `TopLine + LinesInWindow`).
- **Navegação Interativa**:
  - **Clique ou Arraste**: Clique em qualquer linha do mini-mapa ou arraste a barra de viewport para rolar o código instantaneamente.
  - **Roda do Mouse (Wheel)**: Rolar o scroll sobre o mini-mapa move o editor de código.
- **Menu de Contexto**:
  - Clique com botão direito no mini-mapa de código para ajustar a largura (80px, 110px padrão, 140px, 180px) ou ocultar.

---

## 2. Form Designer MiniMap (Mini-mapa do Designer de Formulários)

Ativado automaticamente quando você está desenhando o formulário (aba **Formulário**):

- **Escala Real comparada a 1080p (Full HD)**:
  - O mini-mapa exibe uma área de referência Full HD (`1920x1080`).
  - O formulário é desenhado proporcionalmente, permitindo visualizar instantaneamente o tamanho real do form em um monitor 1080p.
  - Exibe no cabeçalho o nome, dimensões em pixels e porcentagem ocupada (ex: `Form1 [890x411] (46%x38%)`).
- **Desenho Dinâmico de Controles**:
  - Renderiza miniaturas fiéis dos controles visuais (`TPanel`, `TButton`, `TEdit`, `TLabel`, `TDBGrid`, etc.) e ícones para componentes não-visuais (`TTimer`, `TOpenDialog`, `TDataSource`).
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

## Instalação no Lazarus

1. Abra a IDE do Lazarus.
2. Acesse o menu **Pacote (Package)** > **Abrir arquivo de pacote (.lpk)**.
3. Selecione o arquivo `lazarus_minimap_ide.lpk`.
4. Clique em **Compilar** e em seguida **Usar** > **Instalar**.
5. Confirme a recompilação da IDE do Lazarus.
6. Pronto! Ao alternar entre Código e Formulário (F12), cada mini-mapa correspondente aparecerá automaticamente.

---

## Licença

Distribuído sob a licença Modified LGPL / GPL comum aos componentes do Lazarus.
