# Backend - API Whaticket

[Diretório Raiz](../../CLAUDE.md) > [codigo](../) > **backend**

## Change Log (Changelog)

### 2025-09-01 19:03:42 - Inicialização do Contexto Backend
- Mapeado módulo backend TypeScript/Express
- Identificadas 40+ controllers para gestão completa do sistema
- Documentado sistema de migrations extensivo (85+ migrações)
- Configurado ambiente de testes com Jest

## Responsabilidades do Módulo

O backend é uma **API REST robusta** construída em **TypeScript + Express** que centraliza toda a lógica de negócio do sistema Whaticket:

- **🔌 Integração WhatsApp**: Conexão direta via @whiskeysockets/baileys
- **🎫 Sistema de Tickets**: Gestão completa do ciclo de atendimento
- **🏢 Multi-Empresa**: Suporte a múltiplos clientes/empresas
- **👥 Gestão de Usuários**: Autenticação, perfis e permissões
- **📊 Campanhas**: Sistema de envio em massa e campanhas programadas
- **⚡ Tempo Real**: Comunicação via Socket.IO
- **💳 Pagamentos**: Integração com Gateway Gerencianet
- **📈 Analytics**: Dashboard e métricas de atendimento

## Entrada e Inicialização

### Pontos de Entrada
- **`src/app.ts`**: Configuração principal da aplicação Express
- **`src/bootstrap.ts`**: Carregamento de variáveis de ambiente
- **`src/server.ts`**: Inicialização do servidor HTTP e Socket.IO

### Inicialização
```typescript
// Sequência de boot
bootstrap.ts → app.ts → database/index.ts → routes → server.ts
```

### Scripts Disponíveis
```bash
npm run dev:server    # Desenvolvimento com hot reload
npm run build         # Build TypeScript
npm run start         # Produção (requer build)
npm run db:migrate    # Executar migrações
npm run db:seed       # Popular dados iniciais
npm test              # Executar testes
```

## Interfaces Externas

### Controllers Principais

#### **Gestão de Atendimento**
- `TicketController.ts` - CRUD de tickets, transferências, status
- `MessageController.ts` - Envio/recebimento de mensagens
- `ContactController.ts` - Gestão de contatos
- `QueueController.ts` - Filas de atendimento
- `UserController.ts` - Gestão de usuários/atendentes

#### **WhatsApp & Comunicação**
- `WhatsAppController.ts` - Gerenciamento de conexões
- `WhatsAppSessionController.ts` - Sessões e QR codes
- `SessionController.ts` - Autenticação de usuários

#### **Campanhas & Marketing**
- `CampaignController.ts` - Campanhas de envio
- `ContactListController.ts` - Listas de contatos
- `QuickMessageController.ts` - Respostas rápidas

#### **Empresas & Planos**
- `CompanyController.ts` - Gestão multi-empresa
- `PlanController.ts` - Planos de assinatura
- `SubscriptionController.ts` - Controle de assinaturas
- `InvoicesController.ts` - Faturamento

#### **Configurações & Sistema**
- `SettingController.ts` - Configurações globais
- `DashbardController.ts` - Métricas e analytics
- `FilesController.ts` - Upload e gestão de arquivos

### API Endpoints Pattern
```typescript
// Padrão de rotas seguido
/api/users          # CRUD usuários
/api/tickets        # CRUD tickets  
/api/messages       # CRUD mensagens
/api/whatsapp       # Gestão WhatsApp
/api/companies      # Multi-empresa
/api/campaigns      # Marketing
```

## Principais Dependências e Configuração

### Core Dependencies
```json
{
  "@whiskeysockets/baileys": "github:WhiskeySockets/Baileys", // WhatsApp
  "express": "^4.17.3",                    // Web framework
  "sequelize": "^5.22.3",                  // ORM
  "sequelize-typescript": "^1.1.0",       // TypeScript decorators
  "socket.io": "^4.7.4",                  // WebSocket
  "bull": "^4.8.2",                       // Queue system
  "jsonwebtoken": "^8.5.1",               // JWT auth
  "bcryptjs": "^2.4.3"                    // Password hashing
}
```

### Configurações (`src/config/`)
- **`database.ts`**: Sequelize config (PostgreSQL/MySQL)
- **`auth.ts`**: JWT secrets e configuração
- **`redis.ts`**: Configuração de filas
- **`upload.ts`**: Multer para uploads
- **`Gn.ts`**: Gateway de pagamento Gerencianet

