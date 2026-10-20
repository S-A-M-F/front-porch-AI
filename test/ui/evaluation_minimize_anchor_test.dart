// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import '../golden/support/fakes.dart';

// The verification phase streams like the eval does but has no Stop button,
// whose private ChatService read a fake cannot answer.
class StreamingChat extends FakeChatService {
  StreamingChat() : super(verificationPass: 1, verificationMaxPasses: 2);
  String stream = '';
  @override
  bool get isVerifyingRealism => true;
  @override
  String get realismEvalStreamTextClean => stream;
}

void main() {
  testWidgets('Minimize stays put when the live eval stream arrives', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chat = StreamingChat();
    addTearDown(chat.dispose);
    Future<void> render() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              RealismProcessingOverlay(
                chatService: chat,
                isGreeting: false,
                onMinimize: () {},
              ),
            ],
          ),
        ),
      ),
    );
    final minimize = find.text('Minimize evaluation');

    await render();
    await tester.pump(const Duration(milliseconds: 500));
    final before = tester.getTopLeft(minimize);

    chat.stream = List.filled(40, 'relationship +1, trust steady').join('\n');
    await render();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('LIVE EVAL STREAM'), findsOneWidget);
    expect(tester.getTopLeft(minimize), before);
  });
}
