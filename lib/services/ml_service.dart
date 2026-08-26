import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  Interpreter? _interpreter;
  int _inputSize = 112; // Default, will be updated dynamically
  int _outputSize = 192;
  String? loadError;

  Future<void> initialize() async {
    if (_interpreter != null) return;
    try {
      loadError = null;
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      
      _inputSize = inputShape[1];
      _outputSize = outputShape[1];
      
      debugPrint('TFLite loaded successfully. Input: $_inputSize, Output: $_outputSize');
    } catch (e) {
      loadError = e.toString();
      debugPrint('Failed to load TFLite model: $e');
    }
  }

  /// Extracts the face vector (e.g. 192D float array) from a cropped face in an img.Image
  List<double>? extractFaceVector(img.Image image, Rect boundingBox) {
    if (_interpreter == null) throw Exception(loadError ?? "TFLite interpreter is still loading...");

    try {
      img.Image faceImage = _cropAndResizeFace(image, boundingBox);
      
      // Use exact nested list structure [1, _inputSize, _inputSize, 3] expected by tflite
      var input = _imageToNestedList(faceImage);
      var output = List.generate(1, (index) => List.filled(_outputSize, 0.0));
      
      _interpreter!.run(input, output);

      return output[0];
    } catch (e) {
      debugPrint('Error extracting face vector: $e');
      throw Exception('TFLite Error: $e');
    }
  }

  /// Extracts the face vector from a live CameraImage stream
  List<double>? extractFaceVectorFromCameraImage(CameraImage cameraImage, Rect boundingBox) {
    img.Image image = _convertCameraImageToImage(cameraImage);
    image = img.copyRotate(image, angle: 270); // Match MLKit's 270deg rotation!

    return extractFaceVector(image, boundingBox);
  }

  /// Crops the face and resizes to 112x112
  img.Image _cropAndResizeFace(img.Image image, Rect boundingBox) {
    int x = max(0, boundingBox.left.toInt());
    int y = max(0, boundingBox.top.toInt());
    int w = min(image.width - x, boundingBox.width.toInt());
    int h = min(image.height - y, boundingBox.height.toInt());

    img.Image cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
    img.Image resized = img.copyResize(cropped, width: _inputSize, height: _inputSize);

    return resized;
  }

  /// Converts the 112x112 Image to a nested List [1, size, size, 3] expected by MobileFaceNet
  List<dynamic> _imageToNestedList(img.Image image) {
    var input = List.generate(1, (i) => List.generate(_inputSize, (j) => List.generate(_inputSize, (k) => List.filled(3, 0.0))));

    for (int i = 0; i < _inputSize; i++) {
      for (int j = 0; j < _inputSize; j++) {
        var pixel = image.getPixel(j, i);
        // MobileFaceNet normalization: (pixel - 127.5) / 128.0
        input[0][i][j][0] = (pixel.r - 127.5) / 128.0;
        input[0][i][j][1] = (pixel.g - 127.5) / 128.0;
        input[0][i][j][2] = (pixel.b - 127.5) / 128.0;
      }
    }
    return input;
  }

  /// Normalizes a vector to L2 unit length
  List<double> _normalize(List<double> vector) {
    double sum = 0.0;
    for (int i = 0; i < vector.length; i++) {
      sum += vector[i] * vector[i];
    }
    double norm = sqrt(sum);
    if (norm > 0.0) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }
    return vector;
  }

  /// Calculates Euclidean distance between two face vectors
  double calculateDistance(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) return double.maxFinite;
    
    v1 = _normalize(v1);
    v2 = _normalize(v2);

    double sum = 0.0;
    for (int i = 0; i < v1.length; i++) {
      double diff = v1[i] - v2[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  // --- Helper for Android YUV420 conversion ---
  img.Image _convertCameraImageToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    
    // For BGRA8888 (iOS)
    if (image.format.group == ImageFormatGroup.bgra8888) {
      final img.Image result = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: image.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
      return result;
    }
    
    // Use 3-plane YUV420 decoding for full RGB color (crucial for FaceNet)
    if (image.planes.length >= 3) {
      final img.Image result = img.Image(width: width, height: height);
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      for (int y = 0; y < height; y++) {
        int pY = y * image.planes[0].bytesPerRow;
        int pUV = (y ~/ 2) * uvRowStride;

        for (int x = 0; x < width; x++) {
          final int Y = image.planes[0].bytes[pY + x];
          final int uvOffset = pUV + (x ~/ 2) * uvPixelStride;

          final int U = image.planes[1].bytes[uvOffset];
          final int V = image.planes[2].bytes[uvOffset];

          int r = (Y + 1.402 * (V - 128)).toInt();
          int g = (Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)).toInt();
          int b = (Y + 1.772 * (U - 128)).toInt();

          result.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
        }
      }
      return result;
    }
    
    // Fallback if somehow single plane
    final img.Image result = img.Image(width: width, height: height);
    final nv21Bytes = image.planes[0].bytes;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int Y = nv21Bytes[y * width + x] & 0xFF;
        result.setPixelRgb(x, y, Y, Y, Y);
      }
    }
    return result;
  }
}
