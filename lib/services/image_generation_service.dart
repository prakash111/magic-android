import 'dart:async';

import 'mobile_api.dart';

class ImageGenerationService {
  final MobileApi api;
  final Duration pollInterval;
  final Duration maximumWait;
  ImageGenerationService(
    this.api, {
    this.pollInterval = const Duration(seconds: 3),
    this.maximumWait = const Duration(minutes: 2),
  });

  Future<String> generate({
    required String prompt,
    required String model,
  }) async {
    final result = await api.request(
      '/tools/mobile-image/run',
      method: 'POST',
      body: {
        'inputs': {'description': prompt},
        'model': model,
      },
    );
    if (result is! Map ||
        result['images'] is! List ||
        (result['images'] as List).isEmpty) {
      throw const ApiFailure(
        'The provider did not return an image. Please retry.',
      );
    }
    final first = (result['images'] as List).first;
    if (first is! Map) {
      throw const ApiFailure(
        'The server returned an unreadable image result. Please retry.',
      );
    }
    var image = Map<String, dynamic>.from(first);
    final deadline = DateTime.now().add(maximumWait);
    while (['IN_QUEUE', 'IN_PROGRESS', 'CREATED'].contains(image['status'])) {
      if (DateTime.now().isAfter(deadline)) {
        throw const ApiFailure(
          'Your image is still processing. Check generation history before submitting again.',
        );
      }
      final id = int.tryParse('${image['id']}');
      if (id == null) {
        throw const ApiFailure(
          'The server did not return the image task identifier.',
        );
      }
      await Future<void>.delayed(pollInterval);
      final response = await api.request('/images/$id');
      if (response is! Map || response['data'] is! Map) {
        throw const ApiFailure('Unable to read image progress. Please retry.');
      }
      image = Map<String, dynamic>.from(response['data'] as Map);
    }
    if (['FAILED', 'ERROR'].contains(image['status'])) {
      throw const ApiFailure(
        'The image provider could not complete this request. Try another enabled model.',
      );
    }
    final output = image['output'];
    if (output is! String ||
        output.trim().isEmpty ||
        output.contains('loading.svg')) {
      throw const ApiFailure(
        'The provider returned no completed image. Please retry.',
      );
    }
    final url = api.origin.resolve(output);
    if (url.scheme != 'https' || url.userInfo.isNotEmpty) {
      throw const ApiFailure('The server returned an insecure image link.');
    }
    return url.toString();
  }
}
