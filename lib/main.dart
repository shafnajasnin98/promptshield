import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String _geminiApiKey = String.fromEnvironment('API_KEY');
const String _geminiEndpoint =
    'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent';

void main() {
  runApp(const PromptShield());
}

class PromptShield extends StatelessWidget {
  const PromptShield({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PromptShield',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        fontFamily: 'SF Pro Display', // Falls back to system font gracefully
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF818CF8),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

//  Risk Level Enum
// ─────────────────────────────────────────────
enum RiskLevel { safe, medium, high }

extension RiskLevelExtension on RiskLevel {
  Color get color {
    switch (this) {
      case RiskLevel.safe:
        return const Color(0xFF22C55E);
      case RiskLevel.medium:
        return const Color(0xFFF97316);
      case RiskLevel.high:
        return const Color(0xFFEF4444);
    }
  }

  String get label {
    switch (this) {
      case RiskLevel.safe:
        return 'SAFE';
      case RiskLevel.medium:
        return 'MEDIUM';
      case RiskLevel.high:
        return 'HIGH';
    }
  }

  IconData get icon {
    switch (this) {
      case RiskLevel.safe:
        return Icons.shield_outlined;
      case RiskLevel.medium:
        return Icons.warning_amber_rounded;
      case RiskLevel.high:
        return Icons.gpp_bad_outlined;
    }
  }
}

//  Message Model
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

//  Safety Engine

/// Checks for sensitive personal data: email, phone, keywords
Map<String, dynamic> hasSensitiveData(String text) {
  final lower = text.toLowerCase();
  final detections = <String>[];
  int score = 0;

  // Email regex
  final emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
  if (emailRegex.hasMatch(text)) {
    detections.add('email address');
    score += 3;
  }

  // Phone number: 10+ consecutive digits (with optional separators)
  final phoneRegex = RegExp(r'\b\d[\d\s\-().]{8,}\d\b');
  if (phoneRegex.hasMatch(text)) {
    detections.add('phone number');
    score += 2;
  }

  // Sensitive keywords
  const sensitiveKeywords = ['password', 'otp', 'cvv', 'pin', 'ssn', 'credit card'];
  for (final keyword in sensitiveKeywords) {
    if (lower.contains(keyword)) {
      detections.add('"$keyword"');
      score += 3;
    }
  }

  return {'detections': detections, 'score': score};
}

/// Checks for prompt injection / jailbreak attempts
Map<String, dynamic> isPromptInjection(String text) {
  final lower = text.toLowerCase();
  final detections = <String>[];
  int score = 0;

  const injectionPhrases = [
    'ignore previous instructions',
    'ignore all instructions',
    'bypass',
    'act as',
    'jailbreak',
    'override',
    'you are now',
    'pretend you are',
    'disregard',
    'forget your instructions',
    'new persona',
    'do anything now',
    'dan mode',
  ];

  for (final phrase in injectionPhrases) {
    if (lower.contains(phrase)) {
      detections.add('"$phrase"');
      score += 3;
    }
  }

  return {'detections': detections, 'score': score};
}

/// Combines all checks and returns the overall risk level + details
Map<String, dynamic> getRiskLevel(String text) {
  final sensitiveResult = hasSensitiveData(text);
  final injectionResult = isPromptInjection(text);

  final allDetections = <String>[
    ...sensitiveResult['detections'] as List<String>,
    ...injectionResult['detections'] as List<String>,
  ];

  final totalScore =
      (sensitiveResult['score'] as int) + (injectionResult['score'] as int);

  RiskLevel level;
  if (totalScore == 0) {
    level = RiskLevel.safe;
  } else if (totalScore <= 3) {
    level = RiskLevel.medium;
  } else {
    level = RiskLevel.high;
  }

  return {
    'level': level,
    'score': totalScore,
    'detections': allDetections,
  };
}

/// Calls Gemini REST API and returns the response text
Future<String> sendToGemini(String userMessage) async {
  final uri = Uri.parse('$_geminiEndpoint?key=$_geminiApiKey');

  final body = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': userMessage}
        ]
      }
    ]
  });

  try {
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      String reply =
          data['candidates'][0]['content']['parts'][0]['text'] ?? "";

      final lower = reply.toLowerCase();

      // 🔥 Fallback inside SUCCESS
      if (lower.contains("error") ||
          lower.contains("busy") ||
          lower.contains("quota")) {
        reply = "⚠️ AI temporarily unavailable. Please try again.";
      }

      if (reply
          .trim()
          .isEmpty) {
        reply = "⚠️ No response from AI. Try again.";
      }

      return reply;
    } else {
      return "⚠️ AI service unavailable. Please try again.";
    }
  } catch (e) {
    return "⚠️ Network error. Please check your connection.";
  }
}
//  Chat Screen

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  RiskLevel _currentRisk = RiskLevel.safe;
  bool _isLoading = false;

  // Live risk update as user types
  void _onInputChanged(String text) {
    if (text.trim().isEmpty) {
      setState(() => _currentRisk = RiskLevel.safe);
      return;
    }
    final result = getRiskLevel(text);
    setState(() => _currentRisk = result['level'] as RiskLevel);
  }

  // Scroll to bottom after new message
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

  // Main send flow — safety check → optional dialog → Gemini call
  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    final riskResult = getRiskLevel(text);
    final riskLevel = riskResult['level'] as RiskLevel;
    final detections = riskResult['detections'] as List<String>;

    // If risky, show alert dialog
    if (riskLevel != RiskLevel.safe) {
      final shouldSend = await _showSafetyDialog(riskLevel, detections);
      if (!shouldSend) return;
    }

    // Proceed to send
    _addUserMessage(text);
    _inputController.clear();
    setState(() {
      _currentRisk = RiskLevel.safe;
      _isLoading = true;
    });
    _scrollToBottom();

    final reply = await sendToGemini(text);

    _addAIMessage(reply);
    setState(() => _isLoading = false);
    _scrollToBottom();
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    });
  }

  void _addAIMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
  }

  // Safety Alert Dialog
  Future<bool> _showSafetyDialog(
      RiskLevel level, List<String> detections) async {
    final detectionText = detections.isNotEmpty
        ? detections.join(', ')
        : 'Potentially risky content';

    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(level.icon, color: level.color, size: 22),
            const SizedBox(width: 10),
            const Text(
              '⚠️ Safety Alert',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Risk badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: level.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: level.color.withOpacity(0.4)),
              ),
              child: Text(
                'Risk Level: ${level.label}',
                style: TextStyle(
                  color: level.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Detected:',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detectionText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'This message may contain sensitive information. Are you sure you want to send it?',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
        actionsPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF94A3B8),
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: level.color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child:
            const Text('Send Anyway', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildDivider(),
            Expanded(child: _buildMessageList()),
            if (_isLoading) _buildTypingIndicator(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Top Bar with app title + risk badge ──
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // App icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          // Title
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PromptShield',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Protected by AI Safety Layer',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // Risk Level Badge
          _buildRiskBadge(_currentRisk),
        ],
      ),
    );
  }

  // ── Risk Badge in top bar ──
  Widget _buildRiskBadge(RiskLevel level) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: level.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: level.color.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: level.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            level.label,
            style: TextStyle(
              color: level.color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: const Color(0xFF1E293B),
    );
  }

  // ── Message List ──
  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        final msg = _messages[i];
        // Show date separator if it's the first message or day changed
        final showDateSep = i == 0 ||
            !_isSameDay(_messages[i - 1].timestamp, msg.timestamp);
        return Column(
          children: [
            if (showDateSep) _buildDateSeparator(msg.timestamp),
            _buildChatBubble(msg),
          ],
        );
      },
    );
  }

  // ── Empty State ──
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.shield_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'promptshield is active',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your messages are scanned for\nsensitive data before sending.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          _buildFeatureChip(Icons.lock_outline, 'Privacy Detection'),
          const SizedBox(height: 8),
          _buildFeatureChip(Icons.psychology_outlined, 'Injection Guard'),
          const SizedBox(height: 8),
          _buildFeatureChip(Icons.bar_chart_rounded, 'Risk Scoring'),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF6366F1), size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Date Separator ──
  Widget _buildDateSeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFF1E293B))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formatDate(date),
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFF1E293B))),
        ],
      ),
    );
  }

  // ── Chat Bubble ──
  Widget _buildChatBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: msg.isUser ? 60 : 0,
          right: msg.isUser ? 0 : 60,
          bottom: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!msg.isUser) ...[
              // AI avatar
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 8, bottom: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 14),
              ),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: msg.isUser
                      ? const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                      : null,
                  color: msg.isUser ? null : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
                    bottomRight: Radius.circular(msg.isUser ? 4 : 18),
                  ),
                  border: msg.isUser
                      ? null
                      : Border.all(
                      color: const Color(0xFF334155), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      msg.text,
                      style: TextStyle(
                        color: msg.isUser
                            ? Colors.white
                            : const Color(0xFFE2E8F0),
                        fontSize: 14.5,
                        height: 1.45,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(msg.timestamp),
                      style: TextStyle(
                        color: msg.isUser
                            ? Colors.white.withOpacity(0.55)
                            : const Color(0xFF475569),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Typing Indicator ──
  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 8, right: 80),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.shield_rounded,
                  color: Colors.white, size: 14),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const _TypingDots(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Input Bar ──
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          top: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _currentRisk == RiskLevel.safe
                      ? const Color(0xFF334155)
                      : _currentRisk.color.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _inputController,
                onChanged: _onInputChanged,
                onSubmitted: (_) => _handleSend(),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 15,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Send Button
          GestureDetector(
            onTap: _handleSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isLoading
                      ? [const Color(0xFF334155), const Color(0xFF334155)]
                      : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _isLoading
                    ? []
                    : [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _isLoading ? Icons.hourglass_top_rounded : Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(date, yesterday)) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

//  Animated Typing Dots
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger each dot's opacity
            final progress = (_controller.value - i * 0.2).clamp(0.0, 1.0);
            final opacity = (progress < 0.5
                ? progress / 0.5
                : (1.0 - progress) / 0.5)
                .clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
