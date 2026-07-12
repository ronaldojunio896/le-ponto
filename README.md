# Le Ponto

Aplicativo Flutter Android para controle de ponto da loja Le Racoes.

Este projeto esta configurado para funcionar no Firebase Spark/free, sem Cloud
Functions. O servidor usado pelo app e o proprio Firebase:

- Firebase Authentication para login por e-mail e senha.
- Cloud Firestore para usuarios, loja, pontos, logs e relatorios.
- Regras do Firestore para separar funcionario e admin.

## O que ja esta implementado

- Primeiro acesso cria o usuario admin pelo app.
- Login por e-mail e senha.
- Perfis de funcionario e admin.
- Cadastro de funcionarios pelo admin.
- Registro de Entrada, Saida para almoco, Volta do almoco e Saida final.
- Validacao local da sequencia de pontos do dia.
- GPS com cerca virtual da loja.
- Bloqueio local de ponto fora do raio sem justificativa.
- Registro de horario com `FieldValue.serverTimestamp()` no Firestore.
- Historico diario e semanal do funcionario.
- Visao administrativa dos pontos.
- Edicao de ponto pelo admin com justificativa e log.
- Aprovacao de horas extras.
- Relatorio semanal com horas normais, extras, atrasos, saidas antecipadas e valor a pagar.
- Exportacao PDF e Excel.

## Projeto Firebase

Projeto configurado:

```text
le-ponto-junio896
```

Arquivos locais gerados:

- `.firebaserc`
- `android/app/google-services.json`
- `lib/firebase_options.dart`

O arquivo `android/app/google-services.json` fica ignorado no Git.

## Configuracao necessaria

1. No Firebase Console, deixe ativado:
   - Authentication com e-mail/senha.
   - Cloud Firestore.

2. Publique regras do Firestore:

```bash
firebase deploy --only firestore:rules --project le-ponto-junio896
```

3. Instale dependencias Flutter:

```bash
flutter pub get
```

4. Abra o app. Se ainda nao existir admin, a tela inicial vai pedir nome, e-mail e senha para criar o primeiro admin.

5. Entre como admin, va em Funcionarios e cadastre:
   - funcionarios normais;
   - gerente/admin;
   - patrao/admin, se ele tambem vai acompanhar os pontos pelo app.

6. Va em Loja e revise latitude, longitude e raio da loja.

Loja inicial ja cadastrada no Firestore:

```text
stores/le-racoes-sao-gabriel
```

## Observacoes do modo gratis

- PIN foi removido porque PIN seguro exigiria backend/Cloud Functions.
- A validacao de GPS e feita no app e registrada no Firestore. Para poucos funcionarios conhecidos, isso e suficiente para comecar.
- O horario salvo usa timestamp do servidor do Firestore.
- O app depende de internet para bater ponto.
- O plano Spark/free tem cotas de uso. Para 3 funcionarios, deve ser mais que suficiente.

## Gerar APK

Com Flutter configurado:

```bash
flutter build apk --release
```

O APK sera gerado em:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Antes de distribuir em definitivo, configure uma chave de assinatura release.