### Variáveis de Ambiente (`.env`)
```env
# Database
DB_HOST=localhost
DB_USER=postgres
DB_PASS=password
DB_NAME=whaticket

# Auth
JWT_SECRET=secret
JWT_REFRESH_SECRET=refresh_secret

# WhatsApp
BROWSER_CLIENT=Whaticket

# Frontend
FRONTEND_URL=http://localhost:3001
```

## Modelos de Dados

### Entidades Principais

#### **Core Business**
```typescript
// Principais modelos identificados no database/index.ts
User          // Usuários/atendentes
Company       // Multi-empresa
Ticket        // Tickets de atendimento
Message       // Mensagens dos tickets
Contact       // Contatos/clientes
Whatsapp      // Conexões WhatsApp
Queue         // Filas de atendimento
```

#### **Campanhas & Marketing**
```typescript
Campaign          // Campanhas
CampaignSetting   // Configurações de campanha
ContactList       // Listas de contatos
ContactListItem   // Itens das listas
CampaignShipping  // Envios de campanha
```

#### **Sistema & Config**
```typescript
Setting       // Configurações do sistema
Plan          // Planos de assinatura
Subscription  // Assinaturas ativas
Invoice       // Faturamento
TicketNote    // Notas internas dos tickets
```

### Migrations
- **85+ arquivos** de migração desde julho/2020
- Evolução incremental: Users → Contacts → Tickets → Messages → WhatsApp
- Features avançadas: Campanhas, Multi-empresa, Pagamentos
- Todas com timestamps para versionamento

## Testes e Qualidade

### Configuração Jest (`jest.config.js`)
- **Framework**: Jest + ts-jest para TypeScript
- **Coverage**: Coletado de `src/services/**/*.ts`
- **Pattern**: Testes em `__tests__/**/*.spec.ts`
- **Environment**: Node.js
- **Pre/Post**: Setup e teardown de database

### Comando de Testes
```bash
npm run pretest   # Migrate + seed test DB
npm test          # Executar testes
npm run posttest  # Limpar test DB
```

### Quality Tools
- **ESLint**: Airbnb config + TypeScript
- **Prettier**: Formatação de código
- **TypeScript**: Type checking
- **Sentry**: Error tracking em produção

## Perguntas Frequentes (FAQ)

### Como adicionar um novo controller?
1. Criar arquivo em `src/controllers/NomeController.ts`
2. Implementar métodos CRUD seguindo padrão existente
3. Adicionar rotas em `src/routes/`
4. Considerar eventos Socket.IO se necessário

### Como funciona o sistema multi-empresa?
- Campo `companyId` em todos os models principais
- Middleware de autenticação injeta `companyId` no request
- Queries sempre filtradas por empresa ativa

### Como integrar nova funcionalidade WhatsApp?
- Usar instância Baileys via `src/services/WbotServices/`
- Eventos capturados e processados via Socket.IO
- Messages persistidas com `companyId` e `whatsappId`

### Sistema de filas (Queue)?
- Bull + Redis para processamento assíncrono  
- `src/queues/` para jobs de background
- Usado para envio de campanhas e mensagens em massa

## Lista de Arquivos Relacionados

### **Estrutura Principal**
```
codigo/backend/
├── src/
│   ├── app.ts                    # App Express principal
│   ├── bootstrap.ts              # Environment setup
│   ├── @types/                   # Type definitions
│   ├── config/                   # Configurações
│   ├── controllers/              # 40+ controllers API
│   ├── database/                 # Models + 85+ migrations
│   ├── models/                   # Sequelize models
│   ├── services/                 # Business logic
│   ├── helpers/                  # Utilities
│   ├── middleware/               # Express middleware
│   ├── routes/                   # API routes
│   └── queues/                   # Background jobs
├── jest.config.js                # Test configuration
├── package.json                  # Dependencies
└── tsconfig.json                # TypeScript config
```

### **Principais Diretórios para Explorar**
- `src/controllers/` - Todos os endpoints da API
- `src/database/migrations/` - Histórico completo do schema
- `src/models/` - Definições das entidades
- `src/services/` - Lógica de negócio centralizada
- `src/config/` - Todas as configurações do sistema

## Change Log (Changelog)

### [6.0.0] - 2025-09-01
#### Adicionado
- Documentação completa do módulo backend
- Mapeamento de 40+ controllers
- Identificação de 85+ migrations
- Sistema de testes Jest configurado

#### Técnico  
- Stack: Node.js + TypeScript + Express + Sequelize
- Integração: WhatsApp via Baileys, pagamentos via Gerencianet
- Arquitetura: MVC com Socket.IO para tempo real
- Database: PostgreSQL/MySQL com sistema robusto de migrations