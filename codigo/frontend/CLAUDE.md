# Frontend - Interface Web Whaticket

[Diretório Raiz](../../CLAUDE.md) > [codigo](../) > **frontend**

## Change Log (Changelog)

### 2025-09-01 19:03:42 - Inicialização do Contexto Frontend
- Mapeado módulo frontend React SPA
- Identificados 100+ componentes especializados
- Documentado sistema de temas (light/dark mode)
- Configurado ambiente React com Material-UI

## Responsabilidades do Módulo

O frontend é uma **Single Page Application (SPA)** em **React 17** que oferece interface completa para gestão de atendimento WhatsApp:

- **🎨 Dashboard Intuitivo**: Painel de controle com métricas em tempo real
- **🎫 Gestão de Tickets**: Interface para atendimento de conversas
- **💬 Chat Interface**: Simulação da interface WhatsApp
- **👥 Gestão de Usuários**: Admin de usuários, perfis e permissões
- **🏢 Multi-Empresa**: Switching entre empresas/clientes
- **📊 Campanhas**: Criação e gestão de campanhas
- **⚙️ Configurações**: Painéis de configuração do sistema
- **📱 Responsivo**: Adaptado para desktop e mobile

## Entrada e Inicialização

### Pontos de Entrada
- **`src/App.js`**: Componente raiz da aplicação
- **`src/index.js`**: Ponto de montagem React no DOM
- **`public/index.html`**: Template HTML base

### Inicialização
```javascript
// Sequência de boot
index.js → App.js → ThemeProvider → Routes → Pages/Components
```

### Scripts Disponíveis
```bash
npm start         # Desenvolvimento (porta 3001)
npm run build     # Build para produção
npm run builddev  # Build desenvolvimento
npm test          # Executar testes
npm run eject     # Ejetar create-react-app (irreversível)
```

### Configuração Especial
- **NODE_OPTIONS**: `--openssl-legacy-provider` para compatibilidade
- **GENERATE_SOURCEMAP**: `false` em build de produção

## Interfaces Externas

### Principais Componentes

#### **Dashboard & Analytics**
- `Dashboard/CardCounter.js` - Cards de métricas
- `Dashboard/TableAttendantsStatus.js` - Status dos atendentes

#### **Gestão de Tickets & Chat**
- `Ticket/index.js` - Interface principal de tickets
- `TicketsList/` - Lista de tickets/conversas
- `MessagesList/index.js` - Lista de mensagens
- `MessageInput/index.js` - Input de envio de mensagens
- `TicketHeader/index.js` - Header do ticket
- `ContactDrawer/index.js` - Drawer com dados do contato

#### **Campanhas & Marketing**
- `CampaignModal/index.js` - Modal de criação de campanhas
- `ContactListTable/index.js` - Tabela de listas de contatos
- `ContactModal/index.js` - Modal de gestão de contatos

#### **Gestão de Usuários**
- `UserModal/` - CRUD de usuários
- `CompaniesManager/index.js` - Gestão multi-empresa
- `PlansManager/index.js` - Gestão de planos

#### **WhatsApp & Conexões**
- `WhatsAppModal/` - Configuração de conexões
- `QrcodeModal/` - Exibição de QR Code para conexão

#### **UI & UX**
- `MainHeader/index.js` - Header principal
- `MainContainer/index.js` - Layout container
- `BackdropLoading/index.js` - Loading spinner
- `NotificationsPopOver/index.js` - Notificações

### Roteamento
```javascript
// Estrutura de rotas (presumida)
/dashboard        # Dashboard principal
/tickets          # Lista de tickets
/contacts         # Gestão de contatos  
/users            # Gestão de usuários
/connections      # Conexões WhatsApp
/campaigns        # Campanhas de marketing
/settings         # Configurações
```

## Principais Dependências e Configuração

### Core Dependencies
```json
{
  "react": "^17.0.2",                     // Framework base
  "react-dom": "^17.0.2",
  "@material-ui/core": "4.12.3",         // UI components
  "@material-ui/icons": "^4.9.1",        // Ícones
  "@material-ui/lab": "^4.0.0-alpha.56", // Componentes beta
  "socket.io-client": "^4.7.5",          // WebSocket client
  "axios": "^0.21.1",                    // HTTP client
  "react-router-dom": "^5.2.0",          // Roteamento
  "react-query": "^3.39.3"               // State management
}
```

### Bibliotecas Especializadas
```json
{
  "formik": "^2.2.0",                     // Forms
  "yup": "^0.32.8",                       // Validation
  "react-chartjs-2": "^4.3.1",           // Charts
  "chart.js": "^3.9.1",                  // Charting library
  "qrcode.react": "^1.0.0",              // QR Code generation
  "emoji-mart": "^3.0.0",                // Emoji picker
  "react-toastify": "9.0.0",             // Notifications
  "styled-components": "^5.3.5"          // CSS-in-JS
}
```

