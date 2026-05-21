// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:front_porch_ai/services/update_service.dart';

/// Dialog shown when a new version is available.
/// Three stages: prompt → downloading → ready to install.
/// User can always dismiss — never forced.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: Provider.of<UpdateService>(context, listen: false),
        child: const UpdateDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateService>(
      builder: (context, service, _) {
        if (service.downloadComplete) {
          return _buildReadyToInstallDialog(context, service);
        }
        if (service.downloading) {
          return _buildDownloadingDialog(context, service);
        }
        return _buildPromptDialog(context, service);
      },
    );
  }

  /// Stage 1: "A new version is available, would you like to download?"
  Widget _buildPromptDialog(BuildContext context, UpdateService service) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.system_update, color: Colors.greenAccent, size: 28),
          const SizedBox(width: 12),
          const Text('Update Available', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              children: [
                const TextSpan(
                  text: 'A new version of Front Porch AI is available.\n\n',
                ),
                const TextSpan(
                  text: 'Current: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white54,
                  ),
                ),
                TextSpan(text: '${service.displayCurrentVersion}\n'),
                const TextSpan(
                  text: 'Latest: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                ),
                TextSpan(text: '${service.displayLatestVersion}\n'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildChangelogSection(context, service),
          const SizedBox(height: 16),
          const Text(
            'Would you like to download the update?',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          const Text(
            '☕ Enjoying Front Porch AI?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This project is free, open source, and built with love. If you enjoy this program please consider buying me a coffee. It helps keep development going!',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  launchUrl(Uri.parse('https://ko-fi.com/sosukeaizen37411')),
              icon: const Icon(Icons.coffee_outlined, size: 18),
              label: const Text('Support on Ko-fi'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF5E5B),
                side: const BorderSide(color: Color(0xFFFF5E5B), width: 1),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not Now', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          onPressed: () => service.downloadUpdate(),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Download'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  /// Renders the non-technical "What's New" changelog from the GitHub release body.
  /// Uses flutter_markdown (already a dependency) inside a constrained scroll area
  /// so long release notes do not blow out the AlertDialog.
  /// Empty state gracefully falls back to a GitHub link (covers the case where
  /// the release body has not yet been populated with friendly text).
  Widget _buildChangelogSection(BuildContext context, UpdateService service) {
    final notes = service.releaseNotes.trim();
    if (notes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Full release notes are available on GitHub.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final url = service.releaseUrl;
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('View on GitHub'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "What's New in ${service.displayLatestVersion}",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: MarkdownBody(
              data: notes,
              selectable: true,
              onTapLink: (text, href, title) async {
                if (href != null) {
                  await launchUrl(
                    Uri.parse(href),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
                h1: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                h2: TextStyle(
                  color: Colors.greenAccent.shade200,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                listBullet: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
                a: const TextStyle(
                  color: Colors.lightBlueAccent,
                  decoration: TextDecoration.underline,
                ),
                em: const TextStyle(
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                ),
                strong: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Stage 2: Download in progress
  Widget _buildDownloadingDialog(BuildContext context, UpdateService service) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Downloading Update...',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: service.downloadProgress > 0
                ? service.downloadProgress
                : null,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
          ),
          const SizedBox(height: 16),
          Text(
            '${(service.downloadProgress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// Stage 3: Download complete — "Ready to install now?"
  Widget _buildReadyToInstallDialog(
    BuildContext context,
    UpdateService service,
  ) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
          const SizedBox(width: 12),
          const Text('Ready to Install', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The update has been downloaded. Would you like to install it now?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            Platform.isLinux
                ? 'If you choose "Later", the update will be applied when you close the app.'
                : 'If you choose "Later", the update will install automatically when you close the app.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            try {
              await service.installNow();
            } catch (e) {
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Update failed: $e'),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            }
          },
          icon: const Icon(Icons.install_desktop, size: 18),
          label: const Text('Install Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
