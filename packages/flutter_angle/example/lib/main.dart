import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_angle/flutter_angle.dart';
import 'learn_gl.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  final textures = <FlutterGLTexture>[];
  int textureId = -1;
  int textureId2 = -1;
  Lesson? lesson;
  Lesson? lesson2;
  static const textureWidth = 640;
  static const textureHeight = 320;
  static const aspect = textureWidth / textureHeight;

  double dpr = 1.0;
  late double width;
  late double height;
  Size? screenSize;

  @override
  void initState() {
    super.initState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    didInit = true;
    final mq = MediaQuery.of(context);
    screenSize = mq.size;
    dpr = mq.devicePixelRatio;

    width = screenSize!.width;
    height = width;

    await FlutterAngle.initOpenGL(true);

    final options = AngleOptions(
      width: textureWidth, 
      height: textureHeight, 
      dpr: dpr,
    );

    try {
      textures.add(await FlutterAngle.createTexture(options));
      textures.add(await FlutterAngle.createTexture(options));
    } on PlatformException catch (ex) {
      print("failed to get texture id");
      return;
    }

    //resetLessons();
    lesson = Lesson3(textures[0].getContext());
    lesson2 = Lesson4(textures[1].getContext());

    // /// Updating all Textues takes a slighllty less than 150ms
    // /// so we can't get much faster than this at the moment because it could happen that
    // /// the timer starts a new async function while the last one hasn't finished
    // /// which creates an OpenGL Exception

    if (!mounted) return;
    setState(() {
      textureId = textures[0].textureId;
      textureId2 = textures[1].textureId;
    });
    // timer = Timer.periodic(const Duration(milliseconds: 16), updateTexture);
    ticker = createTicker(updateTexture);
    ticker.start();
  }

  Timer? timer;
  Stopwatch stopwatch = Stopwatch();

  late Ticker ticker;
  static bool updating = false;
  int animationCounter = 0;
  int totalTime = 0;
  int iterationCount = 60;
  int framesOver = 0;
  bool didInit = false;
  void updateTexture(_) async {
    if (textureId < 0) return;
    if (!updating) {
      updating = true;
      stopwatch.reset();
      stopwatch.start();
      textures[0].activate();
      lesson?.handleKeys();
      lesson?.animate(animationCounter += 2);
      lesson?.drawScene(-1, 0, aspect);
      await textures[0].signalNewFrameAvailable();
      stopwatch.stop();
      totalTime += stopwatch.elapsedMilliseconds;
      if (stopwatch.elapsedMilliseconds > 16) {
        framesOver++;
      }
      if (--iterationCount == 0) {
        // print('Time: ${totalTime / 60} - Framesover $framesOver');
        totalTime = 0;
        iterationCount = 60;
        framesOver = 0;
      }
      textures[1].activate();
      lesson2?.handleKeys();
      lesson2?.animate(animationCounter += 2);
      lesson2?.drawScene(-1, 0, aspect);
      await textures[1].signalNewFrameAvailable();
      updating = false;
    } else {
      print('Too slow');
    }
  }

  void dispose() {
    ticker.dispose();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red,
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: LayoutBuilder(builder: (context, constraints) {
          final useRow = constraints.maxWidth > constraints.maxHeight;
          if(!didInit){
            initPlatformState();
          }
          return GestureDetector(
            onVerticalDragStart: verticalDragStart,
            onVerticalDragUpdate: verticalDragUpdate,
            onHorizontalDragStart: horizontalDragStart,
            onHorizontalDragUpdate: horizontalDragUpdate,
            child: Container(
              child: 
              kIsWeb?
                useRow
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(child: HtmlElementView(viewType: textureId.toString())),
                      Expanded(child: HtmlElementView(viewType: textureId2.toString())),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(child: HtmlElementView(viewType: textureId.toString())),
                      Expanded(child: HtmlElementView(viewType: textureId2.toString())),
                    ],
                  )
                :useRow
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(child: Texture(textureId: textureId)),
                      Expanded(child: Texture(textureId: textureId2)),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(child: Texture(textureId: textureId)),
                      Expanded(child: Texture(textureId: textureId2)),
                    ],
                  ),
            ),
          );
        }),
      ),
    );
  }

  double lastVertical = 0;

  double lastHorizontal = 0;

  void verticalDragStart(DragStartDetails details) {}

  void verticalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy < 0) {
      movement = Directions.up;
      print('up');
    } else if (details.delta.dy > 0) {
      print('down');
      movement = Directions.down;
    }
  }

  void horizontalDragStart(DragStartDetails details) {}
  void horizontalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dx < 0) {
      movement = Directions.right;
      print('right');
    } else if (details.delta.dx > 0) {
      movement = Directions.left;
      print('left');
    }
  }
}