import 'dart:async';

import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

class WebglLoaderGltf extends StatefulWidget {
  final String fileName;
  const WebglLoaderGltf({super.key, required this.fileName});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<WebglLoaderGltf> {
  late three.ThreeJS threeJs;

  @override
  void initState() {
    threeJs = three.ThreeJS(
      
      onSetupComplete: (){setState(() {});},
      setup: setup,
      rendererUpdate: (){
        threeJs.renderer!.clear(true, true, true);
      },
      settings: three.Settings(
        clearAlpha: 0,
        clearColor: 0xffffff
      ),
    );
    super.initState();
  }
  @override
  void dispose() {
    threeJs.dispose();
    controls.clearListeners();
    three.loading.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
      ),
      body: threeJs.build()
    );
  }

  late three.OrbitControls controls;

  Future<void> setup() async {
    threeJs.scene = three.Scene();

    threeJs.camera = three.PerspectiveCamera(45, threeJs.width / threeJs.height, 0.25, 20);
    threeJs.camera.position.setValues( - 0, 0, 2.7 );
    threeJs.camera.lookAt(threeJs.scene.position);

    controls = three.OrbitControls(threeJs.camera, threeJs.globalKey);

    three.RGBELoader rgbeLoader = three.RGBELoader();
    rgbeLoader.setPath('assets/textures/equirectangular/');
    final hdrTexture = await rgbeLoader.fromAsset('royal_esplanade_1k.hdr');
    hdrTexture?.mapping = three.EquirectangularReflectionMapping;

    threeJs.scene.background = hdrTexture;
    threeJs.scene.environment = hdrTexture;

    threeJs.scene.add( three.AmbientLight( 0xffffff ) );

    three.GLTFLoader loader = three.GLTFLoader()
        .setPath('assets/models/gltf/DamagedHelmet/glTF/');

    final result = await loader.fromAsset('DamagedHelmet.gltf');

    three.console.info(" gltf load sucess result: $result  ");

    final object = result!.scene;

    // final geometry = new three.PlaneGeometry(2, 2);
    // final material = new three.MeshBasicMaterial();

    // object.traverse( ( child ) {
    //   if ( child is three.Mesh ) {
    //     material.map = child.material.map;
    //   }
    // } );

    // final mesh = new three.Mesh(geometry, material);
    // scene.add(mesh);

    // object.traverse( ( child ) {
    //   if ( child.isMesh ) {
    // child.material.map = texture;
    //   }
    // } );

    threeJs.scene.add(object);
  
    threeJs.addAnimationEvent((dt){
      controls.update();
    });
  }
}