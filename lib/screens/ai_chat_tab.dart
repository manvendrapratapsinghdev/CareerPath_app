import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../controllers/ai_chat_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/ai_chat.dart';
import '../services/ai_chat_repository.dart';
import '../services/analytics_service.dart';

class AiChatTab extends StatefulWidget {
  final AiChatRepository repository;
  final AnalyticsService? analyticsService;
  final ValueChanged<AiChatSource?> onOpenExplore;
  final String? streamId;

  const AiChatTab({
    super.key,
    required this.repository,
    required this.onOpenExplore,
    this.analyticsService,
    this.streamId,
  });

  @override
  State<AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends State<AiChatTab> {
  late final AiChatController _chatController;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _chatController = AiChatController(widget.repository)
      ..addListener(_onChatChanged);
    widget.analyticsService?.logEvent('ai_chat_opened');
  }

  @override
  void dispose() {
    _chatController
      ..removeListener(_onChatChanged)
      ..dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send([String? suggestedText]) async {
    final text = (suggestedText ?? _textController.text).trim();
    if (text.isEmpty ||
        text.length > AiChatController.maxInputCharacters ||
        _chatController.isSending ||
        _chatController.chatBlocked) {
      return;
    }

    _textController.clear();
    FocusScope.of(context).unfocus();
    widget.analyticsService?.logEvent('ai_chat_prompt_sent', {
      'turn_count':
          _chatController.messages
              .where((message) => message.role == AiChatRole.user)
              .length +
          1,
      'locale': Localizations.localeOf(context).languageCode,
    });
    await _chatController.sendMessage(
      text: text,
      locale: Localizations.localeOf(context).languageCode,
      streamId: widget.streamId,
    );
    if (!mounted || _chatController.messages.isEmpty) return;
    final last = _chatController.messages.last;
    widget.analyticsService?.logEvent(
      last.isError ? 'ai_chat_error' : 'ai_chat_answer_completed',
      {
        'status': last.status?.name ?? 'error',
        'source_count': last.sources.length,
      },
    );
  }

  Future<void> _retry() async {
    widget.analyticsService?.logEvent('ai_chat_retry');
    await _chatController.retryLast(
      locale: Localizations.localeOf(context).languageCode,
      streamId: widget.streamId,
    );
  }

  Future<void> _confirmNewChat() async {
    final l = AppLocalizations.of(context)!;
    if (!_chatController.hasMessages) {
      _startNewChat();
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.ai_newChatTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l.ai_newChatMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.ai_startNew),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.ai_cancel),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) _startNewChat();
  }

  void _startNewChat() {
    _chatController.startNewChat();
    _textController.clear();
    widget.analyticsService?.logEvent('ai_chat_new_started');
  }

  void _openExplore([AiChatSource? source]) {
    widget.analyticsService?.logEvent('ai_chat_source_opened');
    widget.onOpenExplore(source);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        _ChatHeader(onNewChat: _confirmNewChat, onClearChat: _confirmNewChat),
        Expanded(
          child: _chatController.hasMessages
              ? _buildConversation(l)
              : _ChatEmptyState(onPromptSelected: _send),
        ),
        if (_chatController.chatBlocked)
          _BlockedNotice(onOpenExplore: () => _openExplore())
        else
          _ChatComposer(
            controller: _textController,
            isSending: _chatController.isSending,
            onSend: _send,
            onStop: _chatController.stop,
          ),
      ],
    );
  }

  Widget _buildConversation(AppLocalizations l) {
    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.xl,
      ),
      itemCount:
          _chatController.messages.length + (_chatController.isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _chatController.messages.length) {
          return const _ThinkingIndicator();
        }
        final message = _chatController.messages[index];
        if (message.isError) {
          return _ChatErrorCard(
            onRetry: _retry,
            onOpenExplore: () => _openExplore(),
          );
        }
        return _MessageBubble(
          message: message,
          onOpenExplore: _openExplore,
          onSuggestedPrompt: _send,
        );
      },
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final VoidCallback onNewChat;
  final VoidCallback onClearChat;

  const _ChatHeader({required this.onNewChat, required this.onClearChat});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppRadius.mdAll,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              semanticLabel: 'CareerPath AI',
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.ai_title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  l.ai_subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNewChat,
            tooltip: l.ai_newChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: l.ai_clearChat,
            onSelected: (_) => onClearChat(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded),
                    const SizedBox(width: AppSpacing.md),
                    Text(l.ai_clearChat),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  final ValueChanged<String> onPromptSelected;

  const _ChatEmptyState({required this.onPromptSelected});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final prompts = [
      l.ai_starterScience,
      l.ai_starterCompare,
      l.ai_starterDesign,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: AppShadows.medium(colorScheme.primary),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l.ai_subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l.ai_scopeNotice,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ...prompts.map(
            (prompt) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onPromptSelected(prompt),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(prompt),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AiChatMessage message;
  final ValueChanged<AiChatSource?> onOpenExplore;
  final ValueChanged<String> onSuggestedPrompt;

  const _MessageBubble({
    required this.message,
    required this.onOpenExplore,
    required this.onSuggestedPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiChatRole.user;
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isWarning = message.status == AiChatStatus.policyWarning;
    final isInsufficient = message.status == AiChatStatus.insufficientData;

    return Semantics(
      label: isUser
          ? 'You: ${message.content}'
          : 'AI Guide: ${message.content}',
      excludeSemantics: true,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
          ),
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: isUser
                ? colorScheme.primary
                : isWarning
                ? AppColors.warning.withValues(alpha: 0.12)
                : colorScheme.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadius.lg),
              topRight: const Radius.circular(AppRadius.lg),
              bottomLeft: Radius.circular(isUser ? AppRadius.lg : AppRadius.sm),
              bottomRight: Radius.circular(
                isUser ? AppRadius.sm : AppRadius.lg,
              ),
            ),
            border: isUser
                ? null
                : Border.all(
                    color: isWarning
                        ? AppColors.warning.withValues(alpha: 0.5)
                        : colorScheme.outlineVariant,
                  ),
            boxShadow: isUser ? null : AppShadows.soft(colorScheme.shadow),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isUser ? colorScheme.onPrimary : null,
                  height: 1.45,
                ),
              ),
              if (!isUser && message.sources.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l.ai_sources,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: message.sources
                      .map(
                        (source) => ActionChip(
                          avatar: const Icon(Icons.explore_outlined, size: 17),
                          label: Text(source.title),
                          onPressed: () => onOpenExplore(source),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (!isUser) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l.ai_copy,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: message.content),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(l.ai_copied)));
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                ),
              ],
              if (isInsufficient) ...[
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => onOpenExplore(null),
                    icon: const Icon(Icons.explore_rounded),
                    label: Text(l.ai_openExplore),
                  ),
                ),
              ],
              if (!isUser && message.suggestedPrompts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: message.suggestedPrompts
                      .take(3)
                      .map(
                        (prompt) => ActionChip(
                          label: Text(prompt),
                          onPressed: () => onSuggestedPrompt(prompt),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(l.ai_checkingData),
          ],
        ),
      ),
    );
  }
}

