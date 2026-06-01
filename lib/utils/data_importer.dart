import 'dart:convert';
import 'package:flutter/foundation.dart';
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
          debugPrint("Could not load $path: $e");
        }
      }
    } catch (e) {
      debugPrint("Error importing JSON: $e");
    }
  }

  static List<Map<String, dynamic>> _parseJsonInBackground(String jsonContent) {
    final decoded = json.decode(jsonContent);
    if (decoded is List) {
      return List<Map<String, dynamic>>.from(
        decoded.map((item) => Map<String, dynamic>.from(item as Map)),
      );
    }
    return [];
  }

  static Future<void> importJsonContent(String jsonContent, FirestoreService firestoreService, Set<String> existingIds) async {
    try {
      final List<Map<String, dynamic>> data = await compute(_parseJsonInBackground, jsonContent);
      List<ExamQuestion> newQuestions = [];

      for (var item in data) {
        String qId = item['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        if (!existingIds.contains(qId)) {
          // Handle correct answers (could be int or List<int>)
          dynamic rawCorrect = item['correctAnswer'];
          List<int> correctIndices = [];
          
          if (rawCorrect is List) {
            correctIndices = rawCorrect
                .map((e) => int.tryParse(e.toString()) ?? 1)
                .map((e) => e - 1)
                .toList();
          } else if (rawCorrect != null) {
            final parsedInt = int.tryParse(rawCorrect.toString()) ?? 1;
            correctIndices = [parsedInt - 1];
          } else {
            correctIndices = [0];
          }

          ExamQuestion q = ExamQuestion(
            id: qId,
            year: item['year']?.toString() ?? '',
            subject: item['subject']?.toString() ?? '',
            content: item['content']?.toString() ?? '',
            options: List<String>.from((item['options'] ?? []).map((e) => e.toString())),
            correctAnswers: correctIndices,
            userNote: item['userNote']?.toString() ?? '',
          );
          newQuestions.add(q);
        }
      }

      if (newQuestions.isNotEmpty) {
        debugPrint("Importing ${newQuestions.length} new questions...");
        await firestoreService.batchLoadQuestions(newQuestions);
        debugPrint("Import complete!");
      }
    } catch (e) {
      debugPrint("Error parsing JSON content: $e");
      rethrow;
    }
  }
}
