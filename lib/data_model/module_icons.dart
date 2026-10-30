/// A plugin's static image, including its layout before the bytes arrive.
class ModuleIconImage {
  final String url;
  final String mimeType;
  final double aspectRatio;

  const ModuleIconImage({
    required this.url,
    required this.mimeType,
    this.aspectRatio = 1,
  });

  static ModuleIconImage? tryParse(dynamic value) {
    if (value is! Map) return null;
    final url = value['url'];
    final mime = value['mime_type'];
    final ratio = value['aspect_ratio'] ?? 1;
    if (url is! String ||
        url.isEmpty ||
        (mime != 'image/png' && mime != 'image/svg+xml') ||
        ratio is! num ||
        !ratio.isFinite ||
        ratio <= 0 ||
        ratio > 8) {
      return null;
    }
    return ModuleIconImage(
      url: url,
      mimeType: mime,
      aspectRatio: ratio.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'mime_type': mimeType,
    'aspect_ratio': aspectRatio,
  };
}

/// Optional source artwork; older or unsupported metadata keeps its fallback.
class ModuleIcons {
  final ModuleIconImage small;
  final ModuleIconImage standard;
  final bool monochrome;

  const ModuleIcons({
    required this.small,
    required this.standard,
    this.monochrome = false,
  });

  static ModuleIcons? tryParse(dynamic value) {
    if (value is! Map) return null;
    final small = ModuleIconImage.tryParse(value['small']);
    final standard = ModuleIconImage.tryParse(value['standard']);
    if (small == null || standard == null) return null;
    return ModuleIcons(
      small: small,
      standard: standard,
      monochrome: value['monochrome'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'small': small.toJson(),
    'standard': standard.toJson(),
    'monochrome': monochrome,
  };
}
