class BrandConfig {
  static const name = String.fromEnvironment(
    'MAGICAI_APP_NAME',
    defaultValue: 'MagicAI',
  );
  static const serverUrl = String.fromEnvironment('MAGICAI_SERVER_URL');
  static const company = String.fromEnvironment('MAGICAI_COMPANY');
  static const product = 'MagicAI';
  static const supportEmail = String.fromEnvironment('MAGICAI_SUPPORT_EMAIL');
  static const supportPhone = String.fromEnvironment('MAGICAI_SUPPORT_PHONE');
  static const copyright = String.fromEnvironment('MAGICAI_COPYRIGHT');
  static const logoBase64 = '';
  static const splashLogoBase64 = '';
  static const primary = 0xFF6366F1;
  static const secondary = 0xFF4F46E5;
  static const accent = 0xFF8B5CF6;
  static const background = 0xFF131620;
  static const surface = 0xFF1E2230;
  static const text = 0xFFF8FAFC;
}
