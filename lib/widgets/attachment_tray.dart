import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/extension_workflow_service.dart';

class AttachmentTray extends StatelessWidget {
  final List<WorkflowFile> files;
  final ValueChanged<int>? onRemove;
  final double? progress;
  const AttachmentTray({
    super.key,
    required this.files,
    this.onRemove,
    this.progress,
  });
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (files.isNotEmpty)
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final file = files[index];
              return Container(
                width: 210,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    if (file.mimeType?.startsWith('image/') == true)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          Uint8List.fromList(file.bytes),
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.image_not_supported),
                        ),
                      )
                    else
                      const Icon(Icons.insert_drive_file_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${(file.bytes.length / 1024).toStringAsFixed(0)} KB',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: appTr('Remove attachment'),
                      onPressed: onRemove == null
                          ? null
                          : () => onRemove!(index),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      if (progress != null)
        LinearProgressIndicator(
          value: progress,
          semanticsLabel: appTr('Uploading attachment'),
        ),
    ],
  );
}
