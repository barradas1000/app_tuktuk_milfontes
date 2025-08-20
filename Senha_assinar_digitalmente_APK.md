# Informações de Assinatura Digital do APK

- Arquivo de keystore: `upload-keystore.jks`
- Local: `C:\Users\LENOVO YOGA 500\upload-keystore.jks`
- Alias: `upload`
- Senha do keystore: Senha2025!
- Algoritmo: RSA
- Tamanho da chave: 2048 bits
- Validade: 10.000 dias

## Guarde este arquivo e senha em local seguro. Não compartilhe publicamente.

## Novo keystore gerado (20/08/2025)

- Arquivo de keystore: `upload-keystore.jks`
- Local: `android/app/upload-keystore.jks`
- Alias: `upload`
- Senha do keystore: `Tuktuk2025!`
- Tipo: JKS
- Algoritmo: RSA 2048
- Validade: 10.000 dias

**Este keystore deve ser configurado no build.gradle/app para builds de release.**

---

## Processo completo de geração do keystore (20/08/2025)

### Comando executado:

```powershell
keytool -genkeypair -v -keystore "C:\codigo\TukTuk-VERCEL\TukTuk-Oficiar-VERCEL- para desenvolvimento\tuktuk_gps_tracker\app_gps\tuktuk_gps_tracker\android\app\upload-keystore.jks" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### Passos e respostas:

1. **Senha do keystore:**
   - Digite: `Tuktuk2025!`
   - Confirme a senha.
2. **Distinguished Name (DN):**
   - CN (Nome): `Tuktuk2025!`
   - OU (Unidade organizacional): `Tuktuk2025!`
   - O (Organização): `cb`
   - L (Cidade): `Vila Nova de Milfontes`
   - ST (Estado): `Beja`
   - C (País): `Portugal`
   - Confirme os dados digitando `yes`.
3. **Senha da chave (key password):**
   - Pressione ENTER para usar a mesma senha do keystore.
   - Confirme a senha.

### Resultado:

- Arquivo gerado: `android/app/upload-keystore.jks`
- Algoritmo: RSA 2048
- Validade: 10.000 dias
- Alias: `upload`
- Senha: `Tuktuk2025!`
- DN: CN=Tuktuk2025!, OU=Tuktuk2025!, O=cb, L=Vila Nova de Milfontes, ST=Beja, C=Portugal

### Observação importante:

O formato JKS é proprietário. Recomenda-se migrar para PKCS12, que é padrão da indústria, usando:

```powershell
keytool -importkeystore -srckeystore android/app/upload-keystore.jks -destkeystore android/app/upload-keystore.jks -deststoretype pkcs12
```

---
