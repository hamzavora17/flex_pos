import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';

import 'features/admin/presentation/admin_dashboard_screen.dart';
import 'features/cashier/presentation/new_sale_screen.dart';
import 'features/cashier/presentation/employee_dashboard.dart';
import 'features/manager/presentation/manager_dashboard.dart';
import 'models/user_role.dart';
import 'services/cashier_dashboard_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const FlexPOSApp());
}

class FlexPOSApp extends StatelessWidget {
  const FlexPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlexPOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003366),
          primary: const Color(0xFF003366),
          secondary: const Color(0xFF8DB600),
        ),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const SplashScreen(),
    );
  }
}

Future<UserRole?> _resolveUserRole(String userId) async {
  try {
    final profileData = await Supabase.instance.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    if (profileData == null || profileData['role'] == null) {
      return null;
    }

    final roleStr = profileData['role'].toString();
    return UserRole.fromString(roleStr);
  } catch (e) {
    debugPrint('Error resolving user role for $userId: $e');
    return null;
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progressValue = 0.0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      setState(() {
        _progressValue += 0.01;
        if (_progressValue >= 1.0) {
          _timer.cancel();
          _navigateToHome();
        }
      });
    });
  }

  Future<void> _navigateToHome() async {
    if (!mounted) return;

    if (SupabaseConfig.isConfigured) {
      final session = Supabase.instance.client.auth.currentSession;
      final userId = session?.user.id;
      if (userId != null) {
        try {
          final userRole = await _resolveUserRole(userId);

          if (mounted && userRole != null) {
            if (userRole.isAdmin) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const AdminDashboard()),
                (route) => false,
              );
              return;
            } else if (userRole.isManager) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const ManagerDashboard()),
                (route) => false,
              );
              return;
            } else if (userRole.isCashier) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const EmployeeDashboard()),
                (route) => false,
              );
              return;
            }
          }
        } catch (_) {
          // On error, fall back to LoginPage
        }
      }
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double logoSize = 240.0;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Hero(
              tag: 'app_logo',
              child: Image.asset(
                'assets/FlexPOS_logo_upscaled.png',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: 200,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progressValue,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8DB600)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${(_progressValue * 100).toInt()}%',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _constructFlexPosEmail(String rawInput) {
  var trimmed = rawInput.trim().toLowerCase();
  while (trimmed.endsWith('@flexpos.com')) {
    trimmed = trimmed.substring(0, trimmed.length - '@flexpos.com'.length).trim();
  }
  if (trimmed.endsWith('@')) {
    trimmed = trimmed.substring(0, trimmed.length - 1).trim();
  }
  return '$trimmed@flexpos.com';
}

