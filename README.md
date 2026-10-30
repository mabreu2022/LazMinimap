# LazMinimap - Form Designer MiniMap para Lazarus IDE

**LazMinimap** é uma extensão (IDE Package) para a IDE do **Lazarus (Free Pascal)** que adiciona um **Mini-mapa do Designer de Formulários**, inspirado na experiência visual do Delphi e moderno para desenvolvimento desktop.

## Funcionalidades

- **Visualização em Escala Real de 1080p (Full HD)**:
  - O mini-mapa exibe uma área de referência Full HD (`1920x1080`).
  - O formulário ativo no designer é desenhado proporcionalmente, permitindo visualizar instantaneamente o impacto do tamanho do formulário em relação a um monitor 1080p.
  - Exibe no cabeçalho as dimensões em pixels e a porcentagem ocupada na tela (ex: `Form1 [890x411] (46%x38%)`).

- **Desenho Dinâmico de Controles**:
  - Renderiza miniaturas fiéis dos controles visuais (`TPanel`, `TButton`, `TEdit`, `TLabel`, `TDBGrid`, etc.) e ícones para componentes não-visuais (`TTimer`, `TOpenDialog`, `TDataSource`).
  - Destaque vibrante com alças de dimensionamento para o componente atualmente selecionado.

- **Seleção Interativa**:
  - Clicar em qualquer controle na miniatura seleciona instantaneamente o componente no Form Designer e no Object Inspector da IDE.
  - Tooltip/Hint dinâmico ao passar o mouse sobre os componentes.

- **Ancoragem Flexível e Modo Destacável**:
  - **Ancoragem nos 4 Cantos**:
    - Canto Inferior Esquerdo (Padrão)
    - Canto Inferior Direito
    - Canto Superior Esquerdo
    - Canto Superior Direito
  - **Modo Destacável**: Clique e arraste pela barra de título para posicionar livremente o mini-mapa onde preferir na tela.
  - **Botão Minimizar/Recolher (`-` / `+`)**: Recolha o mini-mapa para uma barra compacta de 20px com apenas um clique.
  - **Menu de Contexto**: Clique com botão direito para alternar rapidamente entre os cantos.

- **Integração Perfeita com o Ciclo de Vida da IDE**:
  - Fica visível **apenas** quando o Designer de Formulários estiver ativo.
  - Oculta-se automaticamente ao alternar para o editor de código-fonte.
  - Proteção robusta contra reentrância de eventos e *Stack overflow* durante o redimensionamento do formulário.

## Instalação no Lazarus

1. Abra a IDE do Lazarus.
2. Acesse o menu **Pacote (Package)** > **Abrir arquivo de pacote (.lpk)**.
3. Selecione o arquivo `lazarus_minimap_ide.lpk`.
4. Clique em **Compilar** e em seguida **Usar** > **Instalar**.
5. Confirme a recompilação da IDE do Lazarus.
6. Ao abrir qualquer formulário no Designer (F12), o mini-mapa surgirá no canto inferior esquerdo.

## Licença

Distribuído sob a licença Modified LGPL / GPL comum aos componentes do Lazarus.
