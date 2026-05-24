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

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' as drift;
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/database/database.dart';

/// A retrieved memory from the vector store.
class RetrievedMemory {
  final String content;
  final String? characterId;
  final String sessionId;
  final int positionStart;
  final int positionEnd;
  final double score; // cosine similarity 0.0–1.0

  const RetrievedMemory({
    required this.content,
    this.characterId,
    required this.sessionId,
    required this.positionStart,
    required this.positionEnd,
    required this.score,
  });
}

/// Orchestrates RAG memory: embedding message windows and retrieving relevant
/// past context for prompt injection.
///
/// Works with [EmbeddingService] for vector generation and [AppDatabase] for
/// vector storage. Only activates when RAG is enabled and embeddings are available.
class MemoryService extends ChangeNotifier {
  final EmbeddingService _embeddingService;
  final StorageService _storageService;
  AppDatabase _db;

  bool _isEmbedding = false;
  int _pendingEmbeddings = 0;
  bool _availabilityChecked = false;

  bool get isEmbedding => _isEmbedding;
  int get pendingEmbeddings => _pendingEmbeddings;

  /// Expose the embedding service for use by other services (e.g. persona fact dedup).
  EmbeddingService get embeddingService => _embeddingService;

  /// Whether RAG memory is fully operational (enabled + embeddings available).
  bool get isOperational =>
      _storageService.ragEnabled && _embeddingService.isAvailable;

  /// Get all stored content chunks for the given characters, sorted chronologically.
  /// Used to ground summary generation in real conversation content.
  Future<List<String>> getAllContentForCharacters(
    List<String> characterIds,
  ) async {
    if (characterIds.isEmpty) return [];
    final embeddings = await _db.getEmbeddingsForCharacters(characterIds);
    // Sort by messageIndex (chronological order)
    embeddings.sort((a, b) => a.positionStart.compareTo(b.positionStart));
    return embeddings.map((e) => e.content).toList();
  }

  MemoryService(this._embeddingService, this._storageService, this._db);

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  /// Maximum characters per embedding window. Embedding models have limited
  /// context, and large texts are very slow on CPU ONNX. 2000 chars ≈ 500 tokens.
  static const int _maxEmbedChars = 2000;

  /// Strip <think>...</think> blocks and truncate for embedding.
  String _cleanForEmbedding(String text) {
    // Remove think blocks (LLM reasoning, not conversation content)
    final cleaned = text
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .trim();
    if (cleaned.length <= _maxEmbedChars) return cleaned;
    return cleaned.substring(0, _maxEmbedChars);
  }

