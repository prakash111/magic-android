class ChatMessage {
  final String id;
  final String sender; // 'user' or 'ai'
  final String text;
  final DateTime timestamp;
  final String? personaName;

  ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.personaName,
  });

  bool get isUser => sender == 'user';

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender': sender,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'personaName': personaName,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] ?? '',
    sender: json['sender'] ?? 'user',
    text: json['text'] ?? '',
    timestamp: json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
        : DateTime.now(),
    personaName: json['personaName'],
  );
}

class ChatPersona {
  final String id;
  final String name;
  final String role;
  final String description;
  final String systemPrompt;

  const ChatPersona({
    required this.id,
    required this.name,
    required this.role,
    required this.description,
    required this.systemPrompt,
  });

  static const List<ChatPersona> defaultPersonas = [
    ChatPersona(
      id: 'seo_specialist',
      name: 'SEO RankMaster',
      role: 'Senior SEO Strategist',
      description:
          'Specializes in on-page SEO, keyword clustering, and SERP rankings.',
      systemPrompt: 'You are a seasoned SEO expert and content strategist. Your goal is to give actionable, data-backed SEO advice, audit recommendations, and keyword strategies.',
    ),
    ChatPersona(
      id: 'general_assistant',
      name: 'MagicAI Assistant',
      role: 'General Intelligence',
      description: 'Friendly, versatile AI ready to help with tasks, brainstorming, and research.',
      systemPrompt: 'You are MagicAI, a helpful, precise, and concise conversational assistant.',
    ),
    ChatPersona(
      id: 'copywriter_pro',
      name: 'Conversion Copywriter',
      role: 'Direct Response Copywriter',
      description: 'Crafts persuasive sales letters, landing pages, and email sequences.',
      systemPrompt: 'You are an elite direct-response copywriter focused on engagement and high conversion rates.',
    ),
    ChatPersona(
      id: 'social_growth',
      name: 'Viral Social Marketer',
      role: 'Social Media Expert',
      description: 'Creates viral hooks, carousels, threads, and short-form video scripts.',
      systemPrompt: 'You are a social media viral marketing consultant specializing in explosive audience growth.',
    ),
  ];
}
