import 'package:flutter/material.dart';

import '../services/ai_coach_settings.dart';
import '../services/ai_training_coach.dart';
import '../widgets/app_toast.dart';

/// One management entry shared by Profile and the marathon coach.
class AiCoachSettingsPage extends StatefulWidget {
  final AiCoachSettingsStore? store;
  final AiCoachTransport transport;
  const AiCoachSettingsPage({
    super.key,
    this.store,
    this.transport = const HttpAiCoachTransport(),
  });

  @override
  State<AiCoachSettingsPage> createState() => _AiCoachSettingsPageState();
}

class _AiCoachSettingsPageState extends State<AiCoachSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  AiCoachSettings? _saved;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  bool _obscure = true;
  bool _persistKey = true;
  String? _status;

  AiCoachSettingsStore get _store =>
      widget.store ?? AiCoachSettingsStore.instance;
  bool get _canReuseKey =>
      _saved?.apiKey != null &&
      _saved?.config?.endpoint == _endpoint.text.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
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
      setState(() {
        _saved = saved;
        _endpoint.text = saved.config?.endpoint ?? '';
        _model.text = saved.config?.model ?? '';
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

  (AiCoachConfig, String)? _input() {
    if (!_form.currentState!.validate()) return null;
    return (
      AiCoachConfig(endpoint: _endpoint.text.trim(), model: _model.text.trim()),
      _key.text.trim().isNotEmpty ? _key.text.trim() : _saved!.apiKey!,
    );
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
      if (mounted) showAppToast(context, error.message);
    } catch (_) {
      if (mounted) showAppToast(context, '设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (_busy) return;
    final input = _input();
    if (input == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('测试模型连接'),
        content: SingleChildScrollView(
          child: Text(
            '目标地址：${input.$1.endpoint}\n模型：${input.$1.model}\n\n'
            '将发送 API Key 和一句固定测试文本，不发送跑步记录、恢复评分或 GPS。'
            '服务商可能收取少量调用费用。测试不会保存设置。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('发送测试'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _busy = true;
      _status = '正在测试连接…';
    });
    try {
      await AiTrainingCoach.testConnection(
        endpoint: input.$1.uri,
        apiKey: input.$2,
        model: input.$1.model,
        transport: widget.transport,
      );
      if (!mounted) return;
      setState(() => _status = '连接成功，模型已返回有效响应。若修改了设置，请记得保存。');
      showAppToast(context, '连接测试成功');
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
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除 AI 设置？'),
        content: const Text('将删除本机保存的服务地址、模型和 API Key。不会删除训练记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _store.clear();
      if (!mounted) return;
      _key.clear();
      await _load();
      if (mounted) setState(() => _status = 'AI 设置和密钥已清除');
    } on AiSettingsException catch (error) {
      if (mounted) showAppToast(context, error.message);
    } catch (_) {
      if (mounted) showAppToast(context, '清除失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    '服务类型：兼容 OpenAI 的 Chat Completions API',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text('填写你选择的服务商或自建网关。保存不会联网；只有确认测试或分析时才发送请求。'),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('ai-endpoint'),
                    controller: _endpoint,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '完整 HTTPS API 地址',
                      hintText: 'https://你的服务域名/v1/chat/completions',
                      helperText: '填写完整请求地址，不是网站首页或仅 /v1',
                      helperMaxLines: 2,
                    ),
                    validator: (value) =>
                        AiCoachConfig.endpointError(value ?? ''),
                    onChanged: (_) => setState(() => _status = null),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('ai-model'),
                    controller: _model,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      helperText: '按服务商文档填写精确模型 ID',
                    ),
                    validator: (value) => AiCoachConfig.modelError(value ?? ''),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('ai-key'),
                    controller: _key,
                    enabled: !_busy,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: _canReuseKey ? '已配置，留空保留现有密钥' : '输入 API Key',
                      helperText: _saved?.apiKey != null && !_canReuseKey
                          ? '服务地址已改变，请重新输入该服务的密钥'
                          : '已保存的密钥不会回填或显示',
                      helperMaxLines: 2,
                      suffixIcon: IconButton(
                        tooltip: _obscure ? '显示输入的密钥' : '隐藏输入的密钥',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _obscure = !_obscure),
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
                  ),
                  const SizedBox(height: 12),
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
                        _busy || !(_saved?.secureStorageAvailable ?? false)
                        ? null
                        : (value) => setState(() => _persistKey = value),
                  ),
                  if (!(_saved?.secureStorageAvailable ?? false))
                    const Text('当前安全存储不可用。不会明文保存密钥，可仅本次使用；稍后重新进入此页可重试安全存储。'),
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Semantics(liveRegion: true, child: Text(_status!)),
                  ],
                  const SizedBox(height: 20),
                  if (_busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_persistKey ? '保存设置' : '保存（密钥仅本次）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _test,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('测试连接'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _clear,
                    child: const Text('清除设置和密钥'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}
