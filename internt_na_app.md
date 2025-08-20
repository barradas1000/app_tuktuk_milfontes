# Implementação da Funcionalidade de Troca de Condutor

O processo envolveu duas alterações principais no ficheiro `lib/main.dart`:

1. **Melhorar o Salvamento de Estado:**
   - A função `_saveTrackingState` agora guarda não só se o tracking está ativo, mas também o ID do condutor da sessão.
2. **Nova Lógica de Inicialização:**
   - A lógica de arranque foi substituída por uma nova função, `_initializeSession`, responsável por gerir todos os cenários:
     - Retomar a sessão para o mesmo condutor.
     - Iniciar uma sessão para um novo condutor via deep link.
     - Trocar de condutor: detetar que um novo ID entrou enquanto uma sessão antiga estava ativa, parar a sessão antiga corretamente, e iniciar uma nova sessão limpa para o novo condutor.

### Alterações Aplicadas

1. Modificação da função `_saveTrackingState` para guardar/remover o ID do condutor ativo.
2. Criação da função `_initializeSession` que compara IDs e executa a lógica de troca de sessão.
3. Atualização da função `initState` para chamar `_initializeSession`.

### Resumo do Novo Comportamento

1. **Guardar Sessão:** A aplicação agora guarda não só que o tracking está ativo, mas também o ID do condutor dessa sessão.
2. **Lógica de Início Inteligente:** Ao arrancar, a aplicação executa a nova lógica `_initializeSession` que:
   - Deteta a Troca: Compara o ID do condutor da sessão anterior (se existir) com o ID do novo deep link.
   - Finaliza a Sessão Antiga: Se os IDs forem diferentes, a aplicação primeiro finaliza corretamente a sessão do condutor antigo, enviando o seu estado "inativo" para o Supabase.
   - Inicia a Nova Sessão: De seguida, inicia uma sessão completamente nova e limpa para o novo condutor.

Com esta alteração, a aplicação é agora robusta e consegue lidar corretamente com todos os cenários discutidos, incluindo a troca de condutores no mesmo dispositivo, garantindo a integridade dos dados de cada sessão.

# Encerramento Manual do Tracking e Troca de Condutor

## Fluxo Atual ao Final do Turno

No final do turno, o condutor deve abrir a aplicação e carregar manualmente no botão "Desligar Tracking". Ao fazer isso, a função `_stopTracking` é chamada e executa as seguintes ações:

1. Pára de receber as atualizações de localização do GPS.
2. Encerra completamente o serviço em segundo plano (a notificação persistente desaparece).
3. Envia uma última atualização para o Supabase, informando que o condutor ficou inativo.
4. Guarda localmente o estado "desligado", para que da próxima vez que a aplicação for aberta (seja por deep link ou manualmente), ela não reinicie o tracking automaticamente e espere por uma nova ação do utilizador.

Este passo manual é crucial para finalizar o ciclo de trabalho de forma explícita e correta.

## Cenário de Troca de Condutor

Se o condutor anterior não desligar o tracking e outro condutor abrir a app com seu ID, o fluxo atual é:

1. App abre com novo ID (Condutor B) via deep link.
2. App detecta tracking ativo (isTracking = true) devido à sessão anterior do Condutor A.
3. Tracking é retomado, mas agora usando o ID do novo condutor (Condutor B).
4. Novas coordenadas são enviadas para o Supabase com o novo ID.

### Efeitos Secundários Indesejados

1. O Condutor A nunca é marcado como inativo no Supabase.
2. Dados de sessão (tempo, distância) são misturados entre condutores.
3. O resumo da viagem do Condutor B pode estar incorreto, pois inclui dados da sessão anterior.

## Recomendação de Melhoria

O código atual não está preparado para troca de condutores. Para garantir integridade dos dados, recomenda-se:

1. Guardar também o ID do condutor ativo no SharedPreferences.
2. Ao abrir com novo deep link, comparar o ID novo com o guardado.
3. Se forem diferentes, parar a sessão antiga (executando `_stopTracking` para o condutor anterior) e iniciar uma sessão nova e limpa para o novo condutor.

Esta melhoria pode ser implementada apenas com o plugin shared_preferences e ajustes na lógica do `main.dart`, sem necessidade de novos plugins.

# Estado Atual e Alterações Recentes no Fluxo da App

## O que JÁ ESTÁ PREPARADO no código

1. **Receber o Deep Link:** O ficheiro AndroidManifest.xml (para Android) está configurado com um `<intent-filter>` que permite que a aplicação seja aberta por um link com o esquema `tuktukgps://`.
2. **Extrair Dados do Link:** O GoRouter no código já está a extrair o `cid` (ID do condutor) dos parâmetros do link assim que a aplicação abre.
3. **Continuar em Segundo Plano:** Uma vez que o tracking é iniciado, a aplicação usa o flutter_foreground_task para garantir que o envio de localização continua mesmo que o utilizador mude para outra aplicação.

