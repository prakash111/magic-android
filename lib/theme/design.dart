import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Shared design tokens and small widgets for the MagicAI redesign.

const kBrandGradient = LinearGradient(
  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFA855F7)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kAccentPalette = <Color>[
  Color(0xFF6366F1), // indigo
  Color(0xFF38BDF8), // sky
  Color(0xFFF472B6), // pink
  Color(0xFF10B981), // emerald
  Color(0xFFF59E0B), // amber
  Color(0xFF8B5CF6), // violet
];

/// Stable accent colour for a tool or module, so each one keeps its colour.
Color accentFor(String key) {
  var h = 0;
  for (final unit in key.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return kAccentPalette[h % kAccentPalette.length];
}

/// 142005000 -> 142.0M, 45000000 -> 45.0M, 1240 -> 1.2K, 87 -> 87.
/// Non-numeric values (for example "Unlimited" or "—") are returned as-is.
String compactNumber(Object? value) {
  final raw = '$value'.trim();
  final n = num.tryParse(raw.replaceAll(',', ''));
  if (n == null) return raw;
  final a = n.abs();
  String one(double v) => v.toStringAsFixed(1);
  if (a >= 1e9) return '${one(n / 1e9)}B';
  if (a >= 1e6) return '${one(n / 1e6)}M';
  if (a >= 1e4) return '${one(n / 1e3)}K';
  if (n % 1 == 0) return n.toInt().toString();
  return one(n.toDouble());
}

Color mutedText(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

/// Rounded tinted square holding an icon.
class IconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconChip({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(icon, color: color, size: size * 0.5),
  );
}

/// "Title ........ action" row used above each content section.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Key? titleKey;
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.titleKey,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              key: titleKey,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                action!,
                style: TextStyle(
                  color: onAction == null
                      ? mutedText(context)
                      : const Color(0xFFA5B4FC),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Tappable card row: icon chip, title, optional subtitle, chevron.
class ToolRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool locked;
  const ToolRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.onTap,
    this.locked = false,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconChip(icon: icon, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mutedText(context),
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              locked ? Icons.lock_outline : Icons.chevron_right,
              size: 20,
              color: mutedText(context),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Dashed "add" style card.
class AddRow extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const AddRow({super.key, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const IconChip(icon: Icons.add, color: AppTheme.primary, size: 34),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFA5B4FC),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
