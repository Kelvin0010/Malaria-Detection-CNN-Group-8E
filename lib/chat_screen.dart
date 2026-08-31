import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// ─────────────────────────────────────────────
// IMPORTANT: Replace with your Gemini API key.
// Get a free key at https://aistudio.google.com/apikey
// ─────────────────────────────────────────────
const String _kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

// ─────────────────────────────────────────────
// System prompt that keeps the AI focused on
// concise, structured malaria health guidance.
// ─────────────────────────────────────────────
const String _kSystemPrompt = '''
You are "Doctor AI", a concise AI health assistant in the MalariaGuard app.

CRITICAL INSTRUCTIONS FOR CONCISENESS:
1. Be short, direct, and action-oriented. NO conversational filler, intros, or repeated disclaimers.
2. Structure EVERY response into these 3 compact sections:
   📌 **Direct Answer**: (1-2 short sentences max)
   💡 **Key Points**: (3 bullet points max, under 12 words per bullet)
   👨‍⚕️ **Next Step**: (1 sentence recommendation)
3. Keep the ENTIRE response under 120 words total.
4. Focus strictly on malaria causes, symptoms, diagnosis, prevention, treatment, or scan results.
5. If asked about unrelated topics, respond with 1 sentence declining and redirecting to malaria.
6. Never recommend specific drug dosages — always say "as prescribed by a doctor".
''';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}

class ChatScreen extends StatefulWidget {
  final String? scanResult;
  final double? confidence;

  const ChatScreen({
    super.key,
    this.scanResult,
    this.confidence,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  late AnimationController _dotController;

  // Gemini chat session (maintains conversation history)
  late final GenerativeModel _model;
  late ChatSession _chat;

  // Suggestion chips
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Initialize Gemini model with system instruction
    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: _kGeminiApiKey,
      systemInstruction: Content.system(_kSystemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: 250,
      ),
    );
    _chat = _model.startChat();

    _initializeChat();
  }

