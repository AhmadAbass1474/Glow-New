import 'package:Glow/core/utils/character_helper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'five saved identities resolve to one asset while uploads stay intact',
    () {
      for (final name in CharacterHelper.characters.keys) {
        expect(
          CharacterHelper.getModelPath(name),
          CharacterHelper.sharedModelPath,
        );
        expect(
          CharacterHelper.getModelPath('${name}_frontal.glb'),
          CharacterHelper.sharedModelPath,
        );
        expect(CharacterHelper.getColorKey('${name}_frontal.glb'), name);
      }
      const upload = 'https://example.com/mascot.glb?color=qort';
      expect(CharacterHelper.getModelPath(upload), upload);
      expect(CharacterHelper.getColorKey(upload), 'qort');
    },
  );

  test(
    'runtime loader skins the dino mascot, hat and expression clips',
    () async {
      final bytes = await rootBundle.load(CharacterHelper.sharedModelPath);
      final loader = three.GLTFLoader();
      final data = await loader.fromBytes(bytes.buffer.asUint8List());
      expect(data, isNotNull);
      final root = data!.scene;
      final meshes = <three.SkinnedMesh>[];
      final materials = <String>{};
      root.traverse((object) {
        if (object is three.SkinnedMesh) {
          meshes.add(object);
          final material = object.material;
          if (material?.name != null) materials.add(material!.name!);
        }
      });
      expect(meshes, isNotEmpty);
      expect(meshes, hasLength(3));
      expect(materials, contains('Hat'));
      expect(meshes.first.geometry!.attributes['_glow_skin_region'], isNotNull);
      expect(meshes.first.skeleton!.bones, hasLength(17));
      expect(root.getObjectByName('Jaw'), isA<three.Bone>());
      expect(root.getObjectByName('Mouth'), isNull);
      expect(root.getObjectByName('LeftHand'), isA<three.Bone>());
      expect(root.getObjectByName('RightFoot'), isA<three.Bone>());
      final clips = data.animations!.cast<three.AnimationClip>();
      expect(clips.map((clip) => clip.name).toSet(), {
        'Idle',
        'Talk',
        'Wave',
        'Happy',
        'Sad',
        'Thinking',
        'Victory',
        'Walk',
        'Smile',
        'Laugh',
      });
      final mixer = three.AnimationMixer(root);
      final arm = root.getObjectByName('RightUpperArm')!;
      for (final clip in clips) {
        mixer.stopAllAction();
        mixer.clipAction(clip)!.reset().play();
        mixer.update(clip.duration.toDouble() * 0.37);
        root.updateMatrixWorld(true);
        for (final bone in meshes.first.skeleton!.bones) {
          expect(
            bone.position.x.isFinite &&
                bone.position.y.isFinite &&
                bone.position.z.isFinite &&
                bone.quaternion.w.isFinite,
            isTrue,
            reason: '${clip.name}/${bone.name}',
          );
        }
      }
      mixer.stopAllAction();
      mixer
          .clipAction(clips.firstWhere((clip) => clip.name == 'Idle'))!
          .reset()
          .play();
      mixer.update(0.4);
      final rest = arm.quaternion.clone();
      mixer.stopAllAction();
      mixer
          .clipAction(clips.firstWhere((clip) => clip.name == 'Victory'))!
          .reset()
          .play();
      mixer.update(0.4);
      expect((arm.quaternion.z - rest.z).abs(), greaterThan(0.1));
      final mesh = meshes.first;
      root.updateMatrixWorld(true);
      final positions = mesh.geometry!.attributes['position'];
      var deformed = 0;
      for (var i = 0; i < positions.count; i += 23) {
        final original = three.Vector3().fromBuffer(positions, i);
        final posed = mesh.applyBoneTransform(i, original.clone());
        expect(
          posed.x.isFinite && posed.y.isFinite && posed.z.isFinite,
          isTrue,
        );
        if (posed.distanceTo(original) > 0.03) deformed++;
      }
      expect(deformed, greaterThan(10));
      mixer.stopAllAction();
      for (final clip in clips) {
        mixer.uncacheAction(clip, root);
      }
      root.dispose();
      loader.dispose();
    },
  );
}
