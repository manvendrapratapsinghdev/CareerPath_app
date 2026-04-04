import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/profile_data.dart';
import '../services/analytics_service.dart';
import '../services/locale_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/feedback_service.dart';
import '../services/profile_service.dart';
import '../services/theme_service.dart';
import 'feedback_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ProfileService profileService;
  final ProfileData? existingProfile;
  final AnalyticsService? analyticsService;
  final FeedbackService? feedbackService;
  final ThemeService? themeService;
  final LocaleService? localeService;

  const ProfileScreen({
    super.key,
    required this.profileService,
    this.existingProfile,
    this.analyticsService,
    this.feedbackService,
    this.themeService,
    this.localeService,
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
      if (_isEditing) {
        widget.analyticsService?.logProfileUpdated(_selectedStream!);
      } else {
        widget.analyticsService?.logProfileCreated(_selectedStream!);
      }
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.profile_saveError)),
      );
    }
  }

  void _skip() {
    // If a stream is selected, name is mandatory — block skip
    if (_selectedStream != null && _nameController.text.trim().isEmpty) {
      _formKey.currentState!.validate();
      return;
    }
    widget.analyticsService?.logProfileSkipped();
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    final body = FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            _isEditing ? AppSpacing.base : MediaQuery.of(context).padding.top + AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.base,
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

                // Theme toggle (only when editing)
                if (_isEditing && widget.themeService != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _buildThemeSection(),
                ],

                // Language selector (only when editing)
                if (_isEditing && widget.localeService != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _buildLanguageSection(),
                ],

                // Feedback button (only when editing)
                if (_isEditing && widget.feedbackService != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _buildFeedbackButton(),
                ],
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
    );

    // Onboarding: full-screen Stack, no AppBar
    if (!_isEditing) {
      return Scaffold(
        body: body,
      );
    }

    // Edit mode: standard Scaffold with AppBar
    return Scaffold(
      appBar: AppBar(
        title: Text(l.profile_editProfileTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildHeroSection(ColorScheme colorScheme) {
    final l = AppLocalizations.of(context)!;
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
          _isEditing ? l.profile_updateDetailsTitle : l.profile_welcomeTitle,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _isEditing
              ? l.profile_updateDetailsSubtitle
              : l.profile_welcomeSubtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.profile_yourName, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _nameController,
          autofocus: !_isEditing,
          decoration: InputDecoration(
            hintText: l.profile_enterYourName,
            prefixIcon: const Icon(Icons.person_outline_rounded),
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return l.profile_nameValidationError;
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildStreamSection() {
    final l = AppLocalizations.of(context)!;
    // Build localized stream data from the static _streams constant
    final localizedStreams = _streams.map((stream) {
      final String localizedName;
      final String localizedDesc;
      switch (stream.$1) {
        case 'science':
          localizedName = l.profile_streamScience;
          localizedDesc = l.profile_streamScienceDesc;
        case 'commerce':
          localizedName = l.profile_streamCommerce;
          localizedDesc = l.profile_streamCommerceDesc;
        case 'art':
          localizedName = l.profile_streamArt;
          localizedDesc = l.profile_streamArtDesc;
        default:
          localizedName = stream.$2;
          localizedDesc = stream.$5;
      }
      return (stream.$1, localizedName, stream.$3, stream.$4, localizedDesc);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.profile_yourStream, style: Theme.of(context).textTheme.titleSmall),
        if (_showStreamError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.profile_selectStreamError,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        ...localizedStreams.map((stream) => _buildStreamCard(stream)),
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

  Widget _buildThemeSection() {
    final l = AppLocalizations.of(context)!;
    final currentMode = widget.themeService!.themeMode;
    final modes = [
      (ThemeMode.system, l.profile_themeSystem, Icons.brightness_auto_rounded),
      (ThemeMode.light, l.profile_themeLight, Icons.light_mode_rounded),
      (ThemeMode.dark, l.profile_themeDark, Icons.dark_mode_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.profile_appearance, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<ThemeMode>(
          segments: modes
              .map((m) => ButtonSegment(
                    value: m.$1,
                    label: Text(m.$2),
                    icon: Icon(m.$3),
                  ))
              .toList(),
          selected: {currentMode},
          onSelectionChanged: (selected) {
            widget.themeService!.setThemeMode(selected.first);
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildLanguageSection() {
    final l = AppLocalizations.of(context)!;
    final currentLocale = widget.localeService!.locale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.profile_language, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<Locale>(
          initialValue: currentLocale,
          isExpanded: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.language_rounded),
          ),
          items: LocaleService.supportedLocales.map((locale) {
            final name = LocaleService.localeNames[locale.languageCode] ??
                locale.languageCode;
            return DropdownMenuItem(
              value: locale,
              child: Text(name),
            );
          }).toList(),
          onChanged: (locale) {
            if (locale != null) {
              widget.localeService!.setLocale(locale);
              setState(() {});
            }
          },
        ),
      ],
    );
  }

  Widget _buildFeedbackButton() {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(Icons.feedback_outlined, color: colorScheme.primary),
        title: Text(l.profile_sendFeedback),
        subtitle: Text(l.profile_sendFeedbackSubtitle),
        trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FeedbackScreen(
                feedbackService: widget.feedbackService!,
                analyticsService: widget.analyticsService,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActions() {
    final l = AppLocalizations.of(context)!;
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
                : Text(_isEditing ? l.profile_updateProfile : l.profile_getStarted),
          ),
        ),
        if (!_isEditing) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: _isSaving ? null : _skip,
            child: Text(l.profile_skipForNow),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.bodySmall;
    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: l.profile_developedBy, style: style),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://www.linkedin.com/in/manvendrapratapsinghdev/'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text('Manvendra Pratap Singh', style: linkStyle),
            ),
          ),
          TextSpan(text: l.profile_under, style: style),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://iitj.irins.org/profile/615298'),
                mode: LaunchMode.externalApplication,
              ),
              child: Text('Dr Dinesh Mohan Joshi', style: linkStyle),
            ),
          ),
          TextSpan(text: l.profile_sola, style: style),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
