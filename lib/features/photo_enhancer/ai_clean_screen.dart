import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'ai_clean_prompt.dart';

class AICleanScreen extends StatefulWidget {
  const AICleanScreen({super.key});

  @override
  State<AICleanScreen> createState() => _AICleanScreenState();
}

class _AICleanScreenState extends State<AICleanScreen> {
  File? _image;
  final _promptController = TextEditingController();
  bool _generating = false;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );

    if (picked != null) {
      setState(() {
        _image = File(picked.path);
      });
    }
  }

  Future<void> _generate() async {
    if (_image == null) return;

    final prompt = AICleanPrompt.build(
      _promptController.text,
    );

    debugPrint('AI PROMPT: $prompt');

    setState(() {
      _generating = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() {
      _generating = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'AI Clean pipeline ready — enhancement engine will process this image.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Clean'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.grey.shade300,
                  ),
                ),
                child: _image == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 64,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Select Photo',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text('Tap to choose an image'),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(
                          _image!,
                          fit: BoxFit.contain,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: _promptController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'AI Prompt',
                hintText:
                    'مثلاً: تصویر صاف، واضح اور HD کریں، چہرہ تبدیل نہ کریں',
                prefixIcon: const Icon(Icons.auto_awesome),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _image == null || _generating
                  ? null
                  : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _generating
                    ? 'Generating...'
                    : 'AI Clean & Generate',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
