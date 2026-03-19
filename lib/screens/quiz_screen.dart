import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exam_question.dart';
import '../models/quiz_session.dart';
import '../services/firestore_service.dart';
import '../utils/animated_background.dart';
import '../utils/glassmorphism.dart';
import 'review_screen.dart';
import 'package:uuid/uuid.dart';

class QuizScreen extends StatefulWidget {
  final List<ExamQuestion> questions;
  const QuizScreen({Key? key, required this.questions}) : super(key: key);

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentIndex = 0;
  List<ExamQuestion> _wrongQuestions = [];
  Map<String, int> _userAnswers = {};
  bool _hasAnsweredCurrent = false;
  int? _selectedOption;
  bool _isFinished = false;

  void _submitAnswer(int index) async {
    setState(() {
      _selectedOption = index;
      _hasAnsweredCurrent = true;
      _userAnswers[widget.questions[_currentIndex].id] = index;
    });

    ExamQuestion q = widget.questions[_currentIndex];
    q.attemptCount += 1;
    q.lastAttemptDate = DateTime.now();

    if (q.correctAnswers.contains(index)) {
      q.correctCount += 1;
      if (q.correctCount >= 2) {
        q.isMastered = true;
      }
    } else {
      q.errorCount += 1;
      q.correctCount = 0; // Reset streak
      if (!_wrongQuestions.contains(q)) {
        _wrongQuestions.add(q);
      }
    }

    // Save update to firestore immediately
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    await firestoreService.updateQuestion(q);
  }

  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex += 1;
        _hasAnsweredCurrent = false;
        _selectedOption = null;
      });
    } else {
      _finishQuiz();
    }
  }

  void _finishQuiz() async {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    
    final session = QuizSession(
      sessionId: const Uuid().v4(),
      timestamp: DateTime.now(),
      totalQuestions: widget.questions.length,
      wrongCount: _wrongQuestions.length,
      wrongQuestionIds: _wrongQuestions.map((q) => q.id).toList(),
      userAnswers: _userAnswers,
    );

    await firestoreService.saveQuizSession(session);

    setState(() {
      _isFinished = true;
    });
  }

  void _toggleFavorite() async {
    ExamQuestion q = widget.questions[_currentIndex];
    setState(() {
      q.isFavorite = !q.isFavorite;
    });
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    await firestoreService.updateQuestion(q);
  }

  @override
  Widget build(BuildContext context) {
    if (_isFinished) {
      return ReviewScreen(wrongQuestions: _wrongQuestions);
    }

    ExamQuestion currentQ = widget.questions[_currentIndex];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('第 ${_currentIndex + 1} 題 / 共 ${widget.questions.length} 題', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(currentQ.isFavorite ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber),
            onPressed: _toggleFavorite,
          )
        ],
      ),
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GlassContainer(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            currentQ.content,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ...List.generate(currentQ.options.length, (index) {
                          Color bgColor = Colors.black.withOpacity(0.05);
                          Color borderColor = Colors.black.withOpacity(0.1);
                          Icon? trailingIcon;
                          Color textColor = Colors.black87;
                          
                          if (_hasAnsweredCurrent) {
                            if (currentQ.correctAnswers.contains(index)) {
                              bgColor = Colors.green.withOpacity(0.2);
                              borderColor = Colors.green;
                              textColor = Colors.green.shade900;
                              if (index == _selectedOption) trailingIcon = const Icon(Icons.check_circle_rounded, color: Colors.green);
                            } else if (index == _selectedOption) {
                              bgColor = Colors.redAccent.withOpacity(0.2);
                              borderColor = Colors.redAccent;
                              textColor = Colors.redAccent.shade700;
                              trailingIcon = const Icon(Icons.cancel_rounded, color: Colors.redAccent);
                            }
                          }

                          List<String> labels = ['A', 'B', 'C', 'D'];
                          String label = index < labels.length ? labels[index] : '';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: InkWell(
                              onTap: _hasAnsweredCurrent ? null : () => _submitAnswer(index),
                              borderRadius: BorderRadius.circular(16),
                              child: GlassContainer(
                                padding: const EdgeInsets.all(16),
                                color: bgColor,
                                borderRadius: BorderRadius.circular(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black.withOpacity(0.05),
                                      ),
                                      child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(currentQ.options[index], style: TextStyle(fontSize: 16, color: textColor)),
                                    ),
                                    if (trailingIcon != null) trailingIcon
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
                if (_hasAnsweredCurrent)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: ElevatedButton(
                      onPressed: _nextQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('下一題', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

