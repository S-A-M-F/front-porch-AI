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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class UiSettingsDialog extends StatelessWidget {
  const UiSettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);

    final backgrounds = [
      _buildBgThumbnail(storageService, 'none', 'None', null),
      _buildBgThumbnail(storageService, 'cyberpunk_bedroom', 'Cyberpunk', 'assets/backgrounds/cyberpunk_bedroom.png'),
      _buildBgThumbnail(storageService, 'coffee_shop', 'Coffee Shop', 'assets/backgrounds/coffee_shop.png'),
      _buildBgThumbnail(storageService, 'beach', 'Beach', 'assets/backgrounds/beach.png'),
      _buildBgThumbnail(storageService, 'futuristic_city', 'Neon City', 'assets/backgrounds/futuristic_city.png'),
      _buildBgThumbnail(storageService, 'edm_rave', 'EDM Rave', 'assets/backgrounds/edm_rave.png'),
      _buildBgThumbnail(storageService, 'cozy_library', 'Library', 'assets/backgrounds/cozy_library.png'),
      _buildBgThumbnail(storageService, 'rainy_japan', 'Rainy Japan', 'assets/backgrounds/rainy_japan.png'),
      _buildBgThumbnail(storageService, 'space_station', 'Space', 'assets/backgrounds/space_station.png'),
      _buildBgThumbnail(storageService, 'enchanted_forest', 'Forest', 'assets/backgrounds/enchanted_forest.png'),
      _buildBgThumbnail(storageService, 'anime_cherry_blossom', 'Sakura', 'assets/backgrounds/anime_cherry_blossom.png'),
      _buildBgThumbnail(storageService, 'anime_rooftop', 'Rooftop', 'assets/backgrounds/anime_rooftop.png'),
      _buildBgThumbnail(storageService, 'anime_rooftop_sunset', 'Sunset', 'assets/backgrounds/anime_rooftop_sunset.png'),
      _buildBgThumbnail(storageService, 'cherry_blossom', 'Blossom', 'assets/backgrounds/cherry_blossom.png'),
      _buildBgThumbnail(storageService, 'beach_waves', 'Waves', 'assets/backgrounds/beach_waves.png'),
      _buildBgThumbnail(storageService, 'waifu_gaming_room', 'Waifu Game', 'assets/backgrounds/waifu_gaming_room.png'),
      _buildBgThumbnail(storageService, 'waifu_beach_bar', 'Waifu Bar', 'assets/backgrounds/waifu_beach_bar.png'),
      _buildBgThumbnail(storageService, 'waifu_garden', 'Waifu Garden', 'assets/backgrounds/waifu_garden.png'),
      _buildBgThumbnail(storageService, 'waifu_neon', 'Waifu Neon', 'assets/backgrounds/waifu_neon.png'),
      _buildBgThumbnail(storageService, 'waifu_beach', 'Waifu Beach', 'assets/backgrounds/waifu_beach.png'),
    ];

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        height: 680,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('UI Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 20),

            // ── Appearance ──────────────────────────────────────────────
            const Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 12),
            _buildSlider(
              'Bubble Opacity',
              storageService.bubbleOpacity,
              0.1, 1.0,
              (val) => storageService.setBubbleOpacity(val),
              divisions: 18,
            ),
            const SizedBox(height: 4),
            _buildSlider(
              'Chat Text Size',
              storageService.textScale,
              0.5, 2.0,
              (val) => storageService.setTextScale(val),
              divisions: 30,
            ),
            const SizedBox(height: 20),

            // ── Chat Background ─────────────────────────────────────────
            const Text('Chat Background', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: backgrounds,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, {int? divisions}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            Text(value.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: Colors.blueAccent,
          inactiveColor: Colors.white24,
        ),
      ],
    );
  }

  Widget _buildBgThumbnail(StorageService storageService, String key, String label, String? assetPath) {
    final isSelected = storageService.chatBackground == key;
    return GestureDetector(
      onTap: () => storageService.setChatBackground(key),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white24,
            width: isSelected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (assetPath != null)
              Image.asset(assetPath, fit: BoxFit.cover)
            else
              Container(
                color: const Color(0xFF111827),
                child: const Center(child: Icon(Icons.block, color: Colors.white38, size: 28)),
              ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.black54,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
