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

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class FormattedAudiobook {
  final StoryProject project;
  final File file;
  final String format;

  FormattedAudiobook({required this.project, required this.file, required this.format});
}

/// A background compiler that utilizes Kokoro parallel batching to build an audiobook.
/// Stitches WAV chunks using pure Dart — zero external dependencies, zero user setup.
class AudiobookGeneratorService extends ChangeNotifier {
  final TtsService _ttsService;
  final StorageService _storageService;

  bool _isGenerating = false;
  double _progress = 0.0;
  String _status = '';
  
  bool get isGenerating => _isGenerating;
  double get progress => _progress;
  String get status => _status;

  AudiobookGeneratorService(this._ttsService, this._storageService);

  /// Stop compilation mid-way (aborts loop)
  void stop() {
    if (_isGenerating) {
      _isGenerating = false;
      _status = 'Aborted.';
      notifyListeners();
    }
  }

  /// Builds the full novel into a downloadable `.wav` audio file.
  /// Uses pure Dart WAV concatenation — no ffmpeg or external tools required.
  Future<FormattedAudiobook?> generateAudiobook(StoryProject project) async {
    if (_isGenerating || !_storageService.ttsEnabled) return null;
    
    _isGenerating = true;
    _progress = 0.0;
    _status = 'Preparing structured story beats...';
    notifyListeners();

    final compiledAudioParts = <File>[];
    
    // 1. Gather all prose blocks sequentially
    final sequentialTexts = <String>[];
    
    // Standard book title sequence
    sequentialTexts.add("${project.title}. A story by Front Porch A I.");
    if (project.cast.isNotEmpty) {
      sequentialTexts.add("Starring ${project.cast.map((c) => c.name).join(', ')}.");
    }

    // Traverse the acts and scenes
    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      sequentialTexts.add("Act ${act.number}. ${act.title}.");

      final scenes = project.scenes[actIdx] ?? [];
      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final beats = project.beats['$actIdx-$sceneIdx'] ?? [];
        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final beatProse = project.prose['$actIdx-$sceneIdx-$beatIdx'];
          if (beatProse != null) {
            final text = beatProse.final_ ?? beatProse.draft ?? '';
            if (text.trim().isNotEmpty) {
              sequentialTexts.add(text);
            }
          }
        }
      }
    }

    if (sequentialTexts.isEmpty) {
      _status = 'No prose to generate.';
      _isGenerating = false;
      notifyListeners();
      return null;
    }

    try {
      // 2. Loop and generate TTS chunks to temporary WAV files
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < sequentialTexts.length; i++) {
        if (!_isGenerating) throw Exception('Generation aborted by user.');
        
        // Calculate ETA from average time per block
        String eta = '';
        if (i > 0) {
          final avgMs = stopwatch.elapsedMilliseconds / i;
          final remainingMs = (avgMs * (sequentialTexts.length - i)).round();
          eta = ' • ~${_formatDuration(remainingMs)} remaining';
        }
        
        _status = 'Synthesizing block ${i + 1} of ${sequentialTexts.length}...$eta';
        _progress = (i / sequentialTexts.length) * 0.85;
        notifyListeners();

        final wavPart = await _ttsService.generateAudioFile(sequentialTexts[i]);
        if (wavPart != null && wavPart.existsSync()) {
          compiledAudioParts.add(wavPart);
        }
      }

      if (compiledAudioParts.isEmpty) throw Exception('No audio files generated.');

      // 3. Stitch WAV files using pure Dart — zero external tools!
      _status = 'Stitching ${compiledAudioParts.length} audio segments...';
      _progress = 0.90;
      notifyListeners();

      final tempDir = Directory.systemTemp;
      final outputWav = File(p.join(tempDir.path, 'audiobook_${project.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.wav'));
      
      await _concatenateWavFiles(compiledAudioParts, outputWav);

      _progress = 1.0;
      _status = 'Audiobook generation complete!';
      _isGenerating = false;
      notifyListeners();

      // Cleanup temp parts
      _cleanupParts(compiledAudioParts);

      return FormattedAudiobook(project: project, file: outputWav, format: 'wav');
    } catch (e) {
      print('Audiobook Generator Error: $e');
      _status = 'Error: $e';
      _isGenerating = false;
      notifyListeners();
      _cleanupParts(compiledAudioParts);
      return null;
    }
  }

  /// Concatenates multiple WAV files into a single WAV by reading raw PCM data
  /// from each file, skipping headers, and writing a new combined header.
  /// This is pure Dart — no ffmpeg, no system tools, no user setup.
  Future<void> _concatenateWavFiles(List<File> parts, File output) async {
    // Read the first file to determine audio format parameters
    final firstBytes = await parts.first.readAsBytes();
    if (firstBytes.length < 44) throw Exception('Invalid WAV file (too small).');

    // Parse WAV header from the first file
    final byteData = ByteData.sublistView(firstBytes);
    final audioFormat = byteData.getUint16(20, Endian.little);
    final numChannels = byteData.getUint16(22, Endian.little);
    final sampleRate = byteData.getUint32(24, Endian.little);
    final bitsPerSample = byteData.getUint16(34, Endian.little);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final byteRate = sampleRate * blockAlign;

    // Collect raw PCM data from all parts (skip the 44-byte WAV header of each)
    final pcmChunks = <Uint8List>[];
    int totalPcmBytes = 0;

    for (final part in parts) {
      final bytes = await part.readAsBytes();
      if (bytes.length <= 44) continue;

      // Find the 'data' subchunk by scanning for 'data' marker
      int dataOffset = 44; // Default standard offset
      for (int i = 12; i < bytes.length - 8; i++) {
        if (bytes[i] == 0x64 && bytes[i + 1] == 0x61 && 
            bytes[i + 2] == 0x74 && bytes[i + 3] == 0x61) { // 'data'
          dataOffset = i + 8; // Skip 'data' + 4-byte size field
          break;
        }
      }

      if (dataOffset < bytes.length) {
        final pcm = bytes.sublist(dataOffset);
        pcmChunks.add(Uint8List.fromList(pcm));
        totalPcmBytes += pcm.length;
      }
    }

    if (totalPcmBytes == 0) throw Exception('No audio data found in WAV chunks.');

    // Build the combined WAV file with a proper header
    final totalFileSize = 36 + totalPcmBytes; // 36 bytes of header metadata + PCM
    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, totalFileSize, Endian.little); // File size - 8
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt subchunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little);           // Subchunk1 size (PCM = 16)
    header.setUint16(20, audioFormat, Endian.little);   // Audio format
    header.setUint16(22, numChannels, Endian.little);   // Channels
    header.setUint32(24, sampleRate, Endian.little);    // Sample rate
    header.setUint32(28, byteRate, Endian.little);      // Byte rate
    header.setUint16(32, blockAlign, Endian.little);    // Block align
    header.setUint16(34, bitsPerSample, Endian.little); // Bits per sample

    // data subchunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, totalPcmBytes, Endian.little); // Data size

    // Write complete file: header + all PCM chunks
    final sink = output.openWrite();
    sink.add(header.buffer.asUint8List());
    for (final chunk in pcmChunks) {
      sink.add(chunk);
    }
    await sink.close();
  }

  void _cleanupParts(List<File> parts) {
    for (final f in parts) {
      try { if (f.existsSync()) f.deleteSync(); } catch (_) {}
    }
  }

  String _formatDuration(int ms) {
    final seconds = (ms / 1000).round();
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes < 60) return '${minutes}m ${secs}s';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }
}
