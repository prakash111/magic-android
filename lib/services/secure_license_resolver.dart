class SecureLicenseResolver {
  static const _parts = [
    [59, 39, 39],
    [42, 41, 96],
    [78, 78, 13],
    [1, 11, 13],
    [1, 28, 10],
    [88, 12, 25],
    [18, 16, 19],
    [225, 229, 246],
    [233, 242, 165],
    [241, 253, 255],
  ];
  static Uri get verificationEndpoint => Uri.parse(
    String.fromCharCodes([
      for (var index = 0; index < _parts.length; index++)
        for (final byte in _parts[index]) byte ^ (83 + index * 7),
    ]),
  ).resolve('/api/verify-license');
}
