import 'package:flutter/material.dart';

import '../components/DownloadsErrorScreen/DownloadErrorList.dart';

class DownloadsErrorScreen extends StatelessWidget {
  const DownloadsErrorScreen({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Download Errors"),
      ),
      body: DownloadErrorList(),
    );
  }
}
