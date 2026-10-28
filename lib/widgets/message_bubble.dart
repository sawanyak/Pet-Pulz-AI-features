import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:pet_core/pet_core.dart';
import '../theme/pet_pulz_theme.dart';

/// One chat bubble. User messages sit on the right, assistant on the left.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    final Color background = message.isError
        ? scheme.errorContainer
        : isUser
            ? PetPulzTheme.primaryPurple
            : Colors.white;

    final Color foreground = message.isError
        ? scheme.onErrorContainer
        : isUser
            ? Colors.white
            : PetPulzTheme.textDark;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isUser ? 20 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 20),
            ),
            boxShadow: [
              BoxShadow(
                color: isUser
                    ? const Color(0x205B4BD8)
                    : const Color(0x104A3BB5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: isUser
                ? null
                : Border.all(color: const Color(0xFFDDD5FB), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildText(context, foreground),
              if (message.isError && onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context, Color foreground) {
    final baseStyle = TextStyle(color: foreground, height: 1.4, fontSize: 14);

    if (message.isUser || message.isError) {
      return SelectableText(message.text, style: baseStyle);
    }

    return MarkdownBody(
      data: message.text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: baseStyle,
        strong: baseStyle.copyWith(fontWeight: FontWeight.bold),
        em: baseStyle.copyWith(fontStyle: FontStyle.italic),
        listBullet: baseStyle,
        h1: baseStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
        h2: baseStyle.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
        h3: baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
        pPadding: const EdgeInsets.only(bottom: 6),
        blockSpacing: 6,
        code: baseStyle.copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.black12,
        ),
      ),
    );
  }
}
