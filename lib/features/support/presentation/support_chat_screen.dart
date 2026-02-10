// support_chat_screen.dart
// In-app support chat UI (User <-> Admin) using SupportRepository (Firestore).

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/data/support_repository.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _repo = SupportRepository();
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  int _lastMsgCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    try {
      await _repo.sendMyMessage(text);
      if (!mounted) return;
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context
                .tr('support.send_failed', args: {'error': e.toString()}))),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final td = Directionality.of(context);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('support.title'))),
        body: Center(child: Text(context.tr('support.login_required'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('support.title')),
        actions: [
          IconButton(
            tooltip: context.tr('support.refresh'),
            onPressed: () async {
              try {
                await _repo.ensureMyTicket();
              } catch (_) {}
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<SupportMessage>>(
              stream: _repo.watchMyMessages(),
              builder: (context, snapshot) {
                final msgs = snapshot.data ?? const <SupportMessage>[];

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.tr('support.load_failed',
                          args: {'error': snapshot.error.toString()})),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    msgs.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (msgs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(context.tr('support.empty')),
                    ),
                  );
                }

                // Auto scroll when new messages arrive.
                if (msgs.length != _lastMsgCount) {
                  _lastMsgCount = msgs.length;
                  _scrollToBottom();
                }

                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    final mine = m.senderId == user.uid && !m.fromAdmin;
                    final bubbleColor =
                        mine ? cs.primaryContainer : cs.surfaceContainerHighest;
                    final bubbleRadius = BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft:
                          mine ? const Radius.circular(16) : Radius.zero,
                      bottomRight:
                          mine ? Radius.zero : const Radius.circular(16),
                    );

                    final ts = m.createdAt;
                    final time = (ts == null)
                        ? ''
                        : '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Align(
                        // IMPORTANT: physical alignment (always right for mine)
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                          ),
                          child: Column(
                            // Force physical alignment inside the bubble column
                            // so RTL does not flip "start/end".
                            textDirection: TextDirection.ltr,
                            crossAxisAlignment: mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: bubbleColor,
                                  borderRadius: bubbleRadius,
                                ),
                                child: Text(
                                  m.text,
                                  textAlign: td == TextDirection.rtl
                                      ? TextAlign.right
                                      : TextAlign.left,
                                ),
                              ),
                              if (time.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  time,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: cs.onSurface
                                            .withValues(alpha: 0.55),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Composer
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      textDirection: td,
                      decoration: InputDecoration(
                        hintText: context.tr('support.hint'),
                        filled: true,
                        fillColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.60),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: cs.primary.withValues(alpha: 0.9),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    tooltip: context.tr('support.send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
