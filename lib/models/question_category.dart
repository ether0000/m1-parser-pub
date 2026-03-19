import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionCategory {
  final String categoryId;
  final String categoryName;
  final String colorCode;

  QuestionCategory({
    required this.categoryId,
    required this.categoryName,
    required this.colorCode,
  });

  factory QuestionCategory.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return QuestionCategory(
      categoryId: doc.id,
      categoryName: data['categoryName'] ?? '',
      colorCode: data['colorCode'] ?? '#F2F2F7',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'categoryName': categoryName,
      'colorCode': colorCode,
    };
  }
}
