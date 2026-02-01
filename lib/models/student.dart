// Student class for use in sections
// Grades structure: {subject: {q1: grade, q2: grade, q3: grade, q4: grade}}
class Student {
  final String name;
  final String studentId;
  final Map<String, Map<String, double>> grades; // subject -> {q1, q2, q3, q4}
  String? uid;
  String? profileImageThumbnail;
  String? profileImageUrl;

  Student({
    required this.name,
    required this.studentId,
    required this.grades,
    this.uid,
    this.profileImageThumbnail,
    this.profileImageUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'studentId': studentId,
      'grades': grades.map((subject, quarters) => MapEntry(subject, quarters)),
      if (uid != null) 'uid': uid,
      if (profileImageThumbnail != null) 'profileImageThumbnail': profileImageThumbnail,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
    };
  }

  factory Student.fromJson(Map<String, dynamic> json) {
    final rawGrades = json['grades'] as Map?;
    final Map<String, Map<String, double>> parsedGrades = {};
    
    if (rawGrades != null) {
      rawGrades.forEach((subject, value) {
        if (value is Map) {
          // New quarterly format: {q1: 85, q2: 90, ...}
          parsedGrades[subject.toString()] = Map<String, double>.from(
            value.map((k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0))
          );
        } else if (value is num) {
          // Legacy format: single grade - migrate to q1
          parsedGrades[subject.toString()] = {'q1': value.toDouble()};
        }
      });
    }
    
    return Student(
      name: json['name'] as String,
      studentId: json['studentId'] as String? ?? '',
      grades: parsedGrades,
      uid: json['uid'] as String?,
      profileImageThumbnail: json['profileImageThumbnail'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
    );
  }
  
  // Calculate average for a subject across all quarters OR specific semester
  double? getSubjectAverage(String subject, {int? semester}) {
    final quarters = grades[subject];
    if (quarters == null || quarters.isEmpty) return null;
    
    List<double> values;
    if (semester == 1) {
      // Sem 1: Q1, Q2
      values = [
        if (quarters['q1'] != null && quarters['q1']! > 0) quarters['q1']!,
        if (quarters['q2'] != null && quarters['q2']! > 0) quarters['q2']!,
      ];
    } else if (semester == 2) {
      // Sem 2: Q3, Q4
      values = [
        if (quarters['q3'] != null && quarters['q3']! > 0) quarters['q3']!,
        if (quarters['q4'] != null && quarters['q4']! > 0) quarters['q4']!,
      ];
    } else {
      // All quarters
      values = quarters.values.where((v) => v > 0).toList();
    }
    
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
  
  // Calculate overall average across all subjects OR specific semester
  double? getOverallAverage({int? semester}) {
    if (grades.isEmpty) return null;
    final averages = grades.keys
        .map((s) => getSubjectAverage(s, semester: semester))
        .where((a) => a != null)
        .cast<double>()
        .toList();
    if (averages.isEmpty) return null;
    return averages.reduce((a, b) => a + b) / averages.length;
  }
}
