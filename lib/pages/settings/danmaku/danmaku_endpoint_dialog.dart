import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/request/core/danmaku_endpoint.dart';
import 'package:kazumi/services/storage/storage.dart';

Future<void> showDanmakuEndpointDialog(BuildContext context) =>
    KazumiDialog.show<void>(
      context: context,
      builder: (_) => const _EndpointDialog(),
    );

class _EndpointDialog extends StatefulWidget {
  const _EndpointDialog();
  @override
  State<_EndpointDialog> createState() => _EndpointDialogState();
}

class _EndpointDialogState extends State<_EndpointDialog> {
  final form = GlobalKey<FormState>();
  final endpoint = TextEditingController(
    text: GStorage.getSetting(SettingsKeys.danmakuEndpoint),
  );
  final id = TextEditingController(
    text: GStorage.getSetting(SettingsKeys.dandanAppId),
  );
  final secret = TextEditingController(
    text: GStorage.getSetting(SettingsKeys.dandanAppSecret),
  );
  @override
  void dispose() {
    endpoint.dispose();
    id.dispose();
    secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('弹幕接口'),
    content: SizedBox(
      width: 450,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Platform.isWindows
                    ? '留空且未配置凭据时，使用本机多来源弹幕服务。可填写弹弹play兼容接口的根地址。'
                    : '平板需要配置可访问的弹弹play兼容接口，或填写官方 AppId 和 AppSecret。',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: endpoint,
                decoration: const InputDecoration(
                  labelText: '兼容接口根地址（可留空）',
                  hintText: 'https://example.com/你的路径',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  try {
                    DanmakuEndpoint.parse(value);
                    return null;
                  } catch (_) {
                    return '请输入有效的 HTTP(S) 根地址';
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                '使用官方接口需在 dev.dandanplay.com 申请 AppId 和 AppSecret；凭据只发送到官方域名。',
              ),
              TextFormField(
                controller: id,
                decoration: const InputDecoration(labelText: '官方 AppId'),
              ),
              TextFormField(
                controller: secret,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '官方 AppSecret'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => KazumiDialog.dismiss(context: context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () async {
          if (!form.currentState!.validate()) return;
          await GStorage.putSetting(
            SettingsKeys.danmakuEndpoint,
            endpoint.text.trim(),
          );
          await GStorage.putSetting(SettingsKeys.dandanAppId, id.text.trim());
          await GStorage.putSetting(
            SettingsKeys.dandanAppSecret,
            secret.text.trim(),
          );
          if (context.mounted) KazumiDialog.dismiss(context: context);
        },
        child: const Text('保存'),
      ),
    ],
  );
}
