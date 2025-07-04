import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:flutter/services.dart';


class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  _LivePageState createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {


  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _iscameraInitialized = false;
  bool _isProcessing = false;
  Timer? _timer;
  bool _isDisposed = false;
  Interpreter? _interpreter;
  List<String> _labels = [];
  Map<String, String> _descriptions = {};
  String _resultText = "Result Here";
  String _resultDescription = "Description Here";
  

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
    _loadLabels();
    _loadDescriptions();
  }

  @override
  void dispose() {
    _stopCamera();
    _cameras = null;
    _interpreter?.close();
  _isDisposed = true;
    _timer?.cancel();
    super.dispose();
  }

  Future <void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/model/model_unquant.tflite',
        options: InterpreterOptions()..threads = 4,
      );
      debugPrint("Model loaded successfully");
    } catch (e) {
      print("Error loading model: $e");
    }
  }

  Future<void> _loadLabels() async {
    try {
      final labelsContent = await rootBundle.loadString('assets/model/labels.txt');
      setState(() {
        _labels = labelsContent
            .split('\n')
            .map((label) => label.trim())
            .where((label) => label.isNotEmpty)
            .toList();
      });
      debugPrint("Labels loaded successfully: $_labels");
    } catch (e) {
      debugPrint("Failed to load labels: $e");
    }
  }

  Future<void> _loadDescriptions() async {
  try {
    final jsonString = await rootBundle.loadString('assets/json/description.json');
    final jsonData = jsonDecode(jsonString) as List;
    _descriptions = {
      for (var item in jsonData)
        item['id'] as String: item['description'] as String
    };
    debugPrint("Descriptions loaded: $_descriptions");
  } catch (e) {
    debugPrint("Error loading descriptions: $e");
  }
}


  Future<void> _initializeCamera() async {
    if (_isDisposed) return;
    await Permission.camera.request();

    if (await Permission.camera.isGranted) {
      _cameras = await availableCameras();
      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.medium
      );

      await _cameraController!.initialize();

      setState(() {
        _iscameraInitialized = true;
      });

      _cameraController!.startImageStream((CameraImage image) async {
        if(_isProcessing) return;

        _isProcessing = true;

        _timer ??= Timer(const Duration(seconds: 1), () async {
          if (_isDisposed) return;
          
          try {
            final floatData = await _processImageInBackground(image);
            if (floatData != null && _interpreter != null && _labels.isNotEmpty) {
              final outputBuffer = Float32List(_labels.length);
              _interpreter!.run(floatData.buffer, outputBuffer.buffer);

              // find top label
              int maxIndex = 0;
              double maxScore = outputBuffer[0];
              for (int i = 1; i < outputBuffer.length; i++) {
                if (outputBuffer[i] > maxScore) {
                  maxScore = outputBuffer[i];
                  maxIndex = i;
                }
              }

              final topLabel = _labels[maxIndex].replaceFirst(RegExp(r'^\d+\s*'), '');
              final percentage = (maxScore * 100).toStringAsFixed(2);
              final description = _descriptions.values.toList()[maxIndex];

              if (!_isDisposed) {
                setState(() {
                  // update UI
                  _resultText = "$topLabel ($percentage%)";
                  _resultDescription = description;
                });
              }

              debugPrint("!!!!Detected: $topLabel with score: $percentage%");
            }
            _isProcessing = false;

          } catch (e) {
            print("Error processing image: $e");
            _isProcessing = false;
            return;
          } finally {
            _isProcessing = false;
            _timer = null;
          }
        });
        
      });


    } else {
      if(await Permission.camera.isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Camera permission is denied. Please allow it in settings."),
            duration: Duration(seconds: 3),
          )
        );
      }
    }

  }

  Future<Float32List> _processImageInBackground(CameraImage image) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_processImage, [image, receivePort.sendPort]);
    final result = await receivePort.first;

    return result as Float32List;
  }

  static void _processImage(List<dynamic> args) async {
    final CameraImage cameraImage = args[0];
    final SendPort sendPort = args[1];

    try {
      final image = _convertYUV420ToImage(cameraImage);
      final resized = img.copyResize(image, width: 224, height: 224);

      // Convert the image to its RGB bytes and normalize it
      final pixel = resized.getBytes(order: img.ChannelOrder.rgb);
      final floatBuffer = Float32List(224 * 224 * 3);

      for (int i = 0; i < pixel.length; i++) {
        floatBuffer[i] = pixel[i] / 255.0; // Normalize to [0, 1]
      }

      sendPort.send(floatBuffer);
    } catch (e) {
      print("Error processing image: $e");
      sendPort.send(null);
      return;
    }
  }

  static img.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image imgImage = img.Image(width: width, height: height);

    final planeY = image.planes[0].bytes;
    final planeU = image.planes[1].bytes;
    final planeV = image.planes[2].bytes;

    final strideY = image.planes[0].bytesPerRow;
    final strideU = image.planes[1].bytesPerRow;
    final strideV = image.planes[2].bytesPerRow;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = (y >> 1) * strideU + (x >> 1);  
        final yIndex = y * strideY + x;

        final yp = planeY[yIndex] & 0xFF;
        final up = planeU[uvIndex] & 0xFF;
        final vp = planeV[uvIndex] & 0xFF;

        final int r = (yp + 1.370705 * (vp - 128)).clamp(0, 255).toInt();
        final int g =
            (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128))
                .clamp(0, 255)
                .toInt();
        final int b = (yp + 1.732446 * (up - 128)).clamp(0, 255).toInt();

        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }
    return imgImage;
  }


  Future<void> _stopCamera() async {
    try {
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
      _cameraController = null;
      debugPrint("Camera stopped and disposed.");
    } catch (e) {
      debugPrint("Error stopping camera: $e");
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child:
          _iscameraInitialized
            ? Column(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.06,
                  width: MediaQuery.of(context).size.width,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(0),
                      ),
                    ),
                    onPressed: () => {
                      Navigator.of(context).pop()
                    }, 
                    child: Row(
                      children: [
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.02,
                        ),
                        Icon(Icons.arrow_back, 
                          color: Colors.black, 
                          size: MediaQuery.of(context).size.width * 0.05,
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.01,
                        ),
                        Text("Back")
                      ],
                    ),
                  )
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.005,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      alignment: Alignment.center,
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.height * 0.5,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: SizedBox.expand(
                        child: CameraPreview(_cameraController!)
                      ),
                      
                    ),
                  ],
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.02,
                ),
                Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: MediaQuery.of(context).size.height * 0.08,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 33, 82, 243),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      _resultText.isNotEmpty ? _resultText : "No result yet",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width * 0.05,
                        fontWeight: FontWeight.bold
                      )
                    ),
                  ),
                ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.01,
                ),
                Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: MediaQuery.of(context).size.height * 0.22,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 33, 82, 243),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(5),
                      child: Text(
                        _resultDescription.isNotEmpty ? _resultDescription : "No description yet",
                      textAlign: TextAlign.justify,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width * 0.043,
                        fontWeight: FontWeight.bold,
                      )
                    ),
                    )
                  ),
                )
              ],
            )
            : Center(
                child: CircularProgressIndicator(),
              ),
        )
    );
  }
}