import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:image_picker/image_picker.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as path;

import 'amplifyconfiguration.dart';

void main() {
  runApp(const AuthenticatedApp());
}

class AuthenticatedApp extends StatefulWidget {
  const AuthenticatedApp({super.key});

  @override
  State<AuthenticatedApp> createState() => _AuthenticatedAppState();
}

class _AuthenticatedAppState extends State<AuthenticatedApp> {
  bool _amplifyConfigured = false;

  @override
  void initState() {
    super.initState();
    _configureAmplify();
  }

  Future<void> _configureAmplify() async {
    try {
      await Amplify.addPlugin(AmplifyAuthCognito());
      await Amplify.addPlugin(AmplifyAPI());
      await Amplify.addPlugin(AmplifyStorageS3());
      await Amplify.configure(amplifyconfig);
      setState(() {
        _amplifyConfigured = true;
      });
    } catch (e) {
      safePrint('Failed to configure Amplify: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_amplifyConfigured) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Authenticator(
      child: MaterialApp(
        builder: Authenticator.builder(),
        home: const MainNavigation(),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final GlobalKey<HistoryPageState> _historyKey = GlobalKey<HistoryPageState>();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 1) {
        _historyKey.currentState?.fetchDiagnoses();
      }
    });
  }

  List<Widget> get _pages => [
        const HomePage(),
        HistoryPage(key: _historyKey),
        const UploadPage(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud_upload),
            label: 'Upload',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Disease Detector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Amplify.Auth.signOut();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome to the Plant Disease Detector!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              "This is a Hydrotek Farm app. We built it to provide value to your farming or gardening operation by allowing you to detect and cure the disease before more of your crops are infected.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            const Text(
              'Use the toolbar below to access your diagnosis history or upload new images for analysis.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.feedback),
              label: const Text('Send Feedback'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FeedbackPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key});
  @override
  Widget build(BuildContext context) {
    final TextEditingController _controller = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Feedback'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'We value your feedback! Please let us know your thoughts or suggestions below.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter your feedback here...',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send Email'),
              onPressed: () async {
                final feedback = Uri.encodeComponent(_controller.text);
                final uri = Uri.parse(
                  'mailto:iankbennett@gmail.com?subject=Hydrotek%20Farm%20App%20Feedback&body=$feedback',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open email app.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  List<Diagnosis> _diagnoses = [];
  String _status = 'Tap refresh to load your history';

  Future<String?> _getCurrentUserEmailLocalPart() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      final email = attributes.firstWhere(
        (attr) => attr.userAttributeKey == AuthUserAttributeKey.email,
        orElse: () => AuthUserAttribute(userAttributeKey: AuthUserAttributeKey.email, value: ''),
      ).value;
      return email.isNotEmpty ? email.split('@').first : null;
    } catch (e) {
      safePrint('Error getting user email: $e');
      return null;
    }
  }

  Future<void> fetchDiagnoses() async {
    setState(() {
      _status = 'Fetching diagnoses...';
    });
    const String graphQLDocument = '''query ListDiagnoses {
      listDiagnoses {
        items {
          id
          image_key
          result
          disease
          severity
          treatment
          createdAt
        }
      }
    }''';

    try {
      final request = GraphQLRequest<String>(document: graphQLDocument);
      final response = await Amplify.API.query(request: request).response;
      final decoded = jsonDecode(response.data!);
      final items = decoded['listDiagnoses']['items'] as List;

      final localPart = await _getCurrentUserEmailLocalPart();
      final userPrefix = 'public/${localPart ?? 'unknown'}/';

      final diagnoses = items
          .where((item) => item != null)
          .map((item) => Diagnosis.fromJson(item as Map<String, dynamic>))
          .where((diag) => diag.imageKey.startsWith(userPrefix))
          .toList();

      setState(() {
        _diagnoses = diagnoses;
        _status = 'Fetched ${_diagnoses.length} diagnoses for your account';
      });
    } catch (e) {
      setState(() {
        _status = 'Query failed: $e';
        _diagnoses = [];
      });
    }
  }

  @override
  void initState() {
    super.initState();
    fetchDiagnoses();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnosis History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchDiagnoses,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(_status),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _diagnoses.length,
                itemBuilder: (context, index) {
                  final diag = _diagnoses[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text('${diag.disease} (${diag.severity})'),
                      subtitle: Text(
                          'Image: ${diag.imageKey}\nResult: ${diag.result}\nTreatment: ${diag.treatment}\nTime: ${diag.createdAt}'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});
  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  String _status = 'Ready to upload';
  XFile? _selectedImage;
  Timer? _timer;
  int _waitSeconds = 0;
  String? _lastImageName;

  Future<String?> _getCurrentUserEmailLocalPart() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      final email = attributes.firstWhere(
        (attr) => attr.userAttributeKey == AuthUserAttributeKey.email,
        orElse: () => AuthUserAttribute(userAttributeKey: AuthUserAttributeKey.email, value: ''),
      ).value;
      return email.isNotEmpty ? email.split('@').first : null;
    } catch (e) {
      safePrint('Error getting user email: $e');
      return null;
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;
    setState(() {
      _selectedImage = pickedFile;
      _status = 'Image selected from gallery. Ready to upload or delete.';
    });
  }

  Future<void> _takePicture() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;
    setState(() {
      _selectedImage = pickedFile;
      _status = 'Image captured from camera. Ready to upload or delete.';
    });
  }

