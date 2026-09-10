import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/providers/app_providers.dart';
import 'opml_service.dart';

/// Helper service for UI-triggered file-based OPML import and export workflows.
class OpmlUiHelper {
  /// Opens a native save file dialog to export all podcast subscriptions as an OPML file.
  static Future<void> exportOpml(
    BuildContext context,
    WidgetRef ref, {
    FilePickerPlatform? filePicker,
  }) async {
    final db = ref.read(databaseProvider);
    final podcasts = await db.getAllPodcasts();

    if (!context.mounted) return;

    if (podcasts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No subscriptions to export.')),
      );
      return;
    }

    final savedPath = await OpmlService.exportOpmlToFile(
      podcasts: podcasts,
      filePicker: filePicker,
    );

    if (!context.mounted) return;

    if (savedPath != null) {
      final fileName = p.basename(savedPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${podcasts.length} subscriptions to $fileName',
          ),
        ),
      );
    }
  }

  /// Opens a native file picker to pick an OPML/XML file, presents a confirmation dialog
  /// showing the parsed podcast outlines and sync toggle, then imports into the local database.
  static Future<void> importOpml(
    BuildContext context,
    WidgetRef ref, {
    FilePickerPlatform? filePicker,
  }) async {
    final fileResult = await OpmlService.pickOpmlFile(filePicker: filePicker);

    if (!context.mounted) return;

    // User canceled the file picker
    if (fileResult == null) return;

    // File contains no valid outlines
    if (fileResult.outlines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No valid podcast subscriptions found in "${fileResult.fileName}".',
          ),
        ),
      );
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Show preview and confirmation dialog
    final confirmedData = await showDialog<({bool confirmed, bool syncWithServer})>(
      context: context,
      builder: (dialogCtx) => OpmlImportPreviewDialog(fileResult: fileResult),
    );

    if (!context.mounted) return;

    if (confirmedData != null && confirmedData.confirmed) {
      final db = ref.read(databaseProvider);
      final syncWithServer = confirmedData.syncWithServer;

      final imported = await OpmlService.importOpml(
        fileResult.xmlContent,
        db,
        syncWithServer: syncWithServer,
      );

      await ref.read(podcastsNotifierProvider.notifier).loadPodcasts();

      if (syncWithServer) {
        ref
            .read(syncStatusNotifierProvider.notifier)
            .pushBacklog()
            .catchError((_) => false);
      }

      if (!context.mounted) return;

      final totalInFile = fileResult.outlines.length;
      final String message;
      if (imported.isEmpty) {
        message = 'All $totalInFile podcasts from "${fileResult.fileName}" are already subscribed.';
      } else if (imported.length < totalInFile) {
        message =
            'Imported ${imported.length} new podcast(s) from "${fileResult.fileName}" (${totalInFile - imported.length} already subscribed).';
      } else {
        message =
            'Successfully imported ${imported.length} podcast(s) from "${fileResult.fileName}".';
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}

/// A modal dialog displaying the parsed contents of a selected OPML file
/// for user review before importing into the local database.
class OpmlImportPreviewDialog extends StatefulWidget {
  final OpmlFileResult fileResult;

  const OpmlImportPreviewDialog({
    super.key,
    required this.fileResult,
  });

  @override
  State<OpmlImportPreviewDialog> createState() => _OpmlImportPreviewDialogState();
}

class _OpmlImportPreviewDialogState extends State<OpmlImportPreviewDialog> {
  bool _syncWithServer = true;

  @override
  Widget build(BuildContext context) {
    final outlines = widget.fileResult.outlines;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.file_download, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Import Subscriptions'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fileResult.fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Found ${outlines.length} podcast subscription${outlines.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Feeds to import (${outlines.length}):',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: outlines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final outline = outlines[index];
                    final displayTitle = outline.title.isNotEmpty
                        ? outline.title
                        : (outline.text.isNotEmpty ? outline.text : outline.xmlUrl);

                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.podcasts, size: 20),
                      title: Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: outline.xmlUrl.isNotEmpty
                          ? Text(
                              outline.xmlUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text(
                'Sync new feeds with gPodder',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                'Upload new subscriptions to Nextcloud / gPodder during next sync',
                style: TextStyle(fontSize: 11),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _syncWithServer,
              onChanged: (val) => setState(() => _syncWithServer = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (confirmed: false, syncWithServer: _syncWithServer)),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, (confirmed: true, syncWithServer: _syncWithServer)),
          child: Text('Import (${outlines.length})'),
        ),
      ],
    );
  }
}