## O que FALTA no código (A Peça-Chave)

O comportamento atual NÃO iniciava o tracking automaticamente só porque a aplicação foi aberta por um deep link.

O fluxo atual, no caso do deep link, era:

1. Utilizador clica no link no navegador.
2. A aplicação abre no ecrã de tracking.
3. A aplicação ficava à espera que o utilizador carregasse no botão "Ligar Tracking".

Isto acontecia porque a lógica de arranque automático (\_restoreTrackingState) só funcionava se o tracking já estava ativo numa sessão anterior. Não havia nenhuma lógica que dissesse: "Se a app foi aberta por um deep link, comece a rastrear imediatamente".

## Conclusão e Solução

Para que o cenário pretendido funcione, foi adicionada uma pequena peça de lógica. Agora, ao iniciar, o código verifica:

> "Fui aberto por um deep link que continha um ID de condutor? Se sim, e se eu ainda não estiver a rastrear, então devo começar a rastrear imediatamente."

### Modificação Implementada

Foi modificada a função `_restoreTrackingState` para adicionar uma lógica que verifica se a aplicação foi aberta com um ID de condutor (vindo do deep link) e, nesse caso, inicia o processo de tracking, pedindo as permissões necessárias.

**Trecho da alteração:**

```dart
} else if (widget.conductorId.isNotEmpty) {
   // Se não estava a rastrear, mas a app foi aberta por um deep link,
   // inicia o tracking automaticamente.
   _checkAndRequestPermissions();
}
```

### Ordem de Prioridade na Inicialização

1. Primeiro, verifica se o tracking já estava ativo. Se sim, reinicia automaticamente.
2. Se não estava ativo, verifica se a aplicação foi aberta com um ID de condutor (deep link). Se sim, inicia o tracking automaticamente, pedindo as permissões necessárias.
3. Se nenhuma das condições acima for verdadeira, a aplicação simplesmente abre e aguarda que o utilizador carregue no botão manualmente.

Agora, ao clicar no link no navegador, a aplicação deve abrir e começar o processo de envio de localização sem necessidade de qualquer outra interação, exatamente como pretendido.

# Estado Atual do Fluxo da App

O código foi programado para ser dinâmico e decidir qual cenário seguir com base no contexto.

## Funcionamento do Fluxo

1. Sempre que a aplicação arranca, a primeira coisa que o código faz é uma pergunta: "O tracking estava ativo da última vez que a app foi fechada?"
2. Se a resposta for NÃO (porque é a primeira vez que a app corre ou porque o utilizador carregou em "Desligar Tracking"), o código segue o Cenário 1 (Manual). Ele fica à espera que o utilizador carregue no botão para começar.
3. Se a resposta for SIM, o código segue o Cenário 2 (Automático). Ele assume que o utilizador quer continuar o tracking e reinicia o envio de dados sozinho.

Portanto, o código atual já contém a lógica para lidar com as duas situações. É um sistema de "auto-recuperação" para garantir que o tracking não é interrompido acidentalmente se a aplicação for fechada.

# Lógica de Segurança para Salvamento de Dados em Segundo Plano

Para garantir que não se perdem dados de localização quando a app está em segundo plano, foi implementada uma lógica de segurança que envolve três passos:

1. Adicionar um log de erro simples ao MyTaskHandler para depuração.
2. Criar uma nova função `_savePendingPositionInBackground` que pode ser chamada a partir da tarefa em segundo plano para guardar dados no SharedPreferences.
3. Modificar a função `_sendDataToSupabase` da tarefa de segundo plano para usar esta nova função de salvamento sempre que ocorrer um erro de rede ou uma resposta de falha do servidor.

## O Desafio Técnico: Tarefas em Primeiro e Segundo Plano

No Flutter, uma tarefa que corre em segundo plano (como o MyTaskHandler) opera num "Isolate" diferente do da interface do utilizador (UI). Um Isolate é como um processo independente com a sua própria memória. Por causa disso, a tarefa em segundo plano não tem acesso direto às funções e variáveis que existem dentro do estado da UI (a classe `_GpsTrackingScreenState`).

O problema era que a função original para guardar dados (`_savePendingPosition`) estava dentro do estado da UI, tornando-a inacessível para a lógica que corria em segundo plano.

## A Solução Implementada

Para resolver isto, a estratégia foi criar uma lógica de salvamento autónoma e acessível globalmente.

### 1. Criação de uma Função de Salvamento Independente (top-level)