String? _validateFlexPosUsername(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '⚠ Please enter your username';
  }
  var clean = value.trim().toLowerCase();
  while (clean.endsWith('@flexpos.com')) {
    clean = clean.substring(0, clean.length - '@flexpos.com'.length).trim();
  }
  if (clean.endsWith('@')) {
    clean = clean.substring(0, clean.length - 1).trim();
  }
  if (clean.isEmpty) {
    return '⚠ Please enter a valid username';
  }
  if (clean.contains('@')) {
    return '⚠ Username should not contain "@"';
  }
  if (RegExp(r'\s').hasMatch(clean)) {
    return '⚠ Username should not contain spaces';
  }
  if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(clean)) {
    return '⚠ Please enter a valid FlexPOS username';
  }
  return null;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _formSubmitted = false;

  final _formKey = GlobalKey<FormState>();
  String? _authError;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
  }

  Future<void> _login() async {
    if (_authError != null) setState(() => _authError = null);
    
    setState(() => _formSubmitted = true);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final email = _constructFlexPosEmail(_emailController.text);
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    if (!SupabaseConfig.isConfigured) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _authError = '⚠ Supabase is not configured. Please check your application configuration.';
        });
      }
      return;
    }

    try {
      final authResponse = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = authResponse.user;
      if (user == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _authError = '⚠ Authentication failed. Please try again.';
          });
        }
        return;
      }

      // Resolve user role exclusively from public.profiles.role
      final userRole = await _resolveUserRole(user.id);

      if (userRole == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _authError = '⚠ Unable to resolve user profile role. Please contact your administrator.';
          });
        }
        return;
      }

      if (userRole.isCashier) {
        try {
          await CashierDashboardService().startShiftOnLogin(user.id);
        } catch (_) {}
      }

      if (mounted) {
        if (userRole.isAdmin) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const AdminDashboard()),
            (route) => false,
          );
        } else if (userRole.isManager) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const ManagerDashboard()),
            (route) => false,
          );
        } else if (userRole.isCashier) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const EmployeeDashboard()),
            (route) => false,
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _authError = '⚠ ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _authError = '⚠ An unexpected error occurred: ${e.toString()}';
        });
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => const _ForgotPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 900;
          return Row(
            children: [
              if (isDesktop)
                const Expanded(
                  flex: 11,
                  child: _BrandPanel(),
                ),
              Expanded(
                flex: 9,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: _buildLoginForm(isDesktop),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginForm(bool isDesktop) {
    return Form(
      key: _formKey,
      autovalidateMode: _formSubmitted 
          ? AutovalidateMode.onUserInteraction 
          : AutovalidateMode.disabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        if (!isDesktop) ...[
          Center(
            child: Hero(
              tag: 'app_logo',
              child: Image.asset(
                'assets/FlexPOS_logo_upscaled.png',
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.storefront_rounded, size: 48, color: Color(0xFF003366)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
        const Text(
          'WELCOME BACK',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sign in to FlexPOS',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your credentials to access your POS terminal.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        const _TerminalStatusBadge(),
        const SizedBox(height: 32),
        _AuthTextField(
          controller: _emailController,
          label: 'USERNAME / EMAIL',
          hint: 'username',
          icon: Icons.person_outline_rounded,
          fixedSuffixText: '@flexpos.com',
          keyboardType: TextInputType.text,
          maxLength: 30,
          enabled: !_isLoading,
          validator: _validateFlexPosUsername,
          onChanged: (val) {
            if (_authError != null) setState(() => _authError = null);
          },
        ),
        const SizedBox(height: 20),
        _AuthTextField(
          controller: _passwordController,
          label: 'PASSWORD',
          hint: 'Enter your password',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          isObscured: _obscurePassword,
          onVisibilityChanged: (show) => setState(() => _obscurePassword = show),
          enabled: !_isLoading,
          onSubmitted: (_) => _login(),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '⚠ Please enter your password';
            }
            if (value.length < 6) {
              return '⚠ Password must be at least 6 characters';
            }
            return null;
          },
          onChanged: (val) {
            if (_authError != null) setState(() => _authError = null);
          },
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: _showForgotPasswordDialog,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'Forgot password?',
                style: TextStyle(
                  color: Color(0xFF003366),
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        if (_authError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _authError!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _buildSubmitButton(),
        const SizedBox(height: 32),
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'SECURE ACCESS',
                style: TextStyle(
                  color: const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
          ],
        ),
        const SizedBox(height: 24),
        const Center(child: _SecurityBadge()),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'FlexPOS • Point of Sale System v2.4',
            style: TextStyle(
              color: const Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF003366),
              Color(0xFF001A33),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF003366).withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _login,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Sign In to Terminal',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TerminalStatusBadge extends StatelessWidget {
  const _TerminalStatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF8DB600).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF8DB600).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF8DB600),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'POS Terminal • Online',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF003366),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final bool enabled;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool? isObscured;
  final String? fixedSuffixText;
  final void Function(bool)? onVisibilityChanged;
  final void Function(String)? onSubmitted;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.enabled = true,
    this.keyboardType,
    this.maxLength,
    this.isObscured,
    this.fixedSuffixText,
    this.onVisibilityChanged,
    this.onSubmitted,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget? suffixWidget;
    if (fixedSuffixText != null) {
      suffixWidget = Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              fixedSuffixText!,
              style: const TextStyle(
                color: Color(0xFF003366),
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      );
    } else if (isPassword) {
      suffixWidget = IconButton(
        icon: Icon(
          (isObscured ?? true)
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
          color: const Color(0xFF64748B),
        ),
        onPressed: () => onVisibilityChanged?.call(!(isObscured ?? true)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: isPassword ? (isObscured ?? true) : false,
          keyboardType: keyboardType,
          maxLength: maxLength,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          onChanged: onChanged,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            counterText: "",
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 15,
              fontWeight: FontWeight.normal,
            ),
            prefixIcon: Icon(icon, size: 22, color: const Color(0xFF64748B)),
            suffixIcon: suffixWidget,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            errorStyle: const TextStyle(
              color: Colors.red,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
            errorMaxLines: 2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF003366), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _SecurityBadge extends StatelessWidget {
  const _SecurityBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.gpp_good_outlined, size: 16, color: Color(0xFF8DB600)),
        SizedBox(width: 6),
        Text(
          'Protected by FlexPOS Security',
          style: TextStyle(
            color: Color(0xFF475569),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF001A33),
      ),
      child: Stack(
        children: [
          // Background Gradient & Glows
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.5, -0.5),
                  radius: 1.5,
                  colors: [
                    const Color(0xFF003366),
                    const Color(0xFF001A33).withValues(alpha: 0.9),
                    const Color(0xFF001122),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -150,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8DB600).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Main Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                      BoxShadow(
                        color: const Color(0xFF8DB600).withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Hero(
                    tag: 'app_logo',
                    child: Image.asset(
                      'assets/FlexPOS_logo_upscaled.png',
                      height: 52,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.storefront_rounded, color: Color(0xFF003366), size: 40),
                          SizedBox(width: 12),
                          Text(
                            'FlexPOS',
                            style: TextStyle(
                              color: Color(0xFF003366),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Smarter selling\nstarts here.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Manage sales, inventory and your business\nfrom one powerful workspace.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 64),
              ],
            ),
          ),
          
          // Floating Abstract UI Elements
          const Positioned(
            right: 64,
            top: 120,
            child: _MetricPreviewCard(
              title: "Today's Sales",
              value: "₹4,289.50",
              icon: Icons.trending_up,
              color: Color(0xFF8DB600),
              delay: 0.2,
            ),
          ),
          const Positioned(
            right: -20,
            top: 240,
            child: _MetricPreviewCard(
              title: "Active Orders",
              value: "24",
              icon: Icons.receipt_long,
              color: Colors.blueAccent,
              delay: 0.4,
            ),
          ),
          const Positioned(
            right: 140,
            top: 360,
            child: _MetricPreviewCard(
              title: "Secure Terminal",
              value: "Encrypted",
              icon: Icons.lock_outline,
              color: Colors.tealAccent,
              delay: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPreviewCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double delay;

  const _MetricPreviewCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.delay,
  });

  @override
  State<_MetricPreviewCard> createState() => _MetricPreviewCardState();
}

class _MetricPreviewCardState extends State<_MetricPreviewCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    Future.delayed(Duration(milliseconds: (widget.delay * 1000).toInt()), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Image.asset(
                'assets/FlexPOS_logo_upscaled.png',
                height: 24,
                errorBuilder: (_, _, _) => const Icon(Icons.store, size: 20, color: Color(0xFF003366)),
              ),
            ),
            const SizedBox(width: 12),
            const Text('FlexPOS Home', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF003366),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              if (SupabaseConfig.isConfigured) {
                await Supabase.instance.client.auth.signOut();
              }
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome to FlexPOS',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF003366)),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage your business with ease',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                children: [
                  _buildHomeCard(context, 'New Sale', Icons.add_shopping_cart, const Color(0xFF8DB600), onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSaleScreen()));
                  }),
                  _buildHomeCard(context, 'Inventory', Icons.inventory_2_outlined, const Color(0xFF003366)),
                  _buildHomeCard(context, 'Reports', Icons.bar_chart_outlined, Colors.orange),
                  _buildHomeCard(context, 'Settings', Icons.settings_outlined, Colors.blueGrey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeCard(BuildContext context, String title, IconData icon, Color color, {VoidCallback? onTap}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminDashboardScreen();
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitted = false;
  bool _isLoading = false;
  bool _formSubmitted = false;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _formSubmitted = true);
    
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1000));
    
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isSubmitted = true;
      });
      // Re-trigger animation for success state
      _animController.reset();
      _animController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: SingleChildScrollView(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(32),
              child: _isSubmitted ? _buildSuccessState() : _buildFormState(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      autovalidateMode: _formSubmitted 
          ? AutovalidateMode.onUserInteraction 
          : AutovalidateMode.disabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF003366).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_outlined, color: Color(0xFF003366), size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Forgot your password?',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Enter the email address associated with your FlexPOS account. Our administrator will help you reset your password.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          _AuthTextField(
            controller: _emailController,
            label: 'USERNAME / EMAIL',
            hint: 'username',
            icon: Icons.person_outline_rounded,
            fixedSuffixText: '@flexpos.com',
            keyboardType: TextInputType.text,
            maxLength: 30,
            enabled: !_isLoading,
            onSubmitted: (_) => _submit(),
            validator: _validateFlexPosUsername,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Password resets are handled by your FlexPOS administrator.',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Please contact your administrator after submitting your email.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003366),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Contact Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF8DB600).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF8DB600), size: 48),
        ),
        const SizedBox(height: 24),
        const Text(
          'Request Submitted',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your password reset request has been noted. Please contact your FlexPOS administrator for further assistance.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 14.5,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF003366),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}
