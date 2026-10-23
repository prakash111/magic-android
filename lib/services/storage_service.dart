import '../theme/brand_config.dart';

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api.dart';
import '../models/saved_document.dart';
import '../models/chat_message.dart';
import '../models/user_model.dart';
import '../models/social_post.dart';
import '../models/social_account.dart';

class StorageService {
  static const String _keyServerUrl = 'server_url';
  static const String _keyApiToken = 'api_token';
  static const String _keyUser = 'auth_user';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyDocuments = 'saved_documents';
  static const String _keyChatHistory = 'chat_history';
  static const String _keySocialPosts = 'social_posts';
  static const String _keySocialAccounts = 'social_accounts';

  // All services use the backend selected at build time.
  static const String defaultServerUrl = BrandConfig.serverUrl;

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // Server URL
  static Future<String> getServerUrl() async {
    return defaultServerUrl;
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await _instance;
    await prefs.setString(_keyServerUrl, defaultServerUrl);
  }

  // API Token
  static Future<String> getApiToken() async {
    final prefs = await _instance;
    await prefs.remove(_keyApiToken);
    return await MobileApi.instance.store.read('access_token') ?? '';
  }

  static Future<void> setApiToken(String token) async {
    final prefs = await _instance;
    await prefs.remove(_keyApiToken);
    await MobileApi.instance.store.write('access_token', token.trim());
  }

  static Future<bool> isLoggedIn() async {
    final token = await getApiToken();
    return token.isNotEmpty;
  }

  // User Profile
  static Future<UserModel?> getUser() async {
    final prefs = await _instance;
    final jsonStr = prefs.getString(_keyUser);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      return UserModel.fromJson(jsonDecode(jsonStr));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveUser(UserModel user) async {
    final prefs = await _instance;
    await prefs.setString(_keyUser, jsonEncode(user.toJson()));
  }

  static Future<void> clearAuth() async {
    final prefs = await _instance;
    await MobileApi.instance.clearSession();
    await prefs.remove(_keyApiToken);
    await prefs.remove(_keyDocuments);
    await prefs.remove(_keyChatHistory);
    await prefs.remove(_keyUser);
    await prefs.remove(_keySocialPosts);
    await prefs.remove(_keySocialAccounts);
  }

  // Theme Mode: 'system', 'light', 'dark'
  static Future<String> getThemeMode() async {
    final prefs = await _instance;
    return prefs.getString(_keyThemeMode) ?? 'dark';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await _instance;
    await prefs.setString(_keyThemeMode, mode);
  }

  // Saved Documents
  static Future<List<SavedDocument>> getDocuments() async {
    final prefs = await _instance;
    final jsonList = prefs.getStringList(_keyDocuments) ?? [];
    return jsonList.map((str) {
      try {
        return SavedDocument.fromJson(jsonDecode(str));
      } catch (_) {
        return SavedDocument(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'Document',
          content: str,
          type: 'general',
          createdAt: DateTime.now(),
        );
      }
    }).toList();
  }

  static Future<void> saveDocument(SavedDocument doc) async {
    final prefs = await _instance;
    final docs = await getDocuments();
    docs.removeWhere((d) => d.id == doc.id);
    docs.insert(0, doc);
    final jsonList = docs.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_keyDocuments, jsonList);
  }

  static Future<void> deleteDocument(String id) async {
    final prefs = await _instance;
    final docs = await getDocuments();
    docs.removeWhere((d) => d.id == id);
    final jsonList = docs.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_keyDocuments, jsonList);
  }

  // Chat History
  static Future<List<ChatMessage>> getChatHistory() async {
    final prefs = await _instance;
    final jsonList = prefs.getStringList(_keyChatHistory) ?? [];
    return jsonList.map((str) {
      try {
        return ChatMessage.fromJson(jsonDecode(str));
      } catch (_) {
        return ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          sender: 'ai',
          text: str,
          timestamp: DateTime.now(),
        );
      }
    }).toList();
  }

  static Future<void> saveChatMessage(ChatMessage msg) async {
    final prefs = await _instance;
    final history = await getChatHistory();
    history.add(msg);
    if (history.length > 100) {
      history.removeRange(0, history.length - 100);
    }
    final jsonList = history.map((m) => jsonEncode(m.toJson())).toList();
    await prefs.setStringList(_keyChatHistory, jsonList);
  }

  static Future<void> clearChatHistory() async {
    final prefs = await _instance;
    await prefs.remove(_keyChatHistory);
  }

  // Social Posts
  static Future<List<SocialPost>> getSocialPosts() async {
    final prefs = await _instance;
    final jsonList = prefs.getStringList(_keySocialPosts) ?? [];
    return jsonList.map((str) {
      try {
        return SocialPost.fromJson(jsonDecode(str));
      } catch (_) {
        return SocialPost(
          id: 'post_${DateTime.now().millisecondsSinceEpoch}',
          caption: '',
          platforms: ['x'],
          scheduledAt: DateTime.now(),
          createdAt: DateTime.now(),
        );
      }
    }).toList();
  }

  static Future<void> saveSocialPosts(List<SocialPost> posts) async {
    final prefs = await _instance;
    final jsonList = posts.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_keySocialPosts, jsonList);
  }

  static Future<void> saveSocialPost(SocialPost post) async {
    final posts = await getSocialPosts();
    final index = posts.indexWhere((p) => p.id == post.id);
    if (index >= 0) {
      posts[index] = post;
    } else {
      posts.insert(0, post);
    }
    await saveSocialPosts(posts);
  }

  static Future<void> deleteSocialPost(String id) async {
    final posts = await getSocialPosts();
    posts.removeWhere((p) => p.id == id);
    await saveSocialPosts(posts);
  }

  // Linked Social Accounts
  static Future<List<SocialAccount>> getSocialAccounts() async {
    final prefs = await _instance;
    final jsonList = prefs.getStringList(_keySocialAccounts);
    if (jsonList == null || jsonList.isEmpty) {
      return [];
    }
    return jsonList.map((str) {
      return SocialAccount.fromJson(jsonDecode(str));
    }).toList();
  }

  static Future<void> saveSocialAccounts(List<SocialAccount> accounts) async {
    final prefs = await _instance;
    final jsonList = accounts.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList(_keySocialAccounts, jsonList);
  }

  static Future<void> updateSocialAccount(SocialAccount account) async {
    final accounts = await getSocialAccounts();
    final index = accounts.indexWhere((a) => a.platform == account.platform);
    if (index >= 0) {
      accounts[index] = account;
    } else {
      accounts.add(account);
    }
    await saveSocialAccounts(accounts);
  }
}
