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

import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

/// The Model Manager's HuggingFace search state: the query field, the
/// filters, the results with their file lists, and the in-flight / error
/// flags. Owned by the page so a search survives switching tabs; listeners
/// rebuild on every change.
class ModelSearchController extends ChangeNotifier {
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  List<HFModel> _results = [];
  Map<String, HFModel> _modelsWithFiles = {};
  HfSearchOptions _options = const HfSearchOptions();
  bool _isSearching = false;
  String? _error;
  bool _disposed = false;

  /// Bumped by every search; a reply whose number is no longer current was
  /// overtaken by a newer search and is dropped.
  int _seq = 0;

  List<HFModel> get results => _results;
  Map<String, HFModel> get modelsWithFiles => _modelsWithFiles;
  HfSearchOptions get options => _options;
  bool get isSearching => _isSearching;
  String? get error => _error;

  /// Changes the filters and, when there is a query, searches again.
  void setOptions(HfSearchOptions options, ModelManager modelManager) {
    _options = options;
    notifyListeners();
    if (textController.text.trim().isNotEmpty) search(modelManager);
  }

  /// Search HuggingFace for the field's text, then fetch every hit's files.
  Future<void> search(ModelManager modelManager) async {
    final query = textController.text.trim();
    if (query.isEmpty) return;

    final seq = ++_seq;
    bool current() => !_disposed && seq == _seq;

    _isSearching = true;
    _results = [];
    _modelsWithFiles = {};
    _error = null;
    notifyListeners();

    try {
      // The plain search keeps its long-standing entry point (test doubles
      // of ModelManager override it); filters take the filtered one.
      final results = _options.isDefault
          ? await modelManager.searchHFModels(query)
          : await modelManager.searchHFModelsFiltered(query, options: _options);
      if (!current()) return;

      if (results.isEmpty) {
        _isSearching = false;
        notifyListeners();
        return;
      }

      final modelsWithFiles = await modelManager.fetchFilesForModels(results);
      if (!current()) return;

      _results = results;
      _modelsWithFiles = modelsWithFiles;
      _isSearching = false;
      notifyListeners();
    } catch (e) {
      if (!current()) return;
      _isSearching = false;
      _error = 'Search failed: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
