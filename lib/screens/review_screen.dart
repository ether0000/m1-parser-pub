import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exam_question.dart';
import '../services/firestore_service.dart';
import '../utils/animated_background.dart';
import '../utils/glassmorphism.dart';

class ReviewScreen extends StatelessWidget {
  final List<ExamQuestion> wrongQuestions;

  const ReviewScreen({Key? key, required this.wrongQuestions}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (wrongQuestions.isEmpty) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('考後提煉與錯題總結', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: AnimatedGradientBackground(
          child: Center(
            child: GlassContainer(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.celebration_rounded, size: 80, color: Colors.amber),
                  const SizedBox(height: 20),
                  const Text('太棒了！這次測驗全對！', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)
                    ),
                    child: const Text('返回看板', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('考後提煉與錯題總結', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: wrongQuestions.length,
                  itemBuilder: (context, index) {
                    ExamQuestion q = wrongQuestions[index];
                    List<String> labels = ['A', 'B', 'C', 'D'];
                    String correctLabels = q.correctAnswers
                        .map((idx) => idx < labels.length ? labels[idx] : '')
                        .join(', ');
                    String correctOptions = q.correctAnswers
                        .map((idx) => q.options[idx])
                        .join(' / ');

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (_getQuestionNumber(q.id) > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                    child: Text('第 ${_getQuestionNumber(q.id)} 題', style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                Expanded(
                                  child: Text(
                                    'ID: ${q.id}',
                                    style: const TextStyle(fontSize: 12, color: Colors.black38),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              q.content,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withOpacity(0.3))
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '正確答案: $correctLabels. $correctOptions',
                                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Row(
                              children: [
                                Icon(Icons.edit_note_rounded, color: Colors.black54),
                                SizedBox(width: 8),
                                Text('電子書重點筆記：', style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: TextEditingController(text: q.userNote),
                              maxLines: 4,
                              style: const TextStyle(color: Colors.black87),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.05),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                hintText: '查閱電子書並輸入重點解析...',
                                hintStyle: const TextStyle(color: Colors.black38),
                              ),
                              onChanged: (val) {
                                q.userNote = val;
                                final firestoreService = Provider.of<FirestoreService>(context, listen: false);
                                firestoreService.updateQuestion(q);
                              },
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text('完成並返回看板', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getQuestionNumber(String id) {
    try {
      if (id.contains('-')) {
        final part = id.split('-').last;
        return int.parse(part);
      }
      return int.parse(id);
    } catch (e) {
      return 0;
    }
  }
}

