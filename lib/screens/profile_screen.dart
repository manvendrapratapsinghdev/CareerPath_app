import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

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

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _selectedStream;
  bool _isSaving = false;

  static const _streams = [
    ('science', 'Science', Icons.science, Color(0xFF4CAF50)),
    ('commerce', 'Commerce', Icons.account_balance, Color(0xFF2196F3)),
    ('art', 'Art', Icons.palette, Color(0xFFFF9800)),
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingProfile?.name ?? '',
    );
    _selectedStream = widget.existingProfile?.stream;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStream == null) return;

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

  void _skip() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingProfile != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Profile' : 'Create Profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero icon
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.school,
                      size: 40,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isEditing ? 'Update your details' : 'Tell us about yourself',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'Select your 10+2 stream',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ..._streams.map(
                  (stream) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      color: _selectedStream == stream.$1
                          ? stream.$4.withValues(alpha: 0.12)
                          : colorScheme.surfaceContainerLow,
                      child: InkWell(
                        onTap: () => setState(() => _selectedStream = stream.$1),
                        borderRadius: BorderRadius.circular(14),
                        child: RadioListTile<String>(
                          title: Row(
                            children: [
                              Icon(stream.$3, color: stream.$4, size: 22),
                              const SizedBox(width: 12),
                              Text(stream.$2),
                            ],
                          ),
                          value: stream.$1,
                          groupValue: _selectedStream,
                          onChanged: (value) {
                            setState(() => _selectedStream = value);
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          activeColor: stream.$4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Save'),
                ),
                const SizedBox(height: 12),
                if (!isEditing)
                  OutlinedButton(
                    onPressed: _isSaving ? null : _skip,
                    child: const Text('Skip'),
                  ),
                const SizedBox(height: 32),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Developed by SoLA under ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
