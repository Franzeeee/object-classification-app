import 'package:flutter/material.dart';
import 'package:object_classification_1/pages/live_page.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:convert';


class DetectPage extends StatefulWidget {
  const DetectPage({super.key});

  @override
  _DetectPageState createState() => _DetectPageState();
}

class _DetectPageState extends State<DetectPage> {

  bool _isModelLoading = false;
  bool _isImagePicking = false;
  bool _isClassifying = false;
  bool _isResultAvailable = false;
  String _resultText = "";
  String _resultDescription = "";
  Interpreter? _interpreter;
  List <String> _labels = [];
  File? _image;
  final ImagePicker _picker = ImagePicker();
  List <double> _result = [];
  Map<String, String> _descriptions = {};
  

  @override
  void initState() {
    super.initState();
    _loadModel();
    _loadLabels();
    _loadDescriptions();
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  Future <void> _loadModel() async {
    setState(() {
      _isModelLoading = true;
    });

    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/model/model_unquant.tflite',
        options: InterpreterOptions()..threads = 4,
      );
      debugPrint("Model loaded successfully");
    } catch (e) {
      print("Error loading model: $e");
    } finally {
      setState(() {
        _isModelLoading = false;
      });
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



Future<void> _classifyImage(File image) async {
  // Check if the model is loaded and labels are available
  if (_isClassifying || _labels.isEmpty || _isImagePicking || _interpreter == null) {
    if (_labels.isEmpty) debugPrint("Labels are not loaded");
    // if (_interpreter == null) debugPrint("Interpreter is not loaded");
    return;
  }

  setState(() {
    _isImagePicking = true;
    _isClassifying = true;
    _isResultAvailable = false;
  });

  try {

    // Process the image in the backgraound
    final inputBuffer = await _processImageInBackground(image);

    // Prepare the output tensor
    final outputBuffer = Float32List(_labels.length);

    // Run the interpreter
    _interpreter!.run(inputBuffer.buffer, outputBuffer.buffer);

    // Interpret results for 3 classes (assuming softmax or multi-class output)
    _result = outputBuffer.sublist(0, 3);
    for (int i = 0; i < _result.length; i++) {
      debugPrint("Label: ${_labels[i]}, Score: ${_result[i]}");
    }

    // Find the top classification and its percentage
    int maxIndex = 0;
    double maxScore = _result[0];
    for (int i = 1; i < _result.length; i++) {
      if (_result[i] > maxScore) {
      maxScore = _result[i];
      maxIndex = i;
      }
    }
    final topLabel = _labels[maxIndex];
    final percentage = (maxScore * 100).toStringAsFixed(2);
    final description = _descriptions.values.toList()[_labels.indexOf(topLabel)];
    debugPrint("Final Classification: $topLabel ($percentage%)");
    debugPrint("Description: $description");

    setState(() {
      _isImagePicking = false;
      _isClassifying = false;
      _isResultAvailable = true;
      // Remove leading number and space from the label
      final displayLabel = topLabel.replaceFirst(RegExp(r'^\d+\s*'), '');
      _resultText = "$displayLabel ($percentage%)";
      _resultDescription = description;
    });

    

  } catch (e) {
    debugPrint("Error decoding image: $e");
    setState(() {
      _isImagePicking = false;
      _isClassifying = false;
    });
    return;
  }

}

Future<Float32List> _processImageInBackground(File image) async {
  final receivePort = ReceivePort();
  await Isolate.spawn(_processImage, [image.path, receivePort.sendPort]);
  final result = await receivePort.first;

  return result as Float32List;
}

static void _processImage(List<dynamic> args) async {
  final String imagePath = args[0];
  final SendPort sendPort = args[1];

  try {
    final imageFile = File(imagePath);
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes)!;
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


Future<void> _showImageSourceDialog() async {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Select Image Source'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Take a Picture'),
                  leading: const Icon(Icons.camera_alt),
                  onTap: () async {
                    Navigator.pop(context);
                    final photo = await _picker.pickImage(
                      source: ImageSource.camera,
                    );
                    if (photo != null) {
                      final imageFile = File(photo.path);
                      setState(() => _image = imageFile);
                      await _classifyImage(imageFile);
                    }
                  },
                ),
                ListTile(
                  title: const Text('Pick from Gallery'),
                  leading: const Icon(Icons.image),
                  onTap: () async {
                    Navigator.pop(context);
                    final photo = await _picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (photo != null) {
                      final imageFile = File(photo.path);
                      setState(() => _image = imageFile);
                      await _classifyImage(imageFile);
                    }
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Container(
                height: MediaQuery.of(context).size.height * 0.55,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    _isModelLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _image == null
                        ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.blueGrey,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(
                              8,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.camera_alt,
                                color: Colors.blueGrey,
                                size: 16,
                              ),
                              SizedBox(width: 10),
                              Text(
                                "No Image Selected",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        )
                        : Image.file(_image!, fit: BoxFit.contain),
              ),
              const SizedBox(height: 20),
              Column(
                children: [
                  Text(
                    _isClassifying ? "Classifying Image..." : "Result: $_resultText",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isClassifying ? "Classifying..." : _resultDescription.isNotEmpty ? _resultDescription : "No description available",
                    textAlign: TextAlign.justify,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed:  _showImageSourceDialog,
                    child: const Text("Select Image"),
                  ),
                  ElevatedButton(onPressed: () => {
                     Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LivePage(),
                        ),
                      )
                  }, child: Text("Live Detection")),
                ],
              )
            ],
          ),
        ),
      )
    );
  }
}