### Configuração de Tema
```javascript
// App.js - Sistema de tema light/dark
const theme = createTheme({
  palette: {
    type: mode, // "light" | "dark"
    primary: { main: mode === "light" ? "#682EE3" : "#FFFFFF" },
    // ... configurações extensas de cores personalizadas
  }
});
```

### Context API
- **ColorModeContext**: Controle de tema light/dark
- **SocketContext**: Gerenciamento da conexão WebSocket
- **AuthContext**: Estado de autenticação (presumido)

## Modelos de Dados (Frontend)

### Estado Global (React Query + Context)
```javascript
// Principais entidades gerenciadas
- tickets          // Lista de tickets
- messages         // Mensagens dos chats
- contacts         // Contatos/clientes
- users            // Usuários do sistema
- companies        // Empresas (multi-tenant)
- connections      // Conexões WhatsApp
- campaigns        // Campanhas ativas
- notifications    // Notificações em tempo real
```

### Socket.IO Events (Tempo Real)
```javascript
// Eventos presumidos baseados na estrutura
- ticket:update    // Atualização de ticket
- message:new      // Nova mensagem
- user:online      // Status online
- notification:new // Nova notificação
- connection:status // Status conexão WhatsApp
```

## Testes e Qualidade

### Configuração de Testes
- **Framework**: React Testing Library + Jest (via react-scripts)
- **Comandos**: `npm test` (modo watch)
- **Coverage**: Não configurado por padrão

### Ferramentas de Qualidade
- **ESLint**: Config "react-app"
- **Browserslist**: Suporte definido para browsers modernos
- **React Scripts**: v3.4.3 (versão estável)

### Debugging
- **React DevTools**: Suporte completo
- **Redux DevTools**: Para React Query
- **Source Maps**: Habilitados em desenvolvimento

## Perguntas Frequentes (FAQ)

### Como adicionar um novo componente?
1. Criar pasta em `src/components/NomeComponente/`
2. Implementar `index.js` com padrões Material-UI
3. Adicionar ao roteamento se necessário
4. Considerar Context API para estado global

### Como funciona o sistema de temas?
- Context API (`ColorModeContext`) gerencia estado
- Preferência salva no localStorage
- Cores personalizadas para cada modo
- Material-UI ThemeProvider aplica globalmente

### Como integrar nova página?
1. Criar componente em `src/pages/`
2. Adicionar rota em router principal  
3. Implementar breadcrumb navigation
4. Considerar permissões de acesso

### Sistema de notificações?
- Socket.IO para tempo real
- React Toastify para UI notifications
- NotificationsPopOver para lista
- Som customizado para novos chats

### Como funciona multi-empresa?
- Context/estado global mantém empresa ativa
- Componentes filtram dados por empresa
- Switching via dropdown/modal de seleção

## Lista de Arquivos Relacionados

### **Estrutura Principal**
```
codigo/frontend/
├── src/
│   ├── App.js                    # Componente raiz
│   ├── index.js                  # Entry point
│   ├── components/               # 100+ componentes especializados
│   │   ├── Dashboard/            # Dashboard components
│   │   ├── Ticket/               # Chat/ticket interface
│   │   ├── MessagesList/         # Lista de mensagens
│   │   ├── ContactDrawer/        # Painel de contato
│   │   ├── CampaignModal/        # Gestão de campanhas
│   │   ├── UserModal/            # Gestão de usuários
│   │   └── WhatsAppModal/        # Configuração WhatsApp
│   ├── pages/                    # Páginas principais
│   ├── context/                  # Context API
│   ├── services/                 # API clients
│   ├── hooks/                    # Custom hooks
│   ├── utils/                    # Utilities
│   └── layout/                   # Layout components
├── public/
│   ├── index.html                # HTML template
│   └── manifest.json            # PWA manifest
├── package.json                  # Dependencies
└── .env.exemple                 # Environment template
```

### **Principais Diretórios para Explorar**
- `src/components/` - Todos os componentes React
- `src/pages/` - Páginas/rotas principais
- `src/context/` - Estado global da aplicação
- `src/services/` - Clientes da API backend
- `src/hooks/` - Custom hooks React

### **Assets & Recursos**
- `src/assets/` - Imagens, sons, planilhas
- `src/assets/logo.png` - Logo da aplicação
- `src/assets/chat_notify.mp3` - Som de notificação
- `src/assets/wa-background.png` - Background WhatsApp

## Change Log (Changelog)

### [6.0.0] - 2025-09-01
#### Adicionado
- Documentação completa do módulo frontend
- Mapeamento de 100+ componentes especializados  
- Sistema de temas light/dark documentado
- Integração Socket.IO para tempo real

#### Técnico
- Stack: React 17 + Material-UI + Socket.IO Client
- State: Context API + React Query  
- Tema: Sistema completo light/dark
- Build: Create React App com configurações legacy