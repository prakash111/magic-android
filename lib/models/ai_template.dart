class TemplateField {
  final String key;
  final String label;
  final String hint;
  final bool isMultiline;

  const TemplateField({
    required this.key,
    required this.label,
    required this.hint,
    this.isMultiline = false,
  });
}

class AITemplate {
  final String id;
  final String title;
  final String description;
  final String category;
  final List<TemplateField> fields;

  const AITemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.fields,
  });

  static const List<AITemplate> defaultTemplates = [
    AITemplate(
      id: 'blog_post',
      title: 'SEO Blog Article',
      description:
          'Generate high-ranking, comprehensive blog articles with headings.',
      category: 'Writing',
      fields: [
        TemplateField(
          key: 'topic',
          label: 'Article Topic',
          hint: 'e.g., Best Local SEO Strategies for Small Businesses in 2026',
        ),
        TemplateField(
          key: 'keywords',
          label: 'Primary & Secondary Keywords',
          hint: 'e.g., local SEO, Google My Business, small business ranking',
        ),
        TemplateField(
          key: 'tone',
          label: 'Tone of Voice',
          hint: 'e.g., Informative, Authoritative, Engaging',
        ),
      ],
    ),
    AITemplate(
      id: 'product_description',
      title: 'Product Description',
      description: 'Compelling eCommerce descriptions with benefit-driven bullet points.',
      category: 'eCommerce',
      fields: [
        TemplateField(
          key: 'name',
          label: 'Product Name',
          hint: 'e.g., Wireless Ergonomic Keyboard Pro',
        ),
        TemplateField(
          key: 'features',
          label: 'Key Features',
          hint:
              'e.g., Bluetooth 5.3, cushioned wrist rest, 6-month battery life',
          isMultiline: true,
        ),
        TemplateField(
          key: 'audience',
          label: 'Target Audience',
          hint: 'e.g., Programmers, remote workers, writers',
        ),
      ],
    ),
    AITemplate(
      id: 'social_post',
      title: 'Viral Social Media Post',
      description:
          'Attention-grabbing posts for LinkedIn, Twitter / X, and Instagram.',
      category: 'Social',
      fields: [
        TemplateField(
          key: 'topic',
          label: 'Post Topic / Message',
          hint: 'e.g., 5 productivity lessons learned from building a SaaS business',
        ),
        TemplateField(
          key: 'platform',
          label: 'Target Platform',
          hint: 'e.g., LinkedIn, Twitter/X, Instagram',
        ),
      ],
    ),
    AITemplate(
      id: 'video_script',
      title: 'YouTube / Reels Script',
      description: 'Hook, body, and call-to-action scripts for video creators.',
      category: 'Video',
      fields: [
        TemplateField(
          key: 'title',
          label: 'Video Concept',
          hint: 'e.g., Stop doing this with your website SEO in 2026',
        ),
        TemplateField(
          key: 'duration',
          label: 'Target Length',
          hint: 'e.g., 60 seconds (Short/Reel) or 8 minutes (YouTube)',
        ),
      ],
    ),
    AITemplate(
      id: 'email_newsletter',
      title: 'Marketing Email / Newsletter',
      description:
          'Engaging emails with catchy subject lines and click-worthy CTAs.',
      category: 'Email',
      fields: [
        TemplateField(
          key: 'subject',
          label: 'Email Focus / Announcement',
          hint: 'e.g., New feature launch: Instant AI SEO Audit',
        ),
        TemplateField(
          key: 'cta',
          label: 'Call to Action',
          hint: 'e.g., Upgrade to Pro today or Try for Free',
        ),
      ],
    ),
  ];
}
