import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'Flutter bug report'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  Object redrawMarker;

  @override
  void initState() {
    redrawMarker = Object();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        imageCache.clear();
        redrawMarker = Object();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('Press the pressed'),
              Text('And then home button immediately after'),
              RaisedButton(
                child: Text('Trigger async thumbnail creation'),
                onPressed: () => createThumbnail(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/bird.png',
                    width: 120,
                    height: 120,
                  ),
                  FutureBuilder(
                    key: ValueKey(redrawMarker),
                    future: getApplicationDocumentsDirectory(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Text("Loading...");
                      }

                      final directory = snapshot.data as Directory;
                      final thumbnailFile = File("${directory.path}/thumbnails/thumbnail.png");
                      return thumbnailFile.existsSync()
                          ? Image.file(
                              thumbnailFile,
                              width: 120,
                              height: 120,
                              key: ValueKey(redrawMarker),
                            )
                          : Text("Thumbnail does not exist");
                    },
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text('If you press the home button, and do not leave the app, the thumbnail is generated correctly.'),
              SizedBox(height: 16),
              Text('If you press the home button, and leave the app, the thumbnail has the clipped image omitted.'),
            ],
          ),
        ),
      ),
    );
  }

  void createThumbnail() {
    Future.delayed(Duration(seconds: 2)).then((_) async {
      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);

      canvas.drawRect(Rect.fromLTRB(0, 0, 120, 120), Paint()..color = Color.fromRGBO(0, 0, 0, 1));

      final size = 120;
      final imageProvider = Image.asset('assets/bird.png', width: 120, height: 120).image;
      final image = await _resolveImage(imageProvider);
      final clippedImage = await _clipImage(image, size);

      canvas.drawImage(clippedImage, Offset.zero, Paint());

      final thumbnail = await pictureRecorder.endRecording().toImage(size, size);
      await saveImage(thumbnail);
      setState(() {
        imageCache.clear();
        redrawMarker = Object();
      });
    });
  }

  Future<ui.Image> _resolveImage(ImageProvider imageProvider) async {
    final stream = imageProvider.resolve(ImageConfiguration(
      bundle: rootBundle,
      devicePixelRatio: 3.0,
      platform: TargetPlatform.android,
    ));
    final completer = Completer<ui.Image>();
    stream.addListener(ImageStreamListener(
      (imageInfo, _) => completer.complete(imageInfo.image),
      onError: (dynamic exception, StackTrace stackTrace) {
        completer.complete(null);
      },
    ));

    return completer.future;
  }

  Future<ui.Image> _clipImage(ui.Image image, int targetSize) async {
    final shortestDimension = math.min(image.width, image.height);
    final radius = shortestDimension / 2;
    final path = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(radius, radius),
        radius: radius,
      ));

    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    canvas.scale(targetSize / shortestDimension);
    canvas.clipPath(path, doAntiAlias: true);
    canvas.drawImage(image, const Offset(0, 0), Paint()..isAntiAlias = true);

    return pictureRecorder.endRecording().toImage(targetSize, targetSize);
  }

  Future<void> saveImage(ui.Image thumbnail) async {
    final byteData = await thumbnail.toByteData(format: ui.ImageByteFormat.png);

    final String path = (await getApplicationDocumentsDirectory()).path;
    final directory = Directory("$path/thumbnails");
    if (!directory.existsSync()) {
      await directory.create();
    }

    final file = File("$path/thumbnails/thumbnail.png");
    if (file.existsSync()) {
      await file.delete();
    }

    await file.writeAsBytes(byteData.buffer.asUint8List());
  }
}
