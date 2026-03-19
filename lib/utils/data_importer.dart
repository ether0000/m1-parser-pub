import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/exam_question.dart';
import '../services/firestore_service.dart';

class DataImporter {
  static Future<void> importLocalJson(FirestoreService firestoreService, Set<String> existingIds) async {

    try {
      // Assuming you will place JSON files in assets/json/
      // Need to read the manifest or hardcode paths. For now, hardcoding an example.
      const paths = [
        'JSON/2005_parsed.json',
        'JSON/2006_parsed.json',
      ];

      for (String path in paths) {
        try {
          final String response = await rootBundle.loadString(path);
          await importJsonContent(response, firestoreService, existingIds);
        } catch (e) {
          print("Could not load $path: $e");
        }
      }
    } catch (e) {
      print("Error importing JSON: $e");
    }
  }

  static Future<void> importJsonContent(String jsonContent, FirestoreService firestoreService, Set<String> existingIds) async {

    try {
      final List<dynamic> data = json.decode(jsonContent);
      List<ExamQuestion> newQuestions = [];

      for (var item in data) {
        String qId = item['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        if (!existingIds.contains(qId)) {
          // Handle correct answers (could be int or List<int>)
          dynamic rawCorrect = item['correctAnswer'];
          List<int> correctIndices = [];
          if (rawCorrect is List) {
            correctIndices = List<int>.from(rawCorrect).map((e) => e - 1).toList();
          } else {
            correctIndices = [((rawCorrect as int?) ?? 1) - 1];
          }

          ExamQuestion q = ExamQuestion(
            id: qId,
            year: item['year']?.toString() ?? '',
            subject: item['subject']?.toString() ?? '',
            content: item['content']?.toString() ?? '',
            options: List<String>.from(item['options'] ?? []),
            correctAnswers: correctIndices,
            userNote: item['userNote']?.toString() ?? '',
            categoryIds: List<String>.from(item['categoryIds'] ?? []),
            tags: List<String>.from(item['tags'] ?? []),
          );
          newQuestions.add(q);
        }
      }

      if (newQuestions.isNotEmpty) {
        print("Importing ${newQuestions.length} new questions...");
        await firestoreService.batchLoadQuestions(newQuestions);
        print("Import complete!");
      }
    } catch (e) {
      print("Error parsing JSON content: $e");
      rethrow;
    }
  }
}
