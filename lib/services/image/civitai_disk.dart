// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/utils/utils.dart';

/// Free bytes on the volume that holds [path], or null when this platform
/// will not say. The probe itself is shared with the model downloader.
Future<int?> civitaiFreeDiskBytes(String path) => freeDiskBytes(path);
