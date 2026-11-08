import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_phone_agent_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockPhoneAgentData = {
    'schema_version': 1,
    'kind': 'phone_agent',
    'view_type': 'agents',
    'metrics': [
      {'label': 'Total Agents', 'value': 2, 'icon': 'invoice'},
      {'label': 'Active Agents', 'value': 1, 'icon': 'paid'},
      {'label': 'Today Calls', 'value': 5, 'icon': 'calendar'},
      {'label': 'Outbound Calls', 'value': 3, 'icon': 'balance'},
    ],
    'voices': [
      {
        'voice_id': '21m00Tcm4TlvDq8ikWAM',
        'name': 'Rachel (Calm & Professional)',
        'category': 'premade',
        'labels': {'accent': 'american', 'gender': 'female', 'language': 'en'},
      },
      {
        'voice_id': 'AZnzlk1XvdvUeBnXmlld',
        'name': 'Domi (Confident & Clear)',
        'category': 'premade',
        'labels': {'accent': 'american', 'gender': 'female', 'language': 'en'},
      },
    ],
    'data': [
      {
        'id': 1,
        'uuid': 'agent-uuid-1',
        'title': 'Sales Support AI',
        'welcome_message': 'Hello, how can I help you today?',
        'instructions': 'Answer customer questions about pricing and plans.',
        'language': 'en',
        'voice_id': '21m00Tcm4TlvDq8ikWAM',
        'voice_name': 'Rachel (Calm & Professional)',
        'ai_model': 'gpt-4o-mini',
        'provider': 'elevenlabs',
        'phone_number': '+16184237161',
        'today_calls_count': 5,
        'total_calls_count': 42,
        'active': true,
        'booking_enabled': true,
        'booking_provider': 'cal_com',
        'booking_event_type_id': '12345',
        'booking_timezone': 'UTC',
      },
      {
        'id': 2,
        'uuid': 'agent-uuid-2',
        'title': 'After Hours Inquiries',
        'welcome_message': 'Thanks for calling after hours.',
        'instructions': 'Take a message and business email.',
        'language': 'en',
        'voice_id': 'AZnzlk1XvdvUeBnXmlld',
        'voice_name': 'Domi (Confident & Clear)',
        'ai_model': 'gpt-4o-mini',
        'provider': 'elevenlabs',
        'phone_number': null,
        'today_calls_count': 0,
        'total_calls_count': 10,
        'active': false,
        'booking_enabled': false,
      },
    ],
    'modules': [],
  };

  testWidgets('NativeModuleRegistry dispatches phone_agent route_type to NativePhoneAgentScreen', (tester) async {
    final api = nativeApi((path, body) async => mockPhoneAgentData);
    final module = {
      'id': 'web:ext_phone_call_agent_dashboard',
      'title': 'Phone Call Agent',
      'category': 'Phone Call Agent',
      'route_type': 'phone_agent',
      'route': 'dashboard.phone-call-agent.index',
    };

    final widget = NativeModuleRegistry.build(module, api: api);
    expect(widget, isA<NativePhoneAgentScreen>());
  });

  testWidgets('NativePhoneAgentScreen renders 3 tabs, Hero banner, KPI stat cards, and Agent cards', (tester) async {
    final api = nativeApi((path, body) async => mockPhoneAgentData);
    final module = {
      'id': 'web:ext_phone_call_agent_dashboard',
      'title': 'Phone Call Agent',
      'category': 'Phone Call Agent',
      'route_type': 'phone_agent',
      'route': 'dashboard.phone-call-agent.index',
    };

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativePhoneAgentScreen(module: module, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify 3 tabs
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Call History'), findsNWidgets(2)); // Tab + Hero button
    expect(find.text('Outbound'), findsOneWidget);

    // Verify Hero Banner
    expect(
      find.text('Create AI agents that answer real phone calls and talk just like a human.'),
      findsOneWidget,
    );
    expect(find.text('Create New Agent'), findsOneWidget);

    // Verify KPI Stat Cards
    expect(find.text('Total Agents'), findsOneWidget);
    expect(find.text('Active Agents'), findsOneWidget);
    expect(find.text('Today Calls'), findsOneWidget);
    expect(find.text('Outbound Calls'), findsNWidgets(2)); // KPI card + Hero button

    // Verify Agent Cards
    expect(find.text('Sales Support AI'), findsOneWidget);
    expect(find.text('+16184237161'), findsOneWidget);
    expect(find.text('5 Calls Today'), findsOneWidget);
    expect(find.text('After Hours Inquiries'), findsOneWidget);
    expect(find.text('No phone number attached'), findsOneWidget);
    expect(find.text('No Calls Today'), findsOneWidget);
    expect(find.text('Test Call'), findsNWidgets(2));
  });

  testWidgets('Tapping the Active switch triggers toggle_active mutation', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final api = nativeApi((path, body) async {
      if (path == '/native/records') {
        calls.add(Map<String, dynamic>.from(body));
        return {'message': 'Agent status updated.'};
      }
      return mockPhoneAgentData;
    });

    final module = {
      'id': 'web:ext_phone_call_agent_dashboard',
      'title': 'Phone Call Agent',
      'category': 'Phone Call Agent',
      'route_type': 'phone_agent',
      'route': 'dashboard.phone-call-agent.index',
    };

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativePhoneAgentScreen(module: module, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap first switch
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    expect(calls.length, 1);
    expect(calls[0]['kind'], 'phone_agent');
    expect(calls[0]['operation'], 'toggle_active');
    expect(calls[0]['record_id'], 1);
  });

  testWidgets('Create New Agent opens Wizard Sheet, validates input and saves agent', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final api = nativeApi((path, body) async {
      if (path == '/native/records') {
        calls.add(Map<String, dynamic>.from(body));
        return {'message': 'Agent saved successfully.'};
      }
      return mockPhoneAgentData;
    });

    final module = {
      'id': 'web:ext_phone_call_agent_dashboard',
      'title': 'Phone Call Agent',
      'category': 'Phone Call Agent',
      'route_type': 'phone_agent',
      'route': 'dashboard.phone-call-agent.index',
    };

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativePhoneAgentScreen(module: module, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Click "Create New Agent" button in banner
    await tester.tap(find.text('Create New Agent'));
    await tester.pumpAndSettle();

    // Modal sheet should open
    expect(find.text('Create Phone Call Agent'), findsOneWidget);
    expect(find.text('1. Configure'), findsOneWidget);
    expect(find.text('2. Train'), findsOneWidget);
    expect(find.text('3. Phone Numbers'), findsOneWidget);

    // Verify fields
    expect(find.text('Welcome Message'), findsOneWidget);
    expect(find.text('Agent Instructions (System Prompt)'), findsOneWidget);
    expect(find.text('Booking Assistant'), findsOneWidget);

    // Click Save button
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(calls.length, 1);
    expect(calls[0]['kind'], 'phone_agent');
    expect(calls[0]['operation'], 'save');
    expect(calls[0]['inputs']['title'], isNotEmpty);
  });

  testWidgets('Call History tab displays call records with duration, caller, and transcript sheet', (tester) async {
    final mockHistoryData = {
      'schema_version': 1,
      'kind': 'phone_agent',
      'view_type': 'history',
      'metrics': [
        {'label': 'Total Agents', 'value': 2, 'icon': 'invoice'},
        {'label': 'Active Agents', 'value': 1, 'icon': 'paid'},
        {'label': 'Today Calls', 'value': 5, 'icon': 'calendar'},
        {'label': 'Outbound Calls', 'value': 3, 'icon': 'balance'},
      ],
      'data': [
        {
          'id': 101,
          'caller_number': '+14155552671',
          'called_number': '+16184237161',
          'agent_title': 'Sales Support AI',
          'direction': 'inbound',
          'duration': 145,
          'status': 'completed',
          'started_at': '2026-11-08 15:30:00',
          'pinned': 1,
          'transcripts': [
            {'id': 1, 'role': 'agent', 'message': 'Hello, thanks for calling! How can I help?'},
            {'id': 2, 'role': 'user', 'message': 'Hi, I would like to ask about your pricing.'},
          ],
        },
      ],
      'stats': {'total': 1, 'completed': 1, 'failed': 0},
      'modules': [],
    };

    final api = nativeApi((path, body) async {
      if (body['view_type'] == 'history') {
        return mockHistoryData;
      }
      return mockPhoneAgentData;
    });

    final module = {
      'id': 'web:ext_phone_call_agent_dashboard',
      'title': 'Phone Call Agent',
      'category': 'Phone Call Agent',
      'route_type': 'phone_agent',
      'route': 'dashboard.phone-call-agent.index',
    };

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativePhoneAgentScreen(module: module, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Call History Tab
    await tester.tap(find.text('Call History').first);
    await tester.pumpAndSettle();

    // Verify call row
    expect(find.text('+14155552671 → +16184237161'), findsOneWidget);
    expect(find.text('Sales Support AI'), findsOneWidget);
    expect(find.text('02:25'), findsOneWidget); // 145s = 02:25
    expect(find.text('COMPLETED'), findsOneWidget);

    // Tap call row to open transcript sheet
    await tester.tap(find.text('+14155552671 → +16184237161'));
    await tester.pumpAndSettle();

    // Verify transcript conversation
    expect(find.text('Hello, thanks for calling! How can I help?'), findsOneWidget);
    expect(find.text('Hi, I would like to ask about your pricing.'), findsOneWidget);
  });

  testWidgets('Outbound tab displays outbound calls, campaigns, and opens Place a Call sheet', (tester) async {
    final mockOutboundData = {
      'schema_version': 1,
      'kind': 'phone_agent',
      'view_type': 'outbound',
      'metrics': [
        {'label': 'Total Agents', 'value': 2, 'icon': 'invoice'},
        {'label': 'Active Agents', 'value': 1, 'icon': 'paid'},
        {'label': 'Today Calls', 'value': 5, 'icon': 'calendar'},
        {'label': 'Outbound Calls', 'value': 3, 'icon': 'balance'},
      ],
      'eligible_agents': [
        {'id': 1, 'title': 'Sales Support AI', 'phone_number': '+16184237161'},
      ],
      'campaigns': [
        {
          'id': 1,
          'name': 'November Outreach Campaign',
          'agent_title': 'Sales Support AI',
          'status': 'scheduled',
          'total_recipients': 50,
          'completed_count': 12,
        },
      ],
      'data': [
        {
          'id': 201,
          'caller_number': '+16184237161',
          'called_number': '+15552345678',
          'agent_title': 'Sales Support AI',
          'direction': 'outbound',
          'duration': 65,
          'status': 'completed',
          'created_at': '2026-11-08 14:00:00',
        },
      ],
      'modules': [],
    };

    final api = nativeApi((path, body) async {
      if (body['view_type'] == 'outbound') {
        return mockOutboundData;
      }
      return mockPhoneAgentData;
    });

    final module = {
      'id': 'web:ext_phone_call_agent_dashboard',
      'title': 'Phone Call Agent',
      'category': 'Phone Call Agent',
      'route_type': 'phone_agent',
      'route': 'dashboard.phone-call-agent.index',
    };

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativePhoneAgentScreen(module: module, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Outbound Tab
    await tester.tap(find.text('Outbound').first);
    await tester.pumpAndSettle();

    // Verify Outbound Campaign & Call
    expect(find.text('November Outreach Campaign'), findsOneWidget);
    expect(find.text('12 / 50 completed'), findsOneWidget);
    expect(find.text('+16184237161 → +15552345678'), findsOneWidget);

    // Tap "Place a Call" button
    await tester.tap(find.text('Place a Call'));
    await tester.pumpAndSettle();

    expect(find.text('Place Outbound Call'), findsOneWidget);
    expect(find.text('From Agent'), findsOneWidget);
    expect(find.text('Phone Number to Call (E.164)'), findsOneWidget);
    expect(find.text('Dial Now'), findsOneWidget);
  });

  testWidgets('Call Simulator sheet opens phone mockup, connects, and allows ending call', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final api = nativeApi((path, body) async {
      if (path == '/native/records') {
        calls.add(Map<String, dynamic>.from(body));
        return {'message': 'Simulation ready.'};
      }
      return mockPhoneAgentData;
    });

    final module = {
      'id': 'web:ext_phone_call_agent_dashboard',
      'title': 'Phone Call Agent',
      'category': 'Phone Call Agent',
      'route_type': 'phone_agent',
      'route': 'dashboard.phone-call-agent.index',
    };

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativePhoneAgentScreen(module: module, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap "Test Call" button on first agent card
    await tester.tap(find.text('Test Call').first);
    await tester.pumpAndSettle();

    // Verify Call Simulator Sheet
    expect(find.text('Call Simulator'), findsOneWidget);
    expect(find.text('Sales Support AI'), findsNWidgets(2)); // Card + Simulator header
    expect(find.text('Test Voice Simulation'), findsOneWidget);

    // Tap Call floating button
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pump(const Duration(milliseconds: 500));

    expect(calls.length, 1);
    expect(calls[0]['kind'], 'phone_agent');
    expect(calls[0]['operation'], 'simulate');
    expect(calls[0]['record_id'], 1);

    // Advance past simulation delay
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.textContaining('Connected'), findsOneWidget);

    // Tap End Call
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Call Ended'), findsOneWidget);
  });
}