  /// Embed a sliding window of messages and store the vectors.
  ///
  /// Called asynchronously after each message generation. Embeds messages
  /// in windows of [ragWindowSize] messages, skipping windows that are
  /// already embedded (by checking existing position ranges).
  Future<void> embedMessageWindow({
    required String sessionId,
    required String characterId,
    required List<String> formattedMessages,
    required int totalMessageCount,
  }) async {
    // Lazy availability check — run once on first use
    if (!_availabilityChecked) {
      _availabilityChecked = true;
      debugPrint('[RAG:Memory] Checking embedding availability...');
      await _embeddingService.checkAvailability();
    }
    if (!isOperational) {
      debugPrint(
        '[RAG:Memory] embedMessageWindow skipped — not operational (enabled=${_storageService.ragEnabled}, available=${_embeddingService.isAvailable})',
      );
      return;
    }

    debugPrint(
      '[RAG:Memory] ── Embedding session $sessionId (char: $characterId, ${formattedMessages.length} msgs, total: $totalMessageCount) ──',
    );

    _isEmbedding = true;
    _pendingEmbeddings++;
    notifyListeners();

    try {
      final windowSize = _storageService.ragWindowSize;

      // Get existing embeddings to avoid re-embedding
      final existing = await _db.getEmbeddingsForSession(sessionId);
      final existingRanges = existing
          .map((e) => (e.positionStart, e.positionEnd))
          .toSet();

      debugPrint(
        '[RAG:Memory] Existing embeddings: ${existing.length}, window size: $windowSize',
      );

      // Build windows from oldest to newest
      final newWindows = <({int start, int end, String text})>[];

      for (
        int i = 0;
        i <= formattedMessages.length - windowSize;
        i += windowSize
      ) {
        final end = (i + windowSize - 1).clamp(0, formattedMessages.length - 1);
        final range = (i, end);

        if (existingRanges.contains(range)) {
          continue; // Already embedded
        }

        final windowText = formattedMessages.sublist(i, end + 1).join('\n');
        final cleanedText = _cleanForEmbedding(windowText);
        if (cleanedText.isEmpty) continue; // Skip if only think blocks
        newWindows.add((start: i, end: end, text: cleanedText));
      }

      if (newWindows.isEmpty) {
        debugPrint(
          '[RAG:Memory] No new windows to embed (all ${existingRanges.length} windows already stored)',
        );
        return;
      }

      debugPrint(
        '[RAG:Memory] ▶ Embedding ${newWindows.length} new window(s)...',
      );

      // Embed each window and store
      int stored = 0;
      for (final window in newWindows) {
        debugPrint(
          '[RAG:Memory]   Window [${window.start}-${window.end}] (${window.text.length} chars)...',
        );
        final vector = await _embeddingService.embed(window.text);
        if (vector == null) {
          debugPrint(
            '[RAG:Memory]   ✗ Embedding returned null for window [${window.start}-${window.end}]',
          );
          continue;
        }

        final bytes = Float32List.fromList(
          vector.map((e) => e.toDouble()).toList(),
        );

        await _db.insertEmbedding(
          MessageEmbeddingsCompanion(
            sessionId: drift.Value(sessionId),
            characterId: drift.Value(characterId),
            positionStart: drift.Value(window.start),
            positionEnd: drift.Value(window.end),
            content: drift.Value(window.text),
            embedding: drift.Value(Uint8List.view(bytes.buffer)),
            dimensions: drift.Value(vector.length),
          ),
        );
        stored++;
        debugPrint(
          '[RAG:Memory]   ✅ Stored in DB (${vector.length}d, ${bytes.lengthInBytes} bytes)',
        );
      }

      debugPrint(
        '[RAG:Memory] ── Done: $stored/${newWindows.length} windows stored ──',
      );
    } catch (e) {
      debugPrint('[RAG:Memory] ✗ Embedding failed: $e');
    } finally {
      _pendingEmbeddings--;
      _isEmbedding = _pendingEmbeddings > 0;
      notifyListeners();
    }
  }

  /// Stores a long-term salient Needs event (e.g. major pleasure spike or
  /// embarrassing catastrophe) into the RAG vector store, tagged with
  /// memoryType='needs_event' and JSON metadata.
  ///
  /// The [narrative] should be a rich, self-contained description in the style
  /// of an internal memory (e.g. "I felt overwhelming pleasure when...").
  /// Caller is responsible for calling this ONLY when needsSimEnabled.
  /// Reuses the same embedding + storage path as message windows.
  Future<void> storeNeedsEventMemory({
    required String narrative,
    required String characterId,
    required String sessionId,
    required int magnitude,
    required String category,
    String? extraMetadataJson,
  }) async {
    if (!_availabilityChecked) {
      _availabilityChecked = true;
      debugPrint('[RAG:Memory] Checking embedding availability...');
      await _embeddingService.checkAvailability();
    }
    if (!isOperational) {
      debugPrint(
        '[RAG:Memory] storeNeedsEventMemory skipped — RAG not operational',
      );
      return;
    }
    if (narrative.trim().isEmpty) {
      debugPrint(
        '[RAG:Memory] storeNeedsEventMemory skipped — empty narrative',
      );
      return;
    }

    debugPrint(
      '[RAG:Memory] ── Storing needs_event (char=$characterId, category=$category, mag=$magnitude, session=$sessionId) ──',
    );

    try {
      final cleaned = _cleanForEmbedding(narrative);
      final textForEmbed = cleaned.isNotEmpty ? cleaned : narrative;

      final vector = await _embeddingService.embed(textForEmbed);
      if (vector == null) {
        debugPrint('[RAG:Memory] ✗ Failed to embed needs_event narrative');
        return;
      }

      final bytes = Float32List.fromList(
        vector.map((e) => e.toDouble()).toList(),
      );
      final embeddingBytes = Uint8List.view(bytes.buffer);

      final Map<String, dynamic> meta = {
        'category': category,
        'magnitude': magnitude,
        'createdAt': DateTime.now().toIso8601String(),
      };
      if (extraMetadataJson != null && extraMetadataJson.isNotEmpty) {
        try {
          final extra = jsonDecode(extraMetadataJson) as Map<String, dynamic>;
          meta.addAll(extra);
        } catch (_) {
          meta['extra'] = extraMetadataJson;
        }
      }
      final metadataJson = jsonEncode(meta);

      await _db.insertEmbedding(
        MessageEmbeddingsCompanion(
          sessionId: drift.Value(sessionId),
          characterId: drift.Value(characterId),
          positionStart: const drift.Value(-1),
          positionEnd: const drift.Value(-1),
          content: drift.Value(narrative),
          embedding: drift.Value(embeddingBytes),
          dimensions: drift.Value(vector.length),
          memoryType: const drift.Value('needs_event'),
          metadata: drift.Value(metadataJson),
        ),
      );

      debugPrint(
        '[RAG:Memory] ✅ Stored needs_event (${vector.length}d, ${embeddingBytes.lengthInBytes} bytes, meta: $metadataJson)',
      );
    } catch (e) {
      debugPrint('[RAG:Memory] ✗ storeNeedsEventMemory failed: $e');
    }
  }

