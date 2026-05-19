import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/pin_login_service.dart';

import 'package:flutter/services.dart';

class PinEntryPage extends StatefulWidget {
  final VoidCallback onSuccess;
  
  const PinEntryPage({super.key, required this.onSuccess});

  @override
  State<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends State<PinEntryPage> {
  String _pin = '';
  bool _isError = false;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    // Request focus once the widget is built so keyboard events are captured immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onDigitPress(String digit) {
    if (_pin.length < 4) {
      setState(() {
        _isError = false;
        _pin += digit;
      });
      
      if (_pin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _isError = false;
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  Future<void> _verifyPin() async {
    // Simulate tiny delay for UX
    await Future.delayed(const Duration(milliseconds: 300));
    
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final isValid = await PinLoginService.verifyPin(user.uid, _pin);
      if (isValid) {
        widget.onSuccess();
      } else {
        setState(() {
          _isError = true;
          _pin = '';
        });
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incorrect PIN')),
          );
        }
      }
    } else {
       // Should not happen, but if so, logout
       await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    // AuthWrapper in main.dart will handle the redirect to SignIn
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.backspace) {
              _onDelete();
            } else {
              // Check for digits 0-9
              final character = event.character;
              if (character != null && int.tryParse(character) != null) {
                 _onDigitPress(character);
              }
            }
          }
        },
        child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;
          final isMobile = screenWidth < 600;
          final verticalScale = (screenHeight / 950).clamp(0.65, 1.0);
          
          double maxWidth;
          if (isMobile) {
            maxWidth = double.infinity;
          } else {
            maxWidth = (screenWidth * 0.4).clamp(400.0, 450.0);
          }
          
          final borderRadius = isMobile ? 20.0 : 28.0;
          final headerFontSize = (isMobile ? 28.0 : 32.0) * verticalScale;
          final welcomeFontSize = (isMobile ? 28.0 : 26.0) * verticalScale;
          final subtitleFontSize = (isMobile ? 16.0 : 15.0) * verticalScale;
          final imageHeight = (isMobile ? 100.0 : 120.0) * verticalScale;
          final contentPadding = isMobile ? 24.0 : 40.0;
          
          return Scaffold(
            backgroundColor: isMobile ? Colors.white : null,
            appBar: isMobile
                ? AppBar(
                    title: Text('Enter PIN', style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
                    backgroundColor: HexColor("#116754"),
                    foregroundColor: Colors.white,
                    centerTitle: true,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                  )
                : null,
            body: Stack(
              children: [
                // Background gradient (desktop/tablet only)
                if (!isMobile)
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          HexColor("#2a7925"),
                          HexColor("#abad23"),
                        ],
                      ),
                    ),
                  ),
                
                // Content
                Center(
                  child: SingleChildScrollView(
                    padding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 24),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 0 : 24),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        decoration: isMobile
                            ? null
                            : BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(borderRadius),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 60,
                                    offset: const Offset(0, 15),
                                  ),
                                ],
                              ),
                        clipBehavior: isMobile ? Clip.none : Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header (Desktop/Tablet only)
                            if (!isMobile)
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(vertical: 22 * verticalScale),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      HexColor("#116754"),
                                      HexColor("#1a8a6f"),
                                    ],
                                  ),
                                ),
                                child: Text(
                                  'Enter PIN',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.merriweather(
                                    color: Colors.white,
                                    fontSize: headerFontSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            
                            // Content
                            Padding(
                              padding: EdgeInsets.all(contentPadding),
                              child: Column(
                                children: [
                                  // Logo
                                  Image.asset(
                                    'lib/pages/assets/LIME ASSETS/lime.png',
                                    height: imageHeight,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Icon(Icons.lock_outline, size: 60, color: HexColor("#116754")),
                                  ),
                                  SizedBox(height: 20 * verticalScale),
                                  
                                  // Welcome text
                                  Text(
                                    'Welcome Back!',
                                    style: GoogleFonts.dmSerifText(
                                      color: HexColor("#116754"),
                                      fontSize: welcomeFontSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 8 * verticalScale),
                                  Text(
                                    'Enter your PIN to continue',
                                    style: TextStyle(
                                      color: const Color(0xFF666666),
                                      fontSize: subtitleFontSize,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 32 * verticalScale),
                                  
                                  // Simple PIN dots
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(4, (index) {
                                      final isFilled = index < _pin.length;
                                      return Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 12),
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: isFilled
                                              ? (_isError ? Colors.redAccent : HexColor("#116754"))
                                              : Colors.transparent,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _isError ? Colors.redAccent : HexColor("#116754"),
                                            width: 2,
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                  SizedBox(height: 32 * verticalScale),
                                  
                                  // Numpad
                                  _buildNumPad(),
                                  
                                  SizedBox(height: 20 * verticalScale),
                                  
                                  // Forgot PIN link
                                  TextButton(
                                    onPressed: _logout,
                                    child: Text(
                                      'Forgot PIN? Sign Out',
                                      style: TextStyle(
                                        color: HexColor("#116754"),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildNumPad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          _buildRow(['1', '2', '3']),
          const SizedBox(height: 16),
          _buildRow(['4', '5', '6']),
          const SizedBox(height: 16),
          _buildRow(['7', '8', '9']),
          const SizedBox(height: 16),
          _buildRow([null, '0', 'back']),
        ],
      ),
    );
  }

  Widget _buildRow(List<String?> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        if (key == null) return const SizedBox(width: 70, height: 70);
        
        if (key == 'back') {
          return SizedBox(
            width: 70, 
            height: 70,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _onDelete,
                borderRadius: BorderRadius.circular(35),
                child: Container(
                  alignment: Alignment.center,
                  child: Icon(Icons.backspace_rounded, color: HexColor("#116754"), size: 24),
                ),
              ),
            ),
          );
        }

        return SizedBox(
          width: 70,
          height: 70,
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(35),
            child: InkWell(
              onTap: () => _onDigitPress(key),
              borderRadius: BorderRadius.circular(35),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: HexColor("#116754").withValues(alpha: 0.5), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  key,
                  style: GoogleFonts.dmSans(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: HexColor("#116754"),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