Foi criada uma nova função chamada `_savePendingPositionInBackground` no topo do ficheiro main.dart, fora de qualquer classe. Funções "top-level" são visíveis e podem ser chamadas de qualquer parte do mesmo ficheiro, incluindo de Isolates de segundo plano.

```dart
/// Salva uma posição pendente no SharedPreferences a partir do background.
Future<void> _savePendingPositionInBackground(String payload) async {
   final prefs = await SharedPreferences.getInstance();
   final pending = prefs.getStringList('pendingPositions') ?? [];
   pending.add(payload);
   await prefs.setStringList('pendingPositions', pending);
}
```

- `SharedPreferences`: Permite guardar dados simples de forma persistente no armazenamento local do telemóvel.
- `async / await`: A função é assíncrona porque as operações de leitura e escrita no disco do telemóvel não são instantâneas.

### 2. Integração da Função na Lógica de Rede

A função `_sendDataToSupabase` (a versão top-level usada pela tarefa de segundo plano) foi modificada para usar esta nova capacidade de salvamento em dois cenários de erro:

```dart
Future<void> _sendDataToSupabase(...) async {
   // ... (preparação dos dados) ...
   try {
      final response = await http.patch(...);
      // CENÁRIO 1: Erro de Servidor
      if (response.statusCode < 200 || response.statusCode >= 300) {
         await _savePendingPositionInBackground(payload);
      }
   } catch (e) {
      // CENÁRIO 2: Erro de Rede
      await _savePendingPositionInBackground(payload);
   }
}
```

- Bloco `try-catch`: Lida com exceções de rede (ex: offline).
- Verificação do `response.statusCode`: Salva dados se o servidor responder com erro.

Em resumo, a solução foi desacoplar a lógica de salvamento da UI, tornando-a autónoma e globalmente acessível, e depois integrá-la nos dois pontos principais de falha de uma requisição de rede: a falha da conexão em si e a resposta de erro do servidor.

# Ponto Crítico de Falha: Tratamento de Erros no Foreground Service

Existe mais um ponto importante no código que, embora não impeça o envio de dados quando tudo funciona, pode causar a perda silenciosa de dados em caso de falha, especialmente quando a app está em segundo plano.

## Check-up do Projeto: Ponto Crítico de Falha

A aplicação usa um "Foreground Service" para enviar a localização mesmo quando o ecrã está desligado ou a app está minimizada. A lógica para esta tarefa em segundo plano está separada da lógica da interface principal, e o tratamento de erros nela está incompleto.

### O Problema

No ficheiro `lib/main.dart`, a tarefa em segundo plano (`MyTaskHandler`) chama uma função `_sendDataToSupabase` que tem o seu próprio mecanismo de tratamento de erros comentado. Além disso, o próprio `MyTaskHandler` tem um bloco de captura de erros vazio.

Veja os dois pontos de falha:

1. Tratamento de erro na chamada da função (dentro do `MyTaskHandler`):

   ```dart
   Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
         .then((position) {
            _sendDataToSupabase(position, isActive: true);
         }).catchError((error) {
            // Handle error (ex.: log ou save offline)  <-- ESTE BLOCO ESTÁ VAZIO
         });
   ```

2. Tratamento de erro dentro da própria função `_sendDataToSupabase` (a versão do topo do ficheiro):
   ```dart
   try {
      final response = await http.patch(...);
      // Se necessário, chame a função para salvar posição pendente
      // if (response.statusCode < 200 || response.statusCode >= 300) {
      //   await _savePendingPosition(payload);  <-- ESTA LÓGICA ESTÁ COMENTADA
      // }
   } catch (e) {
      // Se necessário, chame a função para salvar posição pendente
      // await _savePendingPosition(payload);  <-- E ESTA TAMBÉM
   }
   ```

**Consequência:** Se o telemóvel perder a conexão à internet enquanto a app estiver em segundo plano, a tentativa de enviar os dados irá falhar, o erro não será tratado em lado nenhum, e a coordenada GPS daquele momento será perdida para sempre, em vez de ser guardada para sincronização futura.

### Recomendação

É crucial implementar um tratamento de erros robusto para a tarefa em segundo plano, semelhante ao que já existe para a parte da aplicação que corre em primeiro plano. Isto envolve criar uma função que guarda as localizações pendentes e chamá-la dentro dos blocos catch e após verificar uma resposta de falha do servidor.

# Resumo das Correções

URL no ficheiro .env foi corrigido com sucesso.

Concluímos a verificação dos pontos 1 e 2 e resolvemos dois problemas críticos que impediam a sua aplicação de se conectar à internet:

1. Permissão de Internet (Android): Adicionada a permissão em falta no AndroidManifest.xml.
2. URL de Conexão (.env): Corrigido o URL duplicado do Supabase.

# Registro da Edição do .env