  @override
  void dispose() {
    _dotController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeChat() {
    // Welcome message (local — no API call needed)
    _messages.add(
      ChatMessage(
        text: "👋 Hello! I am **Doctor AI**, your Malaria Health Assistant.\n\n"
            "I can answer any question about malaria — symptoms, treatment, prevention, your scan results, and more. Ask me anything!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    // If scan context is available, add context-aware greeting
    if (widget.scanResult != null && widget.scanResult!.isNotEmpty) {
      final isParasitized = widget.scanResult == 'Parasitized';
      final confidenceText = widget.confidence != null
          ? " with **${widget.confidence!.toStringAsFixed(1)}% confidence**"
          : "";

      String contextMsg;
      if (isParasitized) {
        contextMsg =
            "⚠️ Your scan shows **Parasitized**$confidenceText.\n\n"
            "**Immediate steps recommended:**\n"
            "1. **See a doctor today** — get a confirmatory lab test (RDT or microscopy).\n"
            "2. **Do not self-medicate** — antimalarials need a prescription.\n"
            "3. **Watch for** fever, chills, headache, sweating, and fatigue.\n\n"
            "I'm here to answer any questions you have. 💬";
        _suggestions = [
          "What should I do now?",
          "What are malaria symptoms?",
          "How is malaria treated?",
          "Where can I get tested?",
        ];
      } else {
        contextMsg =
            "✅ Great news! Your scan shows **Uninfected**$confidenceText.\n\n"
            "To stay protected:\n"
            "- Sleep under **insecticide-treated nets** every night.\n"
            "- Use **DEET-based repellent** on exposed skin.\n"
            "- Eliminate **standing water** near your home.\n\n"
            "Feel free to ask me anything! 💬";
        _suggestions = [
          "How do I prevent malaria?",
          "What if I feel sick later?",
          "How accurate is the scan?",
          "What causes malaria?",
        ];
      }

      Timer(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _messages.add(ChatMessage(
              text: contextMsg,
              isUser: false,
              timestamp: DateTime.now(),
            ));
          });
          _scrollToBottom();
        }
      });
    } else {
      _suggestions = [
        "What are malaria symptoms?",
        "How is malaria prevented?",
        "How is malaria treated?",
        "What causes malaria?",
      ];
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });
    _scrollToBottom();

    // Send to Gemini (with one automatic retry on transient errors)
    try {
      // Build context-enriched message so Gemini is aware of scan result
      String contextPrefix = '';
      if (widget.scanResult != null) {
        contextPrefix =
            '[Context: User\'s malaria scan result is "${widget.scanResult}" '
            'with ${widget.confidence?.toStringAsFixed(1) ?? "unknown"}% confidence.] ';
      }

      GenerateContentResponse? response;
      try {
        response = await _chat.sendMessage(
          Content.text('$contextPrefix$text'),
        );
      } catch (firstError) {
        debugPrint('Gemini first attempt failed: $firstError — retrying...');
        await Future.delayed(const Duration(seconds: 2));
        // Retry once with a fresh chat session to recover from stale state
        _chat = _model.startChat();
        response = await _chat.sendMessage(
          Content.text('$contextPrefix$text'),
        );
      }

      if (!mounted) return;
      final responseText = response.text?.trim() ??
          "I'm sorry, I couldn't generate a response. Please try again.";

      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(
          text: responseText,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _updateSuggestions(text);
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Gemini error (after retry): $e');

      final errStr = e.toString().toLowerCase();
      String errorMsg;

      if (errStr.contains('api_key') ||
          errStr.contains('invalid') ||
          errStr.contains('api-key') ||
          errStr.contains('unauthenticated') ||
          errStr.contains('permission')) {
        errorMsg =
            "🔑 **API Key Issue.**\n\n"
            "The Gemini API key is missing or invalid. Please ensure a valid key "
            "(starting with `AIzaSy`) is configured.\n\n"
            "Get a free key at [Google AI Studio](https://aistudio.google.com/apikey).";
      } else if (errStr.contains('not found') || errStr.contains('model')) {
        errorMsg =
            "⚙️ **AI Model Unavailable.**\n\n"
            "The AI model could not be reached. This may be a temporary issue — "
            "please try again in a moment.";
      } else if (errStr.contains('network') ||
          errStr.contains('socket') ||
          errStr.contains('connection') ||
          errStr.contains('timeout')) {
        errorMsg =
            "📶 **No Internet Connection.**\n\n"
            "Doctor AI requires an active internet connection. "
            "Please check your network and try again.";
      } else if (errStr.contains('quota') || errStr.contains('rate')) {
        errorMsg =
            "⏳ **Request Limit Reached.**\n\n"
            "Too many questions were sent too quickly. "
            "Please wait a moment and try again.";
      } else {
        errorMsg =
            "😔 **Doctor AI is temporarily unavailable.**\n\n"
            "An unexpected error occurred. Please try again.\n\n"
            "_Error: ${e.toString().split('\n').first}_";
      }

      setState(() {
        _isTyping = false;
        _messages.add(ChatMessage(
          text: errorMsg,
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
        _updateSuggestions(text);
      });
    }
    _scrollToBottom();
  }





  void _updateSuggestions(String lastQuery) {
    final q = lastQuery.toLowerCase();
    if (q.contains('symptom')) {
      _suggestions = ["How is it treated?", "Where can I get tested?", "Can I recover?"];
    } else if (q.contains('prevent') || q.contains('protect')) {
      _suggestions = ["What causes malaria?", "What are the symptoms?", "How is it treated?"];
    } else if (q.contains('treat') || q.contains('medicine')) {
      _suggestions = ["Where can I get tested?", "How is it prevented?", "How accurate is the scan?"];
    } else if (q.contains('clinic') || q.contains('hospital') || q.contains('test')) {
      _suggestions = ["How is it treated?", "What are the symptoms?", "Can I recover fully?"];
    } else if (q.contains('cause') || q.contains('parasite')) {
      _suggestions = ["What are the symptoms?", "How is it prevented?", "How is it diagnosed?"];
    } else {
      _suggestions = ["What are malaria symptoms?", "How is it prevented?", "Where to get tested?"];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    final isParasitized = widget.scanResult == 'Parasitized';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.psychology, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Doctor AI',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Malaria Health Assistant',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            )
          ],
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: const Text(
                'Gemini AI',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Diagnostic Context Banner
          if (widget.scanResult != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isParasitized
                    ? Colors.red.withValues(alpha: 0.08)
                    : Colors.green.withValues(alpha: 0.08),
                border: Border(
                  bottom: BorderSide(
                    color: isParasitized
                        ? Colors.red.withValues(alpha: 0.2)
                        : Colors.green.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isParasitized
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isParasitized
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      color: isParasitized ? Colors.red[700] : Colors.green[700],
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[800],
                          fontSize: 13,
                        ),
                        children: [
                          const TextSpan(text: "Discussing scan result: "),
                          TextSpan(
                            text: widget.scanResult,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isParasitized
                                  ? Colors.red[700]
                                  : Colors.green[700],
                            ),
                          ),
                          if (widget.confidence != null)
                            TextSpan(
                              text:
                                  " (${widget.confidence!.toStringAsFixed(1)}% confidence)",
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Message List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return _buildTypingIndicator();
                }
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),

          // Suggestion Chips
          if (_suggestions.isNotEmpty)
            Container(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                          _suggestions[index],
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        backgroundColor: isDark
                            ? primaryColor.withValues(alpha: 0.15)
                            : primaryColor.withValues(alpha: 0.08),
                        side: BorderSide(
                          color: primaryColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _handleSubmitted(_suggestions[index]),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  offset: const Offset(0, -2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: TextField(
                        controller: _textController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Ask anything about malaria...',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.grey[500],
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        onSubmitted: _handleSubmitted,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _handleSubmitted(_textController.text),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 6, bottom: 2),
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.psychology, color: Colors.white, size: 16),
            ),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? primaryColor
                    : message.isError
                        ? (isDark
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Colors.orange[50])
                        : (isDark ? const Color(0xFF2D2D2D) : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: message.isError
                    ? Border.all(
                        color: Colors.orange.withValues(alpha: 0.4), width: 1)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: isUser ? 0.08 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isUser
                      ? Text(
                          message.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        )
                      : MarkdownBody(
                          data: message.text,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.87)
                                  : Colors.black87,
                              fontSize: 14,
                              height: 1.4,
                            ),
                            strong: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            em: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : Colors.black87,
                              fontStyle: FontStyle.italic,
                              fontSize: 14,
                            ),
                            listBullet: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : Colors.black54,
                              fontSize: 14,
                            ),
                            blockquoteDecoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.08),
                              border: Border(
                                left: BorderSide(
                                    color: primaryColor, width: 3),
                              ),
                            ),
                            blockquote: TextStyle(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : Colors.black87,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          shrinkWrap: true,
                        ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      "${message.timestamp.hour.toString().padLeft(2, '0')}:"
                      "${message.timestamp.minute.toString().padLeft(2, '0')}",
                      style: TextStyle(
                        color:
                            isUser ? Colors.white60 : Colors.grey[500],
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(left: 6, bottom: 2),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, color: primaryColor, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 6, bottom: 2),
            decoration:
                BoxDecoration(color: primaryColor, shape: BoxShape.circle),
            child:
                const Icon(Icons.psychology, color: Colors.white, size: 16),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _dotController,
                  builder: (context, child) {
                    final delay = index * 0.25;
                    final raw = (_dotController.value - delay) % 1.0;
                    final opacity = raw < 0.5
                        ? (raw / 0.5).clamp(0.3, 1.0)
                        : (1 - (raw - 0.5) / 0.5).clamp(0.3, 1.0);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: opacity),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
