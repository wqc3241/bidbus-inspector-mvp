// A web page shown inside the app (the Carfax report), not in the phone's browser.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'ui.dart';

Future<void> openWebPage(BuildContext context, String title, String? url) async {
  final u = Uri.tryParse(url ?? '');
  if (u == null || !u.hasScheme) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (c) => WebPage(title, u)));
}

class WebPage extends StatefulWidget {
  final String title;
  final Uri url;
  const WebPage(this.title, this.url, {super.key});
  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  int progress = 0;
  late final c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(onProgress: (p) {
      if (mounted) setState(() => progress = p);
    }))
    ..loadRequest(widget.url);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: TitleBar(widget.title),
        body: Column(children: [
          if (progress < 100) LinearProgressIndicator(value: progress / 100, minHeight: 2, color: bid, backgroundColor: alt),
          Expanded(child: WebViewWidget(controller: c)),
        ]),
      );
}
