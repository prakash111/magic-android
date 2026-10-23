import 'chat_service.dart';
import 'ai_model_selection.dart';

import 'dart:convert';

import '../models/seo_analysis_result.dart';
import '../models/keyword_data.dart';
import '../models/user_model.dart';
import '../models/social_post.dart';
import '../models/social_account.dart';
import 'mobile_api.dart';
import 'storage_service.dart';
import 'workspace_service.dart';

class ApiService {
  static MobileApi get api => MobileApi.instance;
  static Future<bool> testConnection() async {
    try {
      await api.bootstrap();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getSocialLoginOptions({
    MobileApi? client,
  }) async {
    final data = await (client ?? api).request(
      '/auth/options',
      authenticated: false,
    );
    if (data is! Map) return [];
    bool active(dynamic value) => value == true || value == 1 || value == '1';
    final config = data['login_config'] is Map
        ? data['login_config'] as Map
        : data;
    final list = data['providers'] is List
        ? data['providers'] as List
        : data['provider_status'] as List? ?? [];
    return ['google', 'github', 'facebook']
        .where((id) {
          if (data.containsKey('${id}_active')) {
            return active(data['${id}_active']);
          }
          if (config.containsKey('${id}_enabled')) {
            return active(config['${id}_enabled']);
          }
          return list.whereType<Map>().any(
            (p) => p['id'] == id && active(p['enabled'] ?? p['available']),
          );
        })
        .map(
          (id) => <String, dynamic>{
            'id': id,
            'label': id == 'github'
                ? 'Github'
                : '${id[0].toUpperCase()}${id.substring(1)}',
            'enabled': true,
            'available': true,
          },
        )
        .toList();
  }

  static Future<List<String>> getSupportedSocialLogins() async =>
      (await getSocialLoginOptions())
          .where((provider) => provider['available'] == true)
          .map((provider) => provider['id'].toString())
          .toList();

  static Future<UserModel> login({
    required String email,
    required String password,
    String? otp,
  }) async {
    final data = await api.request(
      '/auth/login',
      method: 'POST',
      authenticated: false,
      body: {
        'email': email.trim(),
        'password': password,
        if (otp != null && otp.isNotEmpty) 'otp': otp,
      },
    ) as Map<String, dynamic>;
    await StorageService.clearAuth();
    await api.saveSession(data);
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    await StorageService.saveUser(user);
    return user;
  }

  static Future<UserModel> register({
    required String name,
    required String surname,
    required String email,
    required String password,
  }) async {
    await api.request(
      '/auth/register',
      method: 'POST',
      authenticated: false,
      body: {
        'name': name.trim(),
        'surname': surname.trim(),
        'email': email.trim(),
        'password': password,
        'password_confirmation': password,
      },
    );
    return login(email: email, password: password);
  }

  static Future<UserModel> socialLogin({
    required String provider,
    String? token,
    String? userId,
  }) async {
    final data = await BrowserLoginFlow().login(provider: provider);
    final user = UserModel.fromJson(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    await StorageService.saveUser(user);
    return user;
  }

  static Future<UserModel?> fetchUserProfile() async {
    if (!await StorageService.isLoggedIn()) return null;
    final data = await api.request('/auth/profile') as Map<String, dynamic>;
    final credits = await api.request('/credits') as Map<String, dynamic>;
    final user = UserModel.fromJson({
      ...data,
      'credits': credits['words'],
      'plan': credits['plan'],
    });
    await StorageService.saveUser(user);
    return user;
  }

  static Future<void> logout() async {
    try {
      await api.request('/auth/logout', method: 'POST');
    } finally {
      await StorageService.clearAuth();
      try {
        await SecureStore.invokeMethod<void>('clearWebSession');
      } catch (_) {}
    }
  }

  static Future<List<SocialAccount>> getSocialPlatforms() async =>
      (await api.request('/social-media/platforms') as List)
          .map(
            (item) =>
                SocialAccount.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
  static Future<SocialAccount> connectSocialPlatform(
    String platform, {
    String? handle,
  }) async {
    final data = await api.request(
      '/social-media/platforms/connect',
      method: 'POST',
      body: {'platform': platform, 'handle': handle},
    );
    return SocialAccount.fromJson(
      Map<String, dynamic>.from(data['data'] as Map),
    );
  }

  static Future<void> disconnectSocialPlatform(String idOrPlatform) async {
    await api.request(
      '/social-media/platforms/${Uri.encodeComponent(idOrPlatform)}',
      method: 'DELETE',
    );
  }

  static Future<List<SocialPost>> getSocialPosts() async =>
      (await api.request('/social-media/posts') as List)
          .map(
            (item) =>
                SocialPost.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
  static Future<bool> scheduleSocialPost(SocialPost post) async {
    await api.request(
      '/social-media/posts',
      method: 'POST',
      body: {
        'caption': post.caption,
        'platforms': post.platforms,
        'scheduled_at': post.scheduledAt.toUtc().toIso8601String(),
        'status': post.status,
        'media_url': post.mediaUrl,
      },
    );
    return true;
  }

  static Future<void> deleteSocialPost(String id) async {
    await api.request(
      '/social-media/posts/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
  }

  static Future<String> generateSocialCaption({
    required String topic,
    required String platform,
    required String tone,
  }) => generateTemplateContent(
    templateId: 'social_media_post',
    inputs: {'description': topic, 'platform': platform, 'tone_of_voice': tone},
  );
  static Future<SEOAnalysisResult> analyzeArticle({
    required String content,
    required String keyword,
    String contentType = 'article',
  }) async {
    final data = await api.request(
      '/tools/mobile-analyse/run',
      method: 'POST',
      body: {
        'inputs': {
          'resultText': content,
          'topicKeyword': keyword,
          'type': contentType,
        },
      },
    );
    return SEOAnalysisResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  static Future<List<KeywordItem>> suggestKeywords(String keyword) async {
    final data = await api.request(
      '/tools/mobile-keywords/run',
      method: 'POST',
      body: {
        'inputs': {'keyword': keyword},
      },
    );
    return (data['result'] as List)
        .map(
          (item) => item is String
              ? KeywordItem(keyword: item)
              : KeywordItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  static Future<List<SearchQuestionItem>> getSearchQuestions(
    String topic,
  ) async {
    final data = await api.request(
      '/tools/mobile-questions/run',
      method: 'POST',
      body: {
        'inputs': {'title': topic},
      },
    );
    final raw = data['result'];
    final list = raw is String ? jsonDecode(raw) as List : raw as List;
    return list
        .map(
          (item) =>
              SearchQuestionItem(question: item.toString(), category: 'Search'),
        )
        .toList();
  }

  static Future<SEOMetaResult> generateSEOMeta({
    required String keyword,
    required String appName,
    String type = 'all',
  }) async {
    final data = await api.request(
      '/tools/mobile-meta/run',
      method: 'POST',
      body: {
        'inputs': {'keyword': keyword, 'input': type},
      },
    );
    final result = data['result']?.toString() ?? '';
    return SEOMetaResult.fromJson({
      if (type == 'meta_title') 'title': result,
      if (type == 'meta_description') 'description': result,
      if (type == 'meta_keywords') 'keywords': result,
    });
  }

  static Future<String> improveArticle({
    required String content,
    required String keyword,
    List<String> longTailList = const [],
    List<String> competitorList = const [],
  }) => generateTemplateContent(
    templateId: 'article_rewriter',
    inputs: {
      'content_rewrite': content,
      'keywords': keyword,
      'rewrite_mode': 'Improve',
    },
  );
  static Future<String> sendChatMessage({
    required String message,
    required String systemPrompt,
    MobileApi? client,
  }) async {
    final backend = client ?? api;
    final selection = AiModelSelection(backend);
    final options = await ChatService(backend).options();
    final personas = options['personas']!;
    final models = options['models']!;
    if (personas.isEmpty || models.isEmpty) {
      throw const ApiFailure(
        'No chat model is configured for this account. Contact your administrator.',
      );
    }
    final model = await selection.resolve(models);
    final chat = await backend.request(
      '/chat/conversations',
      method: 'POST',
      body: {'category_id': personas.first['id']},
    );
    return backend
        .stream(
          '/chat/conversations/${chat['id']}/stream',
          body: {'prompt': message, 'model': model!},
        )
        .join();
  }

  static Future<String> generateTemplateContent({
    required String templateId,
    required Map<String, String> inputs,
    MobileApi? client,
  }) async {
    final backend = client ?? api;
    final selection = AiModelSelection(backend);
    final model = await selection.resolve(await selection.models());
    if (model == null) {
      throw const ApiFailure(
        'No enabled text models are available for your plan.',
      );
    }
    final prepared = await backend.request(
      '/tools/${Uri.encodeComponent(templateId)}/run',
      method: 'POST',
      body: {'inputs': inputs, 'model': model},
    );
    return backend
        .stream('/writer/${prepared['message_id']}/stream', legacy: true)
        .join();
  }
}
