import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';
import '../../widgets/bug_report_dialog.dart';

class HelpPage extends StatelessWidget {
  final String userType;
  final VoidCallback? onStartTour;
  final VoidCallback? onStartGradeTour;
  final VoidCallback? onStartClassesTour;
  final VoidCallback? onStartTeachersTour;
  final VoidCallback? onStartScheduleTour;
  final VoidCallback? onStartInboxTour;

  const HelpPage({
    super.key, 
    this.userType = 'Student',
    this.onStartTour, 
    this.onStartGradeTour,
    this.onStartClassesTour,
    this.onStartTeachersTour,
    this.onStartScheduleTour,
    this.onStartInboxTour,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('LIME Help & Tutorials', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: HexColor("#116754"),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader("Interactive Tours"),
            const SizedBox(height: 16),
            if (onStartTour != null)
              _buildTourCard(
                context,
                "Getting Started",
                "New to LIME? Take a quick tour of your dashboard.",
                Icons.explore_rounded,
                () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onStartTour?.call();
                },
              ),
            if (onStartTour != null) const SizedBox(height: 12),

            if (onStartClassesTour != null) ...[
              _buildTourCard(
                context,
                "How to Manage Classes",
                "Create sections and add students to your classes.",
                Icons.people_outline,
                () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onStartClassesTour?.call();
                },
              ),
              const SizedBox(height: 12),
            ],

            if (onStartTeachersTour != null) ...[
              _buildTourCard(
                context,
                "How to Manage Teachers",
                "Assign subject teachers and manage class schedules.",
                Icons.school_outlined,
                () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onStartTeachersTour?.call();
                },
              ),
              const SizedBox(height: 12),
            ],

            if (onStartGradeTour != null) ...[
              _buildTourCard(
                context,
                "How to Enter Grades",
                "Input, edit, and view student grades efficiently.",
                Icons.grade_rounded,
                () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onStartGradeTour?.call();
                },
              ),
              const SizedBox(height: 12),
            ],

            if (onStartScheduleTour != null)
              _buildTourCard(
                context,
                "How to View Schedule",
                "Understand your daily timetable and class timings.",
                Icons.schedule_outlined,
                () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                  onStartScheduleTour?.call();
                },
              ),


            
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            _buildSectionHeader("Contact Support"),
            const SizedBox(height: 16),
            _buildTourCard(
              context,
              "Report a Bug",
              "Encountered an issue? Let us know so we can fix it.",
              Icons.bug_report_outlined,
              () {
                showDialog(
                  context: context,
                  builder: (context) => BugReportDialog(userType: userType),
                );
              },
            ),

            const SizedBox(height: 40),
            Center(
              child: Text(
                "Version 1.0.0 • Made with ❤️ for ${userType == 'Teacher' ? 'Teachers' : 'Students'}",
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: HexColor("#116754"),
      ),
    );
  }

  Widget _buildTourCard(
    BuildContext context, 
    String title, 
    String description, 
    IconData icon, 
    VoidCallback onTap,
    {bool isComingSoon = false}
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: HexColor("#116754").withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: HexColor("#116754")),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        trailing: isComingSoon 
          ? const Text("Soon", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12))
          : Icon(Icons.play_circle_fill_rounded, color: HexColor("#116754")),
        onTap: isComingSoon ? null : onTap,
      ),
    );
  }
}
