import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TlsIdentity {
  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;

  const TlsIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  SecurityContext createServerContext() {
    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(utf8.encode(certificatePem));
    context.usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return context;
  }

  SecurityContext createClientContext() {
    final context = SecurityContext(withTrustedRoots: true);
    context.useCertificateChainBytes(utf8.encode(certificatePem));
    context.usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return context;
  }
}

class TlsIdentityStore {
  static const _certKey = 'tls_certificate_pem_v1';
  static const _privateKey = 'tls_private_key_pem_v1';

  final FlutterSecureStorage _storage;

  const TlsIdentityStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  Future<TlsIdentity> loadOrCreate() async {
    final certificate = await _storage.read(key: _certKey);
    final privateKey = await _storage.read(key: _privateKey);

    if (certificate != null &&
        certificate.contains('BEGIN CERTIFICATE') &&
        privateKey != null &&
        privateKey.contains('PRIVATE KEY')) {
      return TlsIdentity(
        certificatePem: certificate,
        privateKeyPem: privateKey,
        fingerprint: fingerprintFromPem(certificate),
      );
    }

    return _create();
  }

  Future<TlsIdentity> _create() async {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;

    final csr = X509Utils.generateRsaCsrPem(
      const {
        'CN': 'Befrest Device',
        'O': 'Befrest',
        'OU': 'Local Transfer',
      },
      privateKey,
      publicKey,
      san: const ['befrest.local', 'localhost'],
    );

    final serial = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      3650,
      sans: const ['befrest.local', 'localhost'],
      serialNumber: serial,
    );

    final privatePem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);

    await _storage.write(key: _certKey, value: certificate);
    await _storage.write(key: _privateKey, value: privatePem);

    return TlsIdentity(
      certificatePem: certificate,
      privateKeyPem: privatePem,
      fingerprint: fingerprintFromPem(certificate),
    );
  }

  static String fingerprintFromPem(String certificatePem) {
    final Uint8List der = CryptoUtils.getBytesFromPEMString(certificatePem);
    return sha256.convert(der).toString().toUpperCase();
  }

  static String fingerprintFromCertificate(X509Certificate certificate) {
    return sha256.convert(certificate.der).toString().toUpperCase();
  }
}
