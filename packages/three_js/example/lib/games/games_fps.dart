import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart';
import 'package:three_js_objects/three_js_objects.dart';

class SphereData{
  SphereData({
    required this.mesh,
    required this.collider,
    required this.velocity
  });

  three.Mesh mesh;
  three.BoundingSphere collider;
  three.Vector3 velocity;
}

class FPSGame extends StatefulWidget {
  const FPSGame({
    super.key,
    required this.fileName
  });

  final String fileName;

  @override
  _FPSGamePageState createState() => _FPSGamePageState();
}

class _FPSGamePageState extends State<FPSGame> {
  late three.ThreeJS threeJs;

  @override
  void initState() {
    threeJs = three.ThreeJS(
      onSetupComplete: (){
        setState(() {});
        // Keybindings
        // Add force on keydown
        threeJs.domElement.addEventListener(three.PeripheralType.pointerdown, (event){
          mouseTime = DateTime.now().millisecondsSinceEpoch;
        });
        threeJs.domElement.addEventListener(three.PeripheralType.pointerup, (event){
          throwBall();
        });
        threeJs.domElement.addEventListener(three.PeripheralType.pointerHover, (event){
          threeJs.camera.rotation.y -= (event as three.WebPointerEvent).movementX/100;
          threeJs.camera.rotation.x -= event.movementY/100;
        });
        threeJs.domElement.addEventListener(three.PeripheralType.keydown, (event){
          switch (event.keyId) {
            case 4294968068:
            case 119:
              keyStates[LogicalKeyboardKey.arrowUp] = true;
              break;
            case 115:
            case 4294968065:
              keyStates[LogicalKeyboardKey.arrowDown] = true;
              break;
            case 97:
            case 4294968066:
              keyStates[LogicalKeyboardKey.arrowLeft] = true;
              break;
            case 4294968067:
            case 100:
              keyStates[LogicalKeyboardKey.arrowRight] = true;
              break;
            case 32:
              keyStates[LogicalKeyboardKey.space] = true;
              break;
          }
        });

        // Reset force on keyup
        threeJs.domElement.addEventListener(three.PeripheralType.keyup, (event){
          switch (event.keyId) {
            case 4294968068:
            case 119:
              keyStates[LogicalKeyboardKey.arrowUp] = false;
              break;
            case 115:
            case 4294968065:
              keyStates[LogicalKeyboardKey.arrowDown] = false;
              break;
            case 97:
            case 4294968066:
              keyStates[LogicalKeyboardKey.arrowLeft] = false;
              break;
            case 4294968067:
            case 100:
              keyStates[LogicalKeyboardKey.arrowRight] = false;
              break;
            case 32:
              keyStates[LogicalKeyboardKey.space] = false;
              break;
          }
        });
      },
      setup: setup
    );
    super.initState();
  }
  @override
  void dispose() {
    threeJs.dispose();
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

  int stepsPerFrame = 5;
  double gravity = 30;

  List<SphereData> spheres = [];
  int sphereIdx = 0;

  Octree worldOctree = Octree();
  Capsule playerCollider = Capsule(
    three.Vector3( 0, 0.35, 0 ), 
    three.Vector3( 0, 1, 0 ), 
    0.35
  );

  three.Vector3 playerVelocity = three.Vector3();
  three.Vector3 playerDirection = three.Vector3();

  bool playerOnFloor = false;
  int mouseTime = 0;
  Map<LogicalKeyboardKey,bool> keyStates = {
    LogicalKeyboardKey.arrowUp: false,
    LogicalKeyboardKey.arrowLeft: false,
    LogicalKeyboardKey.arrowDown: false,
    LogicalKeyboardKey.arrowRight: false,
    LogicalKeyboardKey.space: false,
  };

  three.Vector3 vector1 = three.Vector3();
  three.Vector3 vector2 = three.Vector3();
  three.Vector3 vector3 = three.Vector3();

  Future<void> setup() async {
    threeJs.scene = three.Scene();
    threeJs.scene.background = three.Color.fromHex32(0x88ccee);

    threeJs.camera = three.PerspectiveCamera(70, threeJs.width / threeJs.height, 0.1, 1000);
    threeJs.camera.rotation.order = three.RotationOrders.yxz;

    // lights
    three.HemisphereLight fillLight1 = three.HemisphereLight( 0x4488bb, 0x002244, 0.5 );
    fillLight1.position.setValues( 2, 1, 1 );
    threeJs.scene.add(fillLight1);

    three.DirectionalLight directionalLight = three.DirectionalLight( 0xffffff, 0.8 );
    directionalLight.position.setValues( - 5, 25, - 1 );
    directionalLight.castShadow = true;

    directionalLight.shadow!.camera!.near = 0.01;
    directionalLight.shadow!.camera!.far = 500;
    directionalLight.shadow!.camera!.right = 30;
    directionalLight.shadow!.camera!.left = - 30;
    directionalLight.shadow!.camera!.top	= 30;
    directionalLight.shadow!.camera!.bottom = - 30;
    directionalLight.shadow!.mapSize.width = 1024;
    directionalLight.shadow!.mapSize.height = 1024;
    directionalLight.shadow!.radius = 4;
    directionalLight.shadow!.bias = - 0.00006;

    threeJs.scene.add(directionalLight);

    three.GLTFLoader().setPath('assets/models/gltf/').fromAsset('collision-world.glb').then((gltf){
      three.Object3D object = gltf!.scene;
      threeJs.scene.add(object);
      worldOctree.fromGraphNode(object);

      OctreeHelper helper = OctreeHelper(worldOctree);
      helper.visible = true;
      threeJs.scene.add(helper);

      object.traverse((child){
        if(child.type == 'Mesh'){
          three.Object3D part = child;
          part.castShadow = true;
          part.visible = true;
          part.receiveShadow = true;
        }
      });
    });

    threeJs.addAnimationEvent((dt){
      double deltaTime = math.min(0.05, dt)/stepsPerFrame;
      if(deltaTime != 0){
        for (int i = 0; i < stepsPerFrame; i ++) {
          controls(deltaTime);
          updatePlayer(deltaTime);
          updateSpheres(deltaTime);
          teleportPlayerIfOob();
        }
      }
    });
  }

  void throwBall() {
    double sphereRadius = 0.2;
    IcosahedronGeometry sphereGeometry = IcosahedronGeometry( sphereRadius, 5 );
    three.MeshLambertMaterial sphereMaterial = three.MeshLambertMaterial.fromMap({'color': 0xbbbb44});

    final three.Mesh newsphere = three.Mesh( sphereGeometry, sphereMaterial );
    newsphere.castShadow = true;
    newsphere.receiveShadow = true;

    threeJs.scene.add( newsphere );
    spheres.add(SphereData(
      mesh: newsphere,
      collider: three.BoundingSphere(three.Vector3( 0, - 100, 0 ), sphereRadius),
      velocity: three.Vector3()
    ));
    SphereData sphere = spheres.last;
    threeJs.camera.getWorldDirection( playerDirection );
    sphere.collider.center.setFrom(playerCollider.end).addScaled( playerDirection, playerCollider.radius * 1.5 );
    // throw the ball with more force if we hold the button longer, and if we move forward
    double impulse = 15 + 30 * ( 1 - math.exp((mouseTime-DateTime.now().millisecondsSinceEpoch) * 0.001));
    sphere.velocity.setFrom( playerDirection ).scale( impulse );
    sphere.velocity.addScaled( playerVelocity, 2 );
    sphereIdx = ( sphereIdx + 1 ) % spheres.length;
  }
  
  void playerCollisions() {
    OctreeData? result = worldOctree.capsuleIntersect(playerCollider);
    playerOnFloor = false;
    if(result != null){
      playerOnFloor = result.normal.y > 0;
      if(!playerOnFloor) {
        playerVelocity.addScaled(result.normal, - result.normal.dot(playerVelocity));
      }
      if(result.depth > 0.02){
        playerCollider.translate(result.normal.scale(result.depth));
      }
    }
  }
  void updatePlayer(double deltaTime) {
    double damping = math.exp(-4 * deltaTime) -1;
    if(!playerOnFloor){
      playerVelocity.y -= gravity * deltaTime;
      // small air resistance
      damping *= 0.1;
    }

    playerVelocity.addScaled( playerVelocity, damping );
    three.Vector3 deltaPosition = playerVelocity.clone().scale( deltaTime );
    playerCollider.translate( deltaPosition );
    playerCollisions();
    threeJs.camera.position.setFrom(playerCollider.end);
  }
  void playerSphereCollision(SphereData sphere) {
    three.Vector3 center = vector1.add2(playerCollider.start, playerCollider.end ).scale( 0.5 );
    final sphereCenter = sphere.collider.center;
    double r = playerCollider.radius + sphere.collider.radius;
    double r2 = r*r;

    // approximation: player = 3 spheres
    List<three.Vector3> temp = [playerCollider.start,playerCollider.end,center];
    for(three.Vector3 point in temp) {
      num d2 = point.distanceToSquared(sphereCenter);
      if ( d2 < r2 ) {
        three.Vector3 normal = vector1.sub2(point, sphereCenter).normalize();
        three.Vector3 v1 = vector2.setFrom( normal ).scale( normal.dot( playerVelocity ) );
        three.Vector3 v2 = vector3.setFrom( normal ).scale( normal.dot( sphere.velocity) );

        playerVelocity.add(v2).sub(v1);
        sphere.velocity.add(v1).sub(v2);

        double d = ( r - math.sqrt( d2 ) ) / 2;
        sphereCenter.addScaled( normal, - d );
      }
    }
  }
  
  void spheresCollisions() {
    for (int i = 0, length = spheres.length; i < length; i ++ ) {
      SphereData s1 = spheres[ i ];
      for (int j = i + 1; j < length; j ++ ) {
        SphereData s2 = spheres[ j ];
        num d2 = s1.collider.center.distanceToSquared(s2.collider.center);
        double r = s1.collider.radius + s2.collider.radius;
        double r2 = r * r;

        if ( d2 < r2 ) {
          three.Vector3 normal = vector1.sub2( s1.collider.center, s2.collider.center ).normalize();
          three.Vector3 v1 = vector2.setFrom( normal ).scale( normal.dot( s1.velocity));
          three.Vector3 v2 = vector3.setFrom( normal ).scale( normal.dot( s2.velocity));

          s1.velocity.add( v2 ).sub( v1 );
          s2.velocity.add( v1 ).sub( v2 );

          double d = ( r - math.sqrt( d2 ) ) / 2;

          s1.collider.center.addScaled( normal, d );
          s2.collider.center.addScaled( normal, - d );
        }
      }
    }
  }
  void updateSpheres(double deltaTime) {
    for(final sphere in spheres){
      sphere.collider.center.addScaled(sphere.velocity, deltaTime);
      OctreeData? result = worldOctree.sphereIntersect(sphere.collider);
      if(result != null) {
        sphere.velocity.addScaled( result.normal, - result.normal.dot( sphere.velocity) * 1.5 );
        sphere.collider.center.add( result.normal.scale( result.depth ) );
      } 
      else{
        sphere.velocity.y -= gravity * deltaTime;
      }

      double damping = math.exp(- 1.5*deltaTime) - 1;
      sphere.velocity.addScaled(sphere.velocity, damping);

      playerSphereCollision(sphere);
    }

    spheresCollisions();

    for (SphereData sphere in spheres){
      sphere.mesh.position.setFrom(sphere.collider.center);
    }
  }

  three.Vector3 getForwardVector() {
    threeJs.camera.getWorldDirection(playerDirection);
    playerDirection.y = 0;
    playerDirection.normalize();
    return playerDirection;
  }
  three.Vector3 getSideVector() {
    threeJs.camera.getWorldDirection( playerDirection );
    playerDirection.y = 0;
    playerDirection.normalize();
    playerDirection.cross( threeJs.camera.up );
    return playerDirection;
  }
  void controls(double deltaTime){
    // gives a bit of air control
    double speedDelta = deltaTime*(playerOnFloor?25:8);

    if(keyStates[LogicalKeyboardKey.arrowUp]!){
      playerVelocity.add( getForwardVector().scale(speedDelta));
    }
    if(keyStates[LogicalKeyboardKey.arrowDown]!){
      playerVelocity.add( getForwardVector().scale(-speedDelta));
    }
    if(keyStates[LogicalKeyboardKey.arrowLeft]!){
      playerVelocity.add( getSideVector().scale(-speedDelta));
    }
    if (keyStates[LogicalKeyboardKey.arrowRight]!){
      playerVelocity.add( getSideVector().scale(speedDelta));
    }
    if(playerOnFloor){
      if(keyStates[LogicalKeyboardKey.space]!){
        playerVelocity.y = 15;
      }
    }
  }
  void teleportPlayerIfOob(){
    if(threeJs.camera.position.y <= - 25){
      playerCollider.start.setValues(0,0.35,0);
      playerCollider.end.setValues(0,1,0);
      playerCollider.radius = 0.35;
      threeJs.camera.position.setFrom(playerCollider.end);
      threeJs.camera.rotation.set(0,0,0);
    }
  }
}