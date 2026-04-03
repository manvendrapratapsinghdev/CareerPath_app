import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/profile_data.dart';
import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  final ProfileService profileService;
  final ProfileData? existingProfile;

  const ProfileScreen({
    super.key,
    required this.profileService,
    this.existingProfile,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  String? _selectedStream;
  bool _isSaving = false;
  bool _showStreamError = false;

  static const _streams = [
    ('science', 'Science', Icons.science_rounded, AppColors.science,
        'Physics, Chemistry, Biology, Math'),
    ('commerce', 'Commerce', Icons.account_balance_rounded, AppColors.commerce,
        'Accounting, Economics, Business'),
    ('art', 'Art', Icons.palette_rounded, AppColors.art,
        'Literature, History, Fine Arts'),
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingProfile?.name ?? '',
    );
    _selectedStream = widget.existingProfile?.stream;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _animController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existingProfile != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStream == null) {
      setState(() => _showStreamError = true);
      return;
    }

    setState(() => _isSaving = true);

    final success = await widget.profileService.saveProfile(
      _nameController.text.trim(),
      _selectedStream!,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save profile. Please try again.')),
      );
    }
  }

  void _skip() => Navigator.pushReplacementNamed(context, '/home');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Profile' : ''),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.base,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hero section
                    _buildHeroSection(colorScheme),
                    const SizedBox(height: AppSpacing.xxl),

                    // Name field
                    _buildNameField(),
                    const SizedBox(height: AppSpacing.xl),

                    // Stream selection
                    _buildStreamSection(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Actions
                    _buildActions(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Footer
                    _buildFooter(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: AppShadows.medium(AppColors.primaryLight),
          ),
          child: const Icon(Icons.school_rounded, size: 36, color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          _isEditing ? 'Update your details' : 'Welcome!',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _isEditing
              ? 'Keep your profile up to date'
              : 'Tell us a bit about yourself to get\npersonalized career suggestions',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your Name', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _nameController,
          autofocus: !_isEditing,
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your name';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildStreamSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your 10+2 Stream', style: Theme.of(context).textTheme.titleSmall),
        if (_showStreamError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Please select a stream',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        ..._streams.map((stream) => _buildStreamCard(stream)),
      ],
    );
  }

  Widget _buildStreamCard(
    (String, String, IconData, Color, String) stream,
  ) {
    final isSelected = _selectedStream == stream.$1;
    final color = stream.$4;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : Theme.of(context).cardTheme.color,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: isSelected ? color : Theme.of(context).colorScheme.outline,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.lgAll,
            onTap: () => setState(() {
              _selectedStream = stream.$1;
              _showStreamError = false;
            }),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Icon(stream.$3, color: color, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.base),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stream.$2,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: isSelected ? color : null,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stream.$5,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? color : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? color
                            : Theme.of(context).colorScheme.outline,
                        width: isSelected ? 0 : 1.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(_isEditing ? 'Update Profile' : 'Get Started'),
          ),
        ),
        if (!_isEditing) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: _isSaving ? null : _skip,
            child: const Text('Skip for now'),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Developed by SoLA under ',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://iitj.irins.org/profile/615298'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(
                'Dr Dinesh Mohan Joshi',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
