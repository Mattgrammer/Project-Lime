import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

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
              'Learning Information Management Environment',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
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
                    color: HexColor("#116754").withOpacity(0.3),
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

            _buildInfoCard(
              Icons.lightbulb,
              'Mission',
              'To provide an efficient and user-friendly platform for managing academic information and enhancing the learning experience.',
            ),
            const SizedBox(height: 12),

            _buildInfoCard(
              Icons.star,
              'Features',
              'Student profiles, enrollment management, class schedules, grade tracking, messaging system, and more.',
            ),
            const SizedBox(height: 12),

            _buildInfoCard(
              Icons.security,
              'Privacy',
              'Your data is securely stored and protected. We prioritize student privacy and data security.',
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
              'support@lime.edu',
            ),
            const SizedBox(height: 12),

            _buildContactCard(
              Icons.phone,
              'Phone',
              '+63 XXX XXX XXXX',
            ),
            const SizedBox(height: 12),

            _buildContactCard(
              Icons.language,
              'Website',
              'www.lime.edu',
            ),

            const SizedBox(height: 32),

            Center(
              child: Text(
                '© 2024 LIME. All rights reserved.',
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

  Widget _buildInfoCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HexColor("#0F4C7F").withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: HexColor("#0F4C7F")),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
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
            color: Colors.black.withOpacity(0.05),
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
              color: HexColor("#1e824c").withOpacity(0.1),
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