class _ChatErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onOpenExplore;

  const _ChatErrorCard({required this.onRetry, required this.onOpenExplore});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, color: colorScheme.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(l.ai_errorMessage)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                FilledButton.tonal(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text(l.ai_retry),
                ),
                TextButton(
                  onPressed: onOpenExplore,
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text(l.ai_openExplore),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedNotice extends StatelessWidget {
  final VoidCallback onOpenExplore;

  const _BlockedNotice({required this.onOpenExplore});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(AppSpacing.base),
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: AppRadius.lgAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.ai_blockedTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.ai_blockedMessage,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onOpenExplore,
              icon: const Icon(Icons.explore_rounded),
              label: Text(l.ai_openExplore),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const _ChatComposer({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onStop,
  });

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final length = widget.controller.text.characters.length;
    final isTooLong = length > AiChatController.maxInputCharacters;
    final canSend = length > 0 && !isTooLong && !widget.isSending;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.sm,
          AppSpacing.base,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: AiChatController.maxInputCharacters + 1,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l.ai_inputHint,
                      errorText: isTooLong
                          ? l.ai_messageTooLong(
                              AiChatController.maxInputCharacters,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filled(
                    tooltip: widget.isSending ? l.ai_stop : l.ai_inputHint,
                    onPressed: widget.isSending
                        ? widget.onStop
                        : canSend
                        ? widget.onSend
                        : null,
                    icon: Icon(
                      widget.isSending
                          ? Icons.stop_rounded
                          : Icons.arrow_upward_rounded,
                    ),
                  ),
                ),
              ],
            ),
            if (length >= 450)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '$length/${AiChatController.maxInputCharacters}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isTooLong
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
