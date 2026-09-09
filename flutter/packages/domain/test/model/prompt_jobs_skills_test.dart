import 'package:test/test.dart';

import 'package:domain/model/attachment.dart';
import 'package:domain/model/jobs.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/plan.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/skills.dart';

void main() {
  group('Prompt and job models', () {
    const img = PendingImage(
      id: 'i1',
      mediaType: 'image/png',
      base64Data: 'abc',
    );

    test('SendMessageRequest equality and images collection comparison', () {
      const a = SendMessageRequest(
        sessionId: 's-1',
        text: 'hello',
        mode: PromptMode.steer,
        images: [img],
      );
      const b = SendMessageRequest(
        sessionId: 's-1',
        text: 'hello',
        mode: PromptMode.steer,
        images: [
          PendingImage(id: 'i1', mediaType: 'image/png', base64Data: 'abc'),
        ],
      );
      const diff = SendMessageRequest(
        sessionId: 's-1',
        text: 'hello',
        mode: PromptMode.queue,
        images: [img],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('JobView equality and hashCode', () {
      const a = JobView(
        id: 'job-1',
        kind: 'bash',
        label: 'test run',
        status: JobStatus.running,
        detail: 'running tests',
        startedAt: 1000,
        finishedAt: null,
      );
      const b = JobView(
        id: 'job-1',
        kind: 'bash',
        label: 'test run',
        status: JobStatus.running,
        detail: 'running tests',
        startedAt: 1000,
        finishedAt: null,
      );
      const diff = JobView(
        id: 'job-1',
        kind: 'bash',
        label: 'test run',
        status: JobStatus.completed,
        startedAt: 1000,
        finishedAt: 2000,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('SkillEntry equality and hashCode', () {
      const a = SkillEntry(
        name: 'flutter',
        description: 'Run flutter tasks',
        whenToUse: 'When editing flutter code',
        modelInvocable: true,
      );
      const b = SkillEntry(
        name: 'flutter',
        description: 'Run flutter tasks',
        whenToUse: 'When editing flutter code',
        modelInvocable: true,
      );
      const diff = SkillEntry(
        name: 'flutter',
        description: 'Run flutter tasks',
        modelInvocable: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('PlanState equality and hashCode', () {
      const a = PlanState(active: true, pending: false);
      const b = PlanState(active: true, pending: false);
      const diff = PlanState(active: false, pending: false);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('PermissionSelect and options collection equality', () {
      const opt1 = PermissionPresetOption(
        value: 'workspace-write',
        name: 'Workspace Write',
        description: 'Can edit files in workspace',
      );
      const opt2 = PermissionPresetOption(
        value: 'danger-full-access',
        name: 'Full Access',
      );

      const a = PermissionSelect(
        options: [opt1, opt2],
        currentValue: 'workspace-write',
      );
      const b = PermissionSelect(
        options: [
          PermissionPresetOption(
            value: 'workspace-write',
            name: 'Workspace Write',
            description: 'Can edit files in workspace',
          ),
          PermissionPresetOption(
            value: 'danger-full-access',
            name: 'Full Access',
          ),
        ],
        currentValue: 'workspace-write',
      );
      const diff = PermissionSelect(
        options: [opt1, opt2],
        currentValue: 'danger-full-access',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.currentOption, equals(opt1));
      expect(diff.currentOption, equals(opt2));
      expect(a, isNot(equals(diff)));
    });
  });
}
