import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_provider_catalog.dart';

/// Non-secret settings. The credential is deliberately not part of preferences
/// or RunTrail's JSON backup. Only OpenAI-compatible Chat Completions is used.
class AiCoachConfig {
  final String endpoint;
  final String model;
  final String? providerId;
  final String accessMode;
  const AiCoachConfig({
    required this.endpoint,
    required this.model,
    this.providerId,
    this.accessMode = 'standard',
  });

  Uri get uri => Uri.parse(endpoint);

  static String? endpointError(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return '请输入完整的 HTTPS Chat Completions 地址';
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return '地址不能包含账号、查询参数或片段，密钥请单独填写';
    }
    return null;
  }

  static String? modelError(String value) =>
      value.trim().isEmpty ? '请输入服务商提供的模型名称' : null;

  static String? keyError(String value) {
    if (value.trim().isEmpty) return '请输入 API Key';
    if (value.contains('\n') || value.contains('\r')) return 'API Key 不能包含换行';
    return null;
  }

  void validate() {
    final error =
        endpointError(endpoint) ??
        modelError(model) ??
        (const {'standard', 'tokenPlan'}.contains(accessMode)
            ? null
            : '接入类型无效');
    if (error != null) throw AiSettingsException(error);
    final provider = providerId == null
        ? null
        : AiProviderCatalog.byId(providerId!);
    if (providerId != null &&
        (provider == null || provider.chatEndpoint != endpoint)) {
      throw const AiSettingsException('平台与服务地址不匹配，请重新选择平台');
    }
    if (accessMode == 'tokenPlan' &&
        (provider == null ||
            !provider.supportsTokenPlan ||
            !provider.tokenPlanModels.contains(model))) {
      throw const AiSettingsException('该平台、模型或套餐不适用于本应用，请重新选择');
    }
  }
}

class AiSettingsException implements Exception {
  final String message;
  const AiSettingsException(this.message);
  @override
  String toString() => message;
}

abstract class AiCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class PlatformAiCredentialStore implements AiCredentialStore {
  static const _channel = MethodChannel('runtrail/ai_credentials');
  const PlatformAiCredentialStore();

  @override
  Future<String?> read() => _channel.invokeMethod<String>('read');
  @override
  Future<void> write(String value) =>
      _channel.invokeMethod<void>('write', {'apiKey': value});
  @override
  Future<void> delete() => _channel.invokeMethod<void>('delete');
}

class AiCoachSettings {
  final AiCoachConfig? config;
  final String? apiKey;
  final bool secureStorageAvailable;
  final bool sessionOnly;
  const AiCoachSettings({
    required this.config,
    required this.apiKey,
    required this.secureStorageAvailable,
    required this.sessionOnly,
  });
  bool get ready => config != null && apiKey != null && apiKey!.isNotEmpty;
}

class AiCoachSettingsStore {
  static final instance = AiCoachSettingsStore();
  static const preferencesKey = 'ai_coach_settings_v1';
  final AiCredentialStore credentials;
  String? _sessionEnvelope;
  Future<void> _pending = Future<void>.value();

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  AiCoachSettingsStore({this.credentials = const PlatformAiCredentialStore()});

  Future<AiCoachSettings> load() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    AiCoachConfig? config;
    final raw = prefs.getString(preferencesKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        if (data is Map &&
            data['endpoint'] is String &&
            data['model'] is String) {
          final candidate = AiCoachConfig(
            endpoint: data['endpoint'] as String,
            model: data['model'] as String,
            providerId: data['providerId'] is String
                ? data['providerId'] as String
                : null,
            accessMode: data['accessMode'] is String
                ? data['accessMode'] as String
                : 'standard',
          );
          candidate.validate();
          config = candidate;
        }
      } catch (_) {
        // Invalid/restored metadata must not bind a credential to another URL.
      }
    }
    var available = true;
    String? envelope;
    try {
      envelope = await credentials.read();
    } catch (_) {
      available = false;
    }
    final sessionOnly = _sessionEnvelope != null;
    envelope = _sessionEnvelope ?? envelope;
    String? key;
    if (envelope != null && config != null) {
      try {
        final data = jsonDecode(envelope);
        if (data is Map &&
            data['endpoint'] == config.endpoint &&
            (data['accessMode'] ?? 'standard') == config.accessMode &&
            data['providerId'] == config.providerId &&
            data['apiKey'] is String &&
            AiCoachConfig.keyError(data['apiKey'] as String) == null) {
          key = data['apiKey'] as String;
        }
      } catch (_) {
        // Do not expose a corrupt credential or platform exception in logs/UI.
      }
    }
    return AiCoachSettings(
      config: config,
      apiKey: key,
      secureStorageAvailable: available,
      sessionOnly: sessionOnly,
    );
  }

  Future<void> save({
    required AiCoachConfig config,
    required String apiKey,
    required bool persistKey,
  }) => _serialize(
    () => _save(config: config, apiKey: apiKey, persistKey: persistKey),
  );

  Future<void> _save({
    required AiCoachConfig config,
    required String apiKey,
    required bool persistKey,
  }) async {
    config.validate();
    final key = apiKey.trim();
    final error = AiCoachConfig.keyError(key);
    if (error != null) throw AiSettingsException(error);
    final envelope = jsonEncode({
      'endpoint': config.endpoint,
      'providerId': config.providerId,
      'accessMode': config.accessMode,
      'apiKey': key,
    });
    if (persistKey && utf8.encode(envelope).length > 1024) {
      throw const AiSettingsException('地址与密钥超出安全存储的 1024 字节限制');
    }
    if (persistKey) {
      try {
        await credentials.write(envelope);
      } catch (_) {
        throw const AiSettingsException('安全保存失败，未改为明文保存。请重试或选择仅本次使用密钥。');
      }
    } else {
      // Explicit session-only mode must not leave an old key saved on disk.
      try {
        await credentials.delete();
      } on MissingPluginException {
        // This platform has never supplied a persistent secure backend.
      } catch (_) {
        throw const AiSettingsException('未能清除原有安全密钥，请重试后再切换为仅本次使用。');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      preferencesKey,
      jsonEncode({
        'endpoint': config.endpoint,
        'model': config.model,
        'providerId': config.providerId,
        'accessMode': config.accessMode,
      }),
    )) {
      throw const AiSettingsException('设置保存失败，请重试');
    }
    _sessionEnvelope = persistKey ? null : envelope;
  }

  Future<void> clear() => _serialize(_clear);

  Future<void> _clear() async {
    try {
      await credentials.delete();
    } on MissingPluginException {
      // There is no secure backend on this platform to clear.
    } catch (_) {
      throw const AiSettingsException('安全密钥清除失败，请重试');
    }
    _sessionEnvelope = null;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(preferencesKey)) {
      throw const AiSettingsException('密钥已清除，服务设置清除失败，请重试');
    }
  }
}