  /// Retrieve relevant past memories for the current conversation context.
  ///
  /// Embeds the [queryText] (typically the last 2-3 messages), then searches
  /// the vector store for similar message windows. Only searches embeddings
  /// from the specified [sourceCharacterIds] and excludes any from the
  /// [currentSessionId] that fall within the [inContextPositions] range.
  Future<List<RetrievedMemory>> retrieve({
    required String queryText,
    required List<String> sourceCharacterIds,
    required String currentSessionId,
    int inContextStart = 0,
    int limit = 5,
    double minScore = 0.3,
    Map<String, double>? characterPriorities,
  }) async {
    // Lazy availability check — run once on first use
    if (!_availabilityChecked) {
      _availabilityChecked = true;
      debugPrint('[RAG:Memory] Checking embedding availability...');
      await _embeddingService.checkAvailability();
    }
    if (!isOperational || queryText.trim().isEmpty) {
      debugPrint(
        '[RAG:Memory] retrieve() skipped — not operational or empty query',
      );
      return [];
    }

    // Skip retrieval for brand new sessions with very few messages
    if (inContextStart < 3) {
      debugPrint(
        '[RAG:Memory] retrieve() skipped - session too new (inContextStart=$inContextStart)',
      );
      return [];
    }

    final cleanedQuery = _cleanForEmbedding(queryText);
    final queryPreview = cleanedQuery.length > 100
        ? '${cleanedQuery.substring(0, 100)}...'
        : cleanedQuery;
    debugPrint(
      '[RAG:Memory] ── Retrieving memories (limit: $limit, minScore: $minScore) ──',
    );
    debugPrint('[RAG:Memory] Query: "$queryPreview"');
    debugPrint('[RAG:Memory] Source character IDs: $sourceCharacterIds');
    debugPrint(
      '[RAG:Memory] Current session: $currentSessionId, inContextStart: $inContextStart',
    );

    try {
      // Embed the query
      final queryVector = await _embeddingService.embed(cleanedQuery);
      if (queryVector == null) {
        debugPrint(
          '[RAG:Memory] ✗ Query embedding failed — aborting retrieval',
        );
        return [];
      }
      debugPrint('[RAG:Memory] Query vector: ${queryVector.length}d');

      // Get all candidate embeddings from the specified characters
      final candidates = await _db.getEmbeddingsForCharacters(
        sourceCharacterIds,
      );
      debugPrint('[RAG:Memory] Candidates from DB: ${candidates.length}');

      // Also fetch Data Bank entries with embeddings for these characters
      final dataBankCandidates = <DataBankEntry>[];
      for (final charId in sourceCharacterIds) {
        final entries = await _db.getDataBankEntriesForCharacter(charId);
        dataBankCandidates.addAll(
          entries.where((e) => e.embedding != null && e.dimensions > 0),
        );
      }
      if (dataBankCandidates.isNotEmpty) {
        debugPrint(
          '[RAG:Memory] Data Bank candidates: ${dataBankCandidates.length}',
        );
      }

      if (candidates.isEmpty && dataBankCandidates.isEmpty) {
        debugPrint(
          '[RAG:Memory] No stored embeddings or Data Bank entries found',
        );
        return [];
      }

      // Score each candidate against the query
      final scored = <RetrievedMemory>[];
      int skippedInContext = 0;
      int belowThreshold = 0;

      for (final candidate in candidates) {
        // Skip embeddings from the current session that are still in context
        if (candidate.sessionId == currentSessionId &&
            candidate.positionStart >= inContextStart) {
          skippedInContext++;
          continue;
        }

        // Deserialize the stored embedding
        final storedVector = _bytesToVector(
          candidate.embedding,
          candidate.dimensions,
        );
        if (storedVector == null) continue;

        // Calculate similarity
        final rawScore = cosineSimilarity(queryVector, storedVector);
        final priority = characterPriorities?[candidate.characterId] ?? 1.0;
        final score = rawScore * priority;

        if (score >= minScore) {
          scored.add(
            RetrievedMemory(
              content: candidate.content,
              characterId: candidate.characterId,
              sessionId: candidate.sessionId,
              positionStart: candidate.positionStart,
              positionEnd: candidate.positionEnd,
              score: score,
            ),
          );
        } else {
          belowThreshold++;
        }
      }

      // Score Data Bank entries
      for (final entry in dataBankCandidates) {
        final storedVector = _bytesToVector(entry.embedding!, entry.dimensions);
        if (storedVector == null) continue;

        final rawScore = cosineSimilarity(queryVector, storedVector);
        final priority = characterPriorities?[entry.characterId] ?? 1.0;
        final score = rawScore * priority;

        if (score >= minScore) {
          scored.add(
            RetrievedMemory(
              content: '[Data Bank: ${entry.title}] ${entry.content}',
              characterId: entry.characterId,
              sessionId: 'databank',
              positionStart: -1,
              positionEnd: -1,
              score: score,
            ),
          );
        } else {
          belowThreshold++;
        }
      }

      debugPrint(
        '[RAG:Memory] Scoring: ${scored.length} above threshold, $belowThreshold below, $skippedInContext skipped (in-context)',
      );

      // Sort by score descending and take top N
      scored.sort((a, b) => b.score.compareTo(a.score));
      final results = scored.take(limit).toList();

      if (results.isNotEmpty) {
        debugPrint('[RAG:Memory] ── Top ${results.length} results: ──');
        for (int i = 0; i < results.length; i++) {
          final m = results[i];
          final contentPreview = m.content.length > 60
              ? '${m.content.substring(0, 60)}...'
              : m.content;
          debugPrint(
            '[RAG:Memory]   #${i + 1} score=${m.score.toStringAsFixed(3)} [${m.positionStart}-${m.positionEnd}] char=${m.characterId ?? "n/a"}',
          );
          debugPrint('[RAG:Memory]       "$contentPreview"');
        }
      } else {
        debugPrint('[RAG:Memory] No results above threshold $minScore');
      }

      return results;
    } catch (e) {
      debugPrint('[RAG:Memory] ✗ Retrieval failed: $e');
      return [];
    }
  }