Foi identificada e corrigida uma configuração inválida no arquivo `.env`:

**Antes:**

```
SUPABASE_URL=https://https://iweurnqdomiqlohvaoat.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3ZXVybnFkb21pcWxvaHZhb2F0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM0NTU2MzIsImV4cCI6MjA2OTAzMTYzMn0.LdLnL_sluHpIs_7qS3c3nCqNOrT_G0RaS3vhawloQjc
```

**Depois:**

```
SUPABASE_URL=https://iweurnqdomiqlohvaoat.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3ZXVybnFkb21pcWxvaHZhb2F0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM0NTU2MzIsImV4cCI6MjA2OTAzMTYzMn0.LdLnL_sluHpIs_7qS3c3nCqNOrT_G0RaS3vhawloQjc
```

Essa alteração garante que o endpoint do Supabase está correto e acessível pela aplicação.

# Passo Crítico Encontrado e Correções Implementadas

Durante a análise inicial do problema de conexão à internet, foram identificados dois pontos críticos:

1. **Permissão de Internet ausente no AndroidManifest.xml**

   - O ficheiro AndroidManifest.xml não continha a linha:
     ```xml
     <uses-permission android:name="android.permission.INTERNET"/>
     ```
   - Sem esta declaração, o sistema operativo Android bloqueia todas as tentativas de conexão à internet. Esta era, com alta probabilidade, a principal causa do problema no Android.
   - **Correção implementada:** A permissão de internet foi adicionada ao AndroidManifest.xml.

2. **Erro no valor da SUPABASE_URL no ficheiro .env**
   - O valor da SUPABASE_URL estava incorreto:
     ```env
     SUPABASE_URL=https://https://iweurnqdomiqlohvaoat.supabase.co
     ```
   - O protocolo https:// estava duplicado, criando um URL inválido e impedindo a conexão ao Supabase.
   - **Correção implementada:** O valor foi ajustado para:
     ```env
     SUPABASE_URL=https://iweurnqdomiqlohvaoat.supabase.co
     ```

Essas correções são o primeiro passo essencial para restaurar a conectividade da aplicação.

# Plano de Resolução de Conexão de Internet na App Flutter

## Principais Causas para Falha de Conexão

1. **Permissões de Internet no Android/iOS**

   - Android: Verifique se o arquivo `AndroidManifest.xml` contém:
     ```xml
     <uses-permission android:name="android.permission.INTERNET"/>
     ```
   - iOS: Verifique se o arquivo `Info.plist` contém as chaves para acesso à internet (App Transport Security).

2. **Permissão de rede bloqueada pelo dispositivo**

   - Usuário pode ter negado permissões de rede ou o modo avião está ativado.

3. **Configuração incorreta do Supabase**

   - As variáveis `SUPABASE_URL` e `SUPABASE_ANON_KEY` no `.env` podem estar ausentes, incorretas ou não carregadas.

4. **Problemas de rede local**

   - O dispositivo pode estar sem conexão Wi-Fi/dados móveis ou atrás de um firewall.

5. **Erros de código**

   - O código ignora erros silenciosamente em `_sendDataToSupabase`, então falhas de conexão não aparecem para o usuário.
   - O app pode não estar mostrando o erro real de rede.

6. **API Supabase bloqueada ou errada**

   - O endpoint pode estar incorreto, a chave expirada ou o Supabase bloqueando requisições.

7. **Configuração de proxy ou VPN**
   - O dispositivo pode estar usando proxy/VPN que bloqueia o acesso.

---

## Passos para Diagnóstico e Resolução

1. **Verificar conexão do dispositivo**

   - Teste a internet em outros apps ou navegador.

2. **Revisar permissões de internet nos manifestos**

   - Android: `AndroidManifest.xml`
   - iOS: `Info.plist`

3. **Checar variáveis do .env**

   - Confirme que `SUPABASE_URL` e `SUPABASE_ANON_KEY` estão corretas e acessíveis.

4. **Testar endpoint Supabase manualmente**

   - Use navegador ou Postman para testar a URL e chave.

5. **Melhorar tratamento de erros no app**

   - Adicione logs ou mensagens detalhadas para identificar falhas de rede.

6. **Verificar bloqueios de proxy/VPN/firewall**

   - Desative VPN/proxy e teste novamente.

7. **Atualizar dependências e plugins**
   - Certifique-se que todas as dependências estão atualizadas e compatíveis.

---

## Sugestão de Melhorias no Código

- Exibir mensagens de erro detalhadas para o usuário.
- Logar exceções de rede para facilitar diagnóstico.
- Validar carregamento das variáveis do `.env` no início do app.
- Testar a API Supabase separadamente antes de integrar ao app.

---

**Este plano pode ser expandido conforme novos sintomas ou logs forem identificados.**
