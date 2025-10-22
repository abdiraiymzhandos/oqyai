import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// Импорт нужен для доступа к Android-специфичным классам
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const OqyaiApp());

class OqyaiApp extends StatelessWidget {
  const OqyaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});
  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _c;

  bool _isExternal(String url) {
    final u = Uri.parse(url);
    final host = u.host.toLowerCase();
    final scheme = u.scheme.toLowerCase();
    // Проверяем, что хост не заканчивается на oqyai.kz
    final isOurSite = host.endsWith('oqyai.kz');

    final externalHosts = {
      'wa.me',
      'api.whatsapp.com',
      'instagram.com',
      'www.instagram.com',
      't.me',
      'telegram.me',
      'facebook.com',
      'www.facebook.com',
      'x.com',
      'twitter.com',
      'play.google.com',
      'apps.apple.com',
    };

    // Ссылка считается внешней, если это НЕ наш сайт,
    // или если схема - это мессенджер,
    // или если хост есть в списке внешних.
    return !isOurSite ||
        scheme == 'whatsapp' ||
        scheme == 'instagram' ||
        externalHosts.contains(host);
  }

  // JS-код для исправления ссылок с target="_blank"
  static const _jsFixNewWindow = r'''
    (function() {
      try {
        document.querySelectorAll('a[target="_blank"]').forEach(function(a){
          a.setAttribute('target','_self');
        });
        window.open = function(url){ window.location.href = url; };
      } catch(e) {}
    })();
  ''';

  @override
  void initState() {
    super.initState();
    // Инициализация контроллера происходит асинхронно
    _initController();
  }

  // Запрашиваем разрешение на использование микрофона у пользователя
  Future<void> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('Пользователь отклонил доступ к микрофону');
    }
  }

  // Асинхронный метод для полной настройки контроллера
  Future<void> _initController() async {
    // 1. Создание контроллера
    _c = WebViewController(
      onPermissionRequest: (WebViewPermissionRequest request) {
        // Проверяем, запрашивает ли сайт доступ к микрофону
        final wantsAudio = request.types.contains(WebViewPermissionResourceType.microphone);
        if (wantsAudio) {
          request.grant(); // Даем разрешение
        } else {
          request.deny(); // В остальных случаях - запрещаем
        }
      },
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) async {
            final url = req.url;
            if (_isExternal(url)) {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent; // Запрещаем WebView переходить по внешней ссылке
            }
            return NavigationDecision.navigate; // Разрешаем переход для внутренних ссылок
          },
          onPageFinished: (url) async {
            // Исправляем ссылки после загрузки страницы
            await _c.runJavaScript(_jsFixNewWindow);
          },
        ),
      );

    // 2. Включаем отладку для Android WebView, если это Android
    if (Platform.isAndroid) {
      AndroidWebViewController.enableDebugging(true);
    }

    // 3. Сначала запрашиваем разрешение у пользователя
    await _ensureMicPermission();

    // 4. Только потом загружаем сайт
    await _c.loadRequest(Uri.parse('https://www.oqyai.kz/'));

    // Перерисовываем виджет, если контроллер был инициализирован
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Используем WebViewWidget для отображения
        child: WebViewWidget(controller: _c),
      ),
    );
  }
}