  /// Convert stored bytes back to a vector of doubles.
  List<double>? _bytesToVector(Uint8List bytes, int dimensions) {
    try {
      final floats = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        dimensions,
      );
      return floats.map((f) => f.toDouble()).toList();
    } catch (e) {
      debugPrint('[MemoryService] Failed to deserialize embedding: $e');
      return null;
    }
  }

  /// Cosine similarity between two vectors.
  /// Returns a value between -1.0 and 1.0 (1.0 = identical direction).
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0.0) return 0.0;

    return dotProduct / denominator;
  }

  /// Retrieve only long-term salient Needs events (memoryType == 'needs_event')
  /// via semantic vector search over the character's stored events.
  ///
  /// Unlike [retrieve], this does NOT apply in-context exclusion — Needs events
  /// are persistent character-state memories and should be recallable across
  /// sessions and even within the current chat when contextually relevant.
  /// Caller gates the call with needsSimEnabled.
  ///
  /// Reuses _cleanForEmbedding, embed, cosineSimilarity, _bytesToVector and
  /// the same scoring/priority/boost logic.
  Future<List<RetrievedMemory>> retrieveSalientNeedsEvents({
    required String queryText,
    required List<String> characterIds,
    int limit = 5,
    double minScore = 0.2,
    Map<String, double>? characterPriorities,
  }) async {
    if (!_availabilityChecked) {
      _availabilityChecked = true;
      debugPrint('[RAG:Memory] Checking embedding availability...');
      await _embeddingService.checkAvailability();
    }
    if (!isOperational || queryText.trim().isEmpty || characterIds.isEmpty) {
      debugPrint(
        '[RAG:Memory] retrieveSalientNeedsEvents skipped — not operational / empty query / no characters',
      );
      return [];
    }

    final cleanedQuery = _cleanForEmbedding(queryText);
    final queryPreview = cleanedQuery.length > 80
        ? '${cleanedQuery.substring(0, 80)}...'
        : cleanedQuery;
    debugPrint(
      '[RAG:Memory] ── [NeedsEvents] Retrieving (limit: $limit, minScore: $minScore) ──',
    );
    debugPrint('[RAG:Memory] [NeedsEvents] Query: "$queryPreview"');
    debugPrint('[RAG:Memory] [NeedsEvents] Characters: $characterIds');

    try {
      final queryVector = await _embeddingService.embed(cleanedQuery);
      if (queryVector == null) {
        debugPrint('[RAG:Memory] [NeedsEvents] ✗ Query embedding failed');
        return [];
      }
      debugPrint(
        '[RAG:Memory] [NeedsEvents] Query vector: ${queryVector.length}d',
      );

      // Fetch all for the characters, then filter to only needs_event rows
      final allCandidates = await _db.getEmbeddingsForCharacters(characterIds);
      final needsCandidates = allCandidates
          .where((e) => e.memoryType == 'needs_event')
          .toList();

      debugPrint(
        '[RAG:Memory] [NeedsEvents] Total candidates: ${allCandidates.length}, needs_events: ${needsCandidates.length}',
      );

      if (needsCandidates.isEmpty) {
        debugPrint(
          '[RAG:Memory] [NeedsEvents] No stored needs_event embeddings found',
        );
        return [];
      }

      final scored = <RetrievedMemory>[];
      int belowThreshold = 0;

      for (final candidate in needsCandidates) {
        final storedVector = _bytesToVector(
          candidate.embedding,
          candidate.dimensions,
        );
        if (storedVector == null) continue;

        final rawScore = cosineSimilarity(queryVector, storedVector);
        final priority = characterPriorities?[candidate.characterId] ?? 1.0;
        final score = rawScore * priority;

        if (score >= minScore) {
          scored.add(
            RetrievedMemory(
              content: candidate.content,
              characterId: candidate.characterId,
              sessionId: candidate.sessionId,
              positionStart: candidate.positionStart,
              positionEnd: candidate.positionEnd,
              score: score,
            ),
          );
        } else {
          belowThreshold++;
        }
      }

      debugPrint(
        '[RAG:Memory] [NeedsEvents] Scoring: ${scored.length} above threshold, $belowThreshold below',
      );

      scored.sort((a, b) => b.score.compareTo(a.score));
      final results = scored.take(limit).toList();

      if (results.isNotEmpty) {
        debugPrint(
          '[RAG:Memory] [NeedsEvents] ── Top ${results.length} event(s): ──',
        );
        for (int i = 0; i < results.length; i++) {
          final m = results[i];
          final preview = m.content.length > 70
              ? '${m.content.substring(0, 70)}...'
              : m.content;
          debugPrint(
            '[RAG:Memory] [NeedsEvents]   #${i + 1} score=${m.score.toStringAsFixed(3)} char=${m.characterId ?? "n/a"}',
          );
          debugPrint('[RAG:Memory] [NeedsEvents]       "$preview"');
        }
      } else {
        debugPrint(
          '[RAG:Memory] [NeedsEvents] No events above threshold $minScore',
        );
      }

      return results;
    } catch (e) {
      debugPrint('[RAG:Memory] [NeedsEvents] ✗ Retrieval failed: $e');
      return [];
    }
  }
}
