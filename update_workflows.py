import sys

def replace_dmg_with_pkg(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Define the old block to replace in nightly.yml
    # This might require some careful regex or split
    old_start = "# Notarize the .app BEFORE packaging it into the DMG"
    old_end = "✓ Build complete: DMG and inner .app are fully notarized and stapled!\""

    if old_start in content and old_end in content:
        start_idx = content.find(old_start)
        end_idx = content.find(old_end) + len(old_end) + 1
        
        # We also need to remove any trailing whitespace/newlines of the block
        
        new_block = """# Notarize the .app BEFORE packaging it into the PKG so Apple issues a ticket for its CDHash
      - name: Notarize and Staple .app (pre-PKG)
        if: matrix.platform == 'macos'
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_ID_PASSWORD: ${{ secrets.APPLE_ID_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          APP_NAME=$(ls -d ${{ matrix.build_path }}/*.app | head -1)
          APP_ZIP="${APP_NAME%.app}.zip"

          echo "Creating ZIP of signed .app for notarization submission..."
          ditto -c -k --keepParent "$APP_NAME" "$APP_ZIP"

          echo "Submitting .app to Apple notary service (this may take 1–5 minutes)..."
          xcrun notarytool submit "$APP_ZIP" \\
            --apple-id "$APPLE_ID" \\
            --password "$APPLE_ID_PASSWORD" \\
            --team-id "$APPLE_TEAM_ID" \\
            --wait || { echo "ERROR: .app notarization failed"; exit 1; }

          rm -f "$APP_ZIP"
          echo "✓ .app is notarized. CDHash is now known to Apple."

          echo "Stapling .app..."
          xcrun stapler staple "$APP_NAME"
          xcrun stapler validate "$APP_NAME" || { echo "ERROR: .app staple validation failed"; exit 1; }
          echo "✓ .app is stapled."

      - name: Build macOS PKG
        if: matrix.platform == 'macos'
        env:
          MACOS_INSTALLER_CERT_NAME: ${{ secrets.MACOS_INSTALLER_CERT_NAME }}
        run: |
          cd build/macos/Build/Products/Release
          APP_NAME=$(ls -d *.app | head -1)
          PKG_NAME="Front_Porch_AI_Nightly.pkg"
          if [[ "${{ github.workflow }}" == *"Release"* ]]; then
            VERSION="${{ github.event.release.tag_name || github.ref_name }}"
            PKG_NAME="Front_Porch_AI_${VERSION}.pkg"
          fi
          UNSIGNED_PKG="unsigned_${PKG_NAME}"
          
          echo "Building unsigned .pkg..."
          pkgbuild \\
            --component "$APP_NAME" \\
            --install-location /Applications \\
            "$UNSIGNED_PKG" || { echo "ERROR: pkgbuild failed"; exit 1; }
            
          echo "Signing .pkg with Installer cert..."
          productsign --sign "$MACOS_INSTALLER_CERT_NAME" "$UNSIGNED_PKG" "$PKG_NAME" || { echo "ERROR: productsign failed"; exit 1; }
          rm -f "$UNSIGNED_PKG"
          echo "✓ PKG created successfully: $PKG_NAME"

      - name: Clean quarantine/FinderInfo from PKG file only (before notarization)
        if: matrix.platform == 'macos'
        run: |
          cd build/macos/Build/Products/Release
          PKG_NAME="Front_Porch_AI_Nightly.pkg"
          if [[ "${{ github.workflow }}" == *"Release"* ]]; then
            VERSION="${{ github.event.release.tag_name || github.ref_name }}"
            PKG_NAME="Front_Porch_AI_${VERSION}.pkg"
          fi
          if [ -f "$PKG_NAME" ]; then
            echo "Light xattr cleanup on PKG file only (not recursive)"
            xattr -d com.apple.quarantine "$PKG_NAME" 2>/dev/null || true
            xattr -d com.apple.FinderInfo "$PKG_NAME" 2>/dev/null || true
          fi

      - name: Submit final PKG to notarization and Staple
        if: matrix.platform == 'macos'
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_ID_PASSWORD: ${{ secrets.APPLE_ID_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          cd build/macos/Build/Products/Release
          PKG_NAME="Front_Porch_AI_Nightly.pkg"
          if [[ "${{ github.workflow }}" == *"Release"* ]]; then
            VERSION="${{ github.event.release.tag_name || github.ref_name }}"
            PKG_NAME="Front_Porch_AI_${VERSION}.pkg"
          fi
          
          echo "Submitting PKG for notarization..."
          xcrun notarytool submit "$PKG_NAME" \\
            --apple-id "$APPLE_ID" \\
            --password "$APPLE_ID_PASSWORD" \\
            --team-id "$APPLE_TEAM_ID" \\
            --wait || { echo "ERROR: PKG notarization failed"; exit 1; }
          
          echo "Stapling notarization ticket to PKG..."
          xcrun stapler staple "$PKG_NAME"
          xcrun stapler validate "$PKG_NAME" \\
            && echo "✓ PKG staple verified" \\
            || { echo "⚠ PKG staple validation failed"; exit 1; }
          
          echo "✓ Build complete: PKG and inner .app are fully notarized and stapled!"
"""
        
        content = content[:start_idx] + new_block + content[end_idx:]
        
    # Replace .dmg references in artifacts and releases.
    # BUT: intentionally leave alone any lines that mention "shim", "unsigned",
    # "legacy", or the transitional DMG bridge — those are the one-last unsigned
    # .dmg shims we must keep publishing under the exact legacy names.
    # (This script is a one-time porting helper; shims are the exception.)
    lines = content.splitlines(keepends=True)
    new_lines = []
    # Exact legacy basename allow-list (case-insensitive) so bare entries in
    # artifact "files:" lists and gh-release files: blocks are never rewritten
    # (e.g. "  Front_Porch_AI_Nightly.dmg" in upload lists). This protects the
    # "one last" shim contract even when the line has no "shim" keyword.
    legacy_dmgs = ['front_porch_ai_nightly.dmg', 'front_porch_ai_macos.dmg', 'front_porch_ai.dmg']
    for line in lines:
        llower = line.lower()
        has_legacy = any(legacy in llower for legacy in legacy_dmgs)
        if ('.dmg' in llower) and (has_legacy or any(k in llower for k in ['shim', 'unsigned', 'legacy', 'bridge', 'transition', 'last '])):
            new_lines.append(line)
        else:
            line = line.replace("Front_Porch_AI_Nightly.dmg", "Front_Porch_AI_Nightly.pkg")
            line = line.replace("Front_Porch_AI_${{ github.event.release.tag_name }}.dmg", "Front_Porch_AI_${{ github.event.release.tag_name }}.pkg")
            line = line.replace("Front_Porch_AI_${{ github.ref_name }}.dmg", "Front_Porch_AI_${{ github.ref_name }}.pkg")
            new_lines.append(line)
    content = ''.join(new_lines)
    
    with open(filepath, 'w') as f:
        f.write(content)
        
replace_dmg_with_pkg('.github/workflows/nightly.yml')
replace_dmg_with_pkg('.github/workflows/release.yml')
