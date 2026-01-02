import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome Back!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: HexColor("#0F4C7F"),
              ),
            ),
            const SizedBox(height: 24),

            // Quick Stats Cards
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Enrolled Subjects',
                    '8',
                    Icons.book,
                    HexColor("#0F4C7F"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Upcoming Classes',
                    '3',
                    Icons.schedule,
                    HexColor("#1e824c"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Average Grade',
                    '92.5',
                    Icons.grade,
                    HexColor("#d4af37"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Unread Messages',
                    '5',
                    Icons.mail,
                    HexColor("#e63946"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Recent Announcements
            Text(
              'Recent Announcements',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: HexColor("#0F4C7F"),
              ),
            ),
            const SizedBox(height: 16),
            _buildAnnouncementCard(
              'School Event',
              'Annual Science Fair on January 15, 2025',
              Icons.event,
            ),
            const SizedBox(height: 12),
            _buildAnnouncementCard(
              'Academic Update',
              'Midterm exam schedules are now available',
              Icons.info,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(String title, String description, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
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
}