  Future<void> _uploadSelectedImage() async {
    if (_selectedImage == null) return;
    setState(() {
      _status = 'Uploading image...';
    });

    final localPart = await _getCurrentUserEmailLocalPart();
    final fileKey = 'public/${localPart ?? 'unknown'}/image_${DateTime.now().millisecondsSinceEpoch}${path.extension(_selectedImage!.path)}';
    final imageName = path.basename(_selectedImage!.path);
    try {
      await Amplify.Storage.uploadFile(
        path: StoragePath.fromString(fileKey),
        localFile: AWSFile.fromPath(_selectedImage!.path),
      ).result;

      final fileUrl = await Amplify.Storage.getUrl(
        path: StoragePath.fromString(fileKey),
      ).result;

      _lastImageName = imageName;
      _waitSeconds = 0;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _waitSeconds++;
          _status = 'Image ($_lastImageName) Uploaded ... ($_waitSeconds/s)';
        });
      });

      setState(() {
        _status = 'Image ($_lastImageName) Uploaded ... (0/s)';
        _selectedImage = null;
      });

      // Wait for 30 seconds, then fetch the diagnosis for this image
      await Future.delayed(const Duration(seconds: 30));
      _timer?.cancel();
      await _fetchDiagnosisForImage(fileKey);

    } catch (e) {
      setState(() {
        _status = 'Failed to upload image: $e';
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDiagnosisForImage(String imageKey) async {
    setState(() {
      _status = 'Checking for diagnosis result...';
    });

    const String graphQLDocument = '''query ListDiagnoses {
      listDiagnoses {
        items {
          id
          image_key
          result
          disease
          severity
          treatment
          createdAt
        }
      }
    }''';

    try {
      final request = GraphQLRequest<String>(document: graphQLDocument);
      final response = await Amplify.API.query(request: request).response;
      final decoded = jsonDecode(response.data!);
      final items = decoded['listDiagnoses']['items'] as List;

      final diagnosisItem = items
          .where((item) => item != null && item['image_key'] == imageKey)
          .map((item) => Diagnosis.fromJson(item as Map<String, dynamic>))
          .toList();

      if (diagnosisItem.isNotEmpty) {
        final diag = diagnosisItem.first;
        _showDiagnosisDialog(diag);
        setState(() {
          _status = 'Diagnosis result received!';
        });
      } else {
        setState(() {
          _status = 'No diagnosis result found for this image yet.';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Query failed: $e';
      });
    }
  }

  void _showDiagnosisDialog(Diagnosis diag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnosis Result'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Disease: ${diag.disease}'),
              Text('Severity: ${diag.severity}'),
              Text('Treatment:\n${diag.treatment}'),
              Text('Result: ${diag.result}'),
              Text('Time: ${diag.createdAt}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _deleteSelectedImage() {
    setState(() {
      _selectedImage = null;
      _status = 'Image selection cleared.';
    });
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar here, as the main navigation provides it
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _pickImage,
                child: const Text('Pick Image from Gallery'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _takePicture,
                child: const Text('Take Picture'),
              ),
            ],
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 24),
            Image.file(
              File(_selectedImage!.path),
              height: 200,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _uploadSelectedImage,
                  child: const Text('Upload'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _deleteSelectedImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(_status),
        ],
      ),
    );
  }
}

class Diagnosis {
  final String id;
  final String imageKey;
  final String result;
  final String disease;
  final String severity;
  final String treatment;
  final String? createdAt;

  Diagnosis({
    required this.id,
    required this.imageKey,
    required this.result,
    required this.disease,
    required this.severity,
    required this.treatment,
    this.createdAt,
  });

  factory Diagnosis.fromJson(Map<String, dynamic> json) {
    return Diagnosis(
      id: json['id']?.toString() ?? 'unknown',
      imageKey: json['image_key']?.toString() ?? 'unknown',
      result: json['result']?.toString() ?? 'unknown',
      disease: json['disease']?.toString() ?? 'unknown',
      severity: json['severity']?.toString() ?? 'unknown',
      treatment: json['treatment']?.toString() ?? 'unknown',
      createdAt: json['createdAt']?.toString(),
    );
  }
}
