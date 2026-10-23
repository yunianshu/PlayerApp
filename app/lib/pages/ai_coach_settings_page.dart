import 'package:flutter/material.dart';

import '../services/ai_coach_settings.dart';
import '../services/ai_provider_catalog.dart';
import '../services/ai_training_coach.dart';
import '../widgets/ai_plan_design.dart';
import '../widgets/app_toast.dart';

/// Only the credential is typed. Provider destinations are app-owned constants.
class AiCoachSettingsPage extends StatefulWidget {
  final AiCoachSettingsStore? store;
  final AiCoachTransport transport;
  final AiModelDiscoveryService? discovery;
  const AiCoachSettingsPage({
    super.key,
    this.store,
    this.transport = const HttpAiCoachTransport(),
    this.discovery,
  });

  @override
  State<AiCoachSettingsPage> createState() => _AiCoachSettingsPageState();
}

class _AiCoachSettingsPageState extends State<AiCoachSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController();
  AiCoachSettings? _saved;
  AiProvider? _provider;
  bool _legacy = false;
  String _mode = 'standard';
  List<String> _models = [];
  String? _model;
  String? _modelSource;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  bool _obscure = true;
  bool _persistKey = true;
  String? _status;

  AiCoachSettingsStore get _store =>
      widget.store ?? AiCoachSettingsStore.instance;
  String? get _endpoint =>
      _legacy ? _saved?.config?.endpoint : _provider?.chatEndpoint;
  bool get _eligible =>
      _legacy ||
      (_provider != null &&
          (_mode == 'standard' || _provider!.supportsTokenPlan));
  bool get _canReuseKey =>
      _saved?.apiKey != null &&
      _saved?.config?.endpoint == _endpoint &&
      _saved?.config?.accessMode == _mode &&
      (_legacy || (_saved?.config?.providerId == _provider?.id));
  String? get _credential => _key.text.trim().isNotEmpty
      ? _key.text.trim()
      : _canReuseKey
      ? _saved?.apiKey
      : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final saved = await _store.load();
      if (!mounted) return;
      final id = saved.config?.providerId;
      final known = id == null ? null : AiProviderCatalog.byId(id);
      final provider = known?.chatEndpoint == saved.config?.endpoint
          ? known
          : null;
      setState(() {
        _saved = saved;
        // Old/custom records stay intact. Never guess a provider or move its key.
        _legacy = saved.config != null && provider == null;
        _provider = provider;
        _mode = saved.config?.accessMode ?? 'standard';
        _model = saved.config?.model;
        _models = _model == null ? [] : [_model!];
        _modelSource = _model == null ? null : '当前已保存模型 · 尚未重新获取';
        _key.clear();
        _persistKey = saved.secureStorageAvailable && !saved.sessionOnly;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  void _chooseProvider(String? id) {
    if (_busy) return;
    setState(() {
      _legacy = id == 'legacy';
      _provider = _legacy || id == null ? null : AiProviderCatalog.byId(id);
      _mode = _legacy ? _saved!.config!.accessMode : 'standard';
      _key.clear();
      _obscure = true;
      _model = _legacy ? _saved!.config!.model : null;
      _models = _model == null ? [] : [_model!];
      _modelSource = _legacy ? '保留原有配置，不自动迁移' : null;
      _status = null;
    });
  }

  void _chooseMode(String? mode) {
    if (_busy || mode == null || mode == _mode) return;
    setState(() {
      _mode = mode;
      _key.clear();
      _model = null;
      _models = [];
      _modelSource = null;
      _status = null;
    });
  }

  bool _validateKey() {
    if (!_eligible) {
      setState(() => _status = '请先选择可用于训练分析的平台与接入类型');
      return false;
    }
    return _form.currentState?.validate() ?? false;
  }

  (AiCoachConfig, String)? _input() {
    if (!_validateKey()) return null;
    if (_model == null) {
      setState(() => _status = '请先获取并选择模型');
      return null;
    }
    return (
      AiCoachConfig(
        endpoint: _endpoint!,
        model: _model!,
        providerId: _legacy ? _saved!.config!.providerId : _provider!.id,
        accessMode: _mode,
      ),
      _credential!,
    );
  }

  // Another screen may have replaced or cleared the configuration meanwhile.
  Future<bool> _unchanged() async {
    final current = await _store.load();
    final a = current.config;
    final b = _saved?.config;
    final unchanged =
        a?.endpoint == b?.endpoint &&
        a?.model == b?.model &&
        a?.providerId == b?.providerId &&
        a?.accessMode == b?.accessMode &&
        current.apiKey == _saved?.apiKey;
    if (!unchanged && mounted) {
      setState(() => _status = 'AI 设置已在其他页面变更，请重新读取后再操作');
    }
    return unchanged;
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => Theme(
          data: PlanDesign.theme(context),
          child: AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(text)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(action),
              ),
            ],
          ),
        ),
      ) ==
      true;

  Future<void> _fetchModels() async {
    if (_busy || !_validateKey() || _provider == null) return;
    final provider = _provider!;
    final credential = _credential!;
    if (provider.modelsEndpoint != null) {
      final approved = await _confirm(
        '向平台获取模型？',
        '${provider.label} · ${_mode == 'tokenPlan' ? 'Token Plan / M Plan' : '标准 API'}\n'
            '目标：${provider.modelsEndpoint}\n\n'
            '将向以上官方地址发送 API Key 获取模型列表。密钥泄露可能导致额度被他人使用，请确认平台无误。'
            '不发送训练记录、健康信息或测试对话，也不会自动保存设置。',
        '同意并获取',
      );
      if (!approved || !mounted) return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      if (!await _unchanged() || !mounted) return;
      final result = await (widget.discovery ?? AiModelDiscoveryService())
          .discover(
            providerId: provider.id,
            apiKey: credential,
            accessMode: _mode,
          );
      if (!mounted || !await _unchanged() || !mounted) return;
      setState(() {
        _models = result.models;
        if (!_models.contains(_model)) _model = null;
        _modelSource = result.live
            ? '平台返回的模型列表 · 不代表全部具有调用权限'
            : '官方预置模型 · 未在线验证密钥或权限';
        _status = result.note;
      });
    } on AiModelDiscoveryException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) setState(() => _status = '获取模型失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final input = _input();
    if (input == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      if (!await _unchanged() || !mounted) return;
      await _store.save(
        config: input.$1,
        apiKey: input.$2,
        persistKey: _persistKey,
      );
      final saved = await _store.load();
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _key.clear();
        _obscure = true;
        _status = _persistKey
            ? '设置已保存，API Key 已安全存储'
            : '设置已保存，API Key 仅在本次运行中可用';
      });
      showAppToast(context, _status!);
    } on AiSettingsException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) setState(() => _status = '设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (_busy) return;
    final input = _input();
    if (input == null) return;
    final approved = await _confirm(
      '测试模型连接',
      '目标地址：${input.$1.endpoint}\n模型：${input.$1.model}\n\n'
          '将发送 API Key 和一句固定测试文本，不发送跑步记录、恢复评分或 GPS。'
          '密钥泄露可能导致额度被他人使用。服务商可能收取少量调用费用，Token Plan 可能消耗套餐额度。测试不会保存设置。',
      '发送测试',
    );
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _status = '正在测试连接…';
    });
    try {
      if (!await _unchanged() || !mounted) return;
      await AiTrainingCoach.testConnection(
        endpoint: input.$1.uri,
        apiKey: input.$2,
        model: input.$1.model,
        transport: widget.transport,
      );
      if (!mounted || !await _unchanged() || !mounted) return;
      setState(() => _status = '连接成功。若修改了设置，请记得保存。');
    } on AiCoachException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) setState(() => _status = '连接测试失败，请检查网络和服务设置');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    if (!await _confirm(
          '清除 AI 设置？',
          '将删除本机保存的服务地址、模型和 API Key。不会删除训练记录。',
          '确认清除',
        ) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await _unchanged() || !mounted) return;
      await _store.clear();
      if (!mounted) return;
      await _load();
      if (mounted) setState(() => _status = 'AI 设置和密钥已清除');
    } on AiSettingsException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) setState(() => _status = '清除失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _step(String number, String title, Widget child) {
    final p = PlanDesign.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: p.textMuted,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: child,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PlanDesign.theme(context),
    child: Builder(
      builder: (context) {
        final p = PlanDesign.of(context).palette;
        final legacyAvailable =
            _saved?.config != null && _saved!.config!.providerId == null;
        return Scaffold(
          appBar: AppBar(title: const Text('AI 服务设置')),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadFailed
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: const Text('读取设置失败，点击重试'),
                  ),
                )
              : SafeArea(
                  top: false,
                  child: Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        Text(
                          '连接你的训练助手',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '只需输入一项密钥，其余交给选择。\n保存不会联网，分析前仍会征求你的同意。',
                          style: TextStyle(color: p.textSecondary, height: 1.6),
                        ),
                        const SizedBox(height: 28),
                        _step(
                          '01',
                          '选择国内平台',
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'ai-provider-${_legacy ? 'legacy' : _provider?.id}',
                            ),
                            initialValue: _legacy ? 'legacy' : _provider?.id,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'AI 平台',
                            ),
                            hint: const Text('选择服务商'),
                            items: [
                              if (legacyAvailable || _legacy)
                                const DropdownMenuItem(
                                  value: 'legacy',
                                  child: Text('原有自定义配置'),
                                ),
                              for (final provider
                                  in AiProviderCatalog.providers)
                                DropdownMenuItem(
                                  value: provider.id,
                                  child: Text(
                                    provider.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy ? null : _chooseProvider,
                          ),
                        ),
                        if (_legacy) ...[
                          Text(
                            '原有自定义配置已保留',
                            style: TextStyle(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_saved!.config!.endpoint}\n模型：${_saved!.config!.model}\n地址与模型只读。选择国内平台后，原配置仅在你保存时替换。',
                            style: TextStyle(
                              color: p.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ] else if (_provider != null) ...[
                          _step(
                            '02',
                            '选择接入类型',
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'ai-mode-${_provider!.id}-$_mode',
                                  ),
                                  initialValue: _mode,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: '接入类型',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'standard',
                                      child: Text('标准 API · 按量计费'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'tokenPlan',
                                      child: Text('Token Plan / 订阅套餐'),
                                    ),
                                  ],
                                  onChanged: _busy ? null : _chooseMode,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _mode == 'tokenPlan'
                                      ? _provider!.tokenPlanNote
                                      : '使用该平台标准 API Key；网页会员与 API 额度通常不通用。',
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                                if (_mode == 'tokenPlan' &&
                                    !_provider!.supportsTokenPlan) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '此接入类型暂不可用于训练助手，请选择标准 API。',
                                    style: TextStyle(color: p.danger),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (_eligible) ...[
                          _step(
                            '03',
                            '输入 API Key',
                            TextFormField(
                              key: const Key('ai-key'),
                              controller: _key,
                              enabled: !_busy,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              enableIMEPersonalizedLearning: false,
                              decoration: InputDecoration(
                                labelText: 'API Key',
                                hintText: _canReuseKey
                                    ? '已配置，留空保留现有密钥'
                                    : '输入当前平台与接入类型的密钥',
                                helperText: '已保存的密钥不会回填。切换平台或接入类型会清空输入。',
                                helperMaxLines: 3,
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? '显示输入的密钥' : '隐藏输入的密钥',
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  (value ?? '').trim().isEmpty && _canReuseKey
                                  ? null
                                  : AiCoachConfig.keyError(value ?? ''),
                              onChanged: (_) => setState(() {
                                // An account change invalidates its model availability list.
                                if (!_legacy) {
                                  _models = [];
                                  _model = null;
                                  _modelSource = null;
                                }
                                _status = null;
                              }),
                            ),
                          ),
                          if (!_legacy)
                            _step(
                              '04',
                              '获取并选择模型',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _fetchModels,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: Text(
                                      _provider!.modelsEndpoint == null
                                          ? '查看官方预置模型'
                                          : '获取模型',
                                    ),
                                  ),
                                  if (_provider!.modelsEndpoint == null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        '当前简化接入不支持在线模型列表，使用官方预置选项，不会发送密钥。',
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  if (_models.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'ai-model-${_provider!.id}-${_models.join(',')}-$_model',
                                      ),
                                      initialValue: _model,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: '模型',
                                      ),
                                      hint: const Text('选择一个模型'),
                                      items: [
                                        for (final model in _models)
                                          DropdownMenuItem(
                                            value: model,
                                            child: Text(
                                              model,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: _busy
                                          ? null
                                          : (value) =>
                                                setState(() => _model = value),
                                    ),
                                  ],
                                  if (_modelSource != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        _modelSource!,
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('在本机安全保存 API Key'),
                            subtitle: Text(
                              _persistKey
                                  ? '由系统安全存储保护，不加入应用 JSON 备份'
                                  : '仅本次运行使用，退出应用后需重新输入',
                            ),
                            value: _persistKey,
                            onChanged:
                                _busy ||
                                    !(_saved?.secureStorageAvailable ?? false)
                                ? null
                                : (value) =>
                                      setState(() => _persistKey = value),
                          ),
                          if (!(_saved?.secureStorageAvailable ?? false))
                            const Text('当前安全存储不可用。不会明文保存密钥，可仅本次使用。'),
                        ],
                        if (_status != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _status!,
                                style: TextStyle(
                                  color: p.textPrimary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        if (_busy) const LinearProgressIndicator(),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy || !_eligible ? null : _save,
                          icon: const Icon(Icons.check_rounded),
                          label: Text(_persistKey ? '保存设置' : '保存（密钥仅本次）'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || !_eligible ? null : _test,
                          icon: const Icon(Icons.wifi_tethering),
                          label: const Text('测试连接'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _load,
                          child: const Text('重新读取已保存设置'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _clear,
                          child: const Text('清除设置和密钥'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    ),
  );
}
