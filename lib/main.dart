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

  // Қалқымалы профиль түймесінің ағымдағы орны
  Offset _fab = Offset.zero;
  bool _fabPosInit = false;

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

  // Профиль бетін ашу (онда аккаунтты жою бар)
  void _openProfile() {
    _c.loadRequest(Uri.parse('https://www.oqyai.kz/profile'));
  }

  // Экран өлшеміне қарай FAB-тың бастапқы орнын бір рет есептеу
  void _ensureFabStartPosition(BuildContext context) {
    if (_fabPosInit) return;
    final size = MediaQuery.of(context).size;
    const fabSize = 56.0;
    const margin = 20.0;
    // Оң жақ төмен
    _fab = Offset(size.width - fabSize - margin, size.height - fabSize - margin - 24);
    _fabPosInit = true;
  }

  // Сүйреп жылжыту
  void _onDragUpdate(DragUpdateDetails d) {
    final size = MediaQuery.of(context).size;
    const fabSize = 56.0;
    const pad = 12.0;

    final nx = (_fab.dx + d.delta.dx).clamp(pad, size.width - fabSize - pad);
    final ny = (_fab.dy + d.delta.dy).clamp(pad, size.height - fabSize - pad);

    setState(() {
      _fab = Offset(nx, ny);
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureFabStartPosition(context);

    return Scaffold(
      body: Stack(
        children: [
          // Негізгі WebView толық экран
          SafeArea(
            child: WebViewWidget(controller: _c),
          ),

          // Қалқымалы профиль иконкасы (WebView-ге кедергі келтірмейді)
          Positioned(
            left: _fab.dx,
            top: _fab.dy,
            child: GestureDetector(
              onPanUpdate: _onDragUpdate,
              child: Material(
                elevation: 6,
                shape: const CircleBorder(),
                color: Colors.white.withOpacity(0.95),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openProfile,
                  child: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Center(
                      child: Icon(Icons.person, size: 26, color: Colors.black87),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
