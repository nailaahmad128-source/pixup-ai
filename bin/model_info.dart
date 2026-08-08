import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  final file = File('assets/models/ESRGAN.tflite');

  print('MODEL EXISTS: ${file.existsSync()}');
  print('MODEL SIZE: ${file.existsSync() ? file.lengthSync() : 0}');

  final interpreter = Interpreter.fromFile(file);

  final input = interpreter.getInputTensor(0);
  final output = interpreter.getOutputTensor(0);

  print('INPUT NAME: ${input.name}');
  print('INPUT SHAPE: ${input.shape}');
  print('INPUT TYPE: ${input.type}');

  print('OUTPUT NAME: ${output.name}');
  print('OUTPUT SHAPE: ${output.shape}');
  print('OUTPUT TYPE: ${output.type}');

  interpreter.close();
}
