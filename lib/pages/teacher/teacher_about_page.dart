import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';

class TeacherAboutPage extends StatelessWidget {
  const TeacherAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About LIME',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: HexColor("#0F4C7F"),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Learners Integrated Management Environment',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 32),

            // App Info Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    HexColor("#116754"),
                    HexColor("#1e824c"),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: HexColor("#116754").withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.school,
                    size: 64,
                    color: Colors.white,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'LIME',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'About the System',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: HexColor("#0F4C7F"),
              ),
            ),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                'LIME is a comprehensive learning information management environment designed to streamline academic workflows and enhance the educational experience for both students and teachers.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[800],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Contact & Support',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: HexColor("#0F4C7F"),
              ),
            ),
            const SizedBox(height: 16),

            _buildContactCard(
              Icons.email,
              'Email',
              'projectlimegroup@gmail.com',
            ),
            const SizedBox(height: 12),

            _buildContactCard(
              Icons.phone,
              'Phone',
              '+63 928 153 9498',
            ),

            const SizedBox(height: 32),

            Center(
              child: Text(
                '© 2026 LIME. All rights reserved.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildContactCard(IconData icon, String title, String info) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HexColor("#1e824c").withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: HexColor("#1e824c")),